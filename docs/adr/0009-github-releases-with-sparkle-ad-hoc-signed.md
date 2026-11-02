# Distribute through GitHub Releases, auto-update with Sparkle, ad-hoc signed

Skinny ships as a zipped `Skinny.app` attached to a GitHub Release on `asharism/skinny-dip`, built and published by one command, `scripts/release.sh <version>`. Installed copies update themselves with Sparkle 2. Sparkle reads `releases/latest/download/appcast.xml`, a one-item feed uploaded as an asset on each release, so nothing needs hosting and nothing is committed per release.

There is no Apple Developer ID yet, so releases are **ad-hoc signed and not notarized**. Sparkle accepts an ad-hoc update when its EdDSA signature checks out against the `SUPublicEDKey` in the installed app. The Apple code-signing check fails for ad-hoc builds, and Sparkle only needs one of the two checks to pass. We verified a real 0.1.0 → 0.2.0 update of the sandboxed app on macOS 26. The update is downloaded by the app itself, and Sparkle removes the quarantine flag from it, so Gatekeeper only intervenes on the very first manual install (System Settings → Privacy & Security → Open Anyway).

Alternatives we rejected:
- Paying for the Apple Developer Program now. It's still the upgrade path: `release.sh` switches to Developer ID signing plus notarization as soon as that identity is in the keychain.
- A hand-rolled updater against the GitHub API, which would mean writing our own download, verify, replace and relaunch for a sandboxed app.
- The Mac App Store, which is out of MVP scope.

## Consequences

- **The EdDSA private key is irreplaceable.** It lives in the login keychain. Ad-hoc apps have no Team-ID fallback for key rotation, so if the key is lost, every installed copy is stranded on its version. Export it with `generate_keys -x` and keep it in a password manager.
- Ad-hoc identity is the binary's hash, so after each update macOS may ask again for microphone and speech-recognition (dictation) permission. Developer ID signing removes this.
- Build numbers come from `git rev-list --count HEAD`, and Sparkle only offers a higher build. The script refuses to publish a build that isn't higher than the latest release's.
- The sandbox needs `SUEnableInstallerLauncherService` plus the `-spks`/`-spki` mach-lookup exceptions. Hardened Runtime stays off while ad-hoc signed, because library validation would block Sparkle.
- The multiplatform target needs the Mac rpath `@executable_path/../Frameworks` to load embedded frameworks. Without it, the app crashed at launch. The script checks for it.
- Debug builds never start the updater. Releases check daily and ask before installing, and the app menu has **Check for Updates…**.
- The app is named **Skinny**, but its bundle ID stays `com.hitesh.SkinnyDip`, so the sandbox container, Scratch Documents and settings carry over.
