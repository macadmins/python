```bash
sudo rm -rf /Library/ManagedFrameworks/Python
./build_python_framework_pkgs.zsh --python-version 3.9.13
sudo ditto -x -k outputs/Python3.framework_recommended-3.9.13.*.zip /Library/ManagedFrameworks/Python/
managed_python3 --version && managed_python3 -c "import platform; print(platform.machine())" && managed_python3 -c "import objc, xattr, requests, yaml; print('ok')"

Python 3.9.13
arm64
ok

sudo rm -rf /Library/ManagedFrameworks/Python
./build_python_framework_pkgs.zsh --python-version 3.10.11
sudo ditto -x -k outputs/Python3.framework_recommended-3.10.11.*.zip /Library/ManagedFrameworks/Python/
managed_python3 --version && managed_python3 -c "import platform; print(platform.machine())" && managed_python3 -c "import objc, xattr, requests, yaml; print('ok')"

Python 3.10.11
arm64
ok

sudo rm -rf /Library/ManagedFrameworks/Python
./build_python_framework_pkgs.zsh --python-version 3.11.9
sudo ditto -x -k outputs/Python3.framework_recommended-3.11.9.*.zip /Library/ManagedFrameworks/Python/
managed_python3 --version && managed_python3 -c "import platform; print(platform.machine())" && managed_python3 -c "import objc, xattr, requests, yaml; print('ok')"

Python 3.11.9
arm64
ok

sudo rm -rf /Library/ManagedFrameworks/Python
./build_python_framework_pkgs.zsh --python-version 3.12.10
sudo ditto -x -k outputs/Python3.framework_recommended-3.12.10.*.zip /Library/ManagedFrameworks/Python/
managed_python3 --version && managed_python3 -c "import platform; print(platform.machine())" && managed_python3 -c "import objc, xattr, requests, yaml; print('ok')"

Python 3.12.10
arm64
ok

sudo rm -rf /Library/ManagedFrameworks/Python
./build_python_framework_pkgs.zsh --python-version 3.13.13
sudo ditto -x -k outputs/Python3.framework_recommended-3.13.13.*.zip /Library/ManagedFrameworks/Python/
managed_python3 --version && managed_python3 -c "import platform; print(platform.machine())" && managed_python3 -c "import objc, xattr, requests, yaml; print('ok')"

Python 3.13.13
arm64
ok

sudo rm -rf /Library/ManagedFrameworks/Python
./build_python_framework_pkgs.zsh --python-version 3.14.5
sudo ditto -x -k outputs/Python3.framework_recommended-3.14.5.*.zip /Library/ManagedFrameworks/Python/
managed_python3 --version && managed_python3 -c "import platform; print(platform.machine())" && managed_python3 -c "import objc, xattr, requests, yaml; print('ok')"

Python 3.14.5
arm64
ok
```