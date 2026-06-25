/*
 * liney-osc-filter
 *
 * A transparent PTY relay that rewrites iTerm2 OSC 1337 inline-image
 * sequences into the Kitty graphics protocol, which the vendored Ghostty
 * runtime renders natively.
 *
 * Why this exists: Ghostty does not understand iTerm2's OSC 1337 inline image
 * protocol (the one Claude Code and other AI tools use to print screenshots),
 * but it DOES understand the Kitty graphics protocol. Both carry the same
 * base64-encoded image file, so we can losslessly translate one into the other
 * in the byte stream before Ghostty ever parses it.
 *
 * Liney cannot see the shell's output bytes (Ghostty owns the PTY), so the only
 * place to intercept them is *inside* the PTY, as the foreground process. This
 * program runs the user's real command on an inner PTY and shuttles bytes both
 * ways, scanning the shell->terminal direction for OSC 1337 image sequences.
 *
 * Everything that is not a convertible inline image is passed through verbatim,
 * byte for byte, so an interactive shell behaves exactly as it would without us.
 *
 * Usage: liney-osc-filter <command> [args...]
 * Exit status mirrors the wrapped command's exit status.
 */

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>
#include <util.h> /* forkpty on macOS */

/* The Kitty protocol wants the base64 payload split into chunks no larger than
 * 4096 bytes. */
#define KITTY_CHUNK 4096

/* Cap the buffer we accumulate while waiting for an OSC terminator. Real inline
 * images are large, so allow many megabytes, but never grow without bound: if a
 * sequence runs away we flush it verbatim and resync. */
#define MAX_OSC_BYTES (64 * 1024 * 1024)

static struct termios g_saved_termios;
static int g_termios_saved = 0;
static volatile sig_atomic_t g_winch_pending = 0;

static void restore_termios(void) {
    if (g_termios_saved) {
        tcsetattr(STDIN_FILENO, TCSANOW, &g_saved_termios);
        g_termios_saved = 0;
    }
}

static void on_winch(int sig) {
    (void)sig;
    g_winch_pending = 1;
}

/* Write the whole buffer, retrying on partial writes and EINTR. */
static int write_all(int fd, const unsigned char *buf, size_t len) {
    size_t off = 0;
    while (off < len) {
        ssize_t n = write(fd, buf + off, len - off);
        if (n < 0) {
            if (errno == EINTR)
                continue;
            return -1;
        }
        off += (size_t)n;
    }
    return 0;
}

/* ---- OSC 1337 -> Kitty translation -------------------------------------- */

/* Emit the base64 image payload as a Kitty "transmit and display" command.
 * f=100 tells Kitty the data is PNG; we only translate when we are confident the
 * payload is PNG (see is_png_base64), so this is safe. */
static int emit_kitty_image(int out, const unsigned char *b64, size_t len) {
    static const char esc_g[] = "\x1b_G";
    static const char st[] = "\x1b\\";

    size_t off = 0;
    int first = 1;
    while (off < len) {
        size_t remaining = len - off;
        size_t chunk = remaining > KITTY_CHUNK ? KITTY_CHUNK : remaining;
        int more = (off + chunk < len) ? 1 : 0;

        char control[64];
        int clen;
        if (first) {
            clen = snprintf(control, sizeof(control), "a=T,f=100,m=%d;", more);
        } else {
            clen = snprintf(control, sizeof(control), "m=%d;", more);
        }
        if (clen < 0)
            return -1;

        if (write_all(out, (const unsigned char *)esc_g, sizeof(esc_g) - 1) < 0)
            return -1;
        if (write_all(out, (const unsigned char *)control, (size_t)clen) < 0)
            return -1;
        if (write_all(out, b64 + off, chunk) < 0)
            return -1;
        if (write_all(out, (const unsigned char *)st, sizeof(st) - 1) < 0)
            return -1;

        off += chunk;
        first = 0;
    }
    return 0;
}

/* The base64 encoding of a file is deterministic from its leading bytes, so a
 * PNG (signature 89 50 4E 47 0D 0A 1A 0A) always begins "iVBORw0KGgo" in
 * base64. Checking the prefix lets us recognise PNGs without decoding, and lets
 * us safely decline anything else (JPEG/GIF/...) by passing it through. */
