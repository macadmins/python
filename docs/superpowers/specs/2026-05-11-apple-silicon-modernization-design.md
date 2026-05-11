# Apple Silicon Modernization — Design

**Date:** 2026-05-11
**Author:** Erik Gomez
**Status:** Draft

## Summary

Modernize the macadmins Python framework build pipeline by:

1. Refactoring `build_python_framework_pkgs.zsh` to drop universal2 enforcement, run natively on Apple Silicon, and trim to a single build type (`recommended`).
2. Bumping all upstream dependencies — `relocatable-python`, `munki-pkg`, Python interpreter patches, and Python package pins — and adding Python 3.14 as a supported branch.

CI/CD overhaul (Phase 3) is **deferred to a follow-up spec**; this work targets local-only changes plus the requirement and version updates that ride on top of them.

## Background

`build_python_framework_pkgs.zsh` produces a relocatable `Python3.framework` installed under `/Library/ManagedFrameworks/Python/`, packaged via `munki-pkg`, signed, notarized, and shipped as a `.pkg`. It is consumed by Munki 6, Autopkg, InstallApplications, Nudge, and similar fleet tools.

Today the script:

- Requires an Intel build host. Lines 200–223 enumerate every `.dylib` and `.so` under the built framework and fail the build unless each contains two architectures. This forces `--no-binary` on `cffi`, `charset-normalizer`, `PyYAML`, `tomli`, `xattr`, and `black` in `requirements_recommended.txt` so wheels are compiled fat instead of installed pre-built.
- Supports three build types (`minimal`, `no_customization`, `recommended`) but CI only builds `recommended`.
- Pins `relocatable-python` to `fb4dd9b…` and `munki-pkg` to `96cffb4e…`, both stale.
- Hardcodes `Xcode_15.2.app` and `macos-13` (Intel) GitHub runners.
- Carries a latent path bug in the ad-hoc codesign branch (`build_python_framework_pkgs.zsh:241` — missing `/` between `${FRAMEWORKDIR}` and `Python3.framework`).

The team is shipping macOS deployments to Apple Silicon hardware; the universal2 contract is no longer worth the build-host constraints, the `--no-binary` slowdowns, or the maintenance surface.

## Goals

- Build cleanly from an Apple Silicon Mac with no Intel host required.
- Use pre-built arm64 wheels from PyPI.
- Single supported build flavor (`recommended`); delete the other two.
- Current upstream SHAs and Python patch versions.
- Add Python 3.14 to the supported set.
- One last release of Python 3.9 and 3.10, then retire them.
- Script is readable, factored into clear functions, and easy to invoke locally without simulating a CI environment.

## Non-Goals

- CI/CD changes (workflow consolidation, action bumps, runner migration, release trigger changes). Deferred to Phase 3.
- Compiling CPython from source for EOL branches. 3.9 / 3.10 final releases continue to use python.org's last published `.pkg` (`3.9.13` / `3.10.11`).
- Changing the install location, package identifier, or signing identity.
- Producing an explicitly arm64-thinned framework via `lipo`. The python.org base remains universal2; arm64-only wheels make the *added* content single-arch. We do not strip x86_64 slices from upstream binaries.

## Phase 1 — Script Refactor

### Script signature

Current:

```
build_python_framework_pkgs.zsh <TYPE> <INSTALLER_ID> <APPLICATION_ID> <PYTHON_VERSION> <PYTHON_MAJOR_VERSION> <NOTARY_PASSWORD>
```

New (positional args dropped in favor of long flags for clarity; major version derived from full version):

```
build_python_framework_pkgs.zsh \
  --python-version 3.13.13 \
  [--installer-id "Developer ID Installer: ..."] \
  [--application-id "Developer ID Application: ..."] \
  [--notary-password "$NOTARY_APP_PASSWORD"] \
  [--xcode-path /Applications/Xcode_16.x.app]
```

When `--installer-id` / `--application-id` are omitted, the script falls back to ad-hoc signing and does not produce a signed `.pkg`. When `--notary-password` is omitted, notarization is skipped. This makes local invocation `./build_python_framework_pkgs.zsh --python-version 3.13.13` and nothing more.

### Behavioral changes

