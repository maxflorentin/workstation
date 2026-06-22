# Simulated "client server" for the Hermes sandbox proof-of-concept.
# An isolated box running sshd that ONLY trusts the dedicated Hermes agent
# key. Lets you exercise the full Telegram -> sandbox -> SSH path without
# touching any real client or production host.
#
# NOTE: based on the already-pulled nikolaik image (debian) instead of
# ubuntu:24.04, because Docker's registry DNS goes through Tailscale MagicDNS
# on this host and external pulls fail. apt inside the build works fine.
# Build with DOCKER_BUILDKIT=0 so BuildKit does not phone the registry.
FROM nikolaik/python-nodejs:python3.11-nodejs20

RUN apt-get update \
 && apt-get install -y --no-install-recommends openssh-server \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /run/sshd \
 && ssh-keygen -A

# Unprivileged login user; key-only auth.
RUN useradd -m -s /bin/bash deploy \
 && mkdir -p /home/deploy/.ssh \
 && chmod 700 /home/deploy/.ssh
COPY hermes_id_ed25519.pub /home/deploy/.ssh/authorized_keys
RUN chmod 600 /home/deploy/.ssh/authorized_keys \
 && chown -R deploy:deploy /home/deploy/.ssh

# Harden sshd: key auth only, no root, no passwords.
RUN sed -i \
    -e 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' \
    -e 's/^#\?PermitRootLogin.*/PermitRootLogin no/' \
    -e 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' \
    /etc/ssh/sshd_config

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
