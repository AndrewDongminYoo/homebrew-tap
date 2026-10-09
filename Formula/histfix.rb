class Histfix < Formula
  desc "Find and replace zsh history with previews and regex capture groups"
  homepage "https://github.com/AndrewDongminYoo/zsh-histfix"
  license "MIT"
  head "https://github.com/AndrewDongminYoo/zsh-histfix.git", branch: "main"

  depends_on "python@3.14"

  def install
    (share/"histfix").install "histfix.plugin.zsh", "histfix.py", "_histfix"
    inreplace share/"histfix/histfix.plugin.zsh",
      ":-python3}", ":-#{formula_opt_bin("python@3.14")}/python3.14}"
    (pkgshare/"doc").install "README.md"
  end

  def caveats
    <<~EOS
      Add this after your history configuration in .zshrc:
        source #{opt_share}/histfix/histfix.plugin.zsh

      Preview and confirm a replacement:
        histfix replace 'gpt-6.1-astra' 'gpt-6-astra'

      For replacement and undo, start a fresh zsh session configured without SHARE_HISTORY.
      Close other shells sharing HISTFILE before applying changes.
      Undo the last replacement with: histfix undo
    EOS
  end

  test do
    history_file = testpath/"history"
    invocation = ": 101:0;histfix test invocation\n"
    original = ": 100:1;codex --model gpt-6-sol\n#{invocation}"
    history_file.write original
    script = <<~EOS
      HISTFILE='#{history_file}'
      HISTSIZE=100
      SAVEHIST=100
      fc -R "$HISTFILE"
      source '#{share}/histfix/histfix.plugin.zsh'
      histfix replace --regex 'gpt-6(?:\\.\\d+)?-(sol)' 'gpt-6.1-$1' <<< y || exit 1
      print -s -- 'history-reader-sentinel'
      [[ "${(v)history}" == *gpt-6.1-sol* ]] || exit 2
      HISTFILE=''
    EOS
    system "/bin/zsh", "-f", "-i", "-c", script
    assert_equal ": 100:1;codex --model gpt-6.1-sol\n#{invocation}", history_file.read
    system "/bin/zsh", "-f", "-i", "-c", <<~EOS
      HISTFILE='#{history_file}'
      HISTSIZE=100
      SAVEHIST=100
      fc -R "$HISTFILE"
      source '#{share}/histfix/histfix.plugin.zsh'
      histfix undo <<< y || exit 1
      HISTFILE=''
    EOS
    assert_equal original, history_file.read
  end
end
