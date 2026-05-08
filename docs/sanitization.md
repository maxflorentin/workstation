# Sanitization Policy

This repository must stay safe to publish and share.

Do not commit real references to:

- client names, client brands, or client project names
- client domains, hostnames, VPN profiles, or tailnet names
- personal email addresses
- real Tailscale IPs, LAN IPs, public IPs, or DNS names tied to a private setup
- auth keys, tokens, API keys, private keys, passphrases, or decrypted secrets
- screenshots, logs, or command output containing any of the above

Use placeholders instead:

```text
<client>
<project>
<workstation>
<workstation-tailscale-ip>
<mac-tailscale-ip>
<personal-tailnet-account>
<client-tailnet>
<client-subnet>
<auth-key>
```

Generic examples such as `acme`, `example.com`, `10.0.0.0/8`, and
documentation-only RFC/example values are acceptable when they are clearly not
real.

Before committing docs or scripts, run:

```bash
rg -n "real-client-or-brand|real-email@example.com|real-ip" README.md docs linux scripts workstation tests
```

Replace the patterns with the actual private strings you are checking for.
