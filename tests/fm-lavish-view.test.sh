#!/usr/bin/env bash
# bin/fm-lavish-view.sh forwards Lavish port 4387 and opens the forwarded
# URL when a local opener exists. Inside an SSH session it prints the
# command instead of connecting.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-lavish-view)
VIEW="$ROOT/bin/fm-lavish-view.sh"
FAKEBIN=$(fm_fakebin "$TMP_ROOT")
SSH_LOG="$TMP_ROOT/ssh.log"
OPEN_LOG="$TMP_ROOT/open.log"
export SSH_LOG OPEN_LOG
export SSH_RC=0

cat > "$FAKEBIN/ssh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "${SSH_LOG:?}"
exit "${SSH_RC:-0}"
SH
cat > "$FAKEBIN/xdg-open" <<'SH'
#!/usr/bin/env bash
printf '%s %s\n' "${0##*/}" "$*" >> "${OPEN_LOG:?}"
exit 0
SH
cat > "$FAKEBIN/open" <<'SH'
#!/usr/bin/env bash
printf '%s %s\n' "${0##*/}" "$*" >> "${OPEN_LOG:?}"
exit 0
SH
chmod +x "$FAKEBIN/ssh" "$FAKEBIN/xdg-open" "$FAKEBIN/open"
ln -s "$(command -v bash)" "$FAKEBIN/bash"

reset_logs() {
  : > "$SSH_LOG"
  : > "$OPEN_LOG"
  SSH_RC=0
}

run_view() {
  env -u SSH_CONNECTION -u SSH_CLIENT -u SSH_TTY \
    PATH="$FAKEBIN" SSH_LOG="$SSH_LOG" OPEN_LOG="$OPEN_LOG" SSH_RC="$SSH_RC" \
    "$VIEW" "$@"
}

run_view_in_ssh() {
  local marker=$1
  shift
  # shellcheck disable=SC2086
  env -u SSH_CONNECTION -u SSH_CLIENT -u SSH_TTY \
    $marker \
    PATH="$FAKEBIN" SSH_LOG="$SSH_LOG" OPEN_LOG="$OPEN_LOG" SSH_RC="$SSH_RC" \
    "$VIEW" "$@"
}

test_help_documents_default_port_and_does_not_connect() {
  local out rc
  reset_logs
  out=$(run_view --help)
  rc=$?
  [ "$rc" -eq 0 ] || fail "help exited $rc"
  assert_contains "$out" "default port is 4387" "help did not document the default port"
  assert_contains "$out" "ssh -L 4387:127.0.0.1:4387" "help did not document the forward"
  assert_contains "$out" "remote-target" "help did not name the remote argument"
  assert_contains "$out" "session-url" "help did not name the session URL argument"
  [ ! -s "$SSH_LOG" ] || fail "help invoked ssh"
  [ ! -s "$OPEN_LOG" ] || fail "help opened a browser"
  pass "help documents port 4387 and does not connect"
}

test_missing_arguments_are_refused() {
  local rc
  reset_logs
  run_view >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 2 ] || fail "no arguments exited $rc, expected 2"
  run_view user@host >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 2 ] || fail "one argument exited $rc, expected 2"
  run_view --port 4388 >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 2 ] || fail "a second port flag exited $rc, expected 2"
  [ ! -s "$SSH_LOG" ] || fail "a refused invocation invoked ssh"
  pass "missing arguments and a second port are refused without connecting"
}

test_local_run_forwards_4387_and_opens_rewritten_url() {
  local out
  reset_logs
  out=$(run_view 'user@host' 'http://box.example:9999/session/abc?tab=1#note') || fail "local view failed"
  assert_equals 'http://127.0.0.1:4387/session/abc?tab=1#note' "$out" \
    "the printed URL was not the forwarded path"
  assert_grep '-L' "$SSH_LOG" "ssh was not asked to forward"
  assert_grep '4387:127.0.0.1:4387' "$SSH_LOG" "ssh did not forward 4387 to loopback 4387"
  assert_grep 'user@host' "$SSH_LOG" "ssh was not given the remote target"
  assert_grep 'xdg-open http://127.0.0.1:4387/session/abc?tab=1#note' "$OPEN_LOG" \
    "xdg-open was not given the forwarded URL"
  assert_no_grep 'box.example' "$OPEN_LOG" "the opener was given the remote host"
  if grep -q '^open ' "$OPEN_LOG"; then
    fail "open was used while xdg-open existed"
  fi
  assert_no_grep '9999' "$SSH_LOG" "a port from the session URL was forwarded"
  pass "a local run forwards 4387 and opens the rewritten URL"
}

test_local_run_prefers_xdg_open_and_keeps_a_path_at_sign() {
  local out
  reset_logs
  out=$(run_view 'user@host' 'http://user@box.example:4387/session/a@b') || fail "local view failed"
  assert_equals 'http://127.0.0.1:4387/session/a@b' "$out" \
    "userinfo stripping ate the path"
  assert_grep 'xdg-open http://127.0.0.1:4387/session/a@b' "$OPEN_LOG" \
    "xdg-open was not given the forwarded path"
  pass "a local run prefers xdg-open and keeps an at-sign in the path"
}

