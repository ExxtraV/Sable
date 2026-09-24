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

Update `docs/release-notes.md`. In GitHub Actions run **Prepare release**, select **community** and the **stable** channel, and supply a version such as `0.9.1` and a positive build number greater than all previously published builds (the current local build is 14).

The workflow builds both Apple Silicon and Intel, runs tests, packages the app, builds a drag-to-install disk image, signs the update archive, verifies that signature against the public key embedded in the app, and creates a draft release. It includes the app archive, appcast, release notes, and checksums of the archive and disk image. A stable release also carries the previous stable items forward in its appcast; see [Beta channel](#beta-channel). Ordinary code pushes do not publish updates.

Review and test the draft before publishing it. Mark the published release as the latest stable release so the app can reach its feed at:

https://github.com/ExxtraV/Sable/releases/latest/download/appcast.xml

Every app download in the feed points to a specific version, not a moving latest-download URL. Never reuse a version or build number or overwrite a published archive.

## Beta channel

Betas let you publish frequent builds without prompting everyone. Users opt in with **Settings → General → Get beta updates** (off by default). Sparkle does the filtering: beta appcast items carry `<sparkle:channel>beta</sparkle:channel>`, the app's updater delegate allows the `beta` channel only when that box is on, and untagged (stable) items are seen by everyone.

### Publishing a beta

Run **Prepare release** with **channel: beta**, a version like `0.9.2-beta.1` (`-beta.N`, so every beta gets its own tag and download URL), and a build number greater than every published build. The workflow builds as usual but creates a draft **pre-release**. Review it, then publish it. Publishing fires **Publish beta to update feed** (`.github/workflows/publish-beta-feed.yml`), which adds the beta to the live feed. Nothing reaches anyone before you publish the draft.

A beta needs at least one published stable release first, because the feed lives on it.

### How the feed carries betas forward

The app reads `releases/latest/download/appcast.xml`. GitHub resolves `latest` to the newest **non-prerelease** release, so the live feed is that stable release's `appcast.xml`, and a beta pre-release's own appcast is never served. Getting a beta to opted-in users therefore means writing its item into the stable release's appcast.

- Every build still signs one appcast item with `generate_appcast` (`--channel beta` for betas).
- `scripts/merge-appcast.py` merges items into the live feed, keyed by build number. It keeps the newest 3 stable and the newest 3 beta items, drops any beta at or below the newest stable build (it is superseded), and refuses download URLs outside this repository's releases. It only copies items, so it needs no signing key; the archive signatures inside them are untouched.
- **Stable release:** the workflow downloads the live feed, merges the new item into it, and attaches the result. Once you publish it, it is `latest`, and older betas fall out of the feed.
- **Beta release:** the workflow attaches only its own one-item appcast. When you publish the pre-release, **Publish beta to update feed** downloads the current live feed and the beta's appcast, merges them, and replaces `appcast.xml` on the latest stable release (`gh release upload --clobber`). It merges at publish time, so a stable release published in between is never overwritten by a stale feed.
- Because the stable release's `appcast.xml` can change after it is published, `SHA256SUMS` covers only the archive and disk image. Archives are never overwritten.

### Pulling a bad beta

Users who already installed it can't be moved backwards. Publish a newer beta (or stable) build; it replaces the bad one in the feed and, for stable, prunes it. To hide a beta from the feed sooner, delete its item from the stable release's `appcast.xml` by hand and re-upload it.

## Installing a community build

Download Sable-Markdown-Writer.dmg, open it, and drag Sable Markdown Writer onto the Applications shortcut. (The zip, Sable-Markdown-Writer.zip, is also attached; it is what the in-app updater uses.) Its displayed app name is Sable. The app is not notarized, so macOS may block its first launch. If you trust this download, use System Settings → Privacy & Security → Open Anyway. Managed Macs may prohibit this exception. Do not disable Gatekeeper globally.

A first updater-enabled installation must be installed manually. Later versions can be offered in-app. The repository has to contain a published release with an appcast before Check for Updates can succeed; until then it may report a feed/download error.

## Before relying on updates

Test an older and newer community build: detection, download, signature verification, save/cancel with an unsaved manuscript and an edited reference, installation, relaunch, and unchanged document contents. Test an offline check too. Signature tests and successful packaging do not establish that installation and relaunch work end to end. Keep real writing outside the app bundle.

## Optional paid signing later

Select **notarized** only after configuring the following GitHub environment/repository secrets: APPLE_CERTIFICATE_P12_BASE64, APPLE_CERTIFICATE_PASSWORD, APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD. Add SIGNING_IDENTITY as a variable with the full Developer ID Application certificate name. The existing SPARKLE_PRIVATE_KEY remains required. This mode signs with Developer ID, submits to Apple, staples the ticket, and checks Gatekeeper before packaging.

Keep the same bundle identifier, feed and update-signing key when moving to notarized releases. Do not rotate keys or relocate the feed without a migration plan.

References: [Sparkle setup](https://sparkle-project.org/documentation/), [Apple's first-launch instructions](https://support.apple.com/en-gb/102445).
