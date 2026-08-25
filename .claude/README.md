# Claude Code Configuration

This directory contains workflows and skills for automated development tasks.

## Workflows

### ci-error-logger

Automatically analyzes CI failures and records prevention rules to memory.

**Usage:**
```javascript
Workflow(
  name: "ci-error-logger",
  args: { prNumber: 73 }
)
```

**What it does:**
1. Fetches failure logs from GitHub
2. Analyzes root cause and patterns
3. Records prevention guidance to memory

## Skills

### log-ci-error

Convenience skill wrapper for the ci-error-logger workflow.

**Usage:**
```
Skill(skill: "log-ci-error", args: "73")
```

## Memory System

CI error patterns are recorded to:
```
C:\Users\Lenovo\.claude\projects\D-----medcue\memory\feedback_ci_*.md
```

Each memory file contains:
- Root cause description
- Why it happened (trigger)
- How to prevent it (actionable rule)

### Example Categories

- `feedback_ci_trailing-whitespace.md` - Line ending whitespace issues
- `feedback_ci_source-package-allowlist.md` - Disallowed file paths
- `feedback_ci_build-error.md` - Compilation failures
- `feedback_ci_test-failure.md` - Test failures
- `feedback_ci_xcode-project.md` - Xcode project file issues
