# Mesh

**Encrypted chat for old iPods – no phone number, no account, no central server. Runs over Nostr and Tor.**

WhatsApp, Signal and Telegram lock out old clients on the server side. Nostr relays don't: your own client keeps working as long as it speaks the protocol. Mesh is that client for iPods and iPhones on iOS 4.2 to 6.1 – and the counterpart to the Mesh Android app: same design, same message format, they talk to each other.

## Status

| Device        | iOS   | Status |
|---------------|-------|--------|
| iPod touch 4G | 6.1.6 | works  |
| iPod touch 3G | 5.1.1 | same package, device test pending |
| iPod touch 2G | 4.2.1 | code ready, needs an ARMv6 toolchain (docs/PORTING.md) |

Features: your own secp256k1 identity without an account, NIP-04 encrypted direct messages,
pictures and voice messages (with voice effects), QR code for sharing and scanning, safety number
for verifying contacts, unlock code with lockout and device binding, encrypted
database, TLS with certificate checks. Security model: docs/ARCHITECTURE.md.

## Build

Requirements: [Theos](https://theos.dev), iOS 7.1 SDK under `$THEOS/sdks/`, the vendored
libraries under `vendor/` (instructions in `vendor/README.md`).

```sh
export THEOS=~/theos
make package                    # release build, no log
make package FINALPACKAGE=0     # debug build, writes Documents/mesh.log (test devices only)
```

If `xcrun` aborts with an arm64e message, an old Xcode is selected:
`export DEVELOPER_DIR=/Library/Developer/CommandLineTools`.

Install: copy the `.deb` from `packages/` to the device via SSH, `dpkg -i`, then `uicache`.

## Tests

```sh
tests/run.sh                    # all Mac tests, about 30 s
tools/dev/build.sh              # counterpart (nostrbot), single send, relay query
```

For the crypto and vault tests: `brew install secp256k1`.

## Layout

Layers, threads, data flow and the rules for the different iOS versions:
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

```
mesh/        app code, one layer per folder
tests/       Mac tests (tests/run.sh)
tools/       selftest, developer tools (dev/), icon generation (assets/)
vendor/      secp256k1, mbedTLS, qrcodegen, quirc
docs/        architecture and security model, porting, design preview
```

## Open items

- Device tests on touch 3G and 4G (list in docs/PORTING.md), TLS probe with mbedTLS 3.6.7 on the device.
- touch 2G: ARMv6 toolchain and libraries (docs/PORTING.md).
- NIP-44 instead of NIP-04 – only together with the Android app, otherwise the two can no longer talk.
- Metadata: pubkeys and timestamps are stored unencrypted in the database.

## Install

Easiest via the **[Reboot App Store](https://github.com/SecondTrack/reboot)** right on the iPod. By hand: `.deb` from the [latest release](https://github.com/SecondTrack/mesh/releases/latest), `dpkg -i`, then `uicache`.

## License

GPL-3.0 – see [LICENSE](LICENSE). Libraries under `vendor/` keep their own licenses.
Not affiliated with Apple. iPod is a trademark of Apple Inc.
