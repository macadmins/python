#!/bin/zsh
#
# Build script for Python 3 frameworks
# Adaptd from https://github.com/munki/munki/blob/Munki3dev/code/tools/build_python_framework.sh
# IMPORTANT
# Run this with your current directory being the path where this script is located

# Harcoded versions
RP_SHA="fb4dd9b024b249c71713f14d887f4bcea78aa8b0"
MP_SHA="0fcd47faf0fb2b4e8a0256a77be315a3cb6ab319"
MACOS_VERSION=11 # use 10.9 for non-universal
PYTHON_PRERELEASE_VERSION=
PYTHON_BASEURL="https://www.python.org/ftp/python/%s/python-%s${PYTHON_PRERELEASE_VERSION}-macos%s.pkg"
# Hardcoded paths
FRAMEWORKDIR="/Library/ManagedFrameworks/Python"
PYTHON_BIN="$FRAMEWORKDIR/Python3.framework/Versions/Current/bin/python3"
RP_BINDIR="/tmp/relocatable-python"
MP_BINDIR="/tmp/munki-pkg"
CONSOLEUSER=$(/usr/bin/stat -f "%Su" /dev/console)
PIPCACHEDIR="/Users/${CONSOLEUSER}/Library/Caches/pip"
XCODE_PATH="/Applications/Xcode_15.2.app"
XCODE_NOTARY_PATH="$XCODE_PATH/Contents/Developer/usr/bin/notarytool"
XCODE_STAPLER_PATH="$XCODE_PATH/Contents/Developer/usr/bin/stapler"
NEWSUBBUILD=$((80620 + $(/usr/bin/git rev-parse HEAD~0 | xargs -I{} /usr/bin/git rev-list --count {})))

# Sanity Checks
## Type Check
if [ -n "$1" ]; then
    if [[ "$1" == 'minimal' ]]; then
        TYPE=$1
    elif [[ "$1" == "no_customization" ]]; then
        TYPE=$1
    elif [[ "$1" == 'recommended' ]]; then
        TYPE=$1
    else
        echo "Specified positional argument other than recommended. Using minimal workflow"
        TYPE='minimal'
    fi
else
  echo "runner.zsh"
  echo ""
  echo "  Configures Relocatable Python"
  echo "      Options:"
  echo "        minimal"
  echo "          Identical to the original relocatable python code"
  echo ""
  echo "        no_customization"
  echo "          A python framework without any customizations"
  echo ""
  echo "        recommended"
  echo "          A python framework with libraries for commonly used tools like autopkg and munki"
  exit 1
fi

if [ -n "$4" ]; then
  PYTHON_VERSION=$4
else
  PYTHON_VERSION=3.12.1
fi

if [ -n "$5" ]; then
  PYTHON_MAJOR_VERSION=$5
else
  PYTHON_MAJOR_VERSION=3.12
fi
# Set python bin version based on PYTHON_VERSION
PYTHON_BIN_VERSION="${PYTHON_VERSION%.*}"
AUTOMATED_PYTHON_BUILD="$PYTHON_VERSION.$NEWSUBBUILD"

# Variables
TOOLSDIR=$(dirname $0)
OUTPUTSDIR="$TOOLSDIR/outputs"
CONSOLEUSER=$(/usr/bin/stat -f "%Su" /dev/console)
RP_ZIP="/tmp/relocatable-python.zip"
MP_ZIP="/tmp/munki-pkg.zip"

# Create files to use for build process info
echo "$AUTOMATED_PYTHON_BUILD" > $TOOLSDIR/build_info.txt

echo "Creating Python Framework - $TYPE"

# Create framework path if not present with 777 so sudo is not needed
if [ ! -d "${FRAMEWORKDIR}" ]; then
    /usr/bin/sudo /bin/mkdir -m 777 -p "${FRAMEWORKDIR}"
fi

# remove existing Python.framework if present
if [ -d "${FRAMEWORKDIR}/Python.framework" ]; then
    /usr/bin/sudo /bin/rm -rf "${FRAMEWORKDIR}/Python.framework"
fi

