"""workmux-tg: deterministic Telegram wrapper over workmux.

Browse a client's workmux worktrees and talk to their agents from Telegram via
tappable commands — without the model in the loop. The gateway runs as an
unprivileged user; this plugin SSHes to each client user on localhost with the
per-client agent key and drives workmux directly.

UX (single-user personal bot, one active session):
  /wt              -> menu of clients (tappable /wtc_<client>)
  /wtc_<client>    -> list that client's worktrees (tappable /wt_1, /wt_2, ...)
  /wt_<n>          -> enter worktree n: show the agent's output
  <free text>      -> relayed to the active worktree's agent (workmux send)
  /wtl             -> more output (capture)
  /wtx             -> leave the worktree

Flow: a `pre_gateway_dispatch` hook rewrites the tappable/free-text forms into
`/wt <sub>` and the registered `/wt` command does the work. No LLM call.
"""
from __future__ import annotations

import asyncio
import json
import os
import re
import shlex

WORKMUX = "/home/linuxbrew/.linuxbrew/bin/workmux"
SSH_DIR = os.path.expanduser("~/.hermes/ssh")
_KEY_RE = re.compile(r"^hermes_(.+)_id_ed25519$")

# Single-user personal bot -> a single global session is sufficient.
_S = {"client": None, "items": [], "active": None}  # items: [(repo, handle, status)]


def _clients():
    out = []
    try:
        for f in sorted(os.listdir(SSH_DIR)):
            m = _KEY_RE.match(f)
            if m and m.group(1) != "id":  # skip a bare hermes_id_ed25519 (the POC key)
                out.append(m.group(1))
    except OSError:
        pass
    return out


async def _ssh(client, remote_cmd, timeout=45):
    key = f"{SSH_DIR}/hermes_{client}_id_ed25519"
    argv = [
        "ssh", "-i", key,
        "-o", "IdentitiesOnly=yes", "-o", "BatchMode=yes",
        "-o", "StrictHostKeyChecking=accept-new",
        "-o", "UserKnownHostsFile=/dev/null", "-o", "ConnectTimeout=8",
        f"{client}@127.0.0.1", remote_cmd,
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


def _pick(obj, *keys):
    for k in keys:
        v = obj.get(k)
        if v:
            return str(v)
    return ""


async def _gather(client):
    """Return ([(repo, handle, status)], error_or_None)."""
    script = (
        f"WM={WORKMUX}; shopt -s nullglob; "
        'for r in ~/repos/*__worktrees/; do b="${r%__worktrees/}"; '
        '[ -e "$b/.git" ] || continue; echo "@@@REPO@@@ $(basename "$b")"; '
        '(cd "$b" && "$WM" list --json 2>/dev/null); done'
    )
    out = await _ssh(client, "bash -c " + shlex.quote(script))
    if out.startswith("__ERR__"):
        return None, out[8:].strip()
    items, repo, buf = [], None, []

    def flush():
        nonlocal buf
        if repo and buf:
            try:
                arr = json.loads("".join(buf))
                for o in arr if isinstance(arr, list) else []:
                    h = _pick(o, "handle", "branch", "name")
                    if h:
                        items.append((repo, h, _pick(o, "agent", "status", "agent_status", "mux")))
            except Exception:
                pass
        buf = []

    for line in out.splitlines():
        if line.startswith("@@@REPO@@@ "):
            flush()
            repo = line[len("@@@REPO@@@ "):].strip()
        else:
            buf.append(line)
    flush()
    return items, None


def _rdir(repo):
    return "~/repos/" + shlex.quote(repo)


async def _capture(repo, handle, n=40):
    out = await _ssh(_S["client"], f"cd {_rdir(repo)} && {WORKMUX} capture {shlex.quote(handle)} -n {n} 2>&1")
    return "" if out.startswith("__ERR__") else out.strip()


async def _wt(raw_args):
    parts = (raw_args or "").strip().split(maxsplit=1)
    sub = parts[0] if parts else ""
    rest = parts[1] if len(parts) > 1 else ""

    if sub == "":
        cs = _clients()
        if not cs:
            return "No hay clientes configurados (faltan llaves hermes_<cliente> en ~/.hermes/ssh)."
        return "Clientes — tocá uno para ver sus worktrees:\n" + "\n".join(f"/wtc_{c}" for c in cs)

    if sub == "client":
        client = rest.strip()
        if client not in _clients():
            return f"Cliente desconocido: {client}"
        items, err = await _gather(client)
        if err:
            return (f"No pude leer worktrees de {client}: {err}\n"
                    "(si su home es ecryptfs, necesita una sesión activa/montada)")
        _S.update(client=client, items=items, active=None)
        if not items:
            return f"{client}: no hay worktrees activas."
        lines = [f"{client} — tocá una worktree:"]
        for i, (repo, h, st) in enumerate(items, 1):
            lines.append(f"/wt_{i}  {h} ({repo}){' · ' + st if st else ''}")
        return "\n".join(lines)

    if sub == "sel":
        try:
            repo, handle, _ = _S["items"][int(rest.strip()) - 1]
        except (ValueError, IndexError):
            return "Worktree inválida. Mandá /wt para empezar."
        _S["active"] = (repo, handle)
        body = await _capture(repo, handle, 40) or "(sin salida del agente todavía)"
        return (f"Entraste a {handle} ({repo}).\n\n```\n{body[-2500:]}\n```\n\n"
                "Escribí un mensaje y se lo mando al agente.  /wtl más output  ·  /wtx salir")

    if sub == "send":
        if not _S.get("active"):
            return "No estás en ninguna worktree. Mandá /wt para elegir."
        repo, handle = _S["active"]
        snd = await _ssh(_S["client"], f"cd {_rdir(repo)} && {WORKMUX} send {shlex.quote(handle)} {shlex.quote(rest)} 2>&1", timeout=60)
        if snd.startswith("__ERR__"):
            return f"Error al enviar: {snd[8:].strip()}"
        await asyncio.sleep(3)
        body = await _capture(repo, handle, 40)
        return f"→ enviado a {handle}.\n\n```\n{body[-2500:]}\n```\n\n/wtl más  ·  /wtx salir"

    if sub == "log":
        if not _S.get("active"):
            return "No estás en ninguna worktree."
        repo, handle = _S["active"]
        return f"```\n{(await _capture(repo, handle, 120))[-3500:]}\n```"

    if sub == "exit":
        _S["active"] = None
        return "Saliste de la worktree. /wt para elegir otra."

    return "Subcomando /wt no reconocido."


def _hook(event=None, gateway=None, session_store=None, **kwargs):
    try:
        text = (getattr(event, "text", "") or "").strip()
    except Exception:
        return None
    if not text:
        return None
    m = re.match(r"^/wtc_([A-Za-z0-9_-]+)$", text)
    if m:
        return {"action": "rewrite", "text": f"/wt client {m.group(1)}"}
    m = re.match(r"^/wt_(\d+)$", text)
    if m:
        return {"action": "rewrite", "text": f"/wt sel {m.group(1)}"}
    if text == "/wtl":
        return {"action": "rewrite", "text": "/wt log"}
    if text == "/wtx":
        return {"action": "rewrite", "text": "/wt exit"}
    # free text while inside a worktree -> relay to its agent
    if _S.get("active") and not text.startswith("/"):
        return {"action": "rewrite", "text": f"/wt send {text}"}
    return None


def register(ctx):
    ctx.register_command(
        "wt", _wt,
        description="workmux: browse worktrees and talk to their agents",
        args_hint="[client]",
    )
    ctx.register_hook("pre_gateway_dispatch", _hook)
