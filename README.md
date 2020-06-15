# python
A Python 3 framework that currently installs to `/Library/SystemFrameworks/Python3.framework`.

Please see Apple's documentation on [file system basics](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html) for more information on the thought process here.

This is an intended replacement for when Apple removes `/usr/bin/python`

## Using interactively
After installing any of the packages, a symbolic link can be used within terminal for interactive python sessions. At the time of this writing `/usr/local/bin/python3.framework` points to `/Library/SystemFrameworks/Python3.framework/Versions/3.8/bin/python3.8`

## Using with scripts
Careful consideration should be used when determining the best course of action for using with scripts. Due to various complexities, a shim file has been provided and is located at `/Library/SystemFrameworks/Python3.framework/python3`

It is currently recommended to point directly to this shim as future updates to python3 could change this path.

At the time of this writing `/Library/SystemFrameworks/Python3.framework/python3` points to `/Library/SystemFrameworks/Python3.framework/Versions/3.8/bin/python3.8`

An example script would look like the following:

```
#!/Library/SystemFrameworks/Python3.framework/python3

print('This is an example script.')
```

### Other options to consider
#### zshenv global alias
If you are calling python within zsh scripts, adding a global alias to `/etc/zshenv` may be appropriate.

`alias -g python3.framework='/Library/SystemFrameworks/Python3.framework/python3'`

For more information on this method, please see Moving to Zsh Part [II](https://scriptingosx.com/2019/06/moving-to-zsh-part-2-configuration-files/) and [IV](https://scriptingosx.com/2019/07/moving-to-zsh-part-4-aliases-and-functions/)

## Notes
To decrease complexity, only a _single_ package may be installed at any given time on a machine.

### Upgrades
While Python itself has it's own update cadence and dot release schedule, it is likely that this package will have many updates as 3rd party libraries release their own updates, bug fixes and security enhancements. These packages should not break your workflow, but you should test your scripts prior to wide deployment to your devices.

### Downgrades
Downgrades will not be supported by this repository.

### pip
While `pip` is bundled in this framework, it is **not recommended** to install any external libraries into your frameworks folder outside of what comes with the package. If you need to use or test external libraries not present in the package, it is recommended to use a virtual environment or a tool like [pyenv](https://github.com/pyenv/pyenv).

Pull Requests can be issued to the `opionated` or `recommended` package, but more scrutiny will be applied to the `recommended` package.

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