# remove existing library Python.framework if present
if [ -d "${PIPCACHEDIR}" ]; then
    echo "Removing pip cache to reduce framework build errors"
    /usr/bin/sudo /bin/rm -rf "${PIPCACHEDIR}"
fi

# kill homebrew packages
/usr/local/bin/brew remove --force $(/usr/local/bin/brew list)

# Ensure Xcode is set to run-time
sudo xcode-select -s "$XCODE_PATH"

if [ -e $XCODE_BUILD_PATH ]; then
  XCODE_BUILD="$XCODE_BUILD_PATH"
else
  ls -la /Applications
  echo "Could not find required Xcode build. Exiting..."
  exit 1
fi

# Download specific version of relocatable-python
echo "Downloading relocatable-python tool from github..."
if [ -f "${RP_ZIP}" ]; then
    /usr/bin/sudo /bin/rm -rf ${RP_ZIP}
fi
/usr/bin/curl https://github.com/gregneagle/relocatable-python/archive/${RP_SHA}.zip -L -o ${RP_ZIP}
if [ -d ${RP_BINDIR} ]; then
    /usr/bin/sudo /bin/rm -rf ${RP_BINDIR}
fi
/usr/bin/unzip ${RP_ZIP} -d ${RP_BINDIR}
DL_RESULT="$?"
if [ "${DL_RESULT}" != "0" ]; then
    echo "Error downloading relocatable-python tool: ${DL_RESULT}" 1>&2
    exit 1
fi

# remove existing Python package folders and recreate
if [ -d "$TOOLSDIR/$TYPE" ]; then
    /bin/rm -rf "$TOOLSDIR/$TYPE"
    /bin/mkdir -p "$TOOLSDIR/$TYPE/payload${FRAMEWORKDIR}"
    /bin/mkdir -p "$TOOLSDIR/$TYPE/payload/usr/local/bin"
    /usr/bin/sudo /usr/sbin/chown -R ${CONSOLEUSER}:wheel "$TOOLSDIR/$TYPE"
else
  /bin/mkdir -p "$TOOLSDIR/$TYPE/payload${FRAMEWORKDIR}"
  /bin/mkdir -p "$TOOLSDIR/$TYPE/payload/usr/local/bin"
  /usr/bin/sudo /usr/sbin/chown -R ${CONSOLEUSER}:wheel "$TOOLSDIR/$TYPE"
fi

# make a symbolic link to help with interactive use
if [[ "${PYTHON_MAJOR_VERSION}" == "3.9" ]]; then
  /bin/ln -s "$PYTHON_BIN" "$TOOLSDIR/$TYPE/payload/usr/local/bin/managed_python3"
fi
if [[ "${PYTHON_MAJOR_VERSION}" == "3.10" ]]; then
  /bin/ln -s "$PYTHON_BIN" "$TOOLSDIR/$TYPE/payload/usr/local/bin/managed_python3"
fi
if [[ "${PYTHON_MAJOR_VERSION}" == "3.11" ]]; then
  /bin/cp "$TOOLSDIR/python-$PYTHON_MAJOR_VERSION" "$TOOLSDIR/$TYPE/payload/usr/local/bin/managed_python3"
fi
if [[ "${PYTHON_MAJOR_VERSION}" == "3.12" ]]; then
  /bin/cp "$TOOLSDIR/python-$PYTHON_MAJOR_VERSION" "$TOOLSDIR/$TYPE/payload/usr/local/bin/managed_python3"
fi

SB_RESULT="$?"
if [ "${SB_RESULT}" != "0" ]; then
    echo "Failed create managed_python3 object" 1>&2
    exit 1
fi

# build the framework
# Force the C path depending on the version of Python to allow tools like cffi/xattr to build without wheels otherwise it errors
# Can't use Apple's headers for 3.10 and higher as they are (currently) 3.9
# C_INCLUDE_PATH="/Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/Current/Headers/"

export C_INCLUDE_PATH="/Library/ManagedFrameworks/Python/Python.framework/Versions/Current/Headers/"

