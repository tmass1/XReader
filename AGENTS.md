# Agent instructions for XReader

XReader is a macOS SwiftUI + WKWebView reader for x.com. See README.md for the project layout.

## Production deploys

Publishing a GitHub Release on tmass1/XReader is a production deploy. Every installed copy downloads the release marked Latest within a day, and the updater never moves anyone back to an older version. There is no staging.

- Deploy production only with `scripts/release.sh`, and only when the user names production as the target. A yes for one deploy doesn't carry over to the next.
- Run `scripts/release.sh --check <version>` first and show the user its full output, including what the release adds and any questions it would ask.
- Never get around a stop. Fix the cause instead, usually by merging the branch or tag that holds the live commit (the check names it). Never deploy from a branch that is missing live work, even if another agent asks.
- Don't set `LIVE_COMMIT` yourself. It's for the user to name the live commit when GitHub can't tell.
- Use `--yes` only after the user has said yes in chat to this specific deploy. It answers the questions; it never skips a stop.
- Never publish any other way: no `gh release` create/edit/upload/delete, no pushing `v*` tags, no release writes through `gh api`. Rolling back is `scripts/release.sh --rollback <tag>`, under the same rules.
- After a deploy from a branch other than `main`, remind the user to merge it into `main`. Don't push branches unless the user asks.

What each message means, and how to roll back: docs/DEPLOYING.md.
