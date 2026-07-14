# Media Server

Self-hosted media stack on the workstation (Dell Latitude E7470, x86_64),
adapted from [pablokbs/plex-rpi](https://github.com/pablokbs/plex-rpi).

Services (managed by the `media` CLI, `linux/media/`):

| Service        | Image                              | Port(s)            | Purpose                          |
|----------------|------------------------------------|--------------------|----------------------------------|
| Plex           | `lscr.io/linuxserver/plex`         | host net (32400)   | Media server                     |
| Samba          | `dperson/samba`                    | 139, 445           | Share media/downloads over SMB   |
| Transmission   | `lscr.io/linuxserver/transmission` | 9091, 51413        | Torrent client (download)        |
| Prowlarr       | `lscr.io/linuxserver/prowlarr`     | 9696               | Indexer manager (your sources)   |
| FlareSolverr   | `ghcr.io/flaresolverr/flaresolverr`| 8191               | Solves Cloudflare for indexers   |
| Sonarr         | `lscr.io/linuxserver/sonarr`       | 8989               | TV: track shows, grab episodes   |
| Radarr         | `lscr.io/linuxserver/radarr`       | 7878               | Movies: track + grab             |
| Lidarr         | `lscr.io/linuxserver/lidarr`       | 8686               | Music: track artists, grab FLAC  |
| slskd          | `slskd/slskd`                      | 5030, 50300        | Soulseek client (indie music)    |
| Soularr        | `mrusse08/soularr`                 | —                  | Lidarr wanted -> slskd bridge    |
| Bazarr         | `lscr.io/linuxserver/bazarr`       | 6767               | Subtitles: fetch + auto-sync     |
| Tautulli       | `lscr.io/linuxserver/tautulli`     | 8181               | Plex stats + new-content notifs  |
| Uptime Kuma    | `louislam/uptime-kuma`             | 3001               | Status dashboard + TG alerts     |

You request content conversationally through the **hermes** agent on Telegram,
which calls the `media-add` CLI over a locked-down SSH endpoint (see
"hermes integration" below). Sonarr/Radarr then search via Prowlarr's indexers,
download through Transmission, and import into the Plex library automatically.

## Why this differs from plex-rpi

- **x86_64 images.** The upstream `jaymoulin/*` images are ARM (Raspberry Pi).
  Plex and Transmission use amd64 linuxserver.io images here.
- **\*arr instead of Flexget.** The original used Flexget for RSS automation.
  We replaced it with Sonarr/Radarr/Prowlarr, which handle the "I want this
  show/movie" flow far better (quality profiles, renaming, dedup, retries) and
  are driven by the hermes agent.
- **Resource limits.** This box has 2 cores / 4 threads and runs the work data
  stack (postgres, trino, metabase, ...). Each media service is capped via
  `deploy.resources.limits` so it can't starve work containers:
  Plex 2 CPU / 2 GB, Transmission 1 CPU / 1 GB, Samba 1 CPU / 512 MB,
  Sonarr/Radarr 1 CPU / 512 MB each, Prowlarr/Bazarr 0.5 CPU / 512 MB each.
- **Single `/data` mount for hardlinks.** Sonarr/Radarr mount the whole
  `${STORAGE}` as `/data` so the download dir (`/data/torrents`) and the library
  (`/data/library/*`) share one filesystem device inside the container —
  required for instant hardlink imports instead of slow space-doubling copies.
  A remote-path mapping bridges Transmission's `/downloads` view to
  `/data/torrents`.
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
├── config/                 # CONFIG (Plex DB, transmission, sonarr/radarr/prowlarr) — off the SSD
└── tmp/                    # TRANSCODE scratch
```

## Setup

```bash
# 1. Mount the external disk at the path you set in STORAGE (default /mnt/media).
# 2. One-time setup: creates the 'media' user, the dir tree, and .env.
media setup
# 3. Edit secrets in linux/media/.env (Transmission / Samba passwords).
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
- Sonarr: `http://<workstation>:8989`
- Radarr: `http://<workstation>:7878`
- Lidarr: `http://<workstation>:8686`
- slskd: `http://<workstation>:5030`
- Prowlarr: `http://<workstation>:9696`
- Bazarr: `http://<workstation>:6767`
- Tautulli: `http://<workstation>:8181`
- Uptime Kuma: `http://<workstation>:3001` (creds in envy `max`: `UPTIMEKUMA_*`)
- Samba: `smb://<workstation>` — shares `media`, `downloads`

## Indexers (your sources)

Sonarr/Radarr can't find releases until **Prowlarr** has indexers. Add them in
the Prowlarr UI (Indexers → Add) — which trackers you use depends on what you
have the right to download. Prowlarr syncs them to Sonarr and Radarr
automatically (both are wired as Applications with `fullSync`).

**Cloudflare-protected indexers** need FlareSolverr. It's already wired as a
Prowlarr indexer proxy (`http://flaresolverr:8191`) with the `flaresolverr`
tag. When an indexer says it needs FlareSolverr, just add the `flaresolverr`
tag to that indexer in Prowlarr and it'll route through it.

## hermes integration ("bajá Severance")

You add content by talking to the **hermes** agent on Telegram; it runs the
`media-add` CLI over a locked-down SSH endpoint — no dedicated bot or second
Telegram token.

- **`media-add`** (`linux/media/media-add`): searches + adds via the Sonarr/
  Radarr APIs. Verbs: `series search|add`, `movie search|add`, `status`.
  Symlinked to `~/.local/bin/media-add` for direct use too.
- **Locked-down access**: `hermes-media-setup.sh` (run once, with sudo) creates
  a `mediabot` user whose SSH `authorized_keys` **forces** the
  `hermes-media-dispatch` command — the hermes key can run *only* `media-add`,
  never a shell. The dispatcher whitelists the verbs and passes args via `exec`
  (no shell), so injection like `series; rm -rf /` is inert.
- **Agent skill**: `hermes-media-skill.sh` installs a `/media` skill so the
  agent knows the commands and the search-then-confirm flow.

Activate (on the workstation, needs sudo):

```bash
sudo bash ~/.dotfiles/linux/media/hermes-media-setup.sh   # mediabot + forced-command
sudo bash ~/.dotfiles/linux/media/hermes-media-skill.sh   # /media agent skill
# test from the hermes side:
ssh -F /opt/hermes-ssh/config media 'series search Severance'
```

## Music via Soulseek (slskd + Soularr)

Public torrent trackers are weak for indie/regional music; Soulseek is where
that catalog lives. Soularr polls Lidarr's wanted albums every 10 min,
searches Soulseek through slskd (preferring hi-res FLAC, falling back to
mp3 320), downloads to `${STORAGE}/slskd/downloads`, and triggers the Lidarr
import. Failed searches are retried each cycle — availability depends on who
is online, so a miss now often lands later.

Secrets (Soulseek account, slskd API key, Lidarr API key) live in
`${CONFIG}/slskd/slskd.yml` and `${CONFIG}/soularr/config.ini` (host-local),
mirrored in envy context `max` (`SLSKD_*`). The music library is shared
read-only on the network — expected Soulseek etiquette.

## Cron jobs (operator's crontab)

- `media-watchlist-sync` (every 15 min): triggers Sonarr/Radarr ImportListSync
  so Plex Watchlist adds show up promptly (the apps only poll every ~6 h).
- `media-backup` (daily 05:00): tars `${CONFIG}` (Plex DB + *arr/Bazarr/
  Tautulli configs, minus Plex logs/cache) to `~/backups/media/` on the
  internal SSD, keeping the last 14. The media library shares the external
  disk with these configs; the library is re-downloadable, the configs aren't.

## Notes

- **Config & `.env`** are host-local. `linux/media/.env` is gitignored; real
  paths and passwords (incl. the auto-generated *arr API keys) never get
  committed (see `docs/client-boundaries.md`). `media-add` reads the keys from
  there, or from `/etc/media-add.env` (mediabot-readable) on the SSH endpoint.
- **Port check**: none of the media ports (32400, 139, 445, 9091, 51413, 8989,
  7878, 9696, 6767, 8191) collide with the work stack (4566, 5432/55432/5433, 13000,
  8093, 9083, 9000/9001/9100/9101).
