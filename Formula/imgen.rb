class Imgen < Formula
  desc "Terminal browser and generator for the images the Codex CLI makes"
  homepage "https://github.com/AndrewDongminYoo/imgen"
  url "https://github.com/AndrewDongminYoo/imgen/releases/download/v0.7.0/imgen-darwin-arm64.tar.gz"
  version "0.7.0"
  sha256 "2ac4c246fb8df4cb62d41d862e47fae7bc2eca3f330d60e24a9c0a81691c6d7b"
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
    # --version answers before the renderer claims the terminal, so this runs the binary for real:
    # it loads the native library and reports its own version, neither of which `file` could show.
    assert_match version.to_s, shell_output("#{bin}/imgen --version")
  end
end
