# Agent configuration

Repository-wide instructions live in [`AGENTS.md`](../AGENTS.md).

This folder documents the migration from `.claude/settings.local.json`. There
were no Claude agent definitions to copy. Add task-specific agent guidance here
when needed and reference it from the root instructions.

## Existing Claude settings

The Claude local permission allowlist covers:

- Fetching content from `www.python.org`.
- Staging files with `git add` and a specific `git commit -m` command pattern.
- Running zsh argument-parsing diagnostics with `set -eu` and printing exit codes.
- Calling the GitHub API through `gh api`.
- Fetching PyPI package metadata with `curl` (the recorded URL contains the
  placeholder `__TRACKED_VAR__`).
- Parsing `.github/workflows/notary_log.yml` with Python and PyYAML.
- Checking build-script syntax with `zsh -n build_python_framework_pkgs.zsh`.

The original JSON remains unchanged and is the source for exact Claude command
patterns. This document summarizes those patterns; it does not install equivalent
Codex permission rules. Follow the active runtime permissions and the user's
authorization for the current task.
