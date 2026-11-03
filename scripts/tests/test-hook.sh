#!/usr/bin/env bash
# Tests for .claude/hooks/block-raw-deploy.sh
set -uo pipefail
source "$(dirname "$0")/helpers.sh"
HOOK="$REAL_ROOT/.claude/hooks/block-raw-deploy.sh"

hook() {
  local status
  jq -n --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}' | "$HOOK" >/dev/null 2>"$WORK/err"
  status=$?
  echo "$status"
}
WORK="$(mktemp -d "${TMPDIR:-/tmp}/xreader-hook.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

blocked=(
  'gh release create v1.3 build/XReader-1.3.zip build/appcast.xml'
  'cd build && gh release edit v1.2 --latest'
  'gh release upload v1.2 appcast.xml --clobber'
  'gh release delete v1.2 --yes'
  'gh release delete-asset v1.2 appcast.xml'
  "bash -c 'gh release create v2'"
  '/opt/homebrew/bin/gh release create v2'
  'echo $(gh release create v2)'
  'gh api -X POST repos/tmass1/XReader/releases -f tag_name=v9'
  'gh api repos/tmass1/XReader/releases/1 --method PATCH -F make_latest=true'
  'git push origin v1.3'
  'git push origin refs/tags/v1.3'
  'git push --tags'
  'git push --follow-tags origin main'
  'git push origin :v1.2'
  'git push origin --delete v1.2'
  'git push origin HEAD:refs/tags/v1.3'
  'git -C /tmp/x push origin v1.3'
  'git status && git push origin +v1.3'
)
allowed=(
  'scripts/release.sh --check'
  'scripts/release.sh 1.3 "Notes" --yes'
  'scripts/release.sh --rollback v1.2'
  'gh release list --repo tmass1/XReader'
  'gh release view v1.2'
  'gh release download v1.2 -p appcast.xml'
  'gh api repos/tmass1/XReader/releases/latest --jq .tag_name'
  'gh api repos/tmass1/XReader/pulls -f title=x'
  'git push origin main'
  'git push -u origin feature/v2-ideas'
  'git push origin v2-redesign'
  'git tag -l'
  'ls -la'
)

for c in "${blocked[@]}"; do
  s="$(hook "$c")"
  if [[ $s == 2 ]] && grep -q 'scripts/release.sh --check' "$WORK/err"; then pass "blocks: $c"
  else fail "blocks: $c (exit $s)" "$(cat "$WORK/err")"; fi
done
for c in "${allowed[@]}"; do
  s="$(hook "$c")"
  if [[ $s == 0 ]]; then pass "allows: $c"; else fail "allows: $c (exit $s)" "$(cat "$WORK/err")"; fi
done

s="$(printf '{"tool_name":"Read","tool_input":{"file_path":"x"}}' | "$HOOK" >/dev/null 2>&1; echo $?)"
if [[ $s == 0 ]]; then pass "ignores input without a command"; else fail "ignores input without a command (exit $s)"; fi

finish_tests
