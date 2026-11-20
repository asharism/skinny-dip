---
name: fanout-issues
description: Fan out ready-for-agent GitHub issues to parallel worktree subagents, then integrate and hand back PRs with a merge order. Use when asked to "fan out agents", "fanout subagents", "implement all the ready-for-agent issues", or "give me PRs and merge order".
---

# Fan out issues

One subagent per independent issue, one PR each, all based on `main`. You never merge; the user does.

## 1. Gather

1. `gh issue list --label ready-for-agent --state open`, then `gh issue view <n> --json number,title,body,labels,comments` for each.
2. Find **dependencies**. An issue that blocks others ships first and alone: its PR must be **merged to main** before any dependent starts. Spawn only the foundation, wait, and fan out the rest after the user says "merged".
3. Find **file overlap**. Issues touching the same files either serialize or get a noted likely conflict (and who rebases) for the hand-back.

Done when every issue is classed as foundation, independent, or dependent, with its likely files listed.

## 2. Spawn

Send all independent issues in ONE message: one `Agent` per issue, `isolation: "worktree"`, `model` as the user asks (e.g. `sonnet`). Give each this brief, filled in:

```
Implement GitHub issue #<n> in asharism/skinny-dip. Issue body:
<body>

- Branch `feat/<n>-<slug>` from current `origin/main`.
- PR base is ALWAYS `main`: `gh pr create --base main`. Never base a PR on another feature branch.
- TDD per AGENTS.md: write failing tests first, then code until green.
- Build and test only with `-derivedDataPath .build/agent PRODUCT_BUNDLE_IDENTIFIER=com.hitesh.SkinnyDipAgent` (AGENTS.md Commands). Never use the user's bundle ID.
- Editor changes: also run the `-only-testing:SkinnyDipTests/NativeEditorTests` command from AGENTS.md.
- After adding or moving files, edit `project.yml` (never the generated project) and run `xcodegen generate`.
- If a `drive-app` skill or `scripts/drive.sh` exists, verify the change in the running app with it.
- PR body: `Closes #<n>`, a short summary, and a list of every choice that goes beyond the issue.
- Do not merge. Report the PR URL, what you verified, and what you could not verify in the running app.
```

Why base is always `main`: six PRs once targeted a foundation branch. The foundation merged to main first, the six then merged into the dead branch and never reached main, which cost a roll-up PR.

## 3. Wait

Do not poll. You are notified when each agent finishes.

## 4. Integrate

After all PRs are up, in a temporary local branch from `origin/main`: merge every PR branch, then run both full suites from AGENTS.md (`swift test --package-path Packages/MarkdownCore` and `xcodebuild test` under the agent bundle ID). Report merge conflicts and interaction failures per PR. Delete the temporary branch afterwards.

Done when both suites ran on the combined result, or a conflict is named.

## 5. Hand back

Give the user:

- A table: PR, issue, one-line summary.
- A merge order: dependencies first, then smallest and most isolated first. Say which PRs will conflict and who rebases.
- Choices that go beyond the issues.
- What was not verified in the running app.

## 6. Clean up

After the merges, run `git worktree remove <path>` for each agent worktree, delete merged local branches, then `git worktree prune`.

When the user says "merged", confirm every PR's work reached main: `gh pr view <n> --json baseRefName,state` shows `baseRefName` `main` and `state` `MERGED`. Any PR merged into another branch needs a roll-up PR to `main`.
