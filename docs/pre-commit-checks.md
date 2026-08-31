# MedCue staged pre-commit checks

This is a small, reviewable local guard for changes staged in Git. It does not
rewrite source files and it does not replace the native verification workflow.

## Install and verify

From the repository root:

```bash
bash tools/install-hooks.sh
bash tools/test-pre-commit-system.sh
```

After installation, a normal `git commit` runs
`tools/run-pre-commit-checks.sh` automatically.

The installer honors Git's configured relative or absolute `core.hooksPath`.
An empty path or a path that resolves to the repository root is rejected so a
disabled configuration cannot cause a root-level `pre-commit` file to be
created. `tools/install-hooks.sh --check` is read-only and can be run from any
current working directory. A linked worktree using any path inside the common
`.git` directory is also rejected; configure a worktree-specific
`core.hooksPath` outside that directory to avoid changing hooks for sibling
worktrees. Existing symbolic-link components in the configured hooks path are
rejected before the installer creates or verifies a hook.

## Checks

- The checker disables external diff and text-conversion drivers while reading
  the index and forces text output for its added-line scan, so local Git
  configuration cannot replace staged blob content or hide it as binary.
- `git diff --cached --check` blocks trailing whitespace and malformed staged
  patches.
- Added staged lines are checked for common local-machine path roots and
  Windows drive paths. Use `<PROJECT_ROOT>` or another sanitized placeholder
  in committed examples. The tracked configuration stores symbolic rule IDs so
  the policy itself does not contain a machine path.
- Staged paths must remain inside the repository's checked-in source-package
  allowlist. The checked-in policy is cross-checked against the exact
  `tools/build-source-package.py` source-package policy, so drift fails the
  local check instead of silently changing the release boundary.
- `syntaxExtensions` must keep at least one supported extension enabled
  (`.js`, `.mjs`, `.cjs`, or `.json`); staged files are parsed with Node.js
  only when their exact extension is enabled by that list.

The checker only reads the index. It never runs a repository-wide formatter or
bulk `sed` rewrite, so unrelated user changes remain untouched.

The installed hook executes the staged checker blob from the Git index. The
checker then reads policy, source-package allowlist, staged paths, and staged
file contents from that same index. The local hook is a fast-fail convenience
guard, not trusted release evidence; the reviewed GitHub workflow and native
verification remain authoritative.

## What this does not decide

The hook does not force a Git author identity, pull or switch branches, create a
commit message, or prove Swift compilation. Those are governed by the active
Issue/branch workflow and the relevant CI lane. The current GitHub workflow
already performs its own whitespace, JavaScript/JSON, source-package, and native
verification checks; this local guard is intended to fail faster before a push.

`tools/add-check.sh` and a duplicate `quick-syntax` GitHub job are intentionally
not included in this first version. New trusted checks should be added through a
reviewed change to the JSON policy, checker, tests, and the relevant CI lane.
