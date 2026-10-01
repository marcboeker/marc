cask "marc" do
  version "0.0.0"

  on_arm do
    sha256 "0000000000000000000000000000000000000000000000000000000000000000"
    url "https://github.com/marcboeker/marc/releases/download/v#{version}/Marc-macos-arm64.zip"
  end

  on_intel do
    sha256 "0000000000000000000000000000000000000000000000000000000000000000"
    url "https://github.com/marcboeker/marc/releases/download/v#{version}/Marc-macos-amd64.zip"
  end

  name "Marc"
  desc "Small Markdown window for the terminal"
  homepage "https://github.com/marcboeker/marc"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :tahoe

  app "Marc.app"
  binary "#{appdir}/Marc.app/Contents/Resources/marc"

  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/Marc.app"]
  end

  # Quit the running app before Homebrew replaces the bundle on upgrade/uninstall.
  uninstall quit: "one.m8n.marc"

  zap trash: [
    "~/Library/Preferences/one.m8n.marc.plist",
    "~/Library/Saved Application State/one.m8n.marc.savedState",
  ]
end
