cask "marcdown" do
  version "0.1.1"

  on_arm do
    sha256 "3368b70fe57ab090dedbca986250f96576b052a6b1301265420470e72baa9843"
    url "https://github.com/marcboeker/marcdown/releases/download/v#{version}/Marcdown-macos-arm64.zip"
  end

  on_intel do
    sha256 "b15f51a2b78f88b7af778883517e8699f41d014871dc399230a2e8585b2f51c3"
    url "https://github.com/marcboeker/marcdown/releases/download/v#{version}/Marcdown-macos-amd64.zip"
  end

  name "Marcdown"
  desc "Small Markdown window for the terminal"
  homepage "https://github.com/marcboeker/marcdown"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :tahoe

  app "Marcdown.app"
  binary "#{appdir}/Marcdown.app/Contents/Resources/marcdown"

  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/Marcdown.app"]
  end

  # Quit the running app before Homebrew replaces the bundle on upgrade/uninstall.
  uninstall quit: "one.m8n.marcdown"

  zap trash: [
    "~/Library/Preferences/one.m8n.marcdown.plist",
    "~/Library/Saved Application State/one.m8n.marcdown.savedState",
  ]
end