C_INCLUDE_PATH="/Library/ManagedFrameworks/Python/Python.framework/Versions/Current/Headers/" RP_EXTRACT_BINDIR="${RP_BINDIR}/relocatable-python-${RP_SHA}"
"${RP_EXTRACT_BINDIR}/make_relocatable_python_framework.py" \
--baseurl "${PYTHON_BASEURL}" \
--python-version "${PYTHON_VERSION}" \
--os-version "${MACOS_VERSION}" \
--upgrade-pip \
--no-unsign \
--pip-requirements "${TOOLSDIR}/requirements_${TYPE}.txt" \
--destination "${FRAMEWORKDIR}"

RP_RESULT="$?"
if [ "${RP_RESULT}" != "0" ]; then
    echo "Error running relocatable-python tool: ${RP_RESULT}" 1>&2
    exit 1
fi

# move the framework to the Python package folder
echo "Moving Python.framework to payload folder"
/bin/mv "${FRAMEWORKDIR}/Python.framework" "$TOOLSDIR/$TYPE/payload${FRAMEWORKDIR}/Python3.framework"

RP_RESULT2="$?"
if [ "${RP_RESULT2}" != "0" ]; then
    echo "Failed to move Python framework, likely due to a bug with relocatable python" 1>&2
    exit 1
fi

# confirm truly universal
TOTAL_DYLIB=$(/usr/bin/find "$TOOLSDIR/$TYPE/payload${FRAMEWORKDIR}/Python3.framework/Versions/${PYTHON_BIN_VERSION}/lib" -name "*.dylib" | /usr/bin/wc -l | /usr/bin/xargs)
UNIVERSAL_DYLIB=$(/usr/bin/find "$TOOLSDIR/$TYPE/payload${FRAMEWORKDIR}/Python3.framework/Versions/${PYTHON_BIN_VERSION}/lib" -name "*.dylib" | /usr/bin/xargs file | /usr/bin/grep "2 architectures" | /usr/bin/wc -l | /usr/bin/xargs)
if [ "${TOTAL_DYLIB}" != "${UNIVERSAL_DYLIB}" ] ; then
  echo "Dynamic Libraries do not match, resulting in a non-universal Python framework."
  echo "Total Dynamic Libraries found: ${TOTAL_DYLIB}"
  echo "Universal Dynamic Libraries found: ${UNIVERSAL_DYLIB}"
  exit 1
fi

echo "Dynamic Libraries are confirmed as universal"

TOTAL_SO=$(/usr/bin/find "$TOOLSDIR/$TYPE/payload${FRAMEWORKDIR}/Python3.framework/Versions/${PYTHON_BIN_VERSION}/lib" -name "*.so" | /usr/bin/wc -l | /usr/bin/xargs)
UNIVERSAL_SO=$(/usr/bin/find "$TOOLSDIR/$TYPE/payload${FRAMEWORKDIR}/Python3.framework/Versions/${PYTHON_BIN_VERSION}/lib" -name "*.so" | /usr/bin/xargs file | /usr/bin/grep "2 architectures" | /usr/bin/wc -l | /usr/bin/xargs)
if [ "${TOTAL_SO}" != "${UNIVERSAL_SO}" ] ; then
  echo "Shared objects do not match, resulting in a non-universal Python framework."
  echo "Total shared objects found: ${TOTAL_SO}"
  echo "Universal shared objects found: ${UNIVERSAL_SO}"
  UNIVERSAL_SO_ARRAY=("${(@f)$(/usr/bin/find "$TOOLSDIR/$TYPE/payload${FRAMEWORKDIR}/Python3.framework/Versions/${PYTHON_BIN_VERSION}/lib" -name "*.so" | /usr/bin/xargs file | /usr/bin/grep "2 architectures"  | awk '{print $1;}' | sed 's/:*$//g')}")
  TOTAL_SO_ARRAY=("${(@f)$(/usr/bin/find "$TOOLSDIR/$TYPE/payload${FRAMEWORKDIR}/Python3.framework/Versions/${PYTHON_BIN_VERSION}/lib" -name "*.so" )}")
  echo ${TOTAL_SO_ARRAY[@]} ${UNIVERSAL_SO_ARRAY[@]} | tr ' ' '\n' | sort | uniq -u
  exit 1
fi

echo "Shared objects are confirmed as universal"

# re-sign the framework so it will run on Apple Silicon
if [ -n "$3" ]; then
  echo "Adding developer id code signing so the framework will run on Apple Silicon..."
  /usr/bin/find "$TOOLSDIR/$TYPE/payload${FRAMEWORKDIR}/Python3.framework/Versions/${PYTHON_BIN_VERSION}/bin" -type f -perm -u=x -exec /usr/bin/codesign --sign "$3" --timestamp --preserve-metadata=identifier,entitlements,flags,runtime -f {} \;
  /usr/bin/find "$TOOLSDIR/$TYPE/payload${FRAMEWORKDIR}/Python3.framework/Versions/${PYTHON_BIN_VERSION}/lib" -type f -perm -u=x -exec /usr/bin/codesign --sign "$3" --timestamp --preserve-metadata=identifier,entitlements,flags,runtime -f {} \;
  /usr/bin/find "$TOOLSDIR/$TYPE/payload${FRAMEWORKDIR}/Python3.framework/Versions/${PYTHON_BIN_VERSION}/lib" -type f -name "*dylib" -exec /usr/bin/codesign --sign "$3" --timestamp --preserve-metadata=identifier,entitlements,flags,runtime -f {} \;
  /usr/bin/codesign --sign "$3" --timestamp --deep --force --preserve-metadata=identifier,entitlements,flags,runtime "$TOOLSDIR/$TYPE/payload${FRAMEWORKDIR}/Python3.framework/Versions/${PYTHON_BIN_VERSION}/Resources/Python.app"
  /usr/bin/codesign --sign "$3" --timestamp --force --preserve-metadata=identifier,entitlements,flags,runtime "$TOOLSDIR/$TYPE/payload${FRAMEWORKDIR}/Python3.framework/Versions/${PYTHON_BIN_VERSION}/Python"
  /usr/bin/codesign --sign "$3" --timestamp --force --preserve-metadata=identifier,entitlements,flags,runtime "$TOOLSDIR/$TYPE/payload${FRAMEWORKDIR}/Python3.framework/Versions/Current/Python"
else
  echo "Adding ad-hoc code signing so the framework will run on Apple Silicon..."
  /usr/bin/find "$TOOLSDIR/$TYPE/payload${FRAMEWORKDIR}/Python3.framework/Versions/${PYTHON_BIN_VERSION}/bin" -type f -perm -u=x -exec /usr/bin/codesign -s - --preserve-metadata=identifier,entitlements,flags,runtime -f {} \;
  /usr/bin/find "$TOOLSDIR/$TYPE/payload${FRAMEWORKDIR}/Python3.framework/Versions/${PYTHON_BIN_VERSION}/lib" -type f -perm -u=x -exec /usr/bin/codesign -s - --preserve-metadata=identifier,entitlements,flags,runtime -f {} \;
  /usr/bin/find "$TOOLSDIR/$TYPE/payload${FRAMEWORKDIR}/Python3.framework/Versions/${PYTHON_BIN_VERSION}/lib" -type f -name "*dylib" -exec /usr/bin/codesign -s - --preserve-metadata=identifier,entitlements,flags,runtime -f {} \;
  /usr/bin/codesign -s - --deep --force --preserve-metadata=identifier,entitlements,flags,runtime "$TOOLSDIR/$TYPE/payload${FRAMEWORKDIR}/Python3.framework/Versions/${PYTHON_BIN_VERSION}/Resources/Python.app"
  /usr/bin/codesign -s - --force --preserve-metadata=identifier,entitlements,flags,runtime "$TOOLSDIR/$TYPE/payload${FRAMEWORKDIR}/Python3.framework/Versions/${PYTHON_BIN_VERSION}/Python"
  /usr/bin/codesign -s - --force --preserve-metadata=identifier,entitlements,flags,runtime "$TOOLSDIR/$TYPE/payload${FRAMEWORKDIR}Python3.framework/Versions/Current/Python"
