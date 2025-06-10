# Release Process

## Pre-release Checklist

- [ ] Update VERSION file
- [ ] Update version in main.zig
- [ ] Update version in homebrew formula
- [ ] Run all tests: `zig build test`
- [ ] Run benchmarks: `./benchmark_simple.sh`
- [ ] Test on all platforms:
  - [ ] macOS (Apple Silicon)
  - [ ] macOS (Intel)
  - [ ] Linux (x64)
  - [ ] Linux (ARM64)
- [ ] Update CHANGELOG.md

## Creating a Release

1. **Tag the release:**
   ```bash
   git tag -a v0.1.0 -m "Release v0.1.0"
   git push origin v0.1.0
   ```

2. **GitHub Actions will automatically:**
   - Build binaries for all platforms
   - Create GitHub release
   - Upload artifacts
   - Update release notes

3. **Update Homebrew tap:**
   ```bash
   # In your homebrew-tap repository
   # Update SHA256 hashes in formula
   brew audit --strict supergemlock
   brew test supergemlock
   git commit -am "Update supergemlock to v0.1.0"
   git push
   ```

## Post-release

- [ ] Verify binaries on releases page
- [ ] Test installation script
- [ ] Test Homebrew installation
- [ ] Update documentation if needed
- [ ] Announce release:
  - [ ] Twitter/X
  - [ ] Ruby subreddit
  - [ ] Hacker News
  - [ ] Ruby Weekly newsletter

## Platform Build Matrix

| Platform | Target | Binary Name |
|----------|--------|-------------|
| macOS (M1/M2/M3/M4) | aarch64-macos | supergemlock-darwin-arm64.tar.gz |
| macOS (Intel) | x86_64-macos | supergemlock-darwin-x64.tar.gz |
| Linux (x64) | x86_64-linux | supergemlock-linux-x64.tar.gz |
| Linux (ARM64) | aarch64-linux | supergemlock-linux-arm64.tar.gz |
| Windows (x64) | x86_64-windows | supergemlock-windows-x64.zip |

## Version Numbering

We follow semantic versioning:
- MAJOR: Incompatible API changes
- MINOR: New functionality, backwards compatible
- PATCH: Bug fixes, backwards compatible

Current: 0.1.0 (initial release)