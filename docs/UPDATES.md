# Publishing New Quill updates

New Quill includes Sparkle 2.10.0. The app menu has **Check for Updates…**; Settings controls automatic checks. Installation is always chosen by the writer. Sparkle uses the normal macOS application termination flow; do not add a force-quit handler that bypasses document saving. Preview builds never start the updater.

## One-time setup

1. Create a GitHub repository, preferably `ExxtraV/new-quill`, and upload this project directory as the repository root. Include source, scripts, workflows, assets, Info.plist, Package.swift and Package.resolved. Exclude build folders, personal manuscripts and secrets (see `.gitignore`). A public repository is the simplest distribution channel. A private source repository needs a separately accessible release feed; this workflow intentionally refuses private release hosting.
2. Build once with `sh scripts/build-app.sh` to download the pinned Sparkle tools.
3. Generate a signing key using `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account new-quill`. The private key stays in your Mac's Keychain. Back it up securely; never commit it. Copy `UpdateConfig.example.json` to `UpdateConfig.json`, replacing OWNER and the public key. Only the public key and feed URL belong in this committed file. Without both, local builds show that updates aren't configured and make no update requests.
4. Get an Apple Developer ID Application certificate and notarization credentials. These are required by the production release workflow. The current local app is ad-hoc signed and is not a notarized public release.
5. Create a GitHub Actions environment named `release`. Set its variables and secrets below. For review before publishing, optionally restrict this environment to your main branch and add required reviewers.

Variables:

| Name | Value |
| --- | --- |
| `SPARKLE_PUBLIC_KEY` | Public key printed by generate_keys; must match UpdateConfig.json |
| `SIGNING_IDENTITY` | Full Developer ID Application certificate name |

Secrets:

| Name | Value |
| --- | --- |
| `APPLE_CERTIFICATE_P12_BASE64` | Base64-encoded export of the Developer ID certificate and private key |
| `APPLE_CERTIFICATE_PASSWORD` | Password protecting that export |
| `APPLE_ID` | Apple account used for notarization |
| `APPLE_TEAM_ID` | Developer team ID |
| `APPLE_APP_PASSWORD` | App-specific password for notarization |
| `SPARKLE_PRIVATE_KEY` | Contents exported by generate_keys, kept secret |

To transfer the Sparkle key to the GitHub secret, export it to a protected temporary file using `generate_keys --account new-quill -x <private-file>`. Paste its contents directly into GitHub's secret field and delete the temporary export afterward. Do not paste private keys into chat, a workflow file, or a commit.

## Each release

Update `docs/release-notes.md`. Run **Prepare signed release** from GitHub Actions with a version such as `0.5.0` and a positive build number higher than all published versions. Builds determine update ordering; never reuse them.

The workflow builds both Apple Silicon and Intel, signs nested Sparkle helpers and the app, runs tests, submits to Apple notarization, staples the result, and creates a signed update archive and appcast. Missing signing settings stop the workflow before publishing anything. A release with that version must not already exist.

It creates a **draft** release with the app archive, update feed, and checksums. Download and inspect the app, then publish the draft and mark it as the latest stable release. The stable appcast URL is `https://github.com/OWNER/new-quill/releases/latest/download/appcast.xml`; each archive URL points to its specific version. Normal code pushes only build and test; they never publish an update.

Do not mark a release without an appcast as latest. Do not move or delete the repository, change the feed address, or rotate signing keys without a migration plan for already-installed copies.

## Before the first public launch

Install the updater-enabled version manually into Applications. In a separate test environment, publish a newer signed version and verify: manual update detection, download, signature verification, save/cancel with an unsaved manuscript and edited reference, installation, relaunch, and retained document contents. Test canceled and offline checks as well. A full signed installation/relaunch test cannot be completed until the feed and Apple signing credentials are configured.

The app itself is replaced during an update. Markdown files and preferences live outside the bundle and should remain intact. Do not store real writing inside the app bundle.

References: [Sparkle setup](https://sparkle-project.org/documentation/), [publishing updates](https://sparkle-project.org/documentation/publishing/), [Apple distribution](https://developer.apple.com/macos/distribution/).
