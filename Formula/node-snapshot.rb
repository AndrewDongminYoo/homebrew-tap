class NodeSnapshot < Formula
  desc "Manage nvm LTS versions and global npm packages with snapshots"
  homepage "https://github.com/AndrewDongminYoo/homebrew-tap"
  # Fill url + sha256 after creating a GitHub release tag
  url "https://github.com/AndrewDongminYoo/homebrew-tap/archive/refs/tags/v0.4.3.tar.gz"
  sha256 "497c6fa407091d9e481b1d4e697c90ff5c68e629d31ba2394a979e52eb362592"
  version "0.4.3"
  license "MIT"

  head "https://github.com/AndrewDongminYoo/homebrew-tap.git", branch: "main"

  depends_on "jq"

  def install
    bin.install "bin/node-snapshot"
    (libexec/"node-snapshot"/"commands").install Dir["libexec/node-snapshot/commands/*"]

    # Rewrite LIBEXEC_DIR in the entry point to the Homebrew prefix path
    inreplace bin/"node-snapshot",
      %r{\$\{_self\}/\.\./libexec/node-snapshot/commands},
      "#{opt_libexec}/node-snapshot/commands"
  end

  def caveats
    <<~EOS
      Add shell integration to your .zshrc:
        source <(node-snapshot init)

      On first run, create a config with your tracked LTS aliases:
        mkdir -p ~/.local/share/node-snapshot
        echo '{"tracked":["iron","jod","krypton"],"check_interval_days":7,"last_check_utc":""}' \\
          > ~/.local/share/node-snapshot/config.json

      Default state directory: ~/.local/share/node-snapshot/
      Override: export NODE_SNAPSHOT_DIR=/your/path
    EOS
  end

  test do
    # Dispatcher
    assert_match "Usage: node-snapshot", shell_output("#{bin}/node-snapshot help")
    assert_match "Usage: node-snapshot", shell_output("#{bin}/node-snapshot --help")
    assert_match "node-snapshot",        shell_output("#{bin}/node-snapshot --version")
    assert_match "unknown command",      shell_output("#{bin}/node-snapshot bogus 2>&1", 1)

    # Use an isolated state directory so tests never touch the real home
    ENV["NODE_SNAPSHOT_DIR"] = (testpath/"state").to_s

    # status: no config → guidance message, exit 0
    assert_match "No snapshot found", shell_output("#{bin}/node-snapshot status")

    # status: config present → shows alias in table
    snap = testpath/"state"
    snap.mkpath
    (snap/"config.json").write(
      '{"tracked":["iron"],"check_interval_days":7,"last_check_utc":""}'
    )
    status_out = shell_output("#{bin}/node-snapshot status")
    assert_match "State directory:", status_out
    assert_match "iron",             status_out

    # init: emits shell function definition
    init_out = shell_output("#{bin}/node-snapshot init")
    assert_match "_node_snapshot_chpwd", init_out
    assert_match "add-zsh-hook",         init_out
  end
end