1. **Drop the universal2 validation block.** Remove the `find … "2 architectures"` checks for `.dylib` and `.so` files.
2. **Drop `--no-binary` markers** in `requirements_recommended.txt` for `black`, `cffi`, `charset-normalizer`, `PyYAML`, `tomli`, `xattr`.
3. **Guard CI-only steps.** The `brew remove --force …` and the `sudo xcode-select -s "$XCODE_PATH"` calls run only when `$CI` or `$GITHUB_ACTIONS` is set. Locally they're no-ops.
4. **Parametrize Xcode path.** `--xcode-path` (or `XCODE_PATH` env var) replaces the `Xcode_15.2.app` hardcode. Default to `xcode-select -p`'s active developer dir when not specified.
5. **Collapse per-version symlink block.** The five identical `if [[ "${PYTHON_MAJOR_VERSION}" == "3.x" ]]` blocks at lines 144–158 become a single unconditional `ln -s`.
6. **Single build type.** Delete the `minimal` / `no_customization` branches. `TYPE` becomes an internal constant (`recommended`) used for path naming only.
7. **Fix the codesign path bug** at line 241.
8. **Bump pinned SHAs:**
   - `RP_SHA` → `8ee72fe3a5dbef733365370ebf44f25022b895ef`
   - `MP_SHA` → `bbd07730d1b93ed3828246575ef5676bba74b5d1`

### Refactor for readability

Pull discrete steps into named functions so the top-level script reads as a sequence of intents rather than a wall of inline shell:

- `parse_args` — long-flag parsing, validation, defaults.
- `prepare_build_dirs` — framework dir setup, payload skeleton.
- `download_tool <name> <sha> <url> <dest>` — generic curl-and-unzip used for both `relocatable-python` and `munki-pkg`.
- `build_framework` — runs `make_relocatable_python_framework.py`.
- `codesign_framework` — single implementation that takes the identity (or `-` for ad-hoc) as an argument, replacing the duplicate signed-vs-ad-hoc branches.
- `build_pkg` — emits `build-info.json`, runs `munkipkg`.
- `notarize_and_staple` — runs only when notary credentials are present.
- `zip_framework` — emits the standalone framework zip.
- `cleanup` — removes temp dirs.

Use `set -eu` (zsh equivalent) at the top of the script so a step failure short-circuits the run instead of relying on per-step exit-code checks.

### Files removed

- `requirements_minimal.txt`
- `requirements_no_customization.txt` (empty)
- `requirement_files/requirements_minimal.txt`
- `requirement_files/requirements_opinionated.txt` (no longer referenced)
- `build_all_python_frameworks.zsh` (only purpose was to invoke all three build types)

### Files updated

- `build_python_framework_pkgs.zsh` — full refactor per above.
- `requirements_recommended.txt` — drop `--no-binary` markers.
- `README.md` — drop the "Flavors of Python", "No Customization", "Minimal" sections; drop the "build on an Intel macOS device" note; update interactive-use snippet for Apple Silicon.
- `requirement_files/requirements_recommended.txt` — remains as the human-curated source for which package families are included (no behavior change in Phase 1).

### Local validation steps

After the refactor:

1. `./build_python_framework_pkgs.zsh --python-version 3.13.13` on the Apple Silicon Mac. Expect: an unsigned framework zip in `outputs/`, no signed `.pkg`.
2. Manually install the framework to `/Library/ManagedFrameworks/Python/Python3.framework` and smoke-test:
   - `managed_python3 --version` reports `3.13.13`.
   - `managed_python3 -c "import objc; import xattr; import requests; print('ok')"` succeeds.
   - `managed_python3 -c "import platform; print(platform.machine())"` prints `arm64`.
3. Repeat for `--python-version 3.14.5`.

## Phase 2 — Dependency and Version Bumps

### Python interpreter versions

| Branch | Old | New | Notes |
|---|---|---|---|
| 3.9  | 3.9.13  | 3.9.13  | Final release. No upstream `.pkg` past this. |
| 3.10 | 3.10.11 | 3.10.11 | Final release. No upstream `.pkg` past this. |
| 3.11 | 3.11.7  | 3.11.9  | |
| 3.12 | 3.12.1  | 3.12.10 | |
| 3.13 | 3.13.5  | 3.13.13 | |
| 3.14 | — | 3.14.5  | New supported branch. |

