# Apple Silicon Modernization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor `build_python_framework_pkgs.zsh` to run natively on Apple Silicon without universal2 enforcement, trim to a single build flavor, bump upstream SHAs and Python interpreter versions, add Python 3.14, and cut a final release for the EOL 3.9 and 3.10 branches.

**Architecture:** The build script is reorganized into named functions (`parse_args`, `prepare_build_dirs`, `download_tool`, `build_framework`, `codesign_framework`, `build_pkg`, `notarize_and_staple`, `zip_framework`, `cleanup`) with `set -eu` short-circuiting on failure. Long-flag arguments replace positional ones, with the major Python version derived from the full version. CI-only steps (Homebrew nuke, `xcode-select`) are gated behind `$CI` / `$GITHUB_ACTIONS`. The universal2 dylib/so audit is deleted; arm64 wheels from PyPI are used directly.

**Tech Stack:** zsh, `relocatable-python`, `munki-pkg`, `codesign`, `notarytool`, GitHub Actions, Python 3.9 – 3.14.

---

## File Structure

**Modified files:**
- `build_python_framework_pkgs.zsh` — full rewrite into functions; drops universal check, ad-hoc/signed codesign duplication, per-version symlink branches, and CI-environment hardcodes. Bumps `RP_SHA` and `MP_SHA`.
- `requirements_recommended.txt` — drop `--no-binary` directives for `black`, `cffi`, `charset-normalizer`, `PyYAML`, `tomli`, `xattr`. Bump package pins where newer versions have arm64 wheels across all supported branches.
- `README.md` — drop "Flavors of Python", "Minimal", "No Customization", and "build on Intel macOS" sections; update examples for Apple Silicon.
- `.github/workflows/build_python_3.11.yml` — bump `PYTHON_VERSION` to `3.11.9`.
- `.github/workflows/build_python_3.12.yml` — bump `PYTHON_VERSION` to `3.12.10`.
- `.github/workflows/build_python_3.13.yml` — bump `PYTHON_VERSION` to `3.13.13`.
- `.github/workflows/build_python_3.9.yml` — augment release notes to mark final release; leave Python version at `3.9.13`.
- `.github/workflows/build_python_3.10.yml` — augment release notes to mark final release; leave Python version at `3.10.11`.

**Created files:**
- `.github/workflows/build_python_3.14.yml` — new workflow for Python 3.14.5 (cloned and adapted from 3.13).
- `.github/dependabot.yml` — Dependabot config for GitHub Actions only (no pip).

**Deleted files:**
- `requirements_minimal.txt`
- `requirements_no_customization.txt`
- `requirement_files/requirements_minimal.txt`
- `requirement_files/requirements_opinionated.txt`
- `build_all_python_frameworks.zsh`

---

## Task 1: Rewrite `build_python_framework_pkgs.zsh`

**Files:**
- Modify: `build_python_framework_pkgs.zsh` (full rewrite)

- [ ] **Step 1: Replace the entire file contents**

Replace the file with this content verbatim:

