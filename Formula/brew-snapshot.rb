class BrewSnapshot < Formula
  desc "Snapshot and restore your Homebrew environment"
  homepage "https://github.com/AndrewDongminYoo/homebrew-tap"
  # Stable: fill url + sha256 after creating a GitHub release tag
  url "https://github.com/AndrewDongminYoo/homebrew-tap/archive/refs/tags/v0.3.3.tar.gz"
  sha256 "d4d88d8ec1c328133b7319a685dbab7d6673046e5f415134f8ff7791e882422c"
  version "0.3.3"
  license "MIT"

  head "https://github.com/AndrewDongminYoo/homebrew-tap.git", branch: "main"

  def install
    bin.install "bin/brew-snapshot"
    (libexec/"commands").install Dir["libexec/commands/*"]
    (share/"brew-snapshot").install "share/brew-snapshot.plist.template"

    # Rewrite LIBEXEC_DIR in the entry point to the Homebrew prefix path
    inreplace bin/"brew-snapshot",
      %r{\$\{_self\}/\.\./libexec/commands},
      "#{opt_libexec}/commands"
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
