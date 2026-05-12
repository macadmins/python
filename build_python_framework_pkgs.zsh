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
PYTHON_BASEURL="https://www.python.org/ftp/python/%s/python-%s-macos%s.pkg"
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
    /usr/bin/sudo /bin/mkdir -p "$FRAMEWORKDIR"
    # mkdir -m only applies to newly created dirs; ensure existing dirs are writable.
    /usr/bin/sudo /bin/chmod 777 "$FRAMEWORKDIR"
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
        --pip-requirements "${TOOLSDIR}/requirements_${TYPE}.txt" \
        --destination "${FRAMEWORKDIR}"

    /bin/mv "${FRAMEWORKDIR}/Python.framework" \
        "$TOOLSDIR/$TYPE/payload${FRAMEWORKDIR}/Python3.framework"
}

codesign_framework() {
    local identity="${APPLICATION_ID:--}"   # `-` means ad-hoc
    local framework_root="$TOOLSDIR/$TYPE/payload${FRAMEWORKDIR}/Python3.framework"
    local versioned="$framework_root/Versions/${PYTHON_BIN_VERSION}"
    local nested_frameworks_dir="$versioned/Frameworks"

    if [[ "$identity" == "-" ]]; then
        echo "Ad-hoc signing framework"
    else
        echo "Signing framework with identity: $identity"
    fi

    # Codesign notes:
    #   - Use --options=runtime to force-enable hardened runtime (required for
    #     notarization on macOS 13+). Do NOT include `runtime` in
    #     --preserve-metadata: install_name_tool just invalidated the prior
    #     signature, so there is nothing reliable to inherit.
    #   - Do NOT sign Versions/Current/Python — it's a symlink to
    #     Versions/X.Y/Python which we already signed. Double-signing through
    #     the symlink corrupts the signature on newer Python frameworks.
    #   - Sign nested .framework bundles (Tcl, Tk in Python 3.13+) with --deep,
    #     not via per-binary find. The bundle's _CodeSignature/CodeResources
    #     file must be regenerated to match the re-signed inner binary;
    #     otherwise notarytool reports "nested code is modified or invalid".

    local -a cs_args
    if [[ "$identity" == "-" ]]; then
        cs_args=(--options=runtime --preserve-metadata=identifier,entitlements,flags -f)
    else
        cs_args=(--timestamp --options=runtime --preserve-metadata=identifier,entitlements,flags -f)
    fi

    /usr/bin/find "$versioned/bin" -type f -perm -u=x -exec \
        /usr/bin/codesign -s "$identity" "${cs_args[@]}" {} \;
    /usr/bin/find "$versioned/lib" -type f -perm -u=x -exec \
        /usr/bin/codesign -s "$identity" "${cs_args[@]}" {} \;
    /usr/bin/find "$versioned/lib" -type f -name "*dylib" -exec \
        /usr/bin/codesign -s "$identity" "${cs_args[@]}" {} \;

    if [[ -d "$nested_frameworks_dir" ]]; then
        local nested_fw
        for nested_fw in "$nested_frameworks_dir"/*.framework; do
            [[ -d "$nested_fw" ]] || continue
            if [[ "$identity" == "-" ]]; then
                /usr/bin/codesign -s "$identity" --options=runtime --force --deep "$nested_fw"
            else
                /usr/bin/codesign -s "$identity" --timestamp --options=runtime --force --deep "$nested_fw"
            fi
        done
    fi

    /usr/bin/codesign -s "$identity" --deep "${cs_args[@]}" "$versioned/Resources/Python.app"
    /usr/bin/codesign -s "$identity" "${cs_args[@]}" "$versioned/Python"

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
    local pkg_built="$TOOLSDIR/$TYPE/build/python_${TYPE}_signed-$AUTOMATED_PYTHON_BUILD.pkg"
    /bin/mv "$pkg_built" "$OUTPUTSDIR"
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
    pkg="$OUTPUTSDIR/python_${TYPE}_signed-$AUTOMATED_PYTHON_BUILD.pkg"

    "$xcode_notary" store-credentials \
        --apple-id "opensource@macadmins.io" \
        --team-id "T4SK8ZXCXG" \
        --password "$NOTARY_PASSWORD" \
        macadminpython
    "$xcode_notary" submit "$pkg" --keychain-profile macadminpython --wait
    "$xcode_stapler" staple "$pkg"
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
