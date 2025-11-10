# Handover: Setup & Operate OpenVPN via systemd (Ubuntu Server)

> **Scope**: Run OpenVPN client(s) as systemd services on Ubuntu Server, with auto‑start, auto‑recover, clean DNS handling, and safe credential management. Covers single and multiple profiles.

---

## 0) Quick checklist (TL;DR)
- [ ] `apt install openvpn` (if not installed)
- [ ] Put client config(s) in `/etc/openvpn/client/<NAME>.conf` (rename from `.ovpn`)
- [ ] Put creds at `/etc/openvpn/client/<NAME>.auth` (`chmod 600`), update `auth-user-pass` path
- [ ] Use absolute DNS helper paths (`/etc/openvpn/update-resolv-conf`)
- [ ] Enable service: `systemctl enable --now openvpn-client@<NAME>`
- [ ] Verify: `systemctl status ...` + `ip a show tun0`
- [ ] Add auto-restart drop-in (recommended)
- [ ] Troubleshoot common errors (section 7)

---

## 1) Prerequisites
- Ubuntu Server 20.04+ (works on 18.04+ with minor differences)
- Package: `sudo apt-get update && sudo apt-get install -y openvpn`  
- Root or sudo privileges

Optional (for DNS updates by resolvconf):
```bash
sudo apt-get install -y resolvconf
```

---

## 2) File layout & naming
**systemd expects `.conf` files** inside `/etc/openvpn/client/` when using the `openvpn-client@.service` template.

```
/etc/openvpn/
├─ client/
│  ├─ CBI-VNSG.conf
│  ├─ CBI-VNSG.auth            # optional if server requires username/password
│  ├─ VPN.cbidigital.com-NEW.conf
│  ├─ VPN.cbidigital.com-NEW.auth
│  └─ any-ca-or-key-files-if-external.pem
└─ update-resolv-conf          # DNS helper script (present on Ubuntu)
```

### 2.1 Convert .ovpn → .conf
```bash
sudo mkdir -p /etc/openvpn/client
sudo cp ~/openvpn/CBI-VNSG.ovpn /etc/openvpn/client/CBI-VNSG.conf
```

### 2.2 Credentials (if `auth-user-pass` is used)
- Create `/etc/openvpn/client/CBI-VNSG.auth` with **two lines**:
```
<username>
<password>
```
- Permissions & ownership (required):
```bash
sudo chown root:root /etc/openvpn/client/CBI-VNSG.auth
sudo chmod 600 /etc/openvpn/client/CBI-VNSG.auth
```
- Update the config to reference it:
```
auth-user-pass /etc/openvpn/client/CBI-VNSG.auth
```

### 2.3 Absolute paths for helper scripts
If your config includes DNS hooks, **use absolute paths** and proper script security:
```
script-security 2
up /etc/openvpn/update-resolv-conf
down /etc/openvpn/update-resolv-conf
```

> Tip: Avoid relative paths like `up update-resolv-conf` when running under systemd.

---

## 3) Start/Stop/Enable the VPN service
Use the instance name matching `<NAME>.conf`.

```bash
# Start now and enable on boot
sudo systemctl enable --now openvpn-client@CBI-VNSG

# Check status & logs
sudo systemctl status openvpn-client@CBI-VNSG --no-pager -l
sudo journalctl -u openvpn-client@CBI-VNSG -n 100 --no-pager

# Stop / disable
sudo systemctl stop openvpn-client@CBI-VNSG
sudo systemctl disable openvpn-client@CBI-VNSG
```

**Verification:**
```bash
ip a show tun0     # should show an IP like 10.x.x.x for tun0
ip route | grep tun
```

> If running multiple profiles simultaneously, you may see `tun1`, `tun2`, etc.

---

## 4) Recommended config hardening & compatibility

### 4.1 Remove options that clash with systemd template
The `openvpn-client@.service` template includes `--nobind`. Remove lines like:
```
lport 0
```

### 4.2 Modern cipher negotiation
Prefer `data-ciphers` over legacy `cipher` lines. Example:
```
# prefer modern AEAD; server must agree
ncp-ciphers AES-256-GCM:AES-128-GCM
data-ciphers AES-256-GCM:AES-128-GCM
# fallback for older servers (optional)
data-ciphers-fallback AES-256-CBC
```
> Avoid `cipher none` / `auth none` in production. If the server mandates these, document the risk.

### 4.3 Keepalive & retries
```
resolv-retry infinite
keepalive 10 60
```

### 4.4 Compression
Compression is deprecated due to security risks. If not required by the server, **remove** lines like `comp-lzo yes`. If required, document the risk explicitly.

### 4.5 IPv6 (optional)
If your server supports IPv6, ensure:
```
tun-ipv6
pull
```

---

## 5) Auto-restart on exit / network blips
Sometimes the server **pushes a HALT** causing the client to exit cleanly (code 0). To auto-recover, add a systemd drop‑in override.

Create/edit drop‑in for a specific instance:
```bash
sudo systemctl edit openvpn-client@CBI-VNSG
```
Paste:
```
[Service]
Restart=always
RestartSec=5s

[Unit]
StartLimitIntervalSec=0
```
Then apply:
```bash
sudo systemctl daemon-reload
sudo systemctl restart openvpn-client@CBI-VNSG
```

