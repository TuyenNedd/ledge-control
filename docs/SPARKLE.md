# Sparkle Auto-Update Setup

Ledge uses [Sparkle 2.x](https://sparkle-project.org/) for in-app auto-updates. The appcast is
hosted on GitHub Pages at `https://tuyennedd.github.io/ledge-control/appcast.xml`.

## How It Works

1. On every tagged release (`v*`), the release workflow builds a `.dmg`, creates a GitHub
   Release, generates an `appcast.xml` entry, and pushes it to the `gh-pages` branch.
2. A separate Pages workflow deploys the `gh-pages` branch to GitHub Pages.
3. On launch, Sparkle checks the appcast feed URL (configured in `Info.plist` via `SUFeedURL`)
   and offers to install newer versions.

## Generating Ed25519 Signing Keys

Sparkle uses Ed25519 signatures to verify that updates are authentic. To generate a key pair:

```bash
# From a macOS machine with Sparkle checked out or embedded in your app:
./Sparkle.framework/Resources/generate_keys
```

This prints a **public key** and stores the **private key** in your macOS Keychain.

### Storing the Keys

1. **Public key** - paste it into `Resources/Info.plist` under the `SUPublicEDKey` key.
2. **Private key** - export it and store it as the GitHub Actions secret `SPARKLE_PRIVATE_KEY`.
   This will be used in CI to sign the `.dmg` before generating the appcast entry.

## Signing Releases (Future Enhancement)

Once keys are generated, the release workflow should be updated to:

1. Sign the `.dmg` using `sign_update`:
   ```bash
   echo "$SPARKLE_PRIVATE_KEY" | ./Sparkle.framework/Resources/sign_update \
       dist/Ledge-X.Y.Z.dmg
   ```
2. Insert the resulting `edSignature` and `length` into the appcast `<enclosure>` element.

## Current Status

Until signing keys are generated:

- Auto-update checks work and will detect new versions.
- Signature verification is skipped (the `SUPublicEDKey` in Info.plist is empty).
- Users will still be prompted to download new versions, but without cryptographic assurance
  that the update is untampered.

## Relevant Files

| File | Purpose |
|------|---------|
| `Resources/Info.plist` | Contains `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks` |
| `Sources/Ledge/UpdateController.swift` | Sparkle wrapper initialized at launch |
| `.github/workflows/release.yml` | Builds DMG, generates appcast, pushes to gh-pages |
| `.github/workflows/pages.yml` | Deploys gh-pages branch to GitHub Pages |