test_local_run_uses_open_when_xdg_open_is_absent() {
  local out restricted
  reset_logs
  restricted="$TMP_ROOT/open-only"
  mkdir -p "$restricted"
  cp "$FAKEBIN/ssh" "$FAKEBIN/open" "$restricted/"
  ln -s "$(command -v bash)" "$restricted/bash"
  out=$(env -u SSH_CONNECTION -u SSH_CLIENT -u SSH_TTY \
    PATH="$restricted" SSH_LOG="$SSH_LOG" OPEN_LOG="$OPEN_LOG" SSH_RC=0 \
    "$VIEW" 'user@host' 'http://127.0.0.1:4387/session/abc') || fail "open-only view failed"
  assert_equals 'http://127.0.0.1:4387/session/abc' "$out" "the forwarded URL changed"
  assert_grep 'open http://127.0.0.1:4387/session/abc' "$OPEN_LOG" "open was not invoked"
  pass "a local run uses open when xdg-open is absent"
}

test_local_run_without_an_opener_still_prints_the_url() {
  local out restricted
  reset_logs
  restricted="$TMP_ROOT/ssh-only"
  mkdir -p "$restricted"
  cp "$FAKEBIN/ssh" "$restricted/"
  ln -s "$(command -v bash)" "$restricted/bash"
  out=$(env -u SSH_CONNECTION -u SSH_CLIENT -u SSH_TTY \
    PATH="$restricted" SSH_LOG="$SSH_LOG" OPEN_LOG="$OPEN_LOG" SSH_RC=0 \
    "$VIEW" 'user@host' 'http://[::1]:4387/session/abc') || fail "ssh-only view failed"
  assert_equals 'http://127.0.0.1:4387/session/abc' "$out" \
    "an IPv6 session URL was not rewritten onto the forward"
  [ ! -s "$OPEN_LOG" ] || fail "a missing opener still recorded an open"
  assert_grep '4387:127.0.0.1:4387' "$SSH_LOG" "the forward was skipped when no opener existed"
  pass "a local run without an opener still forwards and prints the URL"
}

test_ssh_failure_does_not_open_a_browser() {
  local rc
  reset_logs
  SSH_RC=7
  run_view 'user@host' 'http://127.0.0.1:4387/session/abc' >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 7 ] || fail "ssh failure exited $rc, expected 7"
  [ ! -s "$OPEN_LOG" ] || fail "a failed forward still opened a browser"
  pass "a failed forward does not open a browser"
}

test_ssh_session_prints_the_command_and_does_not_connect() {
  local marker out
  for marker in 'SSH_CONNECTION=1' 'SSH_CLIENT=1' 'SSH_TTY=/dev/pts/1'; do
    reset_logs
    out=$(run_view_in_ssh "$marker" 'user@host' 'http://box.example:4387/session/abc') || \
      fail "in-session view failed for $marker"
    assert_contains "$out" 'ssh -o ExitOnForwardFailure=yes -f -N -L 4387:127.0.0.1:4387 -- user@host' \
      "the printed command was not the local forward for $marker"
    assert_contains "$out" 'http://127.0.0.1:4387/session/abc' \
      "the printed URL was not the forwarded path for $marker"
    [ ! -s "$SSH_LOG" ] || fail "an SSH session invoked ssh for $marker"
    [ ! -s "$OPEN_LOG" ] || fail "an SSH session opened a browser for $marker"
  done
  pass "an SSH session prints the exact command and does not connect"
}

test_ssh_session_quotes_a_remote_target_with_spaces() {
  local out
  reset_logs
  out=$(run_view_in_ssh 'SSH_CONNECTION=1' 'user@host name' 'http://127.0.0.1:4387/session/abc') || \
    fail "in-session view failed for a spaced target"
  assert_contains "$out" 'ssh -o ExitOnForwardFailure=yes -f -N -L 4387:127.0.0.1:4387 -- user@host\ name' \
    "a spaced remote target was not shell-quoted in the printed command"
  [ ! -s "$SSH_LOG" ] || fail "a spaced target inside SSH still invoked ssh"
  pass "an SSH session quotes the remote target in the printed command"
}

test_help_documents_default_port_and_does_not_connect
test_missing_arguments_are_refused
test_local_run_forwards_4387_and_opens_rewritten_url
test_local_run_prefers_xdg_open_and_keeps_a_path_at_sign
test_local_run_uses_open_when_xdg_open_is_absent
test_local_run_without_an_opener_still_prints_the_url
test_ssh_failure_does_not_open_a_browser
test_ssh_session_prints_the_command_and_does_not_connect
test_ssh_session_quotes_a_remote_target_with_spaces
echo "# all fm-lavish-view tests passed"
