---
name: ship-changes-workflow
description: Package and ship already-made code changes through branch, commit, push, manifests, version bump, changelog, pull request, code review notification, and Jira tracking. Use when the user asks to ship existing staged or unstaged work.
---

# Ship Changes Workflow

Use this when the user has already made changes and wants them packaged and shipped end to end:

`branch -> commit -> push -> manifests -> version bump -> changelog -> PR -> CR notification -> Jira`

Keep the workflow project-agnostic. Do not hardcode repository names, Slack channels, Jira projects, manifest commands, or version files unless the user or local repo configuration provides them.

## Required Variables

Resolve these from the repo, user input, environment, or team config before acting:

- `REPO_REMOTE`: Git remote to push to, usually `origin`.
- `BASE_BRANCHES`: protected/default branches, usually `main`, `master`, `develop`, or `dev`.
- `BRANCH_PREFIX`: `fix/`, `feat/`, `chore/`, or another local convention.
- `VERSION_FILE`: version source, for example `pyproject.toml`, `package.json`, `VERSION`, or another release file.
- `CHANGELOG_FILE`: changelog path, usually `CHANGELOG.md`.
- `MANIFEST_RULES`: mapping from changed paths to regeneration commands and generated files.
- `PR_CREATE_COMMAND`: provider-specific command for creating a PR or merge request.
- `CR_CHANNEL_ID`: chat channel ID for code review requests.
- `CR_CHANNEL_NAME`: chat channel display name.
- `JIRA_PROJECT_KEY`: Jira project key to use when creating an issue, if needed.
- `JIRA_DEFAULT_ISSUE_TYPE`: usually `Task`, `Bug`, or `Story`.
- `JIRA_REVIEW_STATUS`: status to move linked issues into, if appropriate.

## Link Formatting

Use the destination platform's native link syntax.

For Slack messages, use Slack mrkdwn links only:

```text
<URL|display text>
```

Never use Markdown links in Slack messages:

```text
[display text](URL)
```

For Jira comments, plain URLs are acceptable unless the team's Jira renderer requires another format.

## Step 1: Understand The Changes

Run:

```bash
git status
git diff
git diff --staged
git branch --show-current
```

Identify:

- Files changed, staged and unstaged.
- Whether the changes are a fix, feature, chore, or docs-only update.
- A concise scope for commit and PR titles.
- Which project areas were modified.
- Whether any generated manifests, lockfiles, schemas, docs, or build artifacts must be regenerated.
- Whether a Jira issue key is already present in the branch name, commit messages, user prompt, or changed files.

Summarize the changes privately before committing. Use that summary for the commit message, changelog, PR body, chat notification, and Jira comment.

## Step 2: Create A Branch If Needed

If the current branch is one of `BASE_BRANCHES`, create a short descriptive branch:

```bash
git checkout -b <branch-prefix>/<short-description>
```

Branch naming guidance:

- Use `fix/` for bug fixes.
- Use `feat/` for features or non-breaking enhancements.
- Use `chore/` for maintenance-only changes.
- Use kebab-case.
- Include the Jira issue key only if that is the team's convention.

If already on a feature/fix/chore branch, keep it.

## Step 3: Commit And Push User Changes

Stage only relevant files. Avoid `git add .` unless the repo is clean and every change is clearly part of the shipment.

```bash
git add <specific-files>
git commit -m "<type>(<scope>): <short description>"
git push -u <repo-remote> <branch-name>
```

Commit message guidance:

- `fix(scope): short description`
- `feat(scope): short description`
- `chore(scope): short description`
- `docs(scope): short description`

Choose the scope from the changed area, package, service, data project, or domain. Keep it short.

## Step 4: Regenerate Manifests If Needed

Use `MANIFEST_RULES` to regenerate only affected manifests. Example structure:

```text
changed path prefix -> command -> generated files
path/to/project_a/ -> make generate-project-a-manifest -> path/to/manifest_a.json
path/to/project_b/ -> make generate-project-b-manifest -> path/to/manifest_b.json
```

For each affected project:

```bash
<manifest-generation-command>
git add <generated-manifest-files>
git commit -m "chore: regenerate manifests"
git push
```

Skip this step if no manifest-generating project files changed.

## Step 5: Bump Version And Update Changelog

Read the current version from `VERSION_FILE`.

Version bump rules:

- Patch: bug fixes, small maintenance changes, manifest-only updates.
- Minor: new non-breaking features or enhancements.
- Major: breaking changes.

Update `VERSION_FILE` to the new version.

Add a changelog entry at the top of `CHANGELOG_FILE`, below the title/header:

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Fix

- Short description of what changed and why.
```

Use `### Feat`, `### Chore`, or `### Docs` when more appropriate.

Commit and push:

```bash
git add <version-file> <changelog-file>
git commit -m "chore: bump version to X.Y.Z and update changelog"
git push
```

## Step 6: Create The PR

Use the repository's configured PR tool. For GitHub CLI, the command is:

```bash
gh pr create \
  --title "<type>(<scope>): <short description>" \
  --body "<body>"
```

PR body template:

```markdown
## Summary

- What changed.
- Why it was needed.
- What it affects.

## Test plan

- [ ] Specific verification step.
- [ ] Another relevant check.

Jira: ISSUE-123
```

Include the Jira line only when an issue exists.

Capture:

- PR URL.
- PR number.
- Branch name.
- Final version.

## Step 7: Send Code Review Notification

Send a short CR request to `CR_CHANNEL_ID`.

For Slack, every link must use mrkdwn angle-bracket format:

```text
:rocket: *PR ready for CR* - <PR_URL|View PR #NNN>

*What changed:* One-line summary.

*Why:* One-line root cause or motivation.

:point_right: <PR_URL|Review>
```

Keep it short. Avoid bare URLs. Avoid Markdown links.

If the team uses a chat system other than Slack, adapt link syntax to that provider.

## Step 8: Update Jira

If the user mentioned a Jira issue key or URL:

1. Add a comment:

```text
PR ready for code review: PR_URL

One-line summary of what changed and why.
```

2. Move the issue to `JIRA_REVIEW_STATUS` only when that matches the team's workflow and the transition is available.

If no Jira issue was mentioned:

Ask the user whether to create a Jira issue, link an existing issue, or skip Jira.

If creating a Jira issue:

- Project: `JIRA_PROJECT_KEY`.
- Issue type: `JIRA_DEFAULT_ISSUE_TYPE`.
- Summary: derived from the PR title.
- Description: brief summary, impact, and PR URL.

After creating it, comment with the PR URL and, if useful, update the PR body to reference the new issue.

## Final Response

After all steps complete, report:

```text
Done. Here's what was shipped:

- Branch: `branch-name`
- PR: PR_URL
- Version: X.Y.Z
- CR notification: sent to #channel-name
- Jira: commented on ISSUE-123 / created ISSUE-123 / skipped
```

If any step could not be completed, state exactly what was done, what is blocked, and the next command or action needed.
