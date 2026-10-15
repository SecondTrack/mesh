# Mesh

**Encrypted chat for old iPods. No phone number, no account, no company server.**

Mesh is a Nostr messenger for jailbroken iPods and iPhones on iOS 4.2 to 6.1.

## How it works

- **Your identity is a key pair** created on the device. No sign-up, no phone number.
- **Contacts are added by scanning a QR code.** Between two iPods the code is split into three parts, because old cameras can't read dense codes.
- **Messages go through public Nostr relays.** They are end-to-end encrypted with the Signal protocol (NIP-44 until the first exchange). Relays only see ciphertext, public keys and timestamps.
- **All connections go through Tor**, which ships with the app. Without Tor, Mesh stays offline instead of connecting directly.

## Features

- Chats with text, pictures, voice messages (with voice effects), replies, reactions, delete for everyone, disappearing messages and a media gallery per chat.
- Groups of up to 20: one admin, group picture, admin handover, members can suggest contacts, open groups with an invite link. Protocol: [docs/TEAM_GROUPS_PROTOCOL.md](docs/TEAM_GROUPS_PROTOCOL.md).
- Safety numbers to verify a contact, also by scanning a QR code.
- Its own keyboard with emoji images, so every emoji shows on iOS 6 too, plus a frog emoji set.
- Several identities on one device.
- Works with the Mesh Android app: same message format.

## On the device

- Unlock with a 6-digit PIN or 5–6 random words.
- Messages, names and pictures are stored encrypted. Keys are wiped from memory when the app locks.
- Lockout after wrong attempts, plus an emergency wipe code.

## Old iOS, known bugs

iOS 6 no longer gets security updates and has known holes, so Mesh routes around the system instead of trusting it:

- **Images:** JPEG and PNG only. Header and size are checked in Mesh's own code before the system decoder sees them (no TIFF, the classic exploit vector).
- **PDF, Office, HTML:** never opened, so QuickLook and the old WebKit stay out of the picture.
- **TLS:** bundled mbedTLS instead of iOS 6's SecureTransport.
- **Strangers:** media from contacts you haven't accepted is not rendered at all.
- **Remaining surface:** MP4 videos play in the system player (accepted contacts only), and the iOS kernel itself.

## Good to know

- Your profile name and picture are public on the relays. Leave them empty if you want to stay anonymous.
- Relays can see which keys talk to each other. Tor hides your IP address, not your key.
- On a jailbroken device, someone with root access can brute-force a PIN. Random words still hold.
- The code has not been independently audited.

## Code structure

The code lives in `mesh/`, one folder per layer. A layer may only use the layers below it; `tests/layers_check.sh` checks this on every test run by reading the `#import` lines.

```
mesh/
  App/        start-up: main, AppDelegate (window, locks when the app goes to the background)
  UI/         all screens; they talk to the rest only through MeshSession
    Lock/       unlock, protection setup, recovery words, connecting screen
    Chats/      chat list, new group
    Chat/       chat, bubbles, input bar, menus, gallery, group profile, invites, invite links
    Contacts/   add contact, QR scanner, contact profile, safety number
    Me/         own profile, own code, identities
    Settings/   security, audio, voice effects
    Common/     building blocks: headers, popups, avatars, keyboard, emoji rendering, text fields
  Domain/     logic: MeshSession (the single entry point for the UI), identities, messenger,
              groups, Signal, PIN and vault, emergency wipe, inbox rules for strangers
  Media/      images, video, audio: decoding, checks, recording, voice effects, QR detection
  Transport/  network: relay pool, relay, WebSocket, TLS (mbedTLS), Tor, network status
  Storage/    sqlite database with sealed fields, migrations, outbox, vault
  Protocol/   formats: Nostr events, message envelope, NIP-04/NIP-44, Signal wire format,
              contact code, group state, invite link, safety number
  Model/      plain data objects: chat, message, payload, profile, group
  Crypto/     primitives: hash, HMAC, HKDF, AES, ChaCha20, scrypt, Curve25519, sealing
  Compat/     switches for iOS 4.2 to 6, JSON
  Support/    Base64, text, time, logging, memory wiping, notifications
tests/        Mac tests (tests/run.sh), fakes and fixtures
tools/        self-test, developer tools (dev/), icon generation (assets/)
vendor/       secp256k1, mbedTLS, qrcodegen, quirc (build notes in vendor/README.md)
Resources/    strings (de/en), word lists, emoji images, icons, CA certificates
docs/         architecture, porting, group protocol, design preview
```

| Layer     | may use |
|-----------|---------|
| App       | UI, Domain, Support |
| UI        | Domain, Media, Model, Compat, Support |
| Domain    | Transport, Storage, Protocol, Model, Crypto, Compat, Support |
| Media     | Support |
| Transport | Protocol, Crypto, Compat, Support |
| Storage   | Model, Crypto, Support |
| Protocol  | Crypto, Support |
| Model     | Support |
| Crypto    | Support |
| Compat    | Support |
| Support   | – |

The UI never touches the database, the relays or any keys; new features become a method on `MeshSession`. Only `Storage/` opens sqlite, and only the vault sees key material.

**How a message travels**

- *Sending:* screen → `MeshSession` → `MeshMessenger` (in groups once per member) → `MeshEnvelope` builds the plaintext → `MeshSignal` or NIP-44 encrypts → `MeshEvent` signs → `MeshStore` saves it, including the outbox → `MeshRelayPool` sends it to every relay.
- *Receiving:* relay → signature check → `MeshMessenger` decrypts and decides: message, control message or group change → `MeshStore` → the screens get notified.

Threads, database, keys, locking and iOS versions in detail: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Install

Via the **[Reboot App Store](https://github.com/SecondTrack/reboot)** on the iPod, or download the `.deb` from the [latest release](https://github.com/SecondTrack/mesh/releases/latest) and install it with `dpkg -i`, then run `uicache`.

## Build

With [Theos](https://theos.dev) and the iOS 7.1 SDK: `make package`. Tests run on a Mac with `tests/run.sh`. Details on the design and security model are in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## License

GPL-3.0, see [LICENSE](LICENSE). Libraries under `vendor/` keep their own licenses.
Not affiliated with Apple. iPod is a trademark of Apple Inc.
