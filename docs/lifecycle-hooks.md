# Lifecycle Hooks

Liney can run user-defined commands at four lifecycle points:

| Hook name           | When it fires                              | Frequency                     |
| ------------------- | ------------------------------------------ | ----------------------------- |
| `app.on_launch`     | Once after the app finishes loading        | Once per app launch           |
| `app.on_quit`       | When the app is quitting (best effort)     | Once per app quit             |
| `session.on_start`  | When a terminal session is started         | Per session                   |
| `session.on_exit`   | When a terminal session's process exits    | Per session                   |

Hooks are user-controlled and disabled by default. Turn them on in **Settings → App → Hooks**.

## Configuration file

Lives at `~/.liney/hooks.json` (or `~/.liney-debug/hooks.json` for the debug build).

```json
{
  "version": 1,
  "hooks": {
    "app.on_launch": [
      { "enabled": true, "command": "echo \"liney up at $(date)\" >> ~/.liney/hook.log" }
    ],
    "app.on_quit": [],
    "session.on_start": [
      { "enabled": true, "command": "claude --resume" }
    ],
    "session.on_exit": []
  }
}
```

- The `enabled` flag lets you keep a command on file but temporarily skip it.
- Each hook point holds an array, so you can chain multiple commands. They run in order.
- The fastest way to create the file is **Settings → Hooks → Open hooks.json** — Liney will scaffold it with disabled examples.

## How commands run

Each command is invoked as `/bin/sh -c <command>`. Use the shell as you would in `~/.zshrc`:

- `&&`, `||`, pipes, redirects all work.
- Use absolute paths (`/usr/local/bin/foo`) or rely on the inherited `PATH`.
- Hooks run as your user. They are not sandboxed.

### Execution model

| Hook                | Mode                                       |
| ------------------- | ------------------------------------------ |
| `app.on_launch`     | Async, fire-and-forget                     |
| `session.on_start`  | Async, fire-and-forget                     |
| `session.on_exit`   | Async, fire-and-forget                     |
| `app.on_quit`       | Synchronous, total budget **2 seconds**    |

Quit hooks are bounded so a slow command does not stall the app's shutdown. If the budget elapses, lingering child processes are terminated and a line is appended to `hook.log`.

For async hooks, each individual command is killed if it has not exited within 30 seconds.

## Context environment variables

Liney exports a few variables for every hook:

| Variable                  | Set on             | Value                                                |
| ------------------------- | ------------------ | ---------------------------------------------------- |
| `LINEY_HOOK`              | All                | The hook name (e.g. `session.on_start`)              |
| `LINEY_APP_VERSION`       | All                | The Liney version                                    |
| `LINEY_SESSION_ID`        | `session.*`        | The session UUID (lowercase, dashed)                 |
| `LINEY_SESSION_CWD`       | `session.*`        | The session's effective working directory            |
| `LINEY_SESSION_SHELL`     | `session.*`        | The launch path (shell, ssh, agent binary, etc.)     |
| `LINEY_SESSION_BACKEND`   | `session.*`        | One of `localShell`, `ssh`, `agent`, `tmuxAttach`    |
| `LINEY_SESSION_EXIT_CODE` | `session.on_exit`  | Process exit code, if Liney captured one             |

The full process environment of Liney itself is also inherited, so `$HOME`, `$PATH`, `$USER`, etc. are available.

## Logging

Failures (non-zero exit, timeout, or a parse error in `hooks.json`) are appended to `~/.liney/hook.log`. The file is capped at 256 KB; older lines are trimmed when the cap is reached.

Open it from **Settings → Hooks → Open hook.log**, or `tail -f ~/.liney/hook.log` from any terminal.

## Recipes

### Resume Claude Code automatically

```json
{
  "hooks": {
    "session.on_start": [
      { "enabled": true, "command": "claude --resume || true" }
    ]
  }
}
```

The `|| true` swallows the non-zero exit when there is nothing to resume, keeping `hook.log` clean.

### Notify on session exit

```json
{
  "hooks": {
    "session.on_exit": [
      { "enabled": true, "command": "osascript -e 'display notification \"Session exited\" with title \"Liney\"'" }
    ]
  }
}
```

### Boot a background service on app launch

```json
{
  "hooks": {
    "app.on_launch": [
      { "enabled": true, "command": "launchctl load ~/Library/LaunchAgents/dev.local.tunnel.plist 2>/dev/null || true" }
    ]
  }
}
```

### Save a per-session log

```json
{
  "hooks": {
    "session.on_start": [
      { "enabled": true, "command": "echo \"[$LINEY_SESSION_ID] $(date) start cwd=$LINEY_SESSION_CWD\" >> ~/liney-sessions.log" }
    ],
    "session.on_exit": [
      { "enabled": true, "command": "echo \"[$LINEY_SESSION_ID] $(date) exit code=$LINEY_SESSION_EXIT_CODE\" >> ~/liney-sessions.log" }
    ]
  }
}
```

## Security notes

- Hooks run any command as your user. Treat `hooks.json` as a sensitive file.
- The master toggle is off by default. Enable it only after reviewing the file.
- If you sync your home directory across machines, keep hooks reviewed when pulling new versions.

## Troubleshooting

- **Nothing fires.** Confirm **Settings → Hooks → Enable lifecycle hooks** is on, and that the command's `enabled` field is `true`.
- **A command runs locally but not via Liney.** Liney inherits the GUI process environment, which differs from a login shell. Source what you need explicitly inside the command, e.g. `bash -lc 'mycli ...'`.
- **`hooks.json` was edited but old commands keep running.** Liney watches the file modification time; switching the master toggle off and back on also forces a reload.
- **App quit feels slow after enabling hooks.** Reduce the work in `app.on_quit`, or move it to `app.on_launch` of the *next* run.
