class BrewSnapshot < Formula
  desc "Snapshot and restore your Homebrew environment"
  homepage "https://github.com/AndrewDongminYoo/homebrew-brew-snapshot"
  # Stable: fill url + sha256 after creating a GitHub release tag
  url "https://github.com/AndrewDongminYu/homebrew-brew-snapshot/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "0019dfc4b32d63c1392aa264aed2253c1e0c2fb09216f8e2cc269bbfb8bb49b5"
  version "0.1.0"
  license "MIT"

  head "https://github.com/AndrewDongminYoo/homebrew-brew-snapshot.git", branch: "main"

  def install
    bin.install "bin/brew-snapshot"
    (libexec/"commands").install Dir["libexec/commands/*"]
    (share/"brew-snapshot").install "share/brew-snapshot.plist.template"

    # Rewrite LIBEXEC_DIR in the entry point to the Homebrew prefix path
    inreplace bin/"brew-snapshot",
      %r{_self/\.\./libexec/commands},
      "#{libexec}/commands"
  end

  def caveats
    <<~EOS
      Run setup to enable automatic snapshots on login:
        brew-snapshot setup

      Default state directory: ~/.local/share/brew-snapshot/
      Override:  export BREW_SNAPSHOT_DIR=/your/path
    EOS
  end

  test do
    output = shell_output("#{bin}/brew-snapshot help")
    assert_match "Usage: brew-snapshot", output
  end
end