```zsh
#!/bin/zsh
#
# Build the macadmins Python 3 framework.
# Produces an installable .pkg (when signing identities are supplied) and a
# portable framework zip targeting Apple Silicon.
#
# Adapted from https://github.com/munki/munki/blob/Munki3dev/code/tools/build_python_framework.sh

set -eu

# --- Pinned upstream commits ---
RP_SHA="8ee72fe3a5dbef733365370ebf44f25022b895ef"  # gregneagle/relocatable-python
MP_SHA="bbd07730d1b93ed3828246575ef5676bba74b5d1"  # munki/munki-pkg

# --- Paths and constants ---
TYPE="recommended"
FRAMEWORKDIR="/Library/ManagedFrameworks/Python"
PYTHON_BIN_NEW="$FRAMEWORKDIR/Python3.framework/Versions/Current/Resources/Python.app/Contents/MacOS/Python"
PYTHON_BASEURL="https://www.python.org/ftp/python/%s/python-%s-macos11.pkg"
TOOLSDIR="$(/usr/bin/dirname "$0")"
OUTPUTSDIR="$TOOLSDIR/outputs"
RP_BINDIR="/tmp/relocatable-python"
MP_BINDIR="/tmp/munki-pkg"
RP_ZIP="/tmp/relocatable-python.zip"
MP_ZIP="/tmp/munki-pkg.zip"
CONSOLEUSER="$(/usr/bin/stat -f "%Su" /dev/console)"
PIPCACHEDIR="/Users/${CONSOLEUSER}/Library/Caches/pip"

# --- CLI arguments (set by parse_args) ---
PYTHON_VERSION=""
INSTALLER_ID=""
APPLICATION_ID=""
NOTARY_PASSWORD=""
XCODE_PATH=""

usage() {
    cat <<EOF
Usage: $(/usr/bin/basename "$0") --python-version X.Y.Z [options]

Required:
  --python-version    Full Python version, e.g. 3.13.13

Optional (omit for an unsigned local build):
  --installer-id      Developer ID Installer identity
  --application-id    Developer ID Application identity
  --notary-password   App-specific password for notarytool
  --xcode-path        Path to Xcode.app (CI only)
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --python-version)   PYTHON_VERSION="$2";   shift 2 ;;
            --installer-id)     INSTALLER_ID="$2";     shift 2 ;;
            --application-id)   APPLICATION_ID="$2";   shift 2 ;;
            --notary-password)  NOTARY_PASSWORD="$2";  shift 2 ;;
            --xcode-path)       XCODE_PATH="$2";       shift 2 ;;
            -h|--help)          usage; exit 0 ;;
            *)                  echo "Unknown argument: $1" >&2; usage; exit 1 ;;
        esac
    done

    if [[ -z "$PYTHON_VERSION" ]]; then
        echo "error: --python-version is required" >&2
        usage
        exit 1
    fi

    PYTHON_MAJOR_VERSION="${PYTHON_VERSION%.*}"   # 3.13.13 -> 3.13
    PYTHON_BIN_VERSION="$PYTHON_MAJOR_VERSION"
}

is_ci() {
    [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" ]]
}

derive_build_version() {
    local rev_count
    rev_count="$(/usr/bin/git -C "$TOOLSDIR" rev-list --count HEAD)"
    NEWSUBBUILD=$((80620 + rev_count))
    AUTOMATED_PYTHON_BUILD="$PYTHON_VERSION.$NEWSUBBUILD"
    echo "$AUTOMATED_PYTHON_BUILD" > "$TOOLSDIR/build_info.txt"
    echo "Build version: $AUTOMATED_PYTHON_BUILD"
}

prepare_ci_env() {
    if ! is_ci; then
        return
    fi
    echo "CI detected — clearing Homebrew and selecting Xcode."
    /usr/local/bin/brew remove --force "$(/usr/local/bin/brew list)" || true
    if [[ -n "$XCODE_PATH" && -d "$XCODE_PATH" ]]; then
        /usr/bin/sudo /usr/bin/xcode-select -s "$XCODE_PATH"
    fi
}

prepare_build_dirs() {
    /usr/bin/sudo /bin/mkdir -m 777 -p "$FRAMEWORKDIR"
    if [[ -d "$FRAMEWORKDIR/Python.framework" ]]; then
        /usr/bin/sudo /bin/rm -rf "$FRAMEWORKDIR/Python.framework"
    fi
    if [[ -d "$PIPCACHEDIR" ]]; then
        echo "Removing pip cache to reduce build errors"
        /usr/bin/sudo /bin/rm -rf "$PIPCACHEDIR"
    fi

    /bin/rm -rf "$TOOLSDIR/$TYPE"
    /bin/mkdir -p "$TOOLSDIR/$TYPE/scripts"
    /bin/mkdir -p "$TOOLSDIR/$TYPE/payload${FRAMEWORKDIR}"
    /bin/mkdir -p "$TOOLSDIR/$TYPE/payload/usr/local/bin"
    /usr/bin/sudo /usr/sbin/chown -R "${CONSOLEUSER}":wheel "$TOOLSDIR/$TYPE"

    /bin/ln -s "$PYTHON_BIN_NEW" "$TOOLSDIR/$TYPE/payload/usr/local/bin/managed_python3"
}

download_tool() {
    local name="$1" sha="$2" url="$3" zip_path="$4" dest="$5"
    echo "Downloading $name @ $sha"
    /bin/rm -rf "$zip_path" "$dest"
    /usr/bin/curl -fL "$url" -o "$zip_path"
    /usr/bin/unzip -q "$zip_path" -d "$dest"
}

build_framework() {
    export C_INCLUDE_PATH="/Library/ManagedFrameworks/Python/Python.framework/Versions/Current/Headers/"
    local rp_extract="${RP_BINDIR}/relocatable-python-${RP_SHA}"
    "${rp_extract}/make_relocatable_python_framework.py" \
        --baseurl "${PYTHON_BASEURL}" \
        --python-version "${PYTHON_VERSION}" \
        --os-version 11 \
        --upgrade-pip \
        --no-unsign \
        --pip-requirements "${TOOLSDIR}/requirements_${TYPE}.txt" \
        --destination "${FRAMEWORKDIR}"

    /bin/mv "${FRAMEWORKDIR}/Python.framework" \
        "$TOOLSDIR/$TYPE/payload${FRAMEWORKDIR}/Python3.framework"
}

codesign_framework() {
    local identity="${APPLICATION_ID:--}"   # `-` means ad-hoc
    local framework_root="$TOOLSDIR/$TYPE/payload${FRAMEWORKDIR}/Python3.framework"
    local versioned="$framework_root/Versions/${PYTHON_BIN_VERSION}"

    if [[ "$identity" == "-" ]]; then
        echo "Ad-hoc signing framework"
    else
        echo "Signing framework with identity: $identity"
    fi

    local -a cs_args
    if [[ "$identity" == "-" ]]; then
        cs_args=(--preserve-metadata=identifier,entitlements,flags,runtime -f)
    else
        cs_args=(--timestamp --preserve-metadata=identifier,entitlements,flags,runtime -f)
    fi

    /usr/bin/find "$versioned/bin" -type f -perm -u=x -exec \
        /usr/bin/codesign -s "$identity" "${cs_args[@]}" {} \;
    /usr/bin/find "$versioned/lib" -type f -perm -u=x -exec \
        /usr/bin/codesign -s "$identity" "${cs_args[@]}" {} \;
    /usr/bin/find "$versioned/lib" -type f -name "*dylib" -exec \
        /usr/bin/codesign -s "$identity" "${cs_args[@]}" {} \;
    /usr/bin/codesign -s "$identity" --deep "${cs_args[@]}" "$versioned/Resources/Python.app"
    /usr/bin/codesign -s "$identity" "${cs_args[@]}" "$versioned/Python"
    /usr/bin/codesign -s "$identity" "${cs_args[@]}" "$framework_root/Versions/Current/Python"

    /usr/sbin/spctl -a -vvvv "$versioned/Python" || true
}

build_pkg() {
    /bin/mkdir -p "$OUTPUTSDIR"
    /bin/cp "${TOOLSDIR}/preinstall-cleanup" "$TOOLSDIR/$TYPE/scripts/preinstall"

    if [[ -z "$INSTALLER_ID" ]]; then
        echo "No installer identity provided; skipping signed pkg"
        return
    fi

    /bin/cat <<JSON > "$TOOLSDIR/$TYPE/build-info.json"
{
  "ownership": "recommended",
  "suppress_bundle_relocation": true,
  "identifier": "io.macadmins.python.$TYPE",
  "postinstall_action": "none",
  "distribution_style": true,
  "version": "$AUTOMATED_PYTHON_BUILD",
  "name": "python_${TYPE}_signed-$AUTOMATED_PYTHON_BUILD.pkg",
  "install_location": "/",
  "preserve_xattr": true,
  "signing_info": {
    "identity": "$INSTALLER_ID",
    "timestamp": true
  }
}
JSON

    "${MP_BINDIR}/munki-pkg-${MP_SHA}/munkipkg" "$TOOLSDIR/$TYPE"
}

notarize_and_staple() {
    if [[ -z "$NOTARY_PASSWORD" || -z "$INSTALLER_ID" ]]; then
        echo "Skipping notarization (no notary password or installer id)"
        return
    fi
    local xcode_dev xcode_notary xcode_stapler pkg
    xcode_dev="$(/usr/bin/xcode-select -p)"
    xcode_notary="$xcode_dev/usr/bin/notarytool"
    xcode_stapler="$xcode_dev/usr/bin/stapler"
    pkg="$TOOLSDIR/$TYPE/build/python_${TYPE}_signed-$AUTOMATED_PYTHON_BUILD.pkg"

    "$xcode_notary" store-credentials \
        --apple-id "opensource@macadmins.io" \
        --team-id "T4SK8ZXCXG" \
        --password "$NOTARY_PASSWORD" \
        macadminpython
    "$xcode_notary" submit "$pkg" --keychain-profile macadminpython --wait
    "$xcode_stapler" staple "$pkg"
    /bin/mv "$pkg" "$OUTPUTSDIR"
}

zip_framework() {
    local zipfile="Python3.framework_$TYPE-$AUTOMATED_PYTHON_BUILD.zip"
    /usr/bin/ditto -c -k --sequesterRsrc \
        "$TOOLSDIR/$TYPE/payload${FRAMEWORKDIR}/" "$zipfile"
    /bin/mv "$zipfile" "$OUTPUTSDIR"
    /usr/bin/sudo /usr/sbin/chown -R "${CONSOLEUSER}":wheel "$OUTPUTSDIR"
}

cleanup() {
    /usr/bin/sudo /bin/rm -rf "$TOOLSDIR/$TYPE"
    /usr/bin/sudo /bin/rm -rf "$FRAMEWORKDIR"
}

# --- Main ---
parse_args "$@"
echo "Building Python framework — $PYTHON_VERSION"
prepare_ci_env
derive_build_version
prepare_build_dirs
download_tool relocatable-python "$RP_SHA" \
    "https://github.com/gregneagle/relocatable-python/archive/${RP_SHA}.zip" \
    "$RP_ZIP" "$RP_BINDIR"
download_tool munki-pkg "$MP_SHA" \
    "https://github.com/munki/munki-pkg/archive/${MP_SHA}.zip" \
    "$MP_ZIP" "$MP_BINDIR"
build_framework
codesign_framework
build_pkg
notarize_and_staple
zip_framework
cleanup
echo "Done."
```

