# Creating a Self-Signed Code Signing Certificate

A stable signing identity lets the Accessibility grant survive rebuilds. With
the default ad-hoc signature (`codesign --sign -`) the designated requirement
changes every time the binary changes, so TCC forgets the permission. A
self-signed certificate from Keychain Access gives a fixed identity that costs
nothing and requires no paid Developer account.

## Steps

### 1. Open Keychain Access

Launch **Keychain Access** (in `/Applications/Utilities/`, or search Spotlight).

### 2. Start the Certificate Assistant

From the menu bar choose **Keychain Access > Certificate Assistant > Create a
Certificate...**.

### 3. Fill in the certificate details

| Field | Value |
|-------|-------|
| **Name** | `Ledge Dev` |
| **Identity Type** | Self-Signed Root |
| **Certificate Type** | Code Signing |

Leave all other fields at their defaults. Click **Create**.

### 4. Trust the certificate (if prompted)

If macOS does not trust the certificate automatically, double-click it in the
**login** keychain, expand the **Trust** section, and set **Code Signing** to
**Always Trust**. Close the inspector and authenticate when prompted.

### 5. Verify

In Terminal, confirm the certificate is visible to `codesign`:

```bash
security find-identity -v -p codesigning
```

You should see a line containing `"Ledge Dev"`. The Makefile already defaults to
this name:

```bash
make app                        # signs with "Ledge Dev"
make app SIGNING_IDENTITY="-"   # falls back to ad-hoc
```

Once signed with a stable certificate, `make reset-permission` is no longer
needed after rebuilds.
