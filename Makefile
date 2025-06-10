.PHONY: all build release install clean test

PREFIX ?= /usr/local
VERSION := $(shell cat VERSION)

all: build

build:
	zig build -Doptimize=ReleaseFast

release:
	zig build -Doptimize=ReleaseFast -Dtarget=native-native-musl

install: build
	install -m 755 zig-out/bin/supergemlock $(PREFIX)/bin/
	install -m 755 zig-out/bin/zig-bundle $(PREFIX)/bin/supergemlock_bundle

uninstall:
	rm -f $(PREFIX)/bin/supergemlock
	rm -f $(PREFIX)/bin/supergemlock_bundle

clean:
	rm -rf zig-out zig-cache .zig-cache
	rm -f Gemfile.lock Gemfile.lock.bin

test: build
	./scripts/test_simple_gemfiles.sh