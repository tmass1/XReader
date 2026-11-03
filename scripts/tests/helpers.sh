# Shared by the deploy-check tests. Sourced, not run.

REAL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0

# Keep the tests independent of this Mac's own git settings.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

pass() { PASS=$((PASS + 1)); echo "  ok - $1"; }
fail() {
  FAIL=$((FAIL + 1))
  echo "  not ok - $1"
  if [[ -n ${2:-} ]]; then printf '%s\n' "$2" | tail -30 | sed 's/^/      | /'; fi
}

# expect <name> <wanted status> <status> <output> [text the output must contain...]
# A leading ! means the output must not contain that text.
expect() {
  local name=$1 want=$2 got=$3 out=$4 text
  shift 4
  if [[ $got != "$want" ]]; then
    fail "$name (exit $got, wanted $want)" "$out"
    return
  fi
  for text in "$@"; do
    if [[ $text == !* ]]; then
      if [[ $out == *"${text#!}"* ]]; then fail "$name (shouldn't say: ${text#!})" "$out"; return; fi
    elif [[ $out != *"$text"* ]]; then
      fail "$name (missing: $text)" "$out"
      return
    fi
  done
  pass "$name"
}

finish_tests() {
  echo "$PASS passed, $FAIL failed"
  ((FAIL == 0))
}
