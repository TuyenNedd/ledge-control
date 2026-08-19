# Setting Up Code Signing

A stable signing identity lets the Accessibility grant survive rebuilds. Without it,
macOS forgets the permission every time the binary changes.

## Quick setup (one-time, free, no paid Developer account needed)

### 1. Create the certificate in Xcode

1. Open **Xcode → Settings → Accounts** (⌘,)
2. Add your Apple ID if not already there (the "+" button)
3. Select your account → **Manage Certificates...**
4. Click "+" → **Apple Development**
5. Done — close the dialog

### 2. Trust the certificate

```bash
make cert
```

This downloads the Apple WWDR intermediate certificate so macOS trusts your
development cert. Only needed once.

### 3. Verify

```bash
security find-identity -v -p codesigning
```

You should see:
```
1) XXXXXXXX "Apple Development: you@email.com (XXXXXXXXXX)"
   1 valid identities found
```

### 4. Update the Makefile (if your email is different)

The Makefile defaults to:
```makefile
SIGNING_IDENTITY ?= Apple Development: trituyen2003@gmail.com (NZFRWQGKR8)
```

If you're a different developer, override it:
```bash
make app SIGNING_IDENTITY="Apple Development: your@email.com (YOUR_ID)"
```

Or change the default in the Makefile.

## After setup

```bash
make reinstall    # quit → build → sign → install → relaunch
```

Permission persists across rebuilds. No more `make reset-permission`.

## For distribution (sharing with others)

`make dmg` always uses ad-hoc signing — recipients don't need your certificate.
They right-click → Open once, and it works.
