class Supergemlock < Formula
  desc "High-performance Ruby dependency resolver - 20-60x faster than Bundler"
  homepage "https://github.com/tylerdiaz/supergemlock"
  version "0.1.0"
  license "MIT"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/tylerdiaz/supergemlock/releases/download/v#{version}/supergemlock-darwin-arm64.tar.gz"
      sha256 "PLACEHOLDER_SHA256_DARWIN_ARM64"
    else
      url "https://github.com/tylerdiaz/supergemlock/releases/download/v#{version}/supergemlock-darwin-x64.tar.gz"
      sha256 "PLACEHOLDER_SHA256_DARWIN_X64"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/tylerdiaz/supergemlock/releases/download/v#{version}/supergemlock-linux-arm64.tar.gz"
      sha256 "PLACEHOLDER_SHA256_LINUX_ARM64"
    else
      url "https://github.com/tylerdiaz/supergemlock/releases/download/v#{version}/supergemlock-linux-x64.tar.gz"
      sha256 "PLACEHOLDER_SHA256_LINUX_X64"
    end
  end

  def install
    bin.install "supergemlock"
    bin.install "bundle" => "supergemlock_bundle"
  end

  def caveats
    <<~EOS
      supergemlock has been installed as:
        #{HOMEBREW_PREFIX}/bin/supergemlock
        #{HOMEBREW_PREFIX}/bin/supergemlock_bundle

      To use supergemlock as a drop-in replacement for bundler, add this to your shell profile:
        alias bundle='supergemlock_bundle'

      For 0ms fast path on unchanged Gemfiles, supergemlock will create binary lockfiles:
        Gemfile.lock.bin

      Performance improvements:
        - First run: 20-60x faster than bundler
        - Subsequent runs: instant (0ms) when Gemfile unchanged
        - Memory usage: 30-60x more efficient

      Apple Silicon optimizations are automatically enabled on M1/M2/M3/M4 Macs.
    EOS
  end

  test do
    (testpath/"Gemfile").write <<~EOS
      source 'https://rubygems.org'
      gem 'rack', '~> 3.0'
    EOS

    system "#{bin}/supergemlock"
    assert_predicate testpath/"Gemfile.lock", :exist?
    assert_predicate testpath/"Gemfile.lock.bin", :exist?

    # Test bundle wrapper
    system "#{bin}/supergemlock_bundle", "check"
  end
end