---
name: log-ci-error
description: Analyze CI failure and record prevention rules to memory
---

When a CI failure occurs on a PR, use this skill to automatically:
1. Fetch the failure logs from GitHub
2. Analyze the root cause and pattern
3. Record prevention guidance to memory

## Usage

Invoke when you see a `<ci-monitor-event>` indicating CI failure.

## What it does

1. **Fetch**: Gets failed check details and logs using `gh` CLI
2. **Analyze**: Extracts root cause, category, trigger, and prevention rule
3. **Record**: Saves to memory at `C:\Users\Lenovo\.claude\projects\D-----medcue\memory\feedback_ci_*.md`

## Parameters

When invoking via Skill tool, pass the PR number:
```
Skill(skill: "log-ci-error", args: "73")
```

Or use the Workflow directly with args:
```javascript
Workflow(
  name: "ci-error-logger",
  args: {
    prNumber: 73,
    repoOwner: "Gavin8233841",  // optional, defaults to Gavin8233841
    repoName: "medcue-ios"      // optional, defaults to medcue-ios
  }
)
```

## Output

The workflow creates memory files like:
- `feedback_ci_trailing-whitespace.md`
- `feedback_ci_source-package-allowlist.md`
- `feedback_ci_build-error.md`

Each file contains:
- Root cause description
- Why it happened (trigger)
- How to prevent it (actionable rule)

## Example Memory Entry

```markdown
---
name: ci-source-package-allowlist
description: CI failure: source-package-allowlist
metadata:
  type: feedback
---

Files outside the approved source-package allowlist cause CI to fail.

**Why:** The `.claude/plans/` directory is not in ALLOWED_PREFIXES in `tools/build-source-package.py`.

**How to apply:**
1. Only commit files in allowed paths: .github/, docs/, ios-app/, swift-core/, tools/, etc.
2. Check ALLOWED_PREFIXES before adding new directories
3. Use `git diff --name-only` to preview files before committing
4. Work files like plans should stay local or go in docs/
```
