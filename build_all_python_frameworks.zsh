#!/bin/zsh
#
# Build script for all Python 3 frameworks
# Adapted from https://github.com/munki/munki/blob/Munki3dev/code/tools/build_python_framework.sh
# IMPORTANT
# Run this with your current directory being the path where this script is located

TOOLSDIR=$(dirname $0)
SIGNING_IDENTITY="Developer ID Installer: Clever DevOps Co. (9GQZ7KUFR6)"

"$TOOLSDIR/build_python_framework_pkgs.zsh" minimal ${SIGNING_IDENTITY}
"$TOOLSDIR/build_python_framework_pkgs.zsh" no_customization ${SIGNING_IDENTITY}
"$TOOLSDIR/build_python_framework_pkgs.zsh" recommended ${SIGNING_IDENTITY}
"$TOOLSDIR/build_python_framework_pkgs.zsh" opinionated ${SIGNING_IDENTITY}
