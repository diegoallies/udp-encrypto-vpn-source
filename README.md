# udp-encrypto-vpn

A hardened Encrypto VPN UDP server installer for a private Linux host published through a single Playit UDP tunnel.

```text
Encrypto VPN client -> Playit UDP endpoint -> 127.0.0.1:5667 on Linux -> Encrypto VPN server
```

The installer:

- supports x86_64 Linux;
- verifies the pinned upstream ZIVPN 1.4.9 engine checksum;
- requires a strong password;
- binds Encrypto VPN to localhost for Playit forwarding;
- runs the service as a restricted system user;
- does not upgrade the operating system; and
- does not open or redirect a broad UDP port range.

## Install Encrypto VPN

Review the script, then run:

```bash
sudo ./encrypto.sh
```

Press Enter to use the default password `masepoes`, or enter a custom password containing at least 16 characters from `A-Z`, `a-z`, `0-9`, `.`, `_`, `~`, or `-`.

The default password is public and insecure. Use a custom password for any reachable tunnel.

## Connect Playit

Install the Playit agent using its official Linux instructions, claim the agent, and create one custom UDP tunnel with this local address:

```text
127.0.0.1:5667
```

Use the public hostname and port assigned by Playit in the compatible client.

## Uninstall

```bash
sudo ./encrypto-uninstall.sh
```
