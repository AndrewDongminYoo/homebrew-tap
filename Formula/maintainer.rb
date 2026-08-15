class Maintainer < Formula
  desc "Terminal dashboard over every repository you can push to"
  homepage "https://github.com/AndrewDongminYoo/maintainer_tui"
  url "https://github.com/AndrewDongminYoo/maintainer_tui/releases/download/v0.1.1/maintainer-darwin-arm64.tar.gz"
  sha256 "7506720055c9b07d04cfe4f9dbabb614607ccc8ea947f08868298291763dcf49"
  version "0.1.1"
  license "MIT"

  # The release ships a single compiled binary built on Apple Silicon. Other platforms would
  # need their own build rather than this one.
  depends_on arch: :arm64
  depends_on :macos

  # Every listing goes through gh, so it is a runtime requirement rather than a suggestion.
  depends_on "gh"

  def install
    bin.install "maintainer"
  end

  def caveats
    <<~EOS
      Authenticate the GitHub CLI once before first use:
        gh auth login

      Set the directories your checkouts live in:
        maintainer --config

      The current directory is always searched first, and when it is itself a checkout its
      parent is searched too, so running maintainer from inside any project finds its siblings
      without configuration.
    EOS
  end

  test do
    assert_match "GitHub maintenance dashboard", shell_output("#{bin}/maintainer --help")
    # --config writes and prints the resolved configuration without touching the network.
    assert_match "cloneRoot", shell_output("#{bin}/maintainer --config")
  end
end