static int is_png_base64(const unsigned char *b64, size_t len) {
    static const char png_prefix[] = "iVBORw0KGgo";
    size_t plen = sizeof(png_prefix) - 1;
    if (len < plen)
        return 0;
    return memcmp(b64, png_prefix, plen) == 0;
}

/* Given a complete OSC body (the bytes between "ESC ]" and the terminator),
 * decide whether it is a convertible inline image and, if so, write the Kitty
 * translation to `out`. Returns 1 if it was handled (translated), 0 otherwise.
 *
 * iTerm2 inline image form:
 *   1337;File=<key=value;...>:<base64>
 */
static int try_translate_osc(int out, const unsigned char *body, size_t len) {
    static const char prefix[] = "1337;File=";
    size_t plen = sizeof(prefix) - 1;
    if (len < plen || memcmp(body, prefix, plen) != 0)
        return 0;

    /* Find the ':' that separates the key=value arguments from the payload.
     * Base64 never contains ':', so the first one ends the argument list. */
    const unsigned char *colon = memchr(body + plen, ':', len - plen);
    if (colon == NULL)
        return 0;

    const unsigned char *payload = colon + 1;
    size_t payload_len = (size_t)(body + len - payload);
    if (payload_len == 0)
        return 0;

    if (!is_png_base64(payload, payload_len))
        return 0;

    return emit_kitty_image(out, payload, payload_len) == 0 ? 1 : 0;
}

/* ---- Streaming OSC scanner ---------------------------------------------- */

/* The shell->terminal byte stream is scanned by this small state machine. OSC
 * sequences can straddle read() boundaries, so state persists across feeds.
 *
 * We only buffer OSC bodies that begin with "1337;File=" (inline images). Every
 * other byte -- ordinary text, CSI sequences, other OSCs -- is forwarded
 * immediately and unbuffered, so latency and memory are unaffected for normal
 * output. */
typedef enum {
    S_GROUND,     /* normal passthrough */
    S_ESC,        /* saw ESC, deciding what follows */
    S_OSC_SNIFF,  /* inside OSC, still checking if it is 1337;File= */
    S_OSC_IMAGE,  /* inside a confirmed inline-image OSC, buffering body */
    S_OSC_PASS,   /* inside a non-image OSC, forwarding verbatim */
    S_OSC_PASS_ESC /* in S_OSC_PASS and saw ESC (possible ST) */
} scan_state;

typedef struct {
    scan_state state;
    unsigned char *buf; /* accumulates the OSC body for image sequences/sniff */
    size_t len;
    size_t cap;
    int img_esc; /* in S_OSC_IMAGE: saw ESC, watching for ST ('\\') */
    int overflow; /* image buffer hit the cap; bail to verbatim */
} osc_scanner;

static void scanner_init(osc_scanner *s) {
    memset(s, 0, sizeof(*s));
    s->state = S_GROUND;
}

static int scanner_reserve(osc_scanner *s, size_t extra) {
    if (s->len + extra <= s->cap)
        return 0;
    size_t cap = s->cap ? s->cap : 4096;
    while (cap < s->len + extra)
        cap *= 2;
    unsigned char *nb = realloc(s->buf, cap);
    if (nb == NULL)
        return -1;
    s->buf = nb;
    s->cap = cap;
    return 0;
}

static int scanner_push(osc_scanner *s, unsigned char c) {
    if (s->len + 1 > MAX_OSC_BYTES) {
        s->overflow = 1;
        return 0;
    }
    if (scanner_reserve(s, 1) < 0)
        return -1;
    s->buf[s->len++] = c;
    return 0;
}

/* Flush the buffered "ESC ]" + body verbatim (used when a sniffed OSC turns out
 * not to be an image, or when something overflows/aborts). */
static int flush_buffer_verbatim(int out, osc_scanner *s) {
    static const unsigned char osc_intro[] = {0x1b, ']'};
    if (write_all(out, osc_intro, sizeof(osc_intro)) < 0)
        return -1;
    if (s->len && write_all(out, s->buf, s->len) < 0)
        return -1;
    s->len = 0;
    return 0;
}

