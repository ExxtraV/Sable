# Publishing Sable Markdown Writer updates

Sable Markdown Writer is MIT licensed at https://github.com/ExxtraV/Sable. The default **community** release works without paid Apple membership. It is ad-hoc signed, not notarized by Apple. Sparkle separately verifies update downloads with Sable's Ed25519 signing key.

## One-time setup for free-account releases

The public feed URL and public signing key are committed in `UpdateConfig.json`. The private key is stored in the Mac Keychain under the Sparkle account `new-quill` (the account keeps its original name from before the rename; that is only a local label, so leave it as it is); never put it in source control.

In GitHub, open Settings → Secrets and variables → Actions → New repository secret. Name it `SPARKLE_PRIVATE_KEY` and enter the contents of the protected local key export directly into GitHub. Do not paste it into chat or a commit. Keep a secure backup in your password manager or encrypted storage. The `.secrets/` directory is ignored by Git.

### Keep the signing key safe

The Keychain copy is the only one you can read back: GitHub secrets can be used by workflows but never viewed again, and the login Keychain does not sync through iCloud. If the private key is lost, existing installs can no longer receive updates and everyone has to download the next version by hand. If it leaks and someone also gains control of the repository, they could ship a malicious update.

- Check that the key is still present. This prints only the public key, which must match `publicKey` in `UpdateConfig.json`:
  `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account new-quill -p`
- Back it up once: `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account new-quill -x ~/Desktop/sable-sparkle-private-key`, store that file's contents in your password manager (or an encrypted disk image), then delete the file and empty the Trash.
- Protect the GitHub account with two-factor authentication (a passkey is best), and require your own approval on the `release` environment (Settings → Environments → release → Required reviewers).

No Apple certificate, Apple account password, notarization credentials, or paid membership is needed for community releases. The workflow reads the public key from UpdateConfig.json automatically.

## Each release

Update `docs/release-notes.md`. In GitHub Actions run **Prepare release**, select **community**, and supply a version such as `0.9.1` and a positive build number greater than all previously published builds (the current local build is 13).

The workflow builds both Apple Silicon and Intel, runs tests, packages the app, builds a drag-to-install disk image, signs the update archive, verifies that signature against the public key embedded in the app, and creates a draft release. It includes the app archive, appcast, release notes, and checksums. Ordinary code pushes do not publish updates.

Review and test the draft before publishing it. Mark the published release as the latest stable release so the app can reach its feed at:

https://github.com/ExxtraV/Sable/releases/latest/download/appcast.xml

Every app download in the feed points to a specific version, not a moving latest-download URL. Never reuse a version or build number or overwrite a published archive.

## Installing a community build

Download Sable-Markdown-Writer.dmg, open it, and drag Sable Markdown Writer onto the Applications shortcut. (The zip, Sable-Markdown-Writer.zip, is also attached; it is what the in-app updater uses.) Its displayed app name is Sable. The app is not notarized, so macOS may block its first launch. If you trust this download, use System Settings → Privacy & Security → Open Anyway. Managed Macs may prohibit this exception. Do not disable Gatekeeper globally.

A first updater-enabled installation must be installed manually. Later versions can be offered in-app. The repository has to contain a published release with an appcast before Check for Updates can succeed; until then it may report a feed/download error.

## Before relying on updates

Test an older and newer community build: detection, download, signature verification, save/cancel with an unsaved manuscript and an edited reference, installation, relaunch, and unchanged document contents. Test an offline check too. Signature tests and successful packaging do not establish that installation and relaunch work end to end. Keep real writing outside the app bundle.

## Optional paid signing later

Select **notarized** only after configuring the following GitHub environment/repository secrets: APPLE_CERTIFICATE_P12_BASE64, APPLE_CERTIFICATE_PASSWORD, APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD. Add SIGNING_IDENTITY as a variable with the full Developer ID Application certificate name. The existing SPARKLE_PRIVATE_KEY remains required. This mode signs with Developer ID, submits to Apple, staples the ticket, and checks Gatekeeper before packaging.

Keep the same bundle identifier, feed and update-signing key when moving to notarized releases. Do not rotate keys or relocate the feed without a migration plan.

References: [Sparkle setup](https://sparkle-project.org/documentation/), [Apple's first-launch instructions](https://support.apple.com/en-gb/102445).
