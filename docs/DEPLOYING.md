# Deploying XReader

A "deploy" here means publishing an app update. When a new release on GitHub is marked **Latest**, every installed copy of XReader finds it within a day and installs it. That's production. There is no staging.

The risk this guards against: releasing from a branch, folder or computer that doesn't have work that's already out. Everyone would update and quietly lose that work. Worse than on a website, the updater never moves people back to an older version, so the only fix is another release.

## The one command

| What you want | Run |
| --- | --- |
| Check everything, change nothing | `scripts/release.sh --check 1.3` |
| Publish version 1.3 | `scripts/release.sh 1.3 "What changed"` |
| Undo the latest release | `scripts/release.sh --rollback v1.2` |

Leave out the notes and it uses the commit titles since the live release. Leave out the version in `--check` and it checks everything except the version number.

## What it does, in order

1. **Uncommitted changes.** Stops if a file the app is built from (`XReader/`, the Xcode project, `scripts/ExportOptions.plist`) has changes that aren't committed. Other files are only mentioned.
2. **What's live.** Asks GitHub which release is Latest and which commit it was built from, and makes sure the update feed agrees. New releases carry a note saying exactly which commit and branch they came from. Older ones (1.1, 1.2) are traced by their version tag.
3. **Missing live work.** Stops if your branch doesn't contain the live commit, lists what would be lost, and tells you what to merge.
4. **Questions.** Asks you to confirm if you're not on `main`, if you have commits that aren't on GitHub, or if GitHub has commits you don't.
5. **Privacy.** Stops if anything about to become public carries an email other than your private GitHub address.
6. **Version.** Stops unless the version is higher than every release already published.
7. **Tests.** Runs the deploy check's own tests (and the app's, once it has some).
8. **Tools.** Makes sure GitHub sign-in, Apple notarization, Sparkle's tools and your update signing key are ready.
9. **What's new.** Shows every change since the live release, then asks you to type `deploy`.
10. **Build and publish.** Builds, has Apple notarize it, signs the update, makes sure nobody else released in the meantime, then publishes. Only the version tag goes to GitHub. Your branch stays unpushed until you say so.
11. **Live check.** Downloads the update the way an installed copy would and checks it. See "The live check" below.
12. **Wrap-up.** Prints the rollback command and your to-do list.

`--check` does steps 1–9 without building or publishing anything. It also runs the live check against the current release.

`--yes` is for running without a terminal (for example, by an agent after you've said yes in chat). It answers the questions and the `deploy` prompt. It never gets past a stop.

## Stops, and what to do

| Message | What it means | What to do |
| --- | --- | --- |
| Files the app is built from have changes that aren't committed | The release wouldn't match any saved version of the code | Commit or undo them, then check again |
| Couldn't find out which version is live | GitHub didn't answer | Check you're online and `gh auth status`. If GitHub truly can't tell, find the Latest release on the releases page, copy its commit ID, and run `LIVE_COMMIT=<ID> scripts/release.sh --check` |
| The commit you named isn't what's live | `LIVE_COMMIT` disagrees with GitHub | Drop `LIVE_COMMIT`. It only counts when GitHub can't tell |
| The live release's records disagree | The release's note and its tag point at different commits, so someone may have moved the tag | Don't deploy. Find out which is right, then name it with `LIVE_COMMIT` |
| GitHub and the update feed disagree | GitHub's Latest and what installed copies see don't match | Wait a minute and retry. If it persists, look at the releases page |
| The update feed didn't load | Installed copies can't see updates either | Check your connection. If it's really down, fix that first |
| This branch is missing work that's already live | Releasing would take the listed changes away from everyone | Run the `git merge` it suggests, then check again |
| The live commit isn't in this copy of the project | This folder has never seen the live code | `git fetch origin --tags`. If still missing, whoever released hasn't pushed: push from that computer first |
| You're not on a branch | The folder is parked on a single commit | `git switch main` (or your branch) |
| …isn't your private GitHub address | A public email would be published | Set `git config user.email` to your noreply address, and get help rewriting any listed commits |
| Version … isn't higher / was already released | The updater ignores versions that aren't newer | Pick a higher version |
| Tests failed | Something in the check itself is broken | Fix it before deploying |
| Notarization login / Sparkle tools / signing key | This Mac isn't set up to release | Follow the setup in README → Releasing |
| This needs your OK, and there's no terminal to ask in | A question came up with nobody to answer it | Run it yourself in Terminal, or add `--yes` once you've approved in chat |
| Someone released while this was building | Another release went out during the build | Nothing was published. Run the check again |

## The live check

After publishing (and during `--check`), it downloads the update the way an installed copy would and confirms:

- **Public:** the feed offers the new version, the download works and is the right size, the app inside has the right version number, and the release page loads.
- **Protected:** the signature checks out, Apple accepts the app, the update key built into the app is yours, and the release and download contain only what they should.
- **Hidden:** GitHub has only the `main` branch, and every published commit uses your private email.

## Rolling back

```bash
scripts/release.sh --rollback v1.2
```

This marks an earlier release as Latest again. You type `rollback` to confirm.

- People who haven't installed the bad version stop being offered it.
- People who already installed it keep it. The updater never moves anyone to an older version. To fix it for them, release a newer version with the fix.
- Your branches still contain the bad changes. Undo or fix them before the next release, or they'll ship again.

Add `--check` to see what a rollback would do without doing it.

## Agents

AGENTS.md tells every agent (Claude, Codex and others) to deploy only with this command, only when you name production, to show you the `--check` output first, and never to work around a stop. For Claude, a hook in `.claude/settings.json` also blocks the raw publishing commands (`gh release` create/edit/upload/delete, pushing version tags, release writes through `gh api`). The hook reads commands as text, so a commit message that mentions one of those commands is blocked too; reword it.

## Tests

```bash
scripts/tests/run.sh
```

These run the checks against small throwaway projects with a stand-in for GitHub, and feed sample commands to the hook. They never touch the real releases.
