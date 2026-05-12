"""
Site-customization for the macadmins Python framework.

Why this file exists:
    The python.org Python.framework is built with OpenSSL's default CA-bundle
    path hardcoded to /Library/Frameworks/Python.framework/Versions/<X.Y>/etc/
    openssl/cert.pem. Our framework installs under /Library/ManagedFrameworks/
    Python/Python3.framework/..., so that hardcoded path doesn't exist on
    target machines. Stdlib SSL (urllib.request, http.client.HTTPSConnection,
    ssl.SSLContext with default verify paths, etc.) then fails to find a CA
    bundle and certificate validation errors out.

    A regular python.org install ships /Applications/Python 3.X/Install
    Certificates.command that fixes this by symlinking the expected path to
    certifi's bundled cacert.pem. We can't do the equivalent because the
    expected path is outside our framework — touching it would conflict with
    a python.org install if the user has one.

What it does:
    Sets SSL_CERT_FILE to certifi's bundled cert path during interpreter
    startup. OpenSSL reads SSL_CERT_FILE ahead of its compiled-in path, so
    stdlib SSL operations get a working CA bundle.

    Only sets the variable when it isn't already set, so an explicit user
    override (e.g. `export SSL_CERT_FILE=/path/to/ca.pem`) still wins.

References:
    macadmins/python#38
    gregneagle/relocatable-python#13
"""
import os

if "SSL_CERT_FILE" not in os.environ:
    try:
        import certifi
    except ImportError:
        pass
    else:
        os.environ["SSL_CERT_FILE"] = certifi.where()