- [ ] **Step 2: Lint with shellcheck (best-effort)**

Run: `shellcheck -s bash build_python_framework_pkgs.zsh || true`
Expected: any issues are warnings about zsh-only constructs (e.g., `[[ ]]`); resolve real bugs only. shellcheck has limited zsh support — informational only.

- [ ] **Step 3: Verify executable bit**

Run: `ls -l build_python_framework_pkgs.zsh`
Expected: shows `-rwxr-xr-x` (mode 755). If not, run `chmod +x build_python_framework_pkgs.zsh`.

- [ ] **Step 4: Commit**

```bash
git add build_python_framework_pkgs.zsh
git commit -m "Refactor build script for Apple Silicon

- Drop universal2 enforcement; arm64 wheels used directly
- Single 'recommended' flavor; remove minimal/no_customization branches
- Long-flag arguments; derive major version from full version
- Functions: parse_args, prepare_build_dirs, download_tool,
  build_framework, codesign_framework, build_pkg,
  notarize_and_staple, zip_framework, cleanup
- Collapse signed/ad-hoc codesign duplication; fixes latent path bug
- Bump relocatable-python and munki-pkg SHAs
- Gate CI-only steps (brew remove, xcode-select) on \$CI"
```

---

## Task 2: Drop `--no-binary` markers from `requirements_recommended.txt`

**Files:**
- Modify: `requirements_recommended.txt`

- [ ] **Step 1: Remove all `--no-binary` lines**

Replace the file with:

```
asn1crypto==1.5.1
aspy.yaml==1.3.0
attrs==25.3.0
black==25.1.0
certifi==2025.6.15
cffi==1.17.1
cfgv==3.4.0
charset-normalizer==3.4.2
click==8.2.1
distlib==0.3.9
docklib==2.0.0
entrypoints==0.4
filelock==3.18.0
flake8==7.3.0
flake8-bugbear==24.12.12
identify==2.6.12
idna==3.10
isort==6.0.1
mccabe==0.7.0
mypy-extensions==1.1.0
nodeenv==1.9.1
packaging==25.0
pathspec==0.12.1
platformdirs==4.3.8
pre-commit==4.2.0
pycodestyle==2.14.0
pycparser==2.22
pyflakes==3.4.0
pyobjc==11.1
PyYAML==6.0.2
requests==2.32.4
six==1.17.0
tokenize-rt==6.2.0
tomli==2.2.1
urllib3==2.5.0
virtualenv==20.31.2
xattr==1.1.4
```

- [ ] **Step 2: Verify no `--no-binary` remains**

Run: `grep -n -- '--no-binary' requirements_recommended.txt`
Expected: no output (exit code 1 — no matches).

- [ ] **Step 3: Commit**

```bash
git add requirements_recommended.txt
git commit -m "Drop --no-binary directives (use prebuilt arm64 wheels)"
```

---

## Task 3: Delete obsolete build flavors

