#!/bin/zsh
#
# Build script for all Python 3 frameworks
# Adaptd from https://github.com/munki/munki/blob/Munki3dev/code/tools/build_python_framework.sh
# IMPORTANT
# Run this with your current directory being the path where this script is located

TOOLSDIR=$(dirname $0)

sudo "$TOOLSDIR/build_python_framework_pkgs.zsh" minimal
sudo "$TOOLSDIR/build_python_framework_pkgs.zsh" no_customization
sudo "$TOOLSDIR/build_python_framework_pkgs.zsh" recommended
sudo "$TOOLSDIR/build_python_framework_pkgs.zsh" opionated
