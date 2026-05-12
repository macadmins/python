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
