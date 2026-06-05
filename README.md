# PGPMenu

A free, lightweight macOS menu bar app for GPG encryption.

## Why?

Alternatives cost money. PGPMenu gives you encrypt/decrypt/sign/verify from the menu bar, working with **any** app via the clipboard.

## How It Works

PGPMenu sits in your menu bar (🔒). It operates on your clipboard:

1. Copy text you want to encrypt/decrypt
2. Click the menu bar icon → choose action
3. Result replaces your clipboard
4. Paste wherever you need it

## Requirements

- macOS 12+
- GnuPG: `brew install gnupg`
- At least one GPG key: `gpg --full-generate-key`
- Alternatively, get the [GPG Suite](https://gpgtools.org) if you prefer to have a GUI.

## Install

### From release (easiest)

Download the latest `PGPMenu.zip` from [Releases](../../releases), unzip, and drag to Applications.

### From source

```bash
git clone https://github.com/YOUR_USERNAME/PGPMenu.git
cd PGPMenu
make install   # builds and copies to /Applications
```

## Usage

### Sending encrypted email

1. Write your email in plain text
2. Select all → Copy
3. **PGPMenu → Encrypt → pick recipient**
4. Paste into email → Send

### Reading encrypted email

1. Copy the PGP block (`-----BEGIN PGP MESSAGE-----` ... `-----END...`)
2. **PGPMenu → Decrypt**
3. Paste somewhere to read

### Signing & verifying

- **Sign:** Proves a message is from you (text stays readable)
- **Verify:** Checks if a signed message is authentic

## Menu Reference

| Item | Shortcut | Description |
|------|----------|-------------|
| Encrypt Clipboard → | E | Encrypt for a specific recipient (submenu lists your keys) |
| Decrypt Clipboard | D | Decrypt a PGP message using your private key |
| Sign Clipboard | S | Clearsign text with your key |
| Verify Clipboard | V | Check signature validity |
| Clear Clipboard Now | X | Immediately wipe clipboard contents |
| Auto-Clear Timeout → | | Choose auto-clear delay (15s, 30s, 60s, Never) |
| Manage Keys… | K | Open the key management window |
| Refresh Keys | R | Reload keyring after importing new keys |

## Clipboard Security

PGPMenu automatically clears your clipboard after decryption to prevent sensitive plaintext from lingering:

- **Auto-clear timer:** After decrypting, the clipboard is wiped after 30 seconds (configurable).
- **Ownership check:** Only clears if the clipboard still contains PGPMenu's output (won't wipe your other copies).
- **Manual clear:** Use "Clear Clipboard Now" (⌘X) to wipe immediately.
- **On quit:** Clipboard is cleared when you quit PGPMenu.

> **Note:** This is best-effort protection. Other apps may read the clipboard before it's cleared. For maximum security, paste immediately and clear manually.

## Key Management

The **Manage Keys…** window provides a GUI for your GPG keyring:

- **View** all public and secret keys with name, email, key ID, type, creation/expiry dates
- **Import** keys from `.asc` or `.gpg` files
- **Export** public keys to armored ASCII files
- **Delete** keys (secret key deletion requires typing the fingerprint suffix as confirmation)
- **Copy** full fingerprints to clipboard
| Launch at Login | | Toggle automatic startup at login |

## Adding Recipients

Before you can encrypt for someone, you need their public key:

```bash
# Import a key file
gpg --import friend.asc

# Or fetch from a keyserver
gpg --keyserver keys.openpgp.org --recv-keys THEIR_KEY_ID
```

They'll then appear in the Encrypt submenu.

## License

[GPLv3](LICENSE)