/* The OSC body is complete (terminator consumed). Translate if it is an image,
 * otherwise forward it verbatim. Always re-emits the terminator as BEL. */
static int finish_osc_body(int out, osc_scanner *s) {
    int handled = 0;
    if (!s->overflow)
        handled = try_translate_osc(out, s->buf, s->len);

    if (!handled) {
        if (flush_buffer_verbatim(out, s) < 0)
            return -1;
        unsigned char bel = 0x07;
        if (write_all(out, &bel, 1) < 0)
            return -1;
    }
    s->len = 0;
    s->overflow = 0;
    return 0;
}

/* Feed `n` bytes of shell output through the scanner, writing the (possibly
 * translated) result to `out`. Returns 0 on success, -1 on a write/alloc error. */
static int scanner_feed(osc_scanner *s, int out, const unsigned char *in, size_t n) {
    size_t i = 0;
    /* Coalesce runs of plain GROUND bytes into single writes for speed. */
    while (i < n) {
        unsigned char c = in[i];
        switch (s->state) {
        case S_GROUND: {
            size_t start = i;
            while (i < n && in[i] != 0x1b)
                i++;
            if (i > start && write_all(out, in + start, i - start) < 0)
                return -1;
            if (i < n) { /* in[i] == ESC */
                s->state = S_ESC;
                i++;
            }
            break;
        }
        case S_ESC:
            if (c == ']') {
                s->state = S_OSC_SNIFF;
                s->len = 0;
                s->overflow = 0;
            } else {
                /* Not an OSC: emit the ESC we withheld plus this byte. */
                unsigned char esc = 0x1b;
                if (write_all(out, &esc, 1) < 0)
                    return -1;
                if (write_all(out, &c, 1) < 0)
                    return -1;
                s->state = S_GROUND;
            }
            i++;
            break;
        case S_OSC_SNIFF: {
            /* Buffer until we can tell whether this is "1337;File=". */
            if (c == 0x07) { /* short OSC terminated before we decided */
                if (finish_osc_body(out, s) < 0)
                    return -1;
                s->state = S_GROUND;
                i++;
                break;
            }
            if (scanner_push(s, c) < 0)
                return -1;
            i++;

            static const char prefix[] = "1337;File=";
            size_t plen = sizeof(prefix) - 1;
            if (s->len >= plen) {
                if (memcmp(s->buf, prefix, plen) == 0) {
                    s->state = S_OSC_IMAGE;
                    s->img_esc = 0;
                } else {
                    /* Not an image. Forward what we buffered and stream the
                     * rest of this OSC verbatim. */
                    if (flush_buffer_verbatim(out, s) < 0)
                        return -1;
                    s->state = S_OSC_PASS;
                }
            }
            break;
        }
        case S_OSC_IMAGE:
            if (s->img_esc) {
                s->img_esc = 0;
                if (c == '\\') { /* ST terminator: ESC \ */
                    if (finish_osc_body(out, s) < 0)
                        return -1;
                    s->state = S_GROUND;
                    i++;
                    break;
                }
                /* A stray ESC inside the body; keep both bytes. */
                if (scanner_push(s, 0x1b) < 0)
                    return -1;
                if (scanner_push(s, c) < 0)
                    return -1;
                i++;
                break;
            }
            if (c == 0x07) { /* BEL terminator */
                if (finish_osc_body(out, s) < 0)
                    return -1;
                s->state = S_GROUND;
                i++;
                break;
            }
            if (c == 0x1b) {
                s->img_esc = 1;
                i++;
                break;
            }
            if (scanner_push(s, c) < 0)
                return -1;
            i++;
            break;
        case S_OSC_PASS:
            if (c == 0x07) { /* BEL terminator */
                if (write_all(out, &c, 1) < 0)
                    return -1;
                s->state = S_GROUND;
            } else if (c == 0x1b) {
                s->state = S_OSC_PASS_ESC;
            } else {
                if (write_all(out, &c, 1) < 0)
                    return -1;
            }
            i++;
            break;
        case S_OSC_PASS_ESC: {
            unsigned char esc = 0x1b;
            if (write_all(out, &esc, 1) < 0)
                return -1;
            if (write_all(out, &c, 1) < 0)
                return -1;
            /* ESC '\' ends the OSC; either way we are back to normal scanning
             * (a lone ESC mid-OSC is unusual but handled gracefully). */
            s->state = (c == '\\') ? S_GROUND : S_OSC_PASS;
            i++;
            break;
        }
        }
    }
    return 0;
}

