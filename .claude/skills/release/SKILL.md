---
name: release
description: Cut a release of the Skinny macOS app (GitHub Release + Sparkle appcast). Use when the user says "merged, cut a release", "cut a new release", "ship it", or "release X.Y.Z".
---

# Release Skinny

Mechanics live in `scripts/release.sh` (tests, build, sign, tag, publish, appcast). This skill is the judgment around it. Work the steps in order; each ends on a checkable condition.

## 1. Sync main

Run from the repo root checkout, on `main`, with a clean tree: `git switch main && git pull --ff-only`. Done when `git status --porcelain` is empty and `HEAD == origin/main`.

Untracked agent worktrees under `.claude/worktrees/` make `release.sh` fail with "working tree is not clean". Leave them in place (they hold other agents' work). Either tell the user, or hide them locally: `echo .claude/worktrees/ >> .git/info/exclude` (uncommitted).

## 2. Confirm the merged work reached main

The user's "it's merged" is a claim; check it. Find the last tag with `gh release list --limit 1`, then:

```sh
gh pr list --state merged --limit 50 --json number,title,baseRefName,mergedAt
```

Keep PRs with `mergedAt` after the last release. Done when every one has `baseRefName == main`.

A PR whose base is another branch merged into that branch, not into `main`. Stacked PRs have merged into a feature branch after it had itself merged, so the work never shipped. If you find one, stop. Explain which PRs are stranded and offer a roll-up PR from that branch to `main` (`gh pr create --base main`). Release only after it lands.

## 3. Pick the version

Take the latest tag from `gh release list`. Use the user's version if they gave one. Otherwise bump the minor if any PR since the tag added a feature, the patch if only fixes landed.

## 4. Run the release

```sh
scripts/release.sh X.Y.Z
```

Use a 10 minute timeout. Add `--dry-run` first if anything about the environment is uncertain; it builds and signs into `dist/` and publishes nothing. The script refuses if the build number is not newer than the live appcast; that means nothing new was committed.

The Sparkle EdDSA key lives in the login keychain and installed copies verify updates against it. If the script says the key is unavailable or mismatched, stop and tell the user. Restore the original key and leave generation of a new one alone.

## 5. Verify the appcast

```sh
curl -fsL https://github.com/asharism/skinny-dip/releases/latest/download/appcast.xml
```

Done when the output contains `<sparkle:shortVersionString>X.Y.Z</sparkle:shortVersionString>` and `sparkle:edSignature`.

## 6. Close umbrella issues

Run `gh issue list --state open`. For each parent or umbrella issue, read the body for its sub-issue list. Close the parent (with a comment linking the release) when every sub-issue is closed.

## 7. Report

Give the user:
- release URL (`https://github.com/asharism/skinny-dip/releases/tag/vX.Y.Z`) and version
- what is in it, from the PRs since the last tag
- issues closed
- what is still unverified by hand. Releases touching clipboard output expect a Tier 1 paste-matrix run (new Outlook, Outlook for Mac, Teams) from `docs/paste-matrix/fixture.md`, logged in `docs/paste-matrix/results.md`. Name the Tier 1 targets as pending until the user confirms.
