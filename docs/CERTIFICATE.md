# Creating a Self-Signed Code Signing Certificate

A stable signing identity lets the Accessibility grant survive rebuilds. With
the default ad-hoc signature (`codesign --sign -`) the designated requirement
changes every time the binary changes, so TCC forgets the permission. A
self-signed certificate gives a fixed identity that costs nothing and requires
no paid Developer account.

## Quick setup (one command)

```bash
make cert
```

This creates a self-signed code signing certificate named "Ledge Dev" in your
login keychain using the `security` CLI. It works on any macOS version without
needing to find Keychain Access in the GUI.

## What it does

The `make cert` target runs:

```bash
security create-keychain -p "" ledge-dev.keychain-db 2>/dev/null || true
security default-keychain -s login.keychain-db
security find-identity -v -p codesigning | grep -q "Ledge Dev" || \
    security create-identity -s "Ledge Dev" -t codeSign -p codesigning login.keychain-db
```

If a certificate named "Ledge Dev" already exists, it does nothing.

## Verify

```bash
security find-identity -v -p codesigning
```

You should see a line containing `"Ledge Dev"`. Then:

```bash
make app          # signs with "Ledge Dev"
make reinstall    # quit → install → relaunch, permission persists
```

## If you don't want to use a certificate

Ad-hoc signing still works — you just need to re-grant Accessibility after each
rebuild:

```bash
make app SIGNING_IDENTITY="-"
make reset-permission
# relaunch and grant again
```

## Sharing the app with others

The `.dmg` from `make dmg` is always ad-hoc signed (recipients don't have your
certificate). They right-click → Open once, and it works. The certificate is
only for your development convenience.