/* ---- PTY relay ----------------------------------------------------------- */

static void sync_winsize(int master_fd) {
    struct winsize ws;
    if (ioctl(STDIN_FILENO, TIOCGWINSZ, &ws) == 0)
        ioctl(master_fd, TIOCSWINSZ, &ws);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: liney-osc-filter <command> [args...]\n");
        return 2;
    }

    /* Capture the controlling terminal's mode and window size so the inner PTY
     * starts out identical to the one Ghostty handed us. */
    struct winsize ws;
    int have_ws = (ioctl(STDIN_FILENO, TIOCGWINSZ, &ws) == 0);

    struct termios tio;
    int have_tio = (tcgetattr(STDIN_FILENO, &tio) == 0);

    int master_fd = -1;
    pid_t pid = forkpty(&master_fd, NULL, have_tio ? &tio : NULL,
                        have_ws ? &ws : NULL);
    if (pid < 0) {
        perror("forkpty");
        return 1;
    }

    if (pid == 0) {
        /* Child: become the real command. */
        execvp(argv[1], &argv[1]);
        perror("execvp");
        _exit(127);
    }

    /* Parent: put our controlling terminal into raw mode so bytes flow through
     * untouched -- the inner PTY runs its own line discipline. */
    if (have_tio) {
        struct termios raw = tio;
        cfmakeraw(&raw);
        if (tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0) {
            g_saved_termios = tio;
            g_termios_saved = 1;
            atexit(restore_termios);
        }
    }

    signal(SIGWINCH, on_winch);
    signal(SIGPIPE, SIG_IGN);

    osc_scanner scanner;
    scanner_init(&scanner);

    unsigned char in_buf[65536];
    unsigned char out_buf[65536];
    int child_done = 0;

    for (;;) {
        if (g_winch_pending) {
            g_winch_pending = 0;
            sync_winsize(master_fd);
        }

        fd_set rfds;
        FD_ZERO(&rfds);
        FD_SET(STDIN_FILENO, &rfds);
        FD_SET(master_fd, &rfds);
        int maxfd = master_fd > STDIN_FILENO ? master_fd : STDIN_FILENO;

        int rv = select(maxfd + 1, &rfds, NULL, NULL, NULL);
        if (rv < 0) {
            if (errno == EINTR)
                continue;
            break;
        }

        /* Keyboard (Ghostty PTY) -> inner command. */
        if (FD_ISSET(STDIN_FILENO, &rfds)) {
            ssize_t n = read(STDIN_FILENO, in_buf, sizeof(in_buf));
            if (n > 0) {
                if (write_all(master_fd, in_buf, (size_t)n) < 0)
                    break;
            } else if (n == 0) {
                /* stdin closed; stop forwarding input but keep draining output. */
                FD_CLR(STDIN_FILENO, &rfds);
            } else if (errno != EINTR) {
                break;
            }
        }

        /* Inner command output -> scan/translate -> Ghostty PTY. */
        if (FD_ISSET(master_fd, &rfds)) {
            ssize_t n = read(master_fd, out_buf, sizeof(out_buf));
            if (n > 0) {
                if (scanner_feed(&scanner, STDOUT_FILENO, out_buf, (size_t)n) < 0)
                    break;
            } else if (n == 0) {
                child_done = 1;
                break;
            } else if (errno != EINTR) {
                break;
            }
        }
    }

    restore_termios();
    free(scanner.buf);

    int status = 0;
    if (waitpid(pid, &status, child_done ? 0 : WNOHANG) == pid) {
        if (WIFEXITED(status))
            return WEXITSTATUS(status);
        if (WIFSIGNALED(status))
            return 128 + WTERMSIG(status);
    }
    return 0;
}
