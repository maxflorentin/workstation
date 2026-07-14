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

## How content flows in

Three entry points, one pipeline. Sonarr/Radarr/Lidarr search via Prowlarr's
indexers (music also via Soulseek), download through Transmission (or slskd),
import into the Plex library with hardlinks, Bazarr fetches + syncs Spanish
subtitles, Tautulli pings Telegram when it lands in Plex, and the finished
torrent is seeded to ratio 1.0 (or 30 min idle) then removed automatically.

1. **Plex Watchlist**: tap "Add to Watchlist" in any Plex app. Sonarr/Radarr
   import lists (authed with the server account token) pick it up within
   15 min (`media-watchlist-sync` cron; the apps alone only poll every ~6 h).
   If something never shows up, it's usually a Plex→TMDB mapping failure —
   add it by id in the Radarr UI.
2. **Telegram (hermes)**: tappable commands `/m <title>` (series+movies),
   `/mm <artist>` (music), `/mst` (status) — deterministic `media-tg` plugin,
   no model in the loop. Natural language also works at any point in a
   conversation ("bajame la peli X") — the media knowledge lives in the
   agent's SOUL.md, no `/media` invocation needed.
3. **Web UIs** directly (add artist in Lidarr, movie in Radarr, etc.).

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

## Quality policy (movies/TV)

- Everything uses the **HD-1080p** profile; quality definitions cap sizes at
  preferred ~15 MB/min (≈2 GB/movie) and max 40 MB/min (≈5 GB), so 45 GB
  remuxes never get grabbed.
- Radarr custom formats bias hardcoded-sub releases: `Hardsubs` (VOSTFR, HC,
  KORSUB, ...) scores −50, `Hardsubs ES` (SUBESP, CASTELLANO, LATINO) +40,
  profile min score −1000 — clean releases win, but when only hardsubs exist,
  the Spanish one is picked. Unadvertised hardsubs can't be detected.
- Music uses the **Lossless** profile (FLAC / FLAC 24-bit); Soularr prefers
  hi-res FLAC and falls back to mp3 320.

## Subtitles (Bazarr)

Bazarr watches Sonarr/Radarr imports, fetches Spanish subs (profile
"Español") from opensubtitles.com + subtis + subtitulamos.tv + yifysubtitles +
embedded tracks, and **auto-syncs offset/drift** against the audio (ffsubsync).
OpenSubtitles creds live in envy (`OPENSUBTITLES_*`) — the login must be the
**username, not the email**; on auth errors Bazarr throttles the provider 12 h.

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
  Radarr/Lidarr APIs. Verbs: `series search|add`, `movie search|add`,
  `artist search|add`, `status`. Symlinked to `~/.local/bin/media-add`.
- **Locked-down access**: `hermes-media-setup.sh` (run once, with sudo) creates
  a `mediabot` user whose SSH `authorized_keys` **forces** the
  `hermes-media-dispatch` command — the hermes key can run *only* `media-add`,
  never a shell. The dispatcher whitelists the verbs and passes args via `exec`
  (no shell), so injection like `series; rm -rf /` is inert.
- **Three agent-side layers** (hermes repo, `hermes/`):
  - `SOUL.md` media section — always in the agent's context, so natural
    language works mid-conversation without invoking any skill.
  - `/media` skill (`hermes-media-skill.sh`) — detailed operating notes the
    model can pull in.
  - `media-tg` plugin (`hermes/plugins/media-tg/`) — deterministic tappable
    commands (`/m`, `/mm`, `/mst` → `/madd_tv_<id>`, `/ma_<n>`), modeled on
    workmux-tg; no LLM call, state lives in the plugin. NOTE: hermes plugins
    must live in `~hermes/.hermes/plugins/<name>/` **and** be listed under
    `plugins.enabled` in the gateway config — copying alone silently no-ops.

Activate everything (idempotent, needs sudo):

```bash
sudo bash ~/.dotfiles/hermes/install-media-tg.sh
# (runs hermes-media-setup.sh + hermes-media-skill.sh, installs + enables the
#  plugin, refreshes /etc/media-add.env, restarts the gateway)
# test from the hermes side:
ssh -F /opt/hermes-ssh/config media 'artist search Bestia Bebé'
```

