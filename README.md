supergemlock -- fast Ruby dependency resolution
==================================================

supergemlock is a high-performance replacement for Bundler's dependency resolution engine. It reads a Gemfile, resolves dependencies, and writes a Gemfile.lock in the same format as Bundler.

Performance: 20-60x faster than standard Bundler through parallel resolution and zero-allocation algorithms.

## INSTALLATION

    $ curl -fsSL https://raw.githubusercontent.com/tylerdiaz/supergemlock/main/install.sh | bash

Or build from source:

    $ zig build -Doptimize=ReleaseFast
    $ sudo cp zig-out/bin/supergemlock /usr/local/bin/

## OPTIONS

    -v, --version    Print version
    -h, --help       Show help

## USAGE

In a directory containing a Gemfile:

    $ supergemlock

As a drop-in Bundler replacement:

    $ alias bundle='supergemlock'
    $ bundle install
    $ bundle update
    $ bundle check

## PERFORMANCE

Typical resolution times:

    Small app (10 gems):     5ms
    Medium app (50 gems):    15ms  
    Large app (200 gems):    50ms
    Monorepo (500+ gems):    150ms

Memory usage: ~5MB (vs ~200MB for Bundler)

## FILES

    Gemfile           Ruby dependency specification
    Gemfile.lock      Resolved dependency graph
    Gemfile.lock.bin  Binary cache for fast path (0ms)

## COMPATIBILITY

Supports common Gemfile directives:

    source 'https://rubygems.org'
    gem 'rails', '~> 7.0'
    gem 'pg', '>= 1.0', '< 2.0'
    gem 'puma', require: false
    
Limited support for:

    - groups
    - platforms
    - git/github sources

Not supported:

    - gemspec
    - conditional gems
    - ruby version requirements

## IMPLEMENTATION

Written in Zig for performance and reliability. Key optimizations:

- Parallel dependency resolution using work-stealing queues
- Zero-allocation version comparisons via packed integers
- Memory-mapped I/O for lockfile parsing
- SIMD acceleration on Apple Silicon

## LICENSE

MIT License. See LICENSE file.