> To apply to **all** OpenVPN client instances, edit the template:
```bash
sudo systemctl edit openvpn-client@.service
# paste the same [Service] and [Unit] block
```

**Test auto-restart:**
```bash
sudo kill $(pgrep -f 'openvpn.*CBI-VNSG.conf'); sleep 6
systemctl status openvpn-client@CBI-VNSG --no-pager
```

---

## 6) Multiple VPN profiles on the same host
You can run multiple instances, but mind routes & device names.

### 6.1 Dedicated tun device per profile (optional)
Add in the *second* profile:
```
dev tun1
```

### 6.2 Avoid route clashes
If both VPNs push default/routes that conflict, use a selective approach:
```
route-nopull
# add only what you need, e.g. private CIDRs or specific subnets
route 172.31.0.0 255.255.0.0
route 10.0.0.0 255.0.0.0
```

### 6.3 DNS
If both VPNs modify DNS, decide precedence. You may disable DNS pushes from one profile or manage via `systemd-resolved` split‑DNS.

---

## 7) Troubleshooting (field notes)

### 7.1 "TLS key negotiation failed" / handshake loops
- Check server reachability: `nc -uzv <server_ip> 1194` (UDP) or switch to TCP to test connectivity (`proto tcp`)
- Confirm no duplicate client processes: `sudo pkill openvpn && systemctl start ...`
- Verify certs/keys and expiry; ensure `remote-cert-tls server` present when required

### 7.2 "Options error: --lport and --nobind don't make sense together"
- Remove `lport 0` (or any `lport`) from `.conf` when using systemd `openvpn-client@.service` (which adds `--nobind`).

### 7.3 "Options error: --auth-user-pass ... No such file or directory"
- Make sure the credentials file exists and is referenced with an **absolute path**, owned by root, `chmod 600`.

### 7.4 DNS not updating
- Use absolute hooks and `script-security 2` (see §2.3). Ensure `resolvconf`/`systemd-resolved` integration is present on your distro.

### 7.5 Service goes **inactive (dead)** with `server-pushed-halt`
- Add the systemd override in §5 to auto‑restart. Also ask VPN admin why HALT was pushed (maintenance, quota, policy).

### 7.6 Logs & debugging level
- View logs: `journalctl -u openvpn-client@<NAME> -f`
- Temporarily increase verbosity inside `.conf`:
```
verb 4       # or 5 for more detail
log-append /var/log/openvpn-<NAME>.log
```

---

## 8) Operations runbook

**Start a profile**
```bash
sudo systemctl start openvpn-client@CBI-VNSG
```

**Stop a profile**
```bash
sudo systemctl stop openvpn-client@CBI-VNSG
```

**Enable on boot**
```bash
sudo systemctl enable openvpn-client@CBI-VNSG
```

**Disable on boot**
```bash
sudo systemctl disable openvpn-client@CBI-VNSG
```

**Status / health**
```bash
sudo systemctl status openvpn-client@CBI-VNSG --no-pager -l
ip a show tun0 && ip r | grep tun
```

**Tail logs live**
```bash
sudo journalctl -u openvpn-client@CBI-VNSG -f
```

**Restart on config changes**
```bash
sudo systemctl restart openvpn-client@CBI-VNSG
```

---

## 9) Secure handling notes
- Credentials files must be `root:root` with `0600` perms.
- Avoid plaintext passwords when possible; consider certificate‑only auth or token‑based flows.
- Audit configs for deprecated/weak options (`cipher none`, compression). Align with org policy.

---

## 10) Templates

### 10.1 Client config template (modernized example)
```conf
client
dev tun
proto udp
remote <SERVER_HOST_OR_IP> 1194 udp
nobind

# Ciphers (negotiate AEAD)
ncp-ciphers AES-256-GCM:AES-128-GCM
data-ciphers AES-256-GCM:AES-128-GCM
# fallback (optional)
# data-ciphers-fallback AES-256-CBC

auth SHA256
remote-cert-tls server
resolv-retry infinite
keepalive 10 60

# DNS hooks (Ubuntu)
script-security 2
up /etc/openvpn/update-resolv-conf
down /etc/openvpn/update-resolv-conf

# Credentials (if needed)
# auth-user-pass /etc/openvpn/client/<NAME>.auth

# Embedded CA example
# <ca>
# -----BEGIN CERTIFICATE-----
# ...
# -----END CERTIFICATE-----
# </ca>

verb 3
```

### 10.2 Systemd override template
```
[Service]
Restart=always
RestartSec=5s

[Unit]
StartLimitIntervalSec=0
```

---

## 11) Appendix: Running multiple tunnels
- Instance names map 1:1 to config files: `openvpn-client@<NAME>` ↔ `/etc/openvpn/client/<NAME>.conf`.
- For the second tunnel, consider `dev tun1` and `route-nopull` with explicit routes to avoid overriding the first tunnel’s routes/DNS.
- Validate after bringing up both:
```bash
ip a | grep -E 'tun0|tun1'
ip r
resolvectl status # if using systemd-resolved
```

---

**Owner:** <TEAM / CONTACT>  
**Last updated:** <YYYY‑MM‑DD>