### Python package pin sweep

For each pinned package in `requirements_recommended.txt`:

1. Check if a newer release exists on PyPI.
2. Verify an `arm64` macOS wheel exists for **every** supported Python branch (3.9–3.14). If a version lacks a wheel for 3.9 / 3.10 (likely for newer pyobjc, cffi, etc.), pin a per-branch override or hold the package at the last version that supports all branches. Document the holdback inline.
3. The packages most likely to need attention: `pyobjc` (currently 11.1; check arm64 wheel coverage for 3.14), `cffi`, `xattr`, `cryptography` if pulled transitively.

### 3.9 / 3.10 final-release release notes

Each gets a one-time release, kicked off manually via `workflow_dispatch` (no CI restructuring needed for this in Phase 2), with:

- Updated package pins (from the sweep above).
- Release-notes call-out: "**This is the final release of the Python <X.Y> framework. Future updates will target 3.11 and newer. Plan your migration.**"

The workflow files themselves (`build_python_3.9.yml`, `build_python_3.10.yml`) stay in place during Phase 2 so the final builds can run. They are moved to `.github/workflows/archived/` as part of Phase 3.

### 3.14 enablement

`.github/workflows/build_python_3.14.yml` is added as a near-copy of `build_python_3.13.yml`, parametrized for 3.14.5. The file lives alongside the existing per-version workflows; consolidation happens in Phase 3.

### Dependency-update tooling

- **Dependabot for GitHub Actions:** enable in `.github/dependabot.yml`. Low noise; catches stale `apple-actions/import-codesign-certs`, `actions/checkout`, etc. without us thinking about it.
- **Pip pins:** keep manual. We want intentional bumps with smoke testing, not auto-merged churn.

## Deferred to Phase 3

Captured here for context — not in scope for this spec:

- Consolidate the five per-version workflows into one reusable workflow + thin callers.
- Migrate runner from `macos-13` (Intel) → `macos-14` (Apple Silicon).
- Bump action versions: `actions/checkout@v3 → v5`, `softprops/action-gh-release@v0.1.15 → v2`, `actions/upload-artifact@v4.6.2 → latest v4`, `apple-actions/import-codesign-certs → latest`, `metcalfc/changelog-generator → latest` (or replace with a `gh api` shell step).
- Switch release trigger from `pull_request` (currently cuts a prerelease per PR) to `push` on a release tag plus `workflow_dispatch`. PR runs build artifacts but don't publish releases.
- Archive `build_python_3.9.yml` and `build_python_3.10.yml`.

## Risks and Open Questions

- **arm64 wheel coverage for 3.9 / 3.10.** Older Pythons may not have arm64 wheels for the newest pin of every package. Mitigation: per-branch pin overrides, or hold the package at a known-good version. The pin sweep in Phase 2 will surface this.
- **First arm64 build may expose latent assumptions** in `relocatable-python`. The pinned-SHA bump pulls in a year+ of upstream changes; we may need to file/patch downstream issues. Mitigation: local validation gate before merging.
- **3.9 / 3.10 final builds depend on the new script working with old Python branches.** The bumped `relocatable-python` should still accept the older `--python-version` values, but it's a small contract worth verifying as part of local validation.

## Acceptance Criteria

Phase 1 is done when:

- `./build_python_framework_pkgs.zsh --python-version 3.13.13` succeeds end-to-end on an Apple Silicon Mac with no `sudo` other than the existing `mkdir`/`chown` steps and produces an installable framework zip.
- The resulting `managed_python3` runs `import objc; import xattr; import requests` on Apple Silicon.
- `git grep -- '--no-binary'` returns no matches in `requirements_recommended.txt`.
- `minimal` / `no_customization` are gone from the repo and README.

Phase 2 is done when:

- All non-EOL workflows pin the patch versions in the table above.
- `build_python_3.14.yml` exists and runs green end-to-end.
- 3.9.13 and 3.10.11 each have one final release published with "final release" notes.
- `.github/dependabot.yml` is enabled for GitHub Actions.
