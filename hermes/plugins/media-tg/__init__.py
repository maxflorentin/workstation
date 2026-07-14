"""media-tg: deterministic Telegram wrapper over media-add.

Search and add series/movies/music on the home media server via tappable
commands — without the model in the loop, so nothing gets lost between turns.
Talks to the same locked-down `mediabot` forced-command endpoint the /media
skill uses, over SSH on localhost with the agent key.

UX (single-user personal bot):
  /m <query>       -> search series + movies, tappable add commands
  /mm <query>      -> search music artists, tappable /ma_1, /ma_2, ...
  /madd_tv_<id>    -> add series by tvdbId
  /madd_mv_<id>    -> add movie by tmdbId
  /ma_<n>          -> add artist n from the last /mm search
  /mst             -> what's downloading

Flow: a `pre_gateway_dispatch` hook rewrites the tappable forms into
`/m <sub>` and the registered `/m` command does the work. No LLM call.
"""
from __future__ import annotations

import asyncio
import os
import re
import shlex

SSH_DIR = os.path.expanduser("~/.hermes/ssh")
KEY = f"{SSH_DIR}/hermes_id_ed25519"
MEDIABOT = "mediabot@127.0.0.1"

# Artists use MusicBrainz UUIDs (dashes aren't valid in tg commands), so /mm
# stores its results and /ma_<n> picks by index. Single-user -> global state.
_S = {"artists": []}  # [(mbid, label)]

_ITEM = re.compile(r"^\s{2}(?P<label>.+) — (?P<idn>tvdb|tmdb|mb):(?P<id>\S+?)(?P<already> \[already added\])?$")


async def _media(args, timeout=45):
    argv = [
        "ssh", "-i", KEY,
        "-o", "IdentitiesOnly=yes", "-o", "BatchMode=yes",
        "-o", "StrictHostKeyChecking=accept-new",
        "-o", "UserKnownHostsFile=/dev/null", "-o", "ConnectTimeout=8",
        MEDIABOT, args,
    ]
    try:
        p = await asyncio.create_subprocess_exec(
            *argv, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
        )
        out, err = await asyncio.wait_for(p.communicate(), timeout=timeout)
        if p.returncode == 0:
            return out.decode(errors="replace")
        return "__ERR__ " + (err or out).decode(errors="replace").strip()[:300]
    except asyncio.TimeoutError:
        return "__ERR__ timeout"
    except Exception as e:  # noqa: BLE001
        return f"__ERR__ {e}"


def _parse(out):
    """[(label, idn, id, already), ...] from media-add search output."""
    items = []
    for line in (out or "").splitlines():
        m = _ITEM.match(line)
        if m:
            items.append((m["label"], m["idn"], m["id"], bool(m["already"])))
    return items


async def _search_av(query):
    q = shlex.quote(query)
    tv, mv = await asyncio.gather(
        _media(f"series search {q}"), _media(f"movie search {q}")
    )
    if tv.startswith("__ERR__") and mv.startswith("__ERR__"):
        return f"No pude buscar: {tv[8:].strip()}"
    lines = [f"Resultados para «{query}» — tocá para agregar:"]
    for label, _, tid, already in _parse(tv)[:5]:
        lines.append(f"📺 {label}" + (" — ya está" if already else f"\n      /madd_tv_{tid}"))
    for label, _, mid, already in _parse(mv)[:5]:
        lines.append(f"🎬 {label}" + (" — ya está" if already else f"\n      /madd_mv_{mid}"))
    if len(lines) == 1:
        return f"Sin resultados para «{query}». Probá con otro título (o el nombre original)."
    lines.append("\n/mst estado de descargas")
    return "\n".join(lines)


async def _search_music(query):
    out = await _media(f"artist search {shlex.quote(query)}")
    if out.startswith("__ERR__"):
        return f"No pude buscar: {out[8:].strip()}"
    items = _parse(out)[:8]
    if not items:
        return f"Sin artistas para «{query}»."
    _S["artists"] = [(iid, label) for label, _, iid, _ in items]
    lines = [f"Artistas para «{query}» — tocá para agregar (discografía completa):"]
    for i, (label, _, _, already) in enumerate(items, 1):
        lines.append(f"🎵 {label}" + (" — ya está" if already else f"\n      /ma_{i}"))
    return "\n".join(lines)


async def _add(kind, ext_id):
    out = await _media(f"{kind} add {shlex.quote(ext_id)}", timeout=90)
    if out.startswith("__ERR__"):
        return f"No pude agregar: {out[8:].strip()}"
    out = out.strip()
    if out.startswith("Added:"):
        que = {"series": "la serie", "movie": "la película", "artist": "el artista"}[kind]
        return (f"✅ Agregué {que} {out[len('Added:'):].replace('— searching now.', '').strip()} "
                f"— ya está buscando. Te aviso cuando esté en Plex.\n\n/mst estado")
    return out


async def _m(raw_args):
    parts = (raw_args or "").strip().split(maxsplit=1)
    sub = parts[0] if parts else ""
    rest = parts[1] if len(parts) > 1 else ""

    if sub == "":
        return ("Media server — comandos:\n"
                "/m <título>   buscar serie o película\n"
                "/mm <artista> buscar música\n"
                "/mst          qué se está bajando")
    if sub == "addtv":
        return await _add("series", rest.strip())
    if sub == "addmv":
        return await _add("movie", rest.strip())
    if sub == "addartist":
        try:
            mbid, label = _S["artists"][int(rest.strip()) - 1]
        except (ValueError, IndexError):
            return "Ese número no está en la última búsqueda. Mandá /mm <artista> de nuevo."
        return await _add("artist", mbid)
    if sub == "music":
        return await _search_music(rest.strip()) if rest.strip() else "Uso: /mm <artista>"
    if sub == "status":
        out = await _media("status")
        return out[8:].strip() if out.startswith("__ERR__") else out.strip()
    # anything else is a search query (incl. multi-word)
    return await _search_av((sub + " " + rest).strip())


def _hook(event=None, gateway=None, session_store=None, **kwargs):
    try:
        text = (getattr(event, "text", "") or "").strip()
    except Exception:
        return None
    if not text:
        return None
    m = re.match(r"^/madd_tv_(\d+)$", text)
    if m:
        return {"action": "rewrite", "text": f"/m addtv {m.group(1)}"}
    m = re.match(r"^/madd_mv_(\d+)$", text)
    if m:
        return {"action": "rewrite", "text": f"/m addmv {m.group(1)}"}
    m = re.match(r"^/ma_(\d+)$", text)
    if m:
        return {"action": "rewrite", "text": f"/m addartist {m.group(1)}"}
    if text == "/mst":
        return {"action": "rewrite", "text": "/m status"}
    m = re.match(r"^/mm(?:\s+(.*))?$", text)
    if m:
        return {"action": "rewrite", "text": f"/m music {m.group(1) or ''}".rstrip()}
    return None


def register(ctx):
    ctx.register_command(
        "m", _m,
        description="media server: search/add series, movies and music",
        args_hint="<query>",
    )
    ctx.register_hook("pre_gateway_dispatch", _hook)
