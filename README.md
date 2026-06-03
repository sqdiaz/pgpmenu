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
| Refresh Keys | R | Reload keyring after importing new keys |
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

