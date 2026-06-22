# Hermes agent sandbox image: base + OpenSSH client only.
# Used as terminal.docker_image so the sandboxed agent can SSH out using the
# dedicated key mounted read-only at /opt/hermes-ssh (never your personal keys).
FROM nikolaik/python-nodejs:python3.11-nodejs20

RUN apt-get update \
 && apt-get install -y --no-install-recommends openssh-client \
 && rm -rf /var/lib/apt/lists/*

# Sane client defaults for non-interactive agent use: only the explicitly
# provided key, no agent forwarding, learn host keys on first contact.
RUN mkdir -p /etc/ssh/ssh_config.d \
 && printf '%s\n' \
    'IdentitiesOnly yes' \
    'ForwardAgent no' \
    'StrictHostKeyChecking accept-new' \
    'UserKnownHostsFile /root/.ssh/known_hosts' \
    > /etc/ssh/ssh_config.d/00-hermes.conf
