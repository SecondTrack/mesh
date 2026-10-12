# Mesh

**Encrypted chat for old iPods. No phone number, no account, no company server.**

Mesh is a Nostr messenger for jailbroken iPods and iPhones on iOS 4.2 to 6.1.

## How it works

- **Your identity is a key pair** created on the device. No sign-up, no phone number.
- **Contacts are added by scanning a QR code.** Between two iPods the code is split into three parts, because old cameras can't read dense codes.
- **Messages go through public Nostr relays.** They are end-to-end encrypted with the Signal protocol (NIP-44 until the first exchange). Relays only see ciphertext, public keys and timestamps.
- **All connections go through Tor**, which ships with the app. Without Tor, Mesh stays offline instead of connecting directly.

## On the device

- Unlock with a 6-digit PIN or 5–6 random words.
- Messages, names and pictures are stored encrypted. Keys are wiped from memory when the app locks.
- Lockout after wrong attempts, plus an emergency wipe code.

## Good to know

- Your profile name and picture are public on the relays. Leave them empty if you want to stay anonymous.
- Relays can see which keys talk to each other. Tor hides your IP address, not your key.
- On a jailbroken device, someone with root access can brute-force a PIN. Random words still hold.
- The code has not been independently audited.

## Install

Via the **[Reboot App Store](https://github.com/SecondTrack/reboot)** on the iPod, or download the `.deb` from the [latest release](https://github.com/SecondTrack/mesh/releases/latest) and install it with `dpkg -i`, then run `uicache`.

## Build

With [Theos](https://theos.dev) and the iOS 7.1 SDK: `make package`. Tests run on a Mac with `tests/run.sh`. Details on the design and security model are in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## License

GPL-3.0, see [LICENSE](LICENSE). Libraries under `vendor/` keep their own licenses.
Not affiliated with Apple. iPod is a trademark of Apple Inc.
