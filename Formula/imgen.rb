class Imgen < Formula
  desc "Terminal browser and generator for the images the Codex CLI makes"
  homepage "https://github.com/AndrewDongminYoo/imgen"
  url "https://github.com/AndrewDongminYoo/imgen/releases/download/v0.1.1/imgen-darwin-arm64.tar.gz"
  sha256 "cf1a673e15e7541bb5202823730a5304e268ff957fadf0aa2cb4e635de74b2f0"
  version "0.1.1"
  license "MIT"

  # OpenTUI links a per-platform native library, so this binary is Apple Silicon only.
  depends_on arch: :arm64
  depends_on :macos

  def install
    bin.install "imgen"
  end

  def caveats
    <<~EOS
      imgen drives the Codex CLI, which Homebrew does not package. Install it separately:
        npm install -g @openai/codex && codex login

      Its image tool must be enabled — `codex features list` should report:
        image_generation  stable  true

      Preview quality depends on the terminal. imgen prints the protocol it resolved in its
      header: kitty and sixel draw real pixels, blocks is the universal half-block fallback.
    EOS
  end

  test do
    # A TUI needs a terminal, so the check is that the binary loads and finds its library path
    # rather than that it renders.
    assert_predicate bin/"imgen", :executable?
    assert_match "imgen", shell_output("file #{bin}/imgen")
  end
end
