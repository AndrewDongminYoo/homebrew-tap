class BrewSnapshot < Formula
  desc "Snapshot and restore your Homebrew environment"
  homepage "https://github.com/AndrewDongminYoo/homebrew-tap"
  # Stable: fill url + sha256 after creating a GitHub release tag
  url "https://github.com/AndrewDongminYoo/homebrew-tap/archive/refs/tags/v0.3.5.tar.gz"
  sha256 "f573a9811815fce285406fc715ae2bd1796b3580a2af16c568f5f621a4c8c2ff"
  version "0.3.5"
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
    # help / --help / --version / unknown command
    assert_match "Usage: brew-snapshot", shell_output("#{bin}/brew-snapshot help")
    assert_match "Usage: brew-snapshot", shell_output("#{bin}/brew-snapshot --help")
    assert_match "brew-snapshot",        shell_output("#{bin}/brew-snapshot --version")
    assert_match "unknown command",      shell_output("#{bin}/brew-snapshot bogus 2>&1", 1)

    # Use an isolated state directory so tests never touch the real home
    ENV["BREW_SNAPSHOT_DIR"] = (testpath/"state").to_s

    # status: state directory does not exist yet → guidance message, exit 0
    assert_match "No snapshot found", shell_output("#{bin}/brew-snapshot status")

    # status: populate mock state and verify each field is reported
    snap = testpath/"state"
    snap.mkpath
    (snap/"last_snapshot_utc").write("2024-01-01T00:00:00Z")
    (snap/"Brewfile").write("brew \"git\"\nbrew \"curl\"\n")
    (snap/"Brewfile.taps").write("homebrew/cask\n")
    status_out = shell_output("#{bin}/brew-snapshot status")
    assert_match "2024-01-01T00:00:00Z", status_out
    assert_match "Formulae:",            status_out
    assert_match "Taps:",                status_out

    # restore: Brewfile removed → exits 1 with error message
    (snap/"Brewfile").unlink
    assert_match "No Brewfile found", shell_output("#{bin}/brew-snapshot restore 2>&1", 1)

    # restore: Brewfile present → "Installing from" message confirms dispatch to brew bundle
    # brew bundle with an empty Brewfile exits 0 (nothing to install), so no exit code asserted
    (snap/"Brewfile").write("")
    assert_match "Installing from", shell_output("#{bin}/brew-snapshot restore 2>&1")
  end
end