**Files:**
- Delete: `requirements_minimal.txt`
- Delete: `requirements_no_customization.txt`
- Delete: `requirement_files/requirements_minimal.txt`
- Delete: `requirement_files/requirements_opinionated.txt`
- Delete: `build_all_python_frameworks.zsh`

- [ ] **Step 1: Delete files**

Run:

```bash
git rm requirements_minimal.txt requirements_no_customization.txt \
       requirement_files/requirements_minimal.txt \
       requirement_files/requirements_opinionated.txt \
       build_all_python_frameworks.zsh
```

Expected: 5 files removed (`rm 'requirements_minimal.txt'`, etc.).

- [ ] **Step 2: Verify no remaining references**

Run: `grep -rn 'minimal\|no_customization\|build_all_python_frameworks' --include='*.zsh' --include='*.yml' --include='*.md' .`
Expected: only matches in the design spec (`docs/superpowers/specs/…`) and the deletion-context release notes. If any active script or workflow still references them, fix that reference now.

- [ ] **Step 3: Commit**

```bash
git commit -m "Remove minimal and no_customization build flavors"
```

---

## Task 4: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace the file contents**

Replace `README.md` with:

```markdown
# python
A Python 3 framework that installs to `/Library/ManagedFrameworks/Python/Python3.framework`.

Please see Apple's documentation on [file system basics](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html) for context.

This is an intended replacement for `/usr/bin/python`, which Apple removed in macOS 12.3 (Spring 2022).

## Apple Silicon Only
Builds and packages target Apple Silicon (arm64). Universal2 outputs are no longer produced. Build hosts and target machines must be Apple Silicon Macs.

## Why use this instead of a package from python.org?
- Ships with PyObjC and other modules useful for Mac admins, similar in spirit to the Apple Python it replaces
- Installs to a location less likely to be overwritten, removed, or modified by other Python installations

## Using interactively
After installing the package, `/usr/local/bin/managed_python3` is a symlink to `/Library/ManagedFrameworks/Python/Python3.framework/Versions/Current/Resources/Python.app/Contents/MacOS/Python`.

## Using with scripts
Point your shebang directly at the symlink:

```
#!/Library/ManagedFrameworks/Python/Python3.framework/Versions/Current/bin/python3

print('This is an example script.')
```

### zshenv global alias
For zsh scripts you can add a global alias to `/etc/zshenv`:

`alias -g python3.framework='/Library/ManagedFrameworks/Python/Python3.framework/Versions/Current/bin/python3'`

See Armin Briegel's "Moving to Zsh" Part [II](https://scriptingosx.com/2019/06/moving-to-zsh-part-2-configuration-files/) and [IV](https://scriptingosx.com/2019/07/moving-to-zsh-part-4-aliases-and-functions/).

## Notes
Only a single package may be installed at any given time. The preinstall script removes any previous framework.

### Upgrades
Python itself has its own release cadence; this package will see additional updates as 3rd-party libraries release fixes and security updates. Always test your scripts before deploying broadly.

### Downgrades
Not supported.

### pip
`pip` is bundled but **not recommended** for installing external libraries into the framework. Use a [virtual environment](https://docs.python.org/3/library/venv.html) or a tool like [pyenv](https://github.com/pyenv/pyenv) instead. Pull requests to the `recommended` requirements file are welcome.

# Building locally
Build an unsigned framework on Apple Silicon with:

```
./build_python_framework_pkgs.zsh --python-version 3.13.13
```

Pass `--installer-id`, `--application-id`, and `--notary-password` to produce a signed and notarized `.pkg`.

# Updating packages
Do this in a clean virtual environment. After every Python package install, run `pip freeze | xargs pip uninstall -y` to reset the environment.

# CI Job
To update the signing certificate, run `base64 -i /path/to/certificate.p12 -o base64string` and import it into the GitHub Actions secrets store along with the matching password.

# Credits
Built on two open-source tools by [Greg Neagle](https://www.linkedin.com/in/gregneagle/):
- [relocatable-python](https://github.com/gregneagle/relocatable-python)
- [munki-pkg](https://github.com/munki/munki-pkg)
```

- [ ] **Step 2: Verify no flavor references remain**