fi

# Print out some information about the signatures
/usr/sbin/spctl -a -vvvv "$TOOLSDIR/$TYPE/payload${FRAMEWORKDIR}/Python3.framework/Versions/${PYTHON_BIN_VERSION}/Python"
/usr/sbin/spctl -a -vvvv "$TOOLSDIR/$TYPE/payload${FRAMEWORKDIR}/Python3.framework/Versions/${PYTHON_BIN_VERSION}/lib/libssl.1.1.dylib"

# take ownership of the payload folder
echo "Taking ownership of the Payload directory"
/usr/bin/sudo /usr/sbin/chown -R ${CONSOLEUSER}:wheel "$TOOLSDIR/$TYPE"

# Download specific version of munki-pkg
echo "Downloading munki-pkg tool from github..."
if [ -f "${MP_ZIP}" ]; then
    /usr/bin/sudo /bin/rm -rf ${MP_ZIP}
fi
/usr/bin/curl https://github.com/munki/munki-pkg/archive/${MP_SHA}.zip -L -o ${MP_ZIP}
if [ -d ${MP_BINDIR} ]; then
    /usr/bin/sudo /bin/rm -rf ${MP_BINDIR}
fi
/usr/bin/unzip ${MP_ZIP} -d ${MP_BINDIR}
DL_RESULT="$?"
if [ "${DL_RESULT}" != "0" ]; then
    echo "Error downloading munki-pkg tool: ${DL_RESULT}" 1>&2
    exit 1
fi

# Create outputs folder
/bin/mkdir -p "$TOOLSDIR/outputs"

if [ -n "$2" ]; then
  # Create the json file for munki-pkg (signed)
  /bin/cat << SIGNED_JSONFILE > "$TOOLSDIR/$TYPE/build-info.json"
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
      "identity": "$2",
      "timestamp": true
    }
  }
SIGNED_JSONFILE
  # Create the signed pkg
  "${MP_BINDIR}/munki-pkg-${MP_SHA}/munkipkg" "$TOOLSDIR/$TYPE"
  PKG_RESULT="$?"
  if [ "${PKG_RESULT}" != "0" ]; then
    echo "Could not sign package: ${PKG_RESULT}" 1>&2
    exit 1
  else
    if [ -n "$6" ]; then
      # Notarize and staple the package
      $XCODE_NOTARY_PATH store-credentials --apple-id "opensource@macadmins.io" --team-id "T4SK8ZXCXG" --password "$NOTARY_APP_PASSWORD" macadminpython
      # If these fail, it will bail on the entire process
      $XCODE_NOTARY_PATH submit "$TOOLSDIR/$TYPE/build/python_${TYPE}_signed-$AUTOMATED_PYTHON_BUILD.pkg" --keychain-profile "macadminpython" --wait
      $XCODE_STAPLER_PATH staple "$TOOLSDIR/$TYPE/build/python_${TYPE}_signed-$AUTOMATED_PYTHON_BUILD.pkg"
    fi
    # Move the signed + notarized pkg
    /bin/mv "$TOOLSDIR/$TYPE/build/python_${TYPE}_signed-$AUTOMATED_PYTHON_BUILD.pkg" "$OUTPUTSDIR"
  fi
else
  echo "no signing identity passed, skipping signed package creation"
fi

# Zip and move the framework
ZIPFILE="Python3.framework_$TYPE-$AUTOMATED_PYTHON_BUILD.zip"
/usr/bin/ditto -c -k --sequesterRsrc "$TOOLSDIR/$TYPE/payload${FRAMEWORKDIR}/" ${ZIPFILE}
/bin/mv ${ZIPFILE} "$OUTPUTSDIR"

# Ensure outputs directory is owned by the current user
/usr/bin/sudo /usr/sbin/chown -R ${CONSOLEUSER}:wheel "$OUTPUTSDIR"

# Cleanup the temporary files
/usr/bin/sudo /bin/rm -rf "$TOOLSDIR/$TYPE"
/usr/bin/sudo /bin/rm -rf "${FRAMEWORKDIR}"
