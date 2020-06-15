# python
A Python 3 framework that currently installs to `/Library/SystemFrameworks/Python3.framework`.

Please see Apple's documentation on [file system basics](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html) for more information on the thought process here.

This is an intended replacement for when Apple removes `/usr/bin/python`

## Notes
To decrease complexity, only a _single_ package may be installed at any given time on a machine.

# Flavors of Python
We currently offer four versions of Python. You can chose which version suits your needs.

## Minimal
This is a Python.framework that includes `xattr` and `PyObjc` - the original intent of Relocatable Python.

Tools that should work
- vfuse
- dockutil (python 3 pull request [here](https://github.com/kcrawford/dockutil/pull/87))
- outset

## No Customization
This is a Python.framework that contains everything from the official Python package and nothing more.

Many open source tools will not work with this, but it may be helpful for development purposes.

## Recommended
This is a Python.framework that contains everything from minimal, and a few libraries that various well known open source projects require.

Tools that should work:
- autopkg
- InstallApplications
- munki
- munki-pkg
- munki-facts (python 3 pull request [here](https://github.com/munki/munki-facts/pull/17))
- nudge
- UMAD

## Opinionated
This is a Python.framework that contains everything from Recommended, and libraries that various open source projects require.

This is a **kitchen sink** approach, opting for the latest known packages.

Tools that should work:
- Gusto's autopkg promotion tool
- Munki CloudFront Middleware
- Python-jss

# Updating packages
This should be done in a clean virtual environment. After every python package install, you can run `pip freeze | xargs pip uninstall -y` to cleanup the environment.

# Credits
These packages are created with two other open source tools:
- [relocatable-python](https://github.com/gregneagle/relocatable-python)
- [munki-pkg](https://github.com/munki/munki-pkg)

Both are written by [Greg Neagle](https://www.linkedin.com/in/gregneagle/). Thank you for your continued dedication to the macOS platform.
