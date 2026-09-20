# Publishing New Quill updates

New Quill is MIT licensed at https://github.com/ExxtraV/new-quill. The default **community** release works without paid Apple membership. It is ad-hoc signed, not notarized by Apple. Sparkle separately verifies update downloads with New Quill's Ed25519 signing key.

## One-time setup for free-account releases

The public feed URL and public signing key are committed in `UpdateConfig.json`. The private key is stored in the Mac Keychain under the Sparkle account `new-quill`; never put it in source control.

In GitHub, open Settings → Secrets and variables → Actions → New repository secret. Name it `SPARKLE_PRIVATE_KEY` and enter the contents of the protected local key export directly into GitHub. Do not paste it into chat or a commit. Keep a secure backup in your password manager or encrypted storage. The `.secrets/` directory is ignored by Git.

No Apple certificate, Apple account password, notarization credentials, or paid membership is needed for community releases. The workflow reads the public key from UpdateConfig.json automatically.

## Each release

Update `docs/release-notes.md`. In GitHub Actions run **Prepare release**, select **community**, and supply a version such as `0.6.1` and a positive build number greater than all previously published builds (the current local build is 8).

The workflow builds both Apple Silicon and Intel, runs tests, packages the app, signs the update archive, verifies that signature against the public key embedded in the app, and creates a draft release. It includes the app archive, appcast, release notes, and checksums. Ordinary code pushes do not publish updates.

Review and test the draft before publishing it. Mark the published release as the latest stable release so the app can reach its feed at:

https://github.com/ExxtraV/new-quill/releases/latest/download/appcast.xml

Every app download in the feed points to a specific version, not a moving latest-download URL. Never reuse a version or build number or overwrite a published archive.

## Installing a community build

Download New-Quill.zip, unzip it, and move Quill.app into Applications. Its displayed app name is New Quill. The app is not notarized, so macOS may block its first launch. If you trust this download, use System Settings → Privacy & Security → Open Anyway. Managed Macs may prohibit this exception. Do not disable Gatekeeper globally.

A first updater-enabled installation must be installed manually. Later versions can be offered in-app. The repository has to contain a published release with an appcast before Check for Updates can succeed; until then it may report a feed/download error.

## Before relying on updates

Test an older and newer community build: detection, download, signature verification, save/cancel with an unsaved manuscript and an edited reference, installation, relaunch, and unchanged document contents. Test an offline check too. Signature tests and successful packaging do not establish that installation and relaunch work end to end. Keep real writing outside the app bundle.

## Optional paid signing later

Select **notarized** only after configuring the following GitHub environment/repository secrets: APPLE_CERTIFICATE_P12_BASE64, APPLE_CERTIFICATE_PASSWORD, APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD. Add SIGNING_IDENTITY as a variable with the full Developer ID Application certificate name. The existing SPARKLE_PRIVATE_KEY remains required. This mode signs with Developer ID, submits to Apple, staples the ticket, and checks Gatekeeper before packaging.

Keep the same bundle identifier, feed and update-signing key when moving to notarized releases. Do not rotate keys or relocate the feed without a migration plan.

References: [Sparkle setup](https://sparkle-project.org/documentation/), [Apple's first-launch instructions](https://support.apple.com/en-gb/102445).
