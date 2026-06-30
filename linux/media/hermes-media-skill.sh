#!/usr/bin/env bash
# Install a Hermes `/media` skill so the agent knows how to add series/movies
# through the locked-down media-add endpoint set up by hermes-media-setup.sh.
#
#   sudo bash ~/.dotfiles/linux/media/hermes-media-skill.sh
#
# Idempotent: overwrites only the generated skill file.
set -euo pipefail
U="${HERMES_USER:-hermes}"
[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo bash $0"; exit 1; }
id "$U" >/dev/null 2>&1 || { echo "user $U does not exist"; exit 1; }

d="/home/$U/.hermes/skills/media"
install -d -o "$U" -g "$U" "$d"

cat > "$d/SKILL.md" <<'EOF'
---
name: media
description: "Add/track series and movies on the home media server and report download status, by talking to the locked-down media-add endpoint over SSH."
version: 1.0.0
platforms: [linux]
metadata:
  hermes:
    tags: [media, plex, sonarr, radarr, ssh]
---

# Media server (Plex via Sonarr/Radarr)

When Max says he wants to watch / download a **series** or **movie** ("bajá
Severance", "quiero ver Dune", "¿qué se está bajando?"), drive the home media
server. You reach it as a normal target, but it is **locked down**: the only
thing that endpoint can run is the `media-add` CLI.

Run commands as:

    ssh -F /opt/hermes-ssh/config media '<media-add args>'

The argument string IS the media-add command (the `media-add` prefix is
optional). Available verbs — nothing else is permitted:

- `series search <query>`  → list matching shows, each with a `tvdb:<id>`
- `series add <tvdbId>`    → add the show, monitor all seasons, search now
- `movie search <query>`   → list matching movies, each with a `tmdb:<id>`
- `movie add <tmdbId>`     → add the movie, monitor, search now
- `status`                 → what is currently downloading

## How to operate

1. **Search first, then confirm.** Run the matching `search`, read the results,
   and pick the entry that matches what Max meant (right title/year). If it is
   ambiguous, ask him which one before adding.
2. **Add by id.** Use the `tvdb:`/`tmdb:` id from the chosen result, e.g.
   `ssh -F /opt/hermes-ssh/config media 'series add 371980'`.
3. **Report in natural language.** Confirm what you added and that it is
   searching, or summarize `status`. Don't paste raw output.

Examples:

    ssh -F /opt/hermes-ssh/config media 'series search Severance'
    ssh -F /opt/hermes-ssh/config media 'series add 371980'
    ssh -F /opt/hermes-ssh/config media 'movie search Dune 2021'
    ssh -F /opt/hermes-ssh/config media 'status'

Downloads land in Transmission and Sonarr/Radarr import them into Plex
automatically; tell Max it will appear in Plex once the download finishes.
EOF

chown "$U:$U" "$d/SKILL.md"
echo "installed /media skill at $d/SKILL.md"