**Known infra gotcha**: this host has no IPv6 route; without `filter-AAAA` in
`/etc/dnsmasq.d/nextdns.conf` the gateway (Python) tries IPv6 answers first
and Telegram sends/polls flake intermittently while curl-based monitoring
stays green (see `linux/dnsmasq/nextdns.conf.example`).

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

## Remote access & sharing (Tailscale, no Plex Pass)

Plex's 2025 paywall only applies to **remote** streams — and "local" is
decided by IP. Two server prefs make Tailscale devices count as local from
anywhere in the world (set via `/:/prefs`, persisted in Preferences.xml):

- `LanNetworksBandwidth=192.168.68.0/22,100.64.0.0/10` — the tailnet is "LAN".
- `customConnections=http://100.102.172.111:32400,http://workstation.tailf178d0.ts.net:32400`
  — plex.tv advertises the Tailscale addresses to clients, so apps find the
  server off-network (this was the missing piece; without it only same-WiFi
  discovery worked).

Client side: install/enable Tailscale on each device (iOS: turn on VPN
On-Demand). Sharing with family: invite their Plex account (app.plex.tv →
Users & Sharing), put their devices on the tailnet.

All other service UIs are plain HTTP on the Tailscale IP — they work from
anywhere by design; URLs + creds are mirrored in envy context `max`.

## Monitoring & notifications

- **Tautulli** notifies Telegram (hermes bot token, envy `TELEGRAM_*`) when
  content is added to Plex. Its Telegram notifier is agent_id **13**.
- **Uptime Kuma** (`:3001`) checks every service, api.telegram.org
  reachability and the local dnsmasq each 60 s, alerting via Telegram.
  Four **push heartbeats** alert on silence instead: the two cron scripts
  ping `KUMA_PUSH_*` URLs (in the media `.env`) on success; two crontab lines
  (`# kuma-heartbeat`) check the hermes gateway process and the soularr
  container every 5 min. No docker socket is mounted into Kuma.

## Cron jobs (operator's crontab)

- `media-watchlist-sync` (every 15 min): triggers Sonarr/Radarr ImportListSync
  so Plex Watchlist adds show up promptly (the apps only poll every ~6 h).
- `media-backup` (daily 05:00): tars `${CONFIG}` (Plex DB + *arr/Bazarr/
  Tautulli configs, minus Plex logs/cache) to `~/backups/media/` on the
  internal SSD, keeping the last 14. The media library shares the external
  disk with these configs; the library is re-downloadable, the configs aren't.
- Two `# kuma-heartbeat` lines (hermes gateway, soularr) — see Monitoring.

## Notes

- **Config & `.env`** are host-local. `linux/media/.env` is gitignored; real
  paths and passwords (incl. the auto-generated *arr API keys) never get
  committed (see `docs/client-boundaries.md`). `media-add` reads the keys from
  there, or from `/etc/media-add.env` (mediabot-readable) on the SSH endpoint.
- **Envy mirror**: every service URL, API key and credential also lives in
  envy context `max` (`SONARR_API_KEY`, `PLEX_TOKEN`, `SLSKD_*`,
  `UPTIMEKUMA_*`, `RUTRACKER_*`, `OPENSUBTITLES_*`, `TELEGRAM_*`, ...) —
  `evl max` then `evg <KEY>`. If a key rotates, update both the `.env` and envy.
- **Torrent cleanup**: Transmission seeds to ratio 1.0 or 30 min idle, then
  Sonarr/Radarr remove the finished torrent (`removeCompletedDownloads`);
  imports are hardlinks so the library copy survives.
- **Port check**: none of the media ports (32400, 139, 445, 9091, 51413, 8989,
  7878, 8686, 5030/50300, 9696, 6767, 8181, 3001, 8191) collide with the work
  stack (4566, 5432/55432/5433, 13000, 8093, 9083, 9000/9001/9100/9101).
