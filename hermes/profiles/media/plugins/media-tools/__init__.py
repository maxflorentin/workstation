"""Media tools for a terminal-less agent: fixed verbs over the mediabot forced-command endpoint."""
from __future__ import annotations

import json
import os
import re
import subprocess

KEY = os.path.expanduser("~/.hermes/ssh/hermes_id_ed25519")
MEDIABOT = "mediabot@127.0.0.1"
KINDS = ("series", "movie", "artist")
ID_PATTERNS = {
    "series": re.compile(r"^\d{1,10}$"),
    "movie": re.compile(r"^\d{1,10}$"),
    "artist": re.compile(r"^[0-9a-fA-F-]{36}$"),
}
# The remote dispatcher word-splits this string, so a query must stay plain text.
QUERY_UNSAFE = re.compile(r"[^\w\s.,:'&-]", re.UNICODE)


def _run(remote_args: str) -> str:
    argv = [
        "ssh", "-i", KEY, "-o", "IdentitiesOnly=yes", "-o", "BatchMode=yes",
        "-o", "StrictHostKeyChecking=accept-new", "-o", "UserKnownHostsFile=/dev/null",
        "-o", "ConnectTimeout=8", MEDIABOT, remote_args,
    ]
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=45)
    except subprocess.TimeoutExpired:
        return json.dumps({"error": "timeout"})
    if p.returncode != 0:
        return json.dumps({"error": (p.stderr or p.stdout).strip()[:300]})
    return json.dumps({"output": p.stdout.strip()[:6000]}, ensure_ascii=False)


def _search(args: dict, **_) -> str:
    kind, query = args.get("kind"), QUERY_UNSAFE.sub(" ", str(args.get("query", ""))).strip()
    if kind not in KINDS or not query:
        return json.dumps({"error": "kind must be series, movie or artist, and query is required"})
    return _run(f"{kind} search {query}")


def _add(args: dict, **_) -> str:
    kind, item_id = args.get("kind"), str(args.get("id", "")).strip()
    if kind not in KINDS or not ID_PATTERNS[kind].match(item_id):
        return json.dumps({"error": "invalid kind or id; use the id returned by media_search, without its prefix"})
    return _run(f"{kind} add {item_id}")


def _status(args: dict, **_) -> str:
    return _run("status")


KIND_PROP = {"type": "string", "enum": list(KINDS), "description": "series, movie or artist (music)"}


def register(ctx):
    ctx.register_tool(
        name="media_search", toolset="media", handler=_search,
        schema={"name": "media_search", "description": "Search series, movies or music artists on the media server. Results include each item's id and whether it was already added.",
                "parameters": {"type": "object", "properties": {"kind": KIND_PROP, "query": {"type": "string", "description": "Title, optionally with the year"}}, "required": ["kind", "query"]}},
    )
    ctx.register_tool(
        name="media_add", toolset="media", handler=_add,
        schema={"name": "media_add", "description": "Add an item by the id returned from media_search (tvdb number for series, tmdb number for movies, MusicBrainz UUID for artists). This starts downloading.",
                "parameters": {"type": "object", "properties": {"kind": KIND_PROP, "id": {"type": "string"}}, "required": ["kind", "id"]}},
    )
    ctx.register_tool(
        name="media_status", toolset="media", handler=_status,
        schema={"name": "media_status", "description": "Show what is currently downloading.", "parameters": {"type": "object", "properties": {}}},
    )
