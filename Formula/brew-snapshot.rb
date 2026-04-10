class BrewSnapshot < Formula
  desc "Snapshot and restore your Homebrew environment"
  homepage "https://github.com/dongminyu/homebrew-brew-snapshot"
  # url and sha256 are filled after a GitHub release tag is created
  # url "https://github.com/dongminyu/homebrew-brew-snapshot/archive/refs/tags/v0.1.0.tar.gz"
  # sha256 "..."
  version "0.1.0"
  license "MIT"

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
