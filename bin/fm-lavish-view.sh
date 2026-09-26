#!/usr/bin/env bash
# Forward a remote Lavish session to local port 4387 and open it when a
# local browser opener exists.
#
# Usage: fm-lavish-view.sh <remote-target> <session-url>
#        fm-lavish-view.sh --help
#
# The default port is 4387. The forward is always
#   ssh -L 4387:127.0.0.1:4387
# There is no second port.
#
# <remote-target> is the ssh destination that reaches the machine serving
# Lavish. <session-url> is that machine's Lavish session URL. The browser
# opens the same path on http://127.0.0.1:4387, which is the forwarded end.
#
# When SSH_CONNECTION, SSH_CLIENT, or SSH_TTY is set, this script is already
# inside an SSH session. It does not SSH back to this machine. It prints the
# exact command to run on the device you are sitting at, then the forwarded
# URL, and exits 0.
#
# A local run uses ssh -f -N and ExitOnForwardFailure so the browser opens
# only after the forward is up. The -L specification stays
# 4387:127.0.0.1:4387. The remote target is passed after -- so it cannot be
# read as an ssh option.
set -eu

usage() {
  printf '%s\n' \
    'Usage: fm-lavish-view.sh <remote-target> <session-url>' \
    '       fm-lavish-view.sh --help' \
    '' \
    'Forward Lavish from <remote-target> to local port 4387 and open the session' \
    'in a local browser when an opener exists.' \
    '' \
    'The default port is 4387. The forward is always ssh -L 4387:127.0.0.1:4387.' \
    'There is no second port.' \
    '' \
    '<remote-target> is the ssh destination, such as user@host.' \
    '<session-url> is the Lavish session URL on that machine.' \
    '' \
    'When this script is already running inside an SSH session, it does not SSH' \
    'back to this machine. It prints the exact command to run on the device you' \
    'are sitting at.'
}

fm_in_ssh_session() {
  [ -n "${SSH_CONNECTION:-}" ] || [ -n "${SSH_CLIENT:-}" ] || [ -n "${SSH_TTY:-}" ]
}

# Rewrite a session URL onto the forwarded loopback port, keeping path,
# query, and fragment. Userinfo is dropped. A non-URL falls back to the
# forwarded root rather than being opened as given.
fm_forwarded_url() {
  local url=$1 rest authority path
  case "$url" in
    http://*|https://*)
      rest=${url#*://}
      ;;
    *)
      rest=$url
      ;;
  esac
  case "$rest" in
    /*)
      path=$rest
      ;;
    *)
      authority=${rest%%/*}
      case "$authority" in
        *@*) authority=${authority#*@} ;;
      esac
      if [ "$authority" = "$rest" ]; then
        path=/
      else
        path=/${rest#*/}
      fi
      ;;
  esac
  printf 'http://127.0.0.1:4387%s\n' "$path"
}

fm_local_opener() {
  if command -v xdg-open >/dev/null 2>&1; then
    printf '%s\n' xdg-open
    return 0
  fi
  if command -v open >/dev/null 2>&1; then
    printf '%s\n' open
    return 0
  fi
  return 1
}

fm_print_local_command() {
  local remote=$1 quoted
  quoted=$(printf '%q' "$remote")
  printf 'Run this on the device you are sitting at:\n'
  printf 'ssh -o ExitOnForwardFailure=yes -f -N -L 4387:127.0.0.1:4387 -- %s\n' "$quoted"
}

fm_ssh_forward() {
  local remote=$1
  ssh -o ExitOnForwardFailure=yes -f -N -L 4387:127.0.0.1:4387 -- "$remote"
}

if [ "$#" -eq 1 ] && { [ "$1" = "--help" ] || [ "$1" = "-h" ]; }; then
  usage
  exit 0
fi

if [ "$#" -ne 2 ] || [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
  usage >&2
  exit 2
fi

remote=$1
session_url=$2

case "$remote" in
  -*)
    printf '%s\n' "error: remote target must not start with '-'" >&2
    exit 2
    ;;
esac
case "$session_url" in
  -*)
    printf '%s\n' "error: session URL must not start with '-'" >&2
    exit 2
    ;;
esac

forwarded=$(fm_forwarded_url "$session_url")

if fm_in_ssh_session; then
  fm_print_local_command "$remote"
  printf '%s\n' "$forwarded"
  exit 0
fi

fm_ssh_forward "$remote"
printf '%s\n' "$forwarded"
if opener=$(fm_local_opener); then
  "$opener" "$forwarded" || true
fi
