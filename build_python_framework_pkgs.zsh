#!/bin/zsh
#
# Build script for Python 3 frameworks
# Adaptd from https://github.com/munki/munki/blob/Munki3dev/code/tools/build_python_framework.sh
# IMPORTANT
# Run this with your current directory being the path where this script is located

# Harcoded versions
PYTHON_VERSION=3.8.3
RP_SHA="8bce58e91895978da6f238c1d2e1de3559ea4643"
MP_SHA="71c57fcfdf43692adcd41fa7305be08f66bae3e5"
# Hardcoded paths
FRAMEWORKDIR="/Library/SystemFrameworks"
PYTHON_BIN="$FRAMEWORKDIR/Python3.framework/Versions/3.8/bin/python3.8"
RP_BINDIR="/tmp/relocatable-python"
MP_BINDIR="/tmp/munki-pkg"

# Sanity Checks
## Type Check
if [ -n "$1" ]; then
    if [[ "$1" == 'minimal' ]]; then
        TYPE=$1
    elif [[ "$1" == "no_customization" ]]; then
        TYPE=$1
    elif [[ "$1" == "opionated" ]]; then
        TYPE=$1
    elif [[ "$1" == 'recommended' ]]; then
        TYPE=$1
    else
        echo "Specified positional argument other than opionated or recommended. Using minimal workflow"
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
## Root Check
if [[ $(/usr/bin/id -u) -ne 0 ]]; then
    echo "This tool requires elevated access to run"
    exit 1
fi

# Variables
DATE=$(/bin/date -u "+%m%d%Y%H%M%S")
TOOLSDIR=$(dirname $0)
OUTPUTSDIR="$TOOLSDIR/outputs"
CONSOLEUSER=$(/usr/bin/stat -f "%Su" /dev/console)
RP_ZIP="/tmp/relocatable-python.zip"
MP_ZIP="/tmp/munki-pkg.zip"
echo "Creating Python Framework - $TYPE"

# Create framework path if not present
if [ ! -d "${FRAMEWORKDIR}" ]; then
    /usr/bin/sudo /bin/mkdir -p "${FRAMEWORKDIR}"
fi

# remove existing library Python.framework if present
if [ -d "${FRAMEWORKDIR}/Python.framework" ]; then
    /usr/bin/sudo /bin/rm -rf "${FRAMEWORKDIR}/Python.framework"
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
/usr/bin/sudo "${RP_EXTRACT_BINDIR}/make_relocatable_python_framework.py" \
--python-version "${PYTHON_VERSION}" \
--pip-requirements "${TOOLSDIR}/requirements_${TYPE}.txt" \
--destination "${FRAMEWORKDIR}"

RP_RESULT="$?"
if [ "${RP_RESULT}" != "0" ]; then
    echo "Error running relocatable-python tool: ${RP_RESULT}" 1>&2
    exit 1
fi

# move the framework to the Python package folder
echo "Moving Python.framework to payload folder"
/usr/bin/sudo /bin/mv "${FRAMEWORKDIR}/Python.framework" "$TOOLSDIR/$TYPE/payload/${FRAMEWORKDIR}/Python3.framework"

# make a symbolic link to help with interactive use and stable path
/bin/ln -s "$PYTHON_BIN" "$TOOLSDIR/$TYPE/payload/usr/local/bin/python3.framework"
/bin/ln -s "$PYTHON_BIN" "$TOOLSDIR/$TYPE/payload/$FRAMEWORKDIR/Python3.framework/python3"

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
# Create the pkg
"${MP_BINDIR}/munki-pkg-${MP_SHA}/munkipkg" "$TOOLSDIR/$TYPE"

# Zip the framework
ZIPFILE="Python3.framework_$TYPE-$PYTHON_VERSION.$DATE.zip"
/usr/bin/ditto -c -k --sequesterRsrc "$TOOLSDIR/$TYPE/payload/${FRAMEWORKDIR}/" ${ZIPFILE}

# Move all of the output files
/bin/mv ${ZIPFILE} "$OUTPUTSDIR"
/bin/mv "$TOOLSDIR/$TYPE/build/python_$TYPE-$PYTHON_VERSION.$DATE.pkg" "$OUTPUTSDIR"
/usr/bin/sudo /usr/sbin/chown -R ${CONSOLEUSER}:wheel "$OUTPUTSDIR"

# Cleanup
/usr/bin/sudo /bin/rm -rf "$TOOLSDIR/$TYPE"
