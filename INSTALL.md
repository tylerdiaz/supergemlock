INSTALLATION
============

Binary Installation
-------------------

    # Auto-detect platform and install
    $ curl -fsSL https://raw.githubusercontent.com/tylerdiaz/supergemlock/main/install.sh | bash

    # Or download specific version
    $ curl -L https://github.com/tylerdiaz/supergemlock/releases/latest/download/supergemlock-$(uname -s)-$(uname -m).tar.gz | tar xz
    $ sudo mv supergemlock /usr/local/bin/

Build from Source
-----------------

Requirements: Zig 0.14.0+

    $ git clone https://github.com/tylerdiaz/supergemlock.git
    $ cd supergemlock
    $ zig build -Doptimize=ReleaseFast
    $ sudo cp zig-out/bin/supergemlock /usr/local/bin/

Platform Support
----------------

    darwin-arm64     macOS Apple Silicon
    darwin-x64       macOS Intel
    linux-x64        Linux x86_64
    linux-arm64      Linux ARM64

Verification
------------

    $ supergemlock --version
    supergemlock 0.1.0