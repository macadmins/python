#!/bin/zsh
#
# Build script for Python 3 frameworks
# Adaptd from https://github.com/munki/munki/blob/Munki3dev/code/tools/build_python_framework.sh
# IMPORTANT
# Run this with your current directory being the path where this script is located

# Harcoded versions
RP_SHA="93f3fea5290b761b1c25c15f46f7c76641d94d58"
MP_SHA="71c57fcfdf43692adcd41fa7305be08f66bae3e5"
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
  echo ""
  echo "        opionated"
  echo "          A python framework with libraries for as many macadmin tools as possible"
  exit 1
fi

if [ -n "$3" ]; then
  PYTHON_VERSION=$3
else
  PYTHON_VERSION=3.9.5
fi
# Set python bin version based on PYTHON_VERSION
PYTHON_BIN_VERSION="${PYTHON_VERSION%.*}"

if [ -n "$4" ]; then
  DATE=$4
else
  DATE=$(/bin/date -u "+%m%d%Y%H%M%S")
fi

# Variables
TOOLSDIR=$(dirname $0)
OUTPUTSDIR="$TOOLSDIR/outputs"
CONSOLEUSER=$(/usr/bin/stat -f "%Su" /dev/console)
RP_ZIP="/tmp/relocatable-python.zip"
MP_ZIP="/tmp/munki-pkg.zip"
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
    /bin/mkdir -p "$TOOLSDIR/$TYPE/payload/${FRAMEWORKDIR}"
    /bin/mkdir -p "$TOOLSDIR/$TYPE/payload/usr/local/bin"
    /usr/bin/sudo /usr/sbin/chown -R ${CONSOLEUSER}:wheel "$TOOLSDIR/$TYPE"
else
  /bin/mkdir -p "$TOOLSDIR/$TYPE/payload/${FRAMEWORKDIR}"
  /bin/mkdir -p "$TOOLSDIR/$TYPE/payload/usr/local/bin"
  /usr/bin/sudo /usr/sbin/chown -R ${CONSOLEUSER}:wheel "$TOOLSDIR/$TYPE"
fi

# build the framework
RP_EXTRACT_BINDIR="${RP_BINDIR}/relocatable-python-${RP_SHA}"
"${RP_EXTRACT_BINDIR}/make_relocatable_python_framework.py" \
--baseurl "${PYTHON_BASEURL}" \
--python-version "${PYTHON_VERSION}" \
--os-version "${MACOS_VERSION}" \
--upgrade-pip \
--pip-requirements "${TOOLSDIR}/requirements_${TYPE}.txt" \
--destination "${FRAMEWORKDIR}"

RP_RESULT="$?"
if [ "${RP_RESULT}" != "0" ]; then
    echo "Error running relocatable-python tool: ${RP_RESULT}" 1>&2
    exit 1
fi

# move the framework to the Python package folder
echo "Moving Python.framework to payload folder"
/bin/mv "${FRAMEWORKDIR}/Python.framework" "$TOOLSDIR/$TYPE/payload/${FRAMEWORKDIR}/Python3.framework"

# ad-hoc re-sign the framework so it will run on Apple Silicon
echo "Adding ad-hoc code signing so the framework will run on Apple Silicon..."
/usr/bin/codesign -s - --deep --force --preserve-metadata=identifier,entitlements,flags,runtime "$TOOLSDIR/$TYPE/payload/${FRAMEWORKDIR}/Python3.framework/Versions/${PYTHON_BIN_VERSION}/Resources/Python.app"
/usr/bin/codesign -s - --force --preserve-metadata=identifier,entitlements,flags,runtime "$TOOLSDIR/$TYPE/payload/${FRAMEWORKDIR}/Python3.framework/Versions/Current/Python"
/usr/bin/find "$TOOLSDIR/$TYPE/payload/${FRAMEWORKDIR}/Python3.framework/Versions/Current/bin/" -type f -perm -u=x -exec /usr/bin/codesign -s - --preserve-metadata=identifier,entitlements,flags,runtime -f {} \;
/usr/bin/find "$TOOLSDIR/$TYPE/payload/${FRAMEWORKDIR}/Python3.framework/Versions/Current/lib/" -type f -perm -u=x -exec /usr/bin/codesign -s - --preserve-metadata=identifier,entitlements,flags,runtime -f {} \;
/usr/bin/find "$TOOLSDIR/$TYPE/payload/${FRAMEWORKDIR}/Python3.framework/Versions/Current/lib/" -type f -name "*dylib" -exec /usr/bin/codesign -s - --preserve-metadata=identifier,entitlements,flags,runtime -f {} \;

