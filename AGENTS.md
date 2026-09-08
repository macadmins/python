# Repository agent instructions

## Project

This repository builds an Apple Silicon (arm64) Python framework installed at
`/Library/ManagedFrameworks/Python/Python3.framework`. Read `README.md` before
changing build or installation behavior.

- `build_python_framework_pkgs.zsh`: framework build, packaging, signing, and notarization.
- `managed_python_sitecustomize.py`: managed Python runtime customization.
- `requirements_recommended.txt`: bundled third-party dependencies.
- `preinstall-cleanup`: removal of the previous framework during installation.
- `.github/workflows/`: version-specific builds and notarization diagnostics.
- `docs/superpowers/`: existing design and implementation documents.

## Validation

For build-script edits, run:

```sh
zsh -n build_python_framework_pkgs.zsh
```

For workflow edits, parse the affected YAML using an available YAML parser. The
Claude configuration records this check for the notarization workflow (requires
PyYAML):

```sh
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/notary_log.yml'))"
```

Full builds require an Apple Silicon Mac. See `README.md` for build arguments and
signing requirements. Keep generated packages, build outputs, and signing
credentials out of version control.

## Agent collaboration

Default to visible, steerable agent teams for non-trivial parallel work, especially
cross-cutting research, multi-perspective reviews, and multi-module features.
Use subagents only for focused, fire-and-forget work where the consolidated result
is sufficient. If agent teams are unavailable, explicitly tell Erik and ask him
to verify availability before falling back to subagents.

When executing a prepared plan, use `superpowers:subagent-driven-development`.
Use inline plan execution only when explicitly requested.

## Claude configuration migration

The source configuration is `.claude/settings.local.json`. It contains a local
permission allowlist, with no agent definitions or `CLAUDE.md` instructions.
See `.agents/README.md` for its documented intent. These Markdown files do not
configure Codex sandbox permissions or grant authorization for external actions.
