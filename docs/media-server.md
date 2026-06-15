# Media Server

Self-hosted media stack on the workstation (Dell Latitude E7470, x86_64),
adapted from [pablokbs/plex-rpi](https://github.com/pablokbs/plex-rpi).

Services (managed by the `media` CLI, `linux/media/`):

| Service        | Image                              | Port(s)            | Purpose                         |
|----------------|------------------------------------|--------------------|---------------------------------|
| Plex           | `lscr.io/linuxserver/plex`         | host net (32400)   | Media server                    |
| Samba          | `dperson/samba`                    | 139, 445           | Share media/downloads over SMB  |
| Transmission   | `lscr.io/linuxserver/transmission` | 9091, 51413        | Torrent client                  |
| Flexget        | `wiserain/flexget`                 | 5050               | Download automation             |

## Why this differs from plex-rpi

- **x86_64 images.** The upstream `jaymoulin/*` images are ARM (Raspberry Pi).
  Plex and Transmission use amd64 linuxserver.io images here.
- **Resource limits.** This box has 2 cores / 4 threads and runs the work data
  stack (postgres, trino, metabase, ...). Each media service is capped via
  `deploy.resources.limits` so it can't starve work containers:
  Plex 2 CPU / 2 GB, Transmission 1 CPU / 1 GB, Samba 1 CPU / 512 MB,
  Flexget 0.5 CPU / 512 MB.
- **No hardware transcoding.** You run direct-play only (no Plex Pass), so
  QuickSync (`/dev/dri`) stays disabled. Software transcoding on this CPU is
  expensive — keep clients on "Original/Maximum" quality to avoid it. To enable
  HW transcode later: get Plex Pass, uncomment the `devices: /dev/dri` block in
  `docker-compose.yaml`, and turn on HW acceleration in Plex settings.

## Storage

Everything lives on the **512 GB external disk** so the root SSD stays lean and
Plex metadata sits next to the media. Mount it first.

```bash
# Identify the disk
lsblk -o NAME,SIZE,FSTYPE,LABEL

# One-off mount (replace sdX1)
sudo mkdir -p /mnt/media
sudo mount /dev/sdX1 /mnt/media

# Persist across reboots — add to /etc/fstab using the UUID:
sudo blkid /dev/sdX1
# /etc/fstab:
#   UUID=<uuid>  /mnt/media  ext4  defaults,nofail  0  2
```

Use `ext4` if you can. If the disk is NTFS, install `ntfs-3g` and set the
fstab type to `ntfs-3g` (and ownership via `uid=/gid=` mount options, since
NTFS ignores Linux permissions).

Layout created by `media setup`:

```
/mnt/media/                 # STORAGE
├── library/                # MEDIA  (Plex scans this)
│   ├── movies/  tv/  music/
├── torrents/               # downloads + watch/
├── config/                 # CONFIG (Plex DB, transmission, flexget) — off the SSD
└── tmp/                    # TRANSCODE scratch
```

## Setup

```bash
# 1. Mount the external disk at the path you set in STORAGE (default /mnt/media).
# 2. One-time setup: creates the 'media' user, the dir tree, and .env.
media setup
# 3. Edit secrets in linux/media/.env (Transmission / Flexget / Samba passwords).
# 4. For a fresh Plex server, set the claim token (valid ~4 min):
media claim <token-from-https://plex.tv/claim>
# 5. Start it:
media up
media status
```

`media setup` adds your user to the `media` group so you can write to the
library directly — log out/in (or `newgrp media`) for it to take effect.

## Daily use

```bash
media status          # state + CPU/RAM usage + endpoints
media logs plex       # follow one service's logs
media restart plex
media pull && media up # update images
media down            # stop everything
```

Endpoints (on the LAN / over Tailscale):

- Plex: `http://<workstation>:32400/web`
- Transmission: `http://<workstation>:9091`
- Flexget: `http://<workstation>:5050`
- Samba: `smb://<workstation>` — shares `media`, `downloads`

## Notes

- **Config & `.env`** are host-local. `linux/media/.env` is gitignored; real
  paths and passwords never get committed (see `docs/client-boundaries.md`).
- **Flexget → Transmission**: Flexget reaches Transmission by service name on
  the compose network. Keep the credentials in `$CONFIG/flexget/config.yml` in
  sync with `TRANSMISSION_USER`/`TRANSMISSION_PASS` in `.env`.
- **Flexget password**: Flexget rejects weak/common passwords and the
  container crash-loops if `FLEXGET_PASSWD` is too simple (e.g. `changeme`).
  Use a strong one (`openssl rand -base64 12`).
- **Port check**: none of the media ports (32400, 139, 445, 9091, 51413, 5050)
  collide with the work stack (4566, 5432/55432/5433, 13000, 8093, 9083,
  9000/9001/9100/9101).
