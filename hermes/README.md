# Hermes hardened execution sandbox

Infrastructure-as-code for running the [Hermes](https://github.com/) agent
gateway on this workstation **safely**, given that the agent is reachable from
Telegram and has the ability to SSH into client and production hosts.

The threat we defend against: a prompt (or a compromised/abused chat) makes the
agent run arbitrary commands. We make those commands land inside a throwaway
Docker container with only a narrow, revocable SSH identity — never directly on
the host, and never with personal keys.

## Security model

| Layer | Control |
|-------|---------|
| **Who can command the bot** | `TELEGRAM_ALLOWED_USERS` in `~/.hermes/.env` is pinned to your Telegram user id only. DMs from anyone else are dropped. |
| **Command approval** | `approvals.mode: manual` — the agent asks before executing. |
| **Execution isolation** | `terminal.backend: docker`. Every command runs in an ephemeral `hermes-agent-ssh` container (1 CPU, 5 GB RAM, 300 s lifetime). The host filesystem is **not** mounted (`docker_mount_cwd_to_workspace: false`). |
| **SSH identity** | A dedicated key `~/.hermes/ssh/hermes_id_ed25519`, mounted **read-only** at `/opt/hermes-ssh`. Your personal `~/.ssh` is never exposed to the agent. Revoke per-client by deleting that one pubkey from the client's `authorized_keys`. |

## What is in this repo vs. what stays out

This repo contains **only code and configuration logic**. It never contains
secrets. The following live exclusively under `~/.hermes` and are gitignored:

- `ssh/hermes_id_ed25519` — the agent private key (machine-specific)
- `.env` — Telegram bot token, provider API keys, allowed users
- `auth.json`, `credentials/` — provider auth

## Files

```
hermes/
├── docker/
│   ├── agent-ssh/Dockerfile    # sandbox image: base + openssh-client
│   └── poc-client/Dockerfile   # simulated client server (sshd, key-only)
├── setup.sh                    # idempotent provisioner
├── poc.sh                      # build/run/test/down the test client
└── .gitignore                  # keeps secrets and pubkeys out
```

## Usage

```sh
# Provision the sandbox (key + image + config + gateway restart):
./setup.sh

# Same, and also bring up the proof-of-concept client:
./setup.sh --with-poc

# Proof-of-concept lifecycle on its own:
./poc.sh up      # build + run the simulated client, prints its IP
./poc.sh test    # verify the full SSH chain from the host (no Telegram)
./poc.sh down    # remove it
```

After `./poc.sh up`, message the bot from Telegram, e.g.:

> Conectate por SSH a `deploy@<ip>` con la llave
> `/opt/hermes-ssh/hermes_id_ed25519` y decime la versión de OS.

You should see the gateway spin up the sandbox container, SSH into the test
client, and return the OS version to your phone — with your host untouched.

## Granting the agent access to a real host

Append the agent's **public** key to the target's `authorized_keys`
(ideally as a restricted/forced-command user):

```sh
ssh-copy-id -i ~/.hermes/ssh/hermes_id_ed25519.pub deploy@your-server
```

To revoke: delete that line from the server's `authorized_keys`. Your personal
access is unaffected.

## Notes / gotchas

- **Tailscale MagicDNS** on this host breaks Docker's registry DNS, so images
  are built from the already-pulled `nikolaik/python-nodejs` base with
  `DOCKER_BUILDKIT=0` (the legacy builder skips the registry metadata lookup).
- Do **not** set `terminal.docker_volumes` via `hermes config set` — it stores
  the value as a string and silently disables the mount. `setup.sh` writes it
  as a proper YAML list.
