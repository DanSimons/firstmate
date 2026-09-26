---
name: lavish-document
description: >-
  Agent-only procedure for creating or opening a Lavish document.
  Load whenever a Lavish document is about to be made or opened.
  Always serve it on port 4387 and hand a remote session to bin/fm-lavish-view.sh.
user-invocable: false
metadata:
  internal: true
---

# lavish-document

Load this before creating or opening a Lavish document, including a visual decision or report.
It owns the fixed port and the remote handoff.
[`bin/fm-lavish-view.sh`](../../../bin/fm-lavish-view.sh) owns the ssh forward, the in-session refusal, and the local browser open.
Read its header and `--help` before running it.

## Port

Always serve the document on port 4387.
Pass that port explicitly so a changed ambient default cannot move the page.
The installed open help is `lavish-axi <html-file> [--no-open] [--no-gate] [--reopen]`.
That command does not accept `--port`.
A `--port` value before the html file is parsed as the file, and `--port` after the file does not select the server.
Open, poll, and end take the port from `LAVISH_AXI_PORT`, whose built-in default is 4387.
Set `LAVISH_AXI_PORT=4387` on every `lavish-axi` command for the document.
`--port` is only for server and stop, in the position their help shows: `lavish-axi server --port 4387` and `lavish-axi stop --port 4387`.
If a later `lavish-axi` help moves those flags, follow that help and still pin 4387.

## Open

When the captain is at this machine's display, open with `LAVISH_AXI_PORT=4387 lavish-axi <html-file>` so the local browser can launch.
When this machine is remote, do not rely on a local browser open.
Treat the machine as remote when `SSH_CONNECTION`, `SSH_CLIENT`, or `SSH_TTY` is set, or when the captain is not at this display.
Suppress the launch with `--no-open` after the html file: `LAVISH_AXI_PORT=4387 lavish-axi <html-file> --no-open`.
Give the captain the session URL lavish-axi printed and `bin/fm-lavish-view.sh <remote-target> <session-url>` to run on the device they are sitting at.
`<remote-target>` is the ssh destination that reaches this machine.
If that destination is not already known, ask for it rather than guessing or opening an ssh connection from here.
Pass the session URL as lavish-axi printed it.
The viewer script rewrites it onto the forwarded port.
Do not run the viewer on this machine to open a browser.
If it is already inside an SSH session, the script prints the command for the captain's device and does not SSH back.
Do not pass `--reopen` unless the captain asked to reopen a session they ended.