Run: `grep -E 'Minimal|No Customization|Flavors of Python|Intel macOS device' README.md`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Update README for Apple Silicon, single-flavor build"
```

---

## Task 5: Local validation — unsigned 3.13.13 build

**Files:** none (validation only)

- [ ] **Step 1: Run unsigned build**

Run: `./build_python_framework_pkgs.zsh --python-version 3.13.13`
Expected:
- Final lines include `Build version: 3.13.13.<N>` and `Done.`
- `outputs/Python3.framework_recommended-3.13.13.<N>.zip` exists.
- No `outputs/*.pkg` (no installer identity passed).
- No error about `2 architectures` (the validation block is gone).

- [ ] **Step 2: Install the framework and smoke-test**

Run:

```bash
sudo rm -rf /Library/ManagedFrameworks/Python/Python3.framework
sudo mkdir -p /Library/ManagedFrameworks/Python
sudo ditto -x -k outputs/Python3.framework_recommended-3.13.13.*.zip /Library/ManagedFrameworks/Python/
sudo ln -sf /Library/ManagedFrameworks/Python/Python3.framework/Versions/Current/Resources/Python.app/Contents/MacOS/Python /usr/local/bin/managed_python3
managed_python3 --version
managed_python3 -c "import platform; print(platform.machine())"
managed_python3 -c "import objc, xattr, requests, yaml; print('ok')"
```

Expected output:
- `Python 3.13.13`
- `arm64`
- `ok`

If `import objc` fails with `Symbol not found` or an architecture mismatch, halt and investigate — the framework is not arm64 compatible.

- [ ] **Step 3: Tear down the test install**

Run: `sudo rm -rf /Library/ManagedFrameworks/Python/Python3.framework /usr/local/bin/managed_python3`
Expected: no output.

- [ ] **Step 4: Record the validation in the spec / plan**

No commit yet — validation is a checkpoint. If steps 1 and 2 passed, mark this task done and move on.

---

## Task 6: Local validation — unsigned 3.14.5 build

**Files:** none (validation only)

- [ ] **Step 1: Run unsigned build**

Run: `./build_python_framework_pkgs.zsh --python-version 3.14.5`
Expected: `Done.` and `outputs/Python3.framework_recommended-3.14.5.<N>.zip` exists.

- [ ] **Step 2: Smoke-test**

Run the same install + smoke-test commands from Task 5 Step 2, substituting `3.14.5` for `3.13.13` in the zip filename.

Expected:
- `Python 3.14.5`
- `arm64`
- `ok`

If any pip package fails to install during step 1 (no arm64 wheel for 3.14), record which package failed and proceed to Task 10 (pin sweep) to address.

- [ ] **Step 3: Tear down the test install**

Run: `sudo rm -rf /Library/ManagedFrameworks/Python/Python3.framework /usr/local/bin/managed_python3`

---

## Task 7: Bump Python patch versions in 3.11 / 3.12 / 3.13 workflows

**Files:**
- Modify: `.github/workflows/build_python_3.11.yml`
- Modify: `.github/workflows/build_python_3.12.yml`
- Modify: `.github/workflows/build_python_3.13.yml`

- [ ] **Step 1: Bump 3.11**

In `.github/workflows/build_python_3.11.yml`, change `PYTHON_VERSION: "3.11.7"` to `PYTHON_VERSION: "3.11.9"`. Also update the release-notes line `- Upgraded Python to 3.11.7` to `- Upgraded Python to 3.11.9`.

- [ ] **Step 2: Bump 3.12**

In `.github/workflows/build_python_3.12.yml`, change `PYTHON_VERSION: "3.12.1"` to `PYTHON_VERSION: "3.12.10"`. Also update the release-notes line `- Upgraded Python to 3.12.1` to `- Upgraded Python to 3.12.10`.

- [ ] **Step 3: Bump 3.13**

In `.github/workflows/build_python_3.13.yml`, change `PYTHON_VERSION: "3.13.5"` to `PYTHON_VERSION: "3.13.13"`. Also update the release-notes line `- Upgraded Python to 3.13.5` to `- Upgraded Python to 3.13.13`.

- [ ] **Step 4: Verify the script argument call still works**

Search each workflow for the `Run build package script` step. Today it reads:

```yaml
run: ./build_python_framework_pkgs.zsh "$TYPE" "$DEV_INSTALLER_ID" "$DEV_APPLICATION_ID" "$PYTHON_VERSION" "$PYTHON_MAJOR_VERSION" "${NOTARY_APP_PASSWORD}"
```

After Task 1 the script no longer accepts positional arguments, so this **will break in CI**. Phase 3 will rewrite the workflows, but to keep CI green for the in-between window, update the call in each of the three modified workflows to:

```yaml
run: |
  ./build_python_framework_pkgs.zsh \
    --python-version "$PYTHON_VERSION" \
    --installer-id "$DEV_INSTALLER_ID" \
    --application-id "$DEV_APPLICATION_ID" \
    --notary-password "$NOTARY_APP_PASSWORD" \
    --xcode-path "/Applications/Xcode_15.2.app"
```

The `TYPE` env var is unused by the new script; leave it in the env block for now (Phase 3 cleanup will remove it).

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/build_python_3.11.yml \
        .github/workflows/build_python_3.12.yml \
        .github/workflows/build_python_3.13.yml
git commit -m "Bump 3.11/3.12/3.13 to latest patches; update script invocation"
```

---

## Task 8: Add Python 3.14 workflow

**Files:**
- Create: `.github/workflows/build_python_3.14.yml`

- [ ] **Step 1: Create the workflow file**

Create `.github/workflows/build_python_3.14.yml` by copying `.github/workflows/build_python_3.13.yml` and changing:

- `name: Build Python 3.13` → `name: Build Python 3.14`
- `PYTHON_VERSION: "3.13.13"` → `PYTHON_VERSION: "3.14.5"`
- `PYTHON_MAJOR_VERSION: "3.13"` → `PYTHON_MAJOR_VERSION: "3.14"`
- `Python 3.13.13 Framework` → `Python 3.14.5 Framework`
- `- Upgraded Python to 3.13.13` → `- Upgraded Python to 3.14.5`

All other contents (action versions, build script invocation from Task 7) remain identical.

- [ ] **Step 2: Verify YAML parses**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build_python_3.14.yml'))"`
Expected: no output (no errors).

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/build_python_3.14.yml
git commit -m "Add Python 3.14.5 build workflow"
```

---

## Task 9: Mark 3.9 and 3.10 workflows as final releases

**Files:**
- Modify: `.github/workflows/build_python_3.9.yml`
- Modify: `.github/workflows/build_python_3.10.yml`

- [ ] **Step 1: Update script invocation in 3.9 workflow**

In `.github/workflows/build_python_3.9.yml`, replace the `Run build package script` step's `run:` line with the same long-flag invocation as Task 7 Step 4 (so the final release works against the new script).

- [ ] **Step 2: Add final-release notice to 3.9 release body**

In `.github/workflows/build_python_3.9.yml`, find the `Create Release` step's `body:` block. Insert a new section immediately after the existing `## Security Notice` paragraph:

```yaml
            ## Final Release
            **This is the final release of the Python 3.9 framework.** Python 3.9 reached end-of-life on October 2025 and python.org has not published a macOS installer past 3.9.13. Future framework updates will target Python 3.11 and newer. Plan your migration.
```

- [ ] **Step 3: Update script invocation in 3.10 workflow**

In `.github/workflows/build_python_3.10.yml`, apply the same `run:` replacement as Step 1.

- [ ] **Step 4: Add final-release notice to 3.10 release body**

In `.github/workflows/build_python_3.10.yml`, insert after the existing `## Security Notice` paragraph:

```yaml
            ## Final Release
            **This is the final release of the Python 3.10 framework.** Python 3.10 is in security-fixes-only status and python.org has not published a macOS installer past 3.10.11. Future framework updates will target Python 3.11 and newer. Plan your migration.
```

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/build_python_3.9.yml .github/workflows/build_python_3.10.yml
git commit -m "Mark 3.9 and 3.10 as final releases; switch to new script flags"
```

---

## Task 10: Python package pin sweep

**Files:**
- Modify: `requirements_recommended.txt` (only if a package needs a bump or per-branch hold)

- [ ] **Step 1: List currently pinned packages with their versions**

Run: `grep -E '^[a-zA-Z]' requirements_recommended.txt`
Expected: 37 lines of `name==version`.

- [ ] **Step 2: For each pinned package, check PyPI for a newer release**

Run for each package (using `pyobjc` as the example; substitute each name):

```bash
pip index versions pyobjc --python-version 3.14 2>&1 | head -5
```

This requires `pip` 23.3+; if not available, use `pip install --dry-run pyobjc==99.99 2>&1 | grep "from versions"` instead.

Expected: a sorted list of available versions. Note the newest.

- [ ] **Step 3: Verify arm64 wheel availability for each candidate bump**

For each package where a newer version exists, check that arm64 macOS wheels are published for **every** supported Python branch (3.9, 3.10, 3.11, 3.12, 3.13, 3.14). Visit `https://pypi.org/project/<name>/#files` in a browser or run:

```bash
curl -s "https://pypi.org/pypi/<name>/<new-version>/json" \
  | python3 -c "import json,sys; data=json.load(sys.stdin); files=data['urls']; [print(f['filename']) for f in files if 'macosx' in f['filename'] and 'arm64' in f['filename']]"
```

A package qualifies for an unconditional bump only if arm64 macOS wheels exist for **all** supported Python versions. If 3.9 / 3.10 lack a wheel for the new version, hold those at the older pin via Pip's per-version syntax — example: `pyobjc==11.1; python_version >= "3.11"` plus `pyobjc==10.5.1; python_version < "3.11"`.

- [ ] **Step 4: Update `requirements_recommended.txt` with the bumps**

For each package that has a newer version with full arm64 wheel coverage, update the pin. For packages with partial coverage, use the marker syntax from Step 3. Leave packages without newer versions unchanged.

Document each change with a single-line trailing comment if it is a holdback (`pyobjc==10.5.1; python_version < "3.11"  # last version with 3.9/3.10 arm64 wheels`).

- [ ] **Step 5: Re-run local validation for 3.9, 3.10, 3.11, 3.12, 3.13, 3.14**

For each version, run:

```bash
./build_python_framework_pkgs.zsh --python-version <version>
```

Then install and smoke-test as in Task 5 Step 2. Each must produce a working framework. If any version fails on a freshly bumped package, revert that pin or hold it for the affected version.

The patch versions to validate: `3.9.13`, `3.10.11`, `3.11.9`, `3.12.10`, `3.13.13`, `3.14.5`.

- [ ] **Step 6: Commit**

```bash
git add requirements_recommended.txt
git commit -m "Bump Python package pins; add per-branch holdbacks where needed"
```

---

## Task 11: Add Dependabot config

**Files:**
- Create: `.github/dependabot.yml`

- [ ] **Step 1: Create the config**

Create `.github/dependabot.yml` with:

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
    open-pull-requests-limit: 5
```

- [ ] **Step 2: Verify YAML parses**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/dependabot.yml'))"`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add .github/dependabot.yml
git commit -m "Enable Dependabot for GitHub Actions"
```

---

## Task 12: Cut releases for all supported branches

**Files:** none (manual CI dispatch)

This is the final operational step. Each release is kicked off manually via `workflow_dispatch` so we can stage them and verify outputs.

- [ ] **Step 1: Trigger 3.14 release first**

Run: `gh workflow run build_python_3.14.yml --ref <branch-with-this-plan-merged>`

Expected: a workflow run starts. Watch via `gh run watch` or the GitHub UI.

- [ ] **Step 2: Verify 3.14 release artifact**

When the run finishes:

```bash
gh release view v3.14.5.<NEWSUBBUILD>
```

Expected: the release exists, has a signed `.pkg` asset, and the release body matches the new template.

- [ ] **Step 3: Trigger remaining releases in order**

Repeat Steps 1–2 for: `build_python_3.13.yml`, `build_python_3.12.yml`, `build_python_3.11.yml`, `build_python_3.10.yml`, `build_python_3.9.yml`.

The 3.9 and 3.10 releases must include the **Final Release** notice in their body (added in Task 9).

- [ ] **Step 4: No commit**

Nothing to commit — these are CI-side actions only. Phase 3 work (archiving the 3.9 / 3.10 workflows, consolidating the rest) starts after this plan is fully complete.

---

## Self-Review Notes

- Phase 1 spec coverage: Tasks 1–6 cover the script refactor, requirements, deletions, README, and local validation.
- Phase 2 spec coverage: Tasks 7–12 cover patch bumps, 3.14 addition, final-release notes, pin sweep, Dependabot, and release execution.
- Phase 3 explicitly excluded: workflow consolidation, runner migration, action bumps, release-trigger change — Task 7 Step 4 includes a deliberate stopgap (long-flag invocation inside the still-duplicated workflows) so CI keeps working in the in-between state.
- No placeholders: every code block is concrete; every `Expected:` describes verifiable output.
- Type / name consistency: long-flag names (`--python-version`, `--installer-id`, `--application-id`, `--notary-password`, `--xcode-path`) are identical across Tasks 1, 7, and 9.
