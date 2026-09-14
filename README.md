# udp-encrypto-vpn

A hardened ZIVPN UDP server installer for a private Linux host published through a single Playit UDP tunnel.

```text
ZIVPN client -> Playit UDP endpoint -> 127.0.0.1:5667 on Linux -> ZIVPN
```

The installer:

- supports x86_64 Linux;
- verifies the pinned ZIVPN 1.4.9 binary checksum;
- requires a strong password;
- binds ZIVPN to localhost for Playit forwarding;
- runs the service as a restricted system user;
- does not upgrade the operating system; and
- does not open or redirect a broad UDP port range.

## Install ZIVPN

Review the script, then run:

```bash
sudo ./zi.sh
```

Enter a password containing at least 16 characters from `A-Z`, `a-z`, `0-9`, `.`, `_`, `~`, or `-`.

## Connect Playit

Install the Playit agent using its official Linux instructions, claim the agent, and create one custom UDP tunnel with this local address:

```text
127.0.0.1:5667
```

Use the public hostname and port assigned by Playit in the ZIVPN client.

## Uninstall

```bash
sudo ./uninstall.sh
```

## Trust boundary

The ZIVPN server is a precompiled third-party binary. This repository pins the SHA-256 digest of the inspected release asset, but does not provide or independently audit its source code.

Derived from [zahidbd2/udp-zivpn](https://github.com/zahidbd2/udp-zivpn). ZIVPN client: [Google Play](https://play.google.com/store/apps/details?id=com.zi.zivpn).
