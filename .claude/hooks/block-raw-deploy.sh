#!/usr/bin/env bash
# Blocks commands that would publish XReader updates without the deploy check.
# Claude Code runs this before every Bash command (see .claude/settings.json).
# Exit 2 blocks the command and shows the message to Claude; exit 0 lets it run.
#
# It reads the command as text, so it also blocks text that merely mentions a
# blocked command (an echo, a commit message). Reword those.

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)" ||
  cmd="$(printf '%s' "$input" | plutil -extract tool_input.command raw -o - - 2>/dev/null)"
[[ -z $cmd ]] && exit 0

block() {
  cat >&2 <<EOF
Blocked: $1 publishes XReader updates directly and skips the production deploy check.
Use scripts/release.sh instead. Run "scripts/release.sh --check" first and show the user its full output.
Deploy only when the user names production as the target, and never work around a stop. See AGENTS.md.
EOF
  exit 2
}

re_release='(^|[[:space:]/])gh[[:space:]]+release[[:space:]]+(create|edit|upload|delete|delete-asset)([[:space:]]|$)'
re_api='(^|[[:space:]/])gh[[:space:]]+api([[:space:]]|$)'
re_api_write='(-X|--method)[[:space:]=]*(POST|PATCH|PUT|DELETE)|(^|[[:space:]])(-f|-F|--field|--raw-field|--input)([[:space:]=]|$)'
re_push='(^|[[:space:]/])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)*[[:space:]]+push([[:space:]]|$)'
re_version_tag='^v[0-9]+(\.[0-9]+)*$'

# One simple command per line, with quotes dropped so bash -c '...' is seen too
segments="$(printf '%s\n' "$cmd" | tr -d "\"'" | awk '{ gsub(/&&|\|\||;|\||\(|\)|`/, "\n"); print }')"
set -f
while IFS= read -r seg; do
  if [[ $seg =~ $re_release ]]; then
    block "\"gh release ${BASH_REMATCH[2]}\""
  fi
  if [[ $seg =~ $re_api && $seg == *releases* ]] && grep -Eqi -- "$re_api_write" <<<"$seg"; then
    block "Writing to releases with \"gh api\""
  fi
  if [[ $seg =~ $re_push ]]; then
    for word in ${seg#*push}; do
      case $word in
        --tags | --follow-tags | --mirror) block "\"git push $word\" (it sends release tags)" ;;
      esac
      word="${word#+}"
      for part in ${word//:/ }; do
        if [[ $part == refs/tags/* || $part =~ $re_version_tag ]]; then
          block "Pushing the release tag \"$part\""
        fi
      done
    done
  fi
done <<<"$segments"
exit 0
