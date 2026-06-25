# Terminal inline images (OSC 1337 → Kitty)

Liney's terminal is the vendored Ghostty runtime. Ghostty renders the **Kitty
graphics protocol** but does **not** understand iTerm2's **OSC 1337** inline
image protocol — the one Claude Code and other AI tools use to print
screenshots. Without translation those images arrive as garbled escape text
(GitHub issue #125).

Liney cannot intercept the shell's output bytes directly: Ghostty owns the PTY
and only exposes high-level callbacks, so the shell→terminal byte stream never
passes through Liney code. The only place to see those bytes is *inside* the
PTY, as the foreground process.

## Design

A small helper, **`liney-osc-filter`** (`tools/liney-osc-filter.c`), is a
transparent PTY relay:

```
Claude Code → shell → [inner PTY] → liney-osc-filter → Ghostty PTY → Ghostty render
                                          │
                                          └─ rewrites OSC 1337 image → Kitty graphics
```

- It `forkpty`s the real command onto an inner PTY and shuttles bytes both ways,
  byte-for-byte, so an interactive shell behaves exactly as before (raw mode,
  `SIGWINCH` propagation, exit-status passthrough are all handled).
- On the shell→terminal side it scans for `ESC ] 1337 ; File = … : <base64> (BEL|ST)`
  and re-emits the payload as a Kitty `a=T,f=100` graphics command, chunked at
  4096 bytes.
- It only converts payloads it can prove are **PNG** (base64 prefix
  `iVBORw0KGgo`). Anything else (JPEG/GIF/…) and every non-image sequence is
  passed through untouched, so the feature can never make output *worse* than
  today.

## Wiring

- The helper is compiled into `Liney.app/Contents/Resources/liney-osc-filter`
  by the **"Compile OSC Filter"** build phase (universal across `$ARCHS`, then
  code-signed).
- `TerminalInlineImageFilter` (`Liney/Services/Terminal/`) resolves the bundled
  helper and, when enabled, wraps the launch command so
  `executablePath` becomes the helper and the original command becomes its
  arguments. Wrapping happens in `SessionBackendLaunch` for **local shell** and
  **agent** sessions, *after* shell-integration preparation (so zsh/fish
  detection still sees the real shell).
- The feature is **on by default** (so inline images work out of the box) but
  fully toggleable, backed by the UserDefaults key
  `liney.terminal.inlineImageProtocol` and a toggle in Settings → Terminal. When
  the key is absent it is treated as on; once the user flips the toggle their
  stored choice is honored. It applies to newly opened terminals only, and fails
  safe: if the helper is missing or the toggle is off, commands launch unwrapped
  exactly as before.

## Notes / follow-ups

- Release/notarization: the build phase ad-hoc signs the helper (and signs with
  the build's identity when available). The packaged nested binary should be
  verified against the notarization flow before shipping a signed release.
- Possible enhancements: map iTerm2 `width`/`height` args to Kitty cell sizing;
  optionally transcode non-PNG images so JPEG/GIF screenshots also render.
