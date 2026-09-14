# udp-encrypto-vpn

![Encrypto VPN](encrypto-vpn.png)

A hardened Encrypto VPN UDP server installer for a private Linux host published through a single Playit UDP tunnel.

```text
Encrypto VPN client -> Playit UDP endpoint -> 127.0.0.1:5667 on Linux -> Encrypto VPN server
```

The installer:

- supports x86_64 Debian-based Linux, including Kali;
- safely resumes when run again and preserves existing credentials;
- verifies the pinned upstream server engine checksum;
- requires a strong password;
- binds Encrypto VPN to localhost for Playit forwarding;
- installs and starts the Playit agent;
- runs the service as a restricted system user;
- does not upgrade the operating system; and
- does not open or redirect a broad UDP port range.

## Install Encrypto VPN

Review the script, then run:

```bash
sudo ./encrypto.sh
```

Or download and run it directly:

```bash
wget -O encrypto.sh https://raw.githubusercontent.com/diegoallies/udp-encrypto-vpn-source/main/encrypto.sh && chmod +x encrypto.sh && sudo ./encrypto.sh
```

Press Enter to use the default password `masepoes`, or enter a custom password containing at least 16 characters from `A-Z`, `a-z`, `0-9`, `.`, `_`, `~`, or `-`.

The default password is public and insecure. Use a custom password for any reachable tunnel.

## Connect Playit

The installer runs `playit setup`. Open the claim URL it prints and approve the Kali agent in your Playit account. It then prints an account-login link. Open that link and create a custom UDP tunnel for this local address:

```text
127.0.0.1:5667
```

The installer walks through the Playit form one answer at a time and waits for Enter between browser steps.
Playit's usage-confirmation sentence must be typed manually because that field blocks pasting.
The guide covers the complete flow through Free Network selection, agent assignment, origin configuration, review, and tunnel creation.

Use the public hostname and port assigned by Playit in the compatible client.

## Uninstall

```bash
sudo ./encrypto-uninstall.sh
```
