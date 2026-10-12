# Mesh

**Encrypted chat for old iPods. No phone number, no account, no company server. Messages travel over Nostr relays, and the app reaches them only through Tor.**

WhatsApp, Signal and Telegram block clients that are too old. Nostr relays don't care which app you use, so a client that speaks the protocol keeps working. Mesh is that client for jailbroken iPods and iPhones on iOS 4.2 to 6.1, written in Objective-C. It uses the same message format as the Mesh app for Android, so the two can talk to each other.

## How it works

**Your identity is a key pair.** On first start Mesh creates a secp256k1 key pair on the device. The public key (an `npub`) is your address. There is no sign-up, no phone number and no email. You can have several identities on one device, each with its own database.

**Adding someone means scanning their code.** The contact code contains the npub and a fresh Signal pre-key bundle with a one-time key, so even the first message has forward secrecy. The code on screen changes every 10 seconds. A scanned code stays valid until it is used. Old iPod cameras have fixed focus and struggle with dense codes, so between two iPods the code is split into three QR codes that can be scanned in any order. For Android the app can show the single full code.

**Messages are Nostr events.** Each message is encrypted, signed with your key and published to four public relays (`relay.primal.net`, `relay.snort.social`, `nos.lol`, `nostr.mom`). Your contact's app picks it up from whichever relay answers first. Events that no relay has confirmed are kept in an outbox and sent again on every reconnect. After seven days without confirmation the message is marked as not delivered.

**Encryption:**
- After the first exchange, chats use the Signal protocol (X3DH and the Double Ratchet), compatible with libsignal-protocol-java 2.8.1. Every message gets a new key. Both sides can compare a safety number, and the app warns when it changes.
- Before a Signal session exists, messages use NIP-44 (ChaCha20 and HMAC-SHA256). Messages over 64 KB fall back to NIP-04.
- Relays only ever see ciphertext, the sender's and recipient's public keys, the time and the size.

**Tor is built in.** The app ships its own Tor (0.4.9) and starts it as a separate process. All relay connections go through it. If Tor isn't ready, Mesh stays offline and never falls back to a direct connection. The first start takes a few minutes on an iPod, because Tor has to download the network directory once.

## On the device

**Unlock code.** You choose one of two options at first start:
- **6-digit PIN.** Derived with PBKDF2-HMAC-SHA256, 40,000 rounds.
- **5 or 6 random words.** Rolled by the app from a 7,776-word list (about 12.9 bits per word), derived with scrypt (N = 16384, r = 8, p = 1).

**Storage:**
- The secret key is stored only inside an encrypted vault (AES-256-CBC). The key derivation also uses a 32-byte device secret from the keychain that never leaves the device and isn't included in backups. A copied database can't be guessed at on another machine.
- After four wrong attempts the app locks for 30 seconds up to one hour. The counter lives in the keychain, so restarting or reinstalling the app doesn't reset it. Moving the clock forward doesn't shorten a lockout.
- Message contents, contact names, profile names and pictures are stored sealed in SQLite (AES-256-CBC, then HMAC-SHA256 over the ciphertext and its context). A sealed field can't be moved to another row unnoticed. Deleted rows are overwritten (`secure_delete`).

**Locking.** Pressing the sleep button, the home button or any system dialog locks the app. Before that, the secret key, the database key and the device secret are overwritten in memory.

**Emergency wipe.** Entering the panic code instead of your real one wipes the app. You can also allow a trusted contact to wipe your device remotely: it only works with a codeword you set, and only a hash of it is sent.

## Features

- Text, pictures, voice messages (with voice effects), short videos, files and contact cards
- Replies, reactions, delete for everyone, clear chat, self-destructing messages
- QR code to share and scan, safety numbers to verify contacts
- Requests from strangers stay separate until you answer. Pictures from them are only shown after you accept.
- Several identities on one device
- German and English

## Limits

| | |
|---|---|
| Messages between contacts | no limit |
| Text per message | 64 KB |
| File per message | 500 KB |
| Video | 20 seconds |
| Voice message | 60 minutes |
| Profile picture | 300 KB |
| Strangers (not yet accepted) | 50 at most, 100 messages or 5 MB each, 20 MB together. The oldest is dropped first. |

## What Mesh does not protect

- **Metadata in the network.** Relays see which public keys write to each other and when. Tor hides your IP address from them, but not the keys.
- **Your profile is public.** Name, "about" and profile picture are published as a normal Nostr profile (kind 0) that anyone can read. Leave them empty if that matters to you.
- **Metadata on the device.** To search and sort, the database keeps public keys, times, delivery status and media sizes unencrypted. Who you talk to is visible on the device, what you say is not.
- **Root access with a PIN.** On a jailbroken device, someone with root can read the keychain and the database together. A 6-digit PIN then falls in seconds to minutes offline. Five random words (about 65 bits with scrypt) still hold. If this matters to you, use words.
- **Jailbreak and old iOS.** The device itself is old and jailbroken, and Mesh can't fix that.
- **No audit.** The cryptography is tested against official test vectors and against libsignal, but nobody independent has reviewed it.

## Status

| Device | iOS | Status |
|---|---|---|
| iPod touch 4G | 6.1.6 | works, with Tor |
| iPod touch 3G | 5.1.1 | same package, device test pending |
| iPod touch 2G | 4.2.1 | code ready, needs an ARMv6 toolchain ([docs/PORTING.md](docs/PORTING.md)) |

## Install

Easiest via the **[Reboot App Store](https://github.com/SecondTrack/reboot)** right on the iPod. By hand: download the `.deb` from the [latest release](https://github.com/SecondTrack/mesh/releases/latest), install it with `dpkg -i`, then run `uicache`.

## Build

Requirements: [Theos](https://theos.dev), the iOS 7.1 SDK under `$THEOS/sdks/`, and the vendored libraries under `vendor/` (see `vendor/README.md`).

```sh
export THEOS=~/theos
make package                    # release build, no log
make package FINALPACKAGE=0     # debug build, writes Documents/mesh.log (test devices only)
make package MESH_TOR=0         # without Tor (e.g. ARMv6)
```

If `xcrun` stops with an arm64e error, an old Xcode is selected: `export DEVELOPER_DIR=/Library/Developer/CommandLineTools`.

## Tests

`tests/run.sh` runs on a Mac without a device, in about 30 seconds. It covers:
- the cryptography against official vectors (NIP-44, ChaCha20 from RFC 8439, HKDF from RFC 5869, Curve25519 from RFC 7748/8032, scrypt from RFC 7914, PBKDF2)
- Signal between two instances, plus `tools/dev/interop/run.sh` against libsignal-protocol-java
- the message format and the store, vault and database encryption
- two simulated devices exchanging messages
- attack tests: malformed WebSocket frames, Bech32, relay messages, image headers, tampered sealed fields, the PIN lockout and certificate time

For the crypto and vault tests: `brew install secp256k1`.

Layers, threads, data flow and the full security model: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## License

GPL-3.0, see [LICENSE](LICENSE). Libraries under `vendor/` keep their own licenses: secp256k1, mbedTLS, qrcodegen, quirc and Tor.
Not affiliated with Apple. iPod is a trademark of Apple Inc.
