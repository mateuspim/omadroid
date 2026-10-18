# 2. One scrcpy session per machine, tracked by a state file

- Status: Accepted
- Date: 2026-09-23 (`session.sh`, release 0.3.0); polling replaced by a
  file watch and `session.sh wait` on 2026-10-04 (`04c253f`)

## Context

The first mirror pane started scrcpy as a child of the shell. It died with an
Omarchy shell restart, and each monitor's widget only knew about the session
it had started itself. Later the widgets polled the session status (every
second while open, every 5 s while closed with a session) so that a rotation
lock OmaDroid set could be released after scrcpy exited, which kept a timer
and a process spawn running all the time.

## Decision

- `session.sh` owns the one session of the machine. scrcpy runs in a detached
  terminal (foot preferred, else the Omarchy default terminal) on a hidden
  `special:omadroid` workspace, outside the shell process.
- The session is a state file in `$XDG_RUNTIME_DIR/omadroid-$UID/session`:
  PID, process start time, serial, type, recording path or webcam sink. A PID
  counts only if its `/proc` start time matches, so a reused PID is ignored.
  A `flock` guards every read and write; `launch` refuses while a session is
  active or another launch is starting (`launching` marker).
- Nothing polls. Each `MirrorSession` watches the state file (`FileView` on
  `session.sh path`) and, while a session runs, keeps one `session.sh wait`
  that sleeps on the scrcpy PID (util-linux `waitpid`), then ends the session
  and releases an owned rotation lock, even with the popup closed.
- `launch` waits for a `started` marker written by `run`, not for the state
  file, which a watching widget may already have removed for a scrcpy that
  died at once. The request travels in a NUL-separated file, not terminal
  argv, because Ghostty's hold mode drops empty arguments (`8bd39e4`).

## Consequences

- A session survives popup close, view changes and shell restarts, and every
  widget on every monitor sees and can stop the same session.
- With the popup closed and no session, OmaDroid spawns nothing for sessions.
- Only one session can run at a time; switching is handled in
  [ADR 10](0010-starting-a-session-switches-to-it.md). Multiple simultaneous
  sessions would need a different state layout.
- `session.sh` is tested with a fake scrcpy and terminal (`tests/session.sh`),
  including the launch race and argument preservation.