# confirm truly universal
TOTAL_DYLIB=$(/usr/bin/find "$TOOLSDIR/$TYPE/payload/${FRAMEWORKDIR}/Python3.framework/Versions/Current/lib" -name "*.dylib" | /usr/bin/wc -l | /usr/bin/xargs)
UNIVERSAL_DYLIB=$(/usr/bin/find "$TOOLSDIR/$TYPE/payload/${FRAMEWORKDIR}/Python3.framework/Versions/Current/lib" -name "*.dylib" | /usr/bin/xargs file | /usr/bin/grep "2 architectures" | /usr/bin/wc -l | /usr/bin/xargs)
if [ "${TOTAL_DYLIB}" != "${UNIVERSAL_DYLIB}" ] ; then
  echo "Dynamic Libraries do not match, resulting in a non-universal Python framework."
  echo "Total Dynamic Libraries found: ${TOTAL_DYLIB}"
  echo "Universal Dynamic Libraries found: ${UNIVERSAL_DYLIB}"
  exit 1
fi

echo "Dynamic Libraries are confirmed as universal"

TOTAL_SO=$(/usr/bin/find "$TOOLSDIR/$TYPE/payload/${FRAMEWORKDIR}/Python3.framework/Versions/Current/lib" -name "*.so" | /usr/bin/wc -l | /usr/bin/xargs)
UNIVERSAL_SO=$(/usr/bin/find "$TOOLSDIR/$TYPE/payload/${FRAMEWORKDIR}/Python3.framework/Versions/Current/lib" -name "*.so" | /usr/bin/xargs file | /usr/bin/grep "2 architectures" | /usr/bin/wc -l | /usr/bin/xargs)
if [ "${TOTAL_SO}" != "${UNIVERSAL_SO}" ] ; then
  echo "Shared objects do not match, resulting in a non-universal Python framework."
  echo "Total shared objects found: ${TOTAL_SO}"
  echo "Universal shared objects found: ${UNIVERSAL_SO}"
  UNIVERSAL_SO_ARRAY=("${(@f)$(/usr/bin/find "$TOOLSDIR/$TYPE/payload/${FRAMEWORKDIR}/Python3.framework/Versions/Current/lib" -name "*.so" | /usr/bin/xargs file | /usr/bin/grep "2 architectures"  | awk '{print $1;}' | sed 's/:*$//g')}")
  TOTAL_SO_ARRAY=("${(@f)$(/usr/bin/find "$TOOLSDIR/$TYPE/payload/${FRAMEWORKDIR}/Python3.framework/Versions/Current/lib" -name "*.so" )}")
  echo ${TOTAL_SO_ARRAY[@]} ${UNIVERSAL_SO_ARRAY[@]} | tr ' ' '\n' | sort | uniq -u
  exit 1
fi

echo "Shared objects are confirmed as universal"

# make a symbolic link to help with interactive use
/bin/ln -s "$PYTHON_BIN" "$TOOLSDIR/$TYPE/payload/usr/local/bin/managed_python3"

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

# Create the json file for munki-pkg
/bin/cat << JSONFILE > "$TOOLSDIR/$TYPE/build-info.json"
{
  "ownership": "recommended",
  "suppress_bundle_relocation": true,
  "identifier": "org.macadmins.python.$TYPE",
  "postinstall_action": "none",
  "distribution_style": true,
  "version": "$PYTHON_VERSION.$DATE",
  "name": "python_$TYPE-$PYTHON_VERSION.$DATE.pkg",
  "install_location": "/"
}
JSONFILE
# Create the unsigned pkg
"${MP_BINDIR}/munki-pkg-${MP_SHA}/munkipkg" "$TOOLSDIR/$TYPE"
# Move the unsigned pkg
/bin/mv "$TOOLSDIR/$TYPE/build/python_$TYPE-$PYTHON_VERSION.$DATE.pkg" "$OUTPUTSDIR"

if [ -n "$2" ]; then
  # Create the json file for munki-pkg (signed)
  /bin/cat << SIGNED_JSONFILE > "$TOOLSDIR/$TYPE/build-info.json"
  {
    "ownership": "recommended",
    "suppress_bundle_relocation": true,
    "identifier": "org.macadmins.python.$TYPE",
    "postinstall_action": "none",
    "distribution_style": true,
    "version": "$PYTHON_VERSION.$DATE",
    "name": "python_${TYPE}_signed-$PYTHON_VERSION.$DATE.pkg",
    "install_location": "/",
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
  else
    # Move the signed pkg
    /bin/mv "$TOOLSDIR/$TYPE/build/python_${TYPE}_signed-$PYTHON_VERSION.$DATE.pkg" "$OUTPUTSDIR"
  fi
else
  echo "no signing identity passed, skipping signed package creation"
fi

# Zip and move the framework
ZIPFILE="Python3.framework_$TYPE-$PYTHON_VERSION.$DATE.zip"
/usr/bin/ditto -c -k --sequesterRsrc "$TOOLSDIR/$TYPE/payload/${FRAMEWORKDIR}/" ${ZIPFILE}
/bin/mv ${ZIPFILE} "$OUTPUTSDIR"

# Ensure outputs directory is owned by the current user
/usr/bin/sudo /usr/sbin/chown -R ${CONSOLEUSER}:wheel "$OUTPUTSDIR"

# Cleanup the temporary files
/usr/bin/sudo /bin/rm -rf "$TOOLSDIR/$TYPE"
/usr/bin/sudo /bin/rm -rf "${FRAMEWORKDIR}"
