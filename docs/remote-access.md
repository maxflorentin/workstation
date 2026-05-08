# Remote Access

How to reach the Pi workstation (or future mini PC) from anywhere — iPhone, Mac, coffee shop, whatever.

## Network Topology

```
Internet
  │
  ▼
┌─────────────────────────────┐
│ ISP Modem (Movistar)        │
│ 192.168.1.1                 │
│ NAT #1                      │
└──────────┬──────────────────┘
           │ 192.168.1.49
           ▼
┌─────────────────────────────┐
│ Mesh Router (TP-Link Deco)  │
│ 192.168.68.1                │
│ NAT #2                      │
└──────────┬──────────────────┘
           │ 192.168.68.55
           ▼
┌─────────────────────────────┐
│ Pi / Server                 │
│ Tailscale: <workstation-tailscale-ip> │
└─────────────────────────────┘
```

**Double NAT**: the ISP modem does NAT, then the Deco does NAT again. Inbound port forwarding requires rules on **both** devices. This is why Tailscale is the recommended path — it punches through NAT without any port forwarding.

---

## Option A: Tailscale (recommended)

Zero config, zero port forwarding, works through any NAT. Free tier supports 100 devices.

Tailscale creates a WireGuard mesh where each device gets a stable `100.x.x.x` IP. A coordination server (hosted by Tailscale) handles key exchange — your traffic goes peer-to-peer, not through their servers.

### Server setup

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
# Follow the auth URL and login with your personal tailnet account
```

After auth:

```bash
tailscale status          # shows all peers
tailscale ip -4           # shows this node's Tailscale IP
```

### Mac setup

```bash
brew install --cask tailscale
# Open Tailscale from menu bar → login with same account
```

Or headless:

```bash
brew install tailscale
sudo tailscale up
```

### iPhone setup

1. App Store → install **Tailscale**
2. Open and login with your personal tailnet account
3. Toggle VPN on

### Troubleshooting

**Nodekey conflict (iPhone shows "device already registered")**

This happens when the app's local keys get out of sync with the coordination server. Fix:

1. On iPhone: **delete** the Tailscale app entirely
2. Reinstall from App Store
3. Login with your personal tailnet account
4. On the Pi, verify the iPhone appears:
   ```bash
   tailscale status
   ```

**Node not appearing**

```bash
# On the server — force re-authentication:
sudo tailscale logout
sudo tailscale up
```

**Check connectivity**

```bash
# From Mac or server:
tailscale ping <hostname>
tailscale status
```

---

## Option B: WireGuard (self-hosted)

Use this if you want zero dependency on external coordination servers. Requires port forwarding through both NAT layers.

### Port forwarding (double NAT)

You need rules on **both** routers:

1. **Movistar modem** (192.168.1.1):
   - Protocol: UDP
   - External port: 51820
   - Forward to: 192.168.1.49 (Deco's WAN IP), port 51820

2. **Deco router** (192.168.68.1):
   - Protocol: UDP
   - External port: 51820
   - Forward to: 192.168.68.55 (server), port 51820

### Server config

```bash
sudo apt install -y wireguard

# Generate keys
wg genkey | sudo tee /etc/wireguard/private.key
sudo chmod 600 /etc/wireguard/private.key
sudo cat /etc/wireguard/private.key | wg pubkey | sudo tee /etc/wireguard/public.key
```

`/etc/wireguard/wg0.conf`:

```ini
[Interface]
Address = 10.0.0.1/24
ListenPort = 51820
PrivateKey = <server-private-key>
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
# Mac
PublicKey = <mac-public-key>
AllowedIPs = 10.0.0.2/32

[Peer]
# iPhone
PublicKey = <iphone-public-key>
AllowedIPs = 10.0.0.3/32
```

```bash
sudo systemctl enable --now wg-quick@wg0
```

### Mac client

```bash
brew install wireguard-tools
```

Create `~/.config/wireguard/wg0.conf` (or use the macOS WireGuard app):

```ini
[Interface]
Address = 10.0.0.2/24
PrivateKey = <mac-private-key>

[Peer]
PublicKey = <server-public-key>
Endpoint = <your-public-ip>:51820
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
```

### iPhone client

1. App Store → **WireGuard**
2. Add tunnel → Create from scratch (or scan QR)
3. Same config as Mac but with `Address = 10.0.0.3/24` and iPhone's private key

### Dynamic DNS

If your ISP changes your public IP, WireGuard clients can't find the server. Options:

- **DuckDNS** (free): set up a cron on the server to update `max-home.duckdns.org`
- **Cloudflare DDNS**: if you own a domain, use a script to update an A record
- **Tailscale**: avoids this problem entirely (another reason to prefer Option A)

---

## SSH Profiles

### Mac (`~/.ssh/config.d/workstation`)

All hosts use the Tailscale IP so they work both on LAN and remotely:

```
Host workstation
    HostName <workstation-tailscale-ip>
    User max

Host ws-<client>
    HostName <workstation-tailscale-ip>
    User <client>
    # Add LocalForward as needed per client (ports in ~/.clientrc)

# For ecryptfs clients, add:
#   PreferredAuthentications password
#   PubkeyAuthentication no

# Emergency LAN fallback
Host ws-lan
    HostName 192.168.68.55
    User max
```

### iPhone (WebSSH / Blink Shell)

Create one profile per client user:

| Profile | Host | User | Auth |
|---------|------|------|------|
| workstation | `<workstation-tailscale-ip>` | max | SSH key |
| ws-&lt;client&gt; | `<workstation-tailscale-ip>` | &lt;client&gt; | SSH key (or password if ecryptfs) |

Tailscale must be active (VPN toggle on) before connecting.

### ecryptfs clients (password auth)

Clients with encrypted homes need password auth on first login so ecryptfs can mount. This is handled server-side in `/etc/ssh/sshd_config`:

```
Match User <client>
    AuthenticationMethods password
    PasswordAuthentication yes
```

After the first SSH login decrypts the home, key-based auth also works (keys are in `/etc/ssh/authorized_keys/%u`). Client names configured in sshd_config live on the server, not in this repo.

---

## Verification Checklist

Run these after setup or when troubleshooting:

```bash
# 1. Tailscale mesh is connected
tailscale ping workstation        # from Mac
tailscale status                     # from any node

# 2. SSH works via Tailscale IP
ssh workstation                   # key auth, admin user
ssh ws-<client>                      # per-client host from ~/.ssh/config.d/

# 3. From iPhone
# Tailscale VPN on → open terminal app → ssh max@<workstation-tailscale-ip>

# 4. LAN fallback (only if on same network)
ssh ws-lan
```

---

## Migration to New Hardware

1. Install Tailscale on the new machine, auth with the same account
2. The new machine gets a **new** Tailscale IP — update SSH configs
3. Optionally remove the old node: `tailscale logout` on old machine, or remove from [Tailscale admin](https://login.tailscale.com/admin/machines)
4. WireGuard (if used): copy `/etc/wireguard/` configs, update port forwarding rules to new server's LAN IP
