# Security Policy

## Supported versions

Sable Markdown Writer is pre-1.0 and ships a single rolling release. Only the
[latest release](https://github.com/ExxtraV/Sable/releases/latest) is
supported; please update before reporting an issue.

## Reporting a vulnerability

**Please don't open a public issue for a security vulnerability.**

Report it privately through GitHub Security Advisories:

1. Go to the [Security tab](https://github.com/ExxtraV/Sable/security) of this repository.
2. Click **Report a vulnerability** to open a draft advisory.
3. Describe the issue: what it is, where it lives (app code, a build/release
   script, or the update mechanism), and, if you can, the steps to reproduce
   it or a proof of concept.

This opens a private conversation with the maintainers that isn't visible to
the public until a fix is ready.

If you're unable to use GitHub Security Advisories for some reason, open a
regular issue asking to be contacted privately, without describing the
vulnerability, and a maintainer will follow up.

## Scope

Sable is a local, offline-first Markdown editor: there is no account system,
server, or telemetry to compromise. Areas most worth a careful look include:

- The Sparkle auto-update path (`UpdateConfig.json`, `SUFeedURL`/`SUPublicEDKey`
  in `Info.plist`, and `scripts/prepare-release.sh`) — anything that could let
  an unsigned or tampered update be accepted.
- File handling and Markdown/HTML import (`Sources/Quill/Import.swift`) —
  anything that could lead to unexpected code or script execution from an
  opened document.
- The release pipeline (`.github/workflows/release.yml`, `scripts/*.py`) —
  anything that could leak signing material or credentials.

## What to expect

We aim to acknowledge new reports within a few days and to keep you updated
as the issue is investigated. Once a fix is released, we'll credit you in the
release notes if you'd like (or keep you anonymous if you'd rather).
