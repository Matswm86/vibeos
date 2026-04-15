# VibeOS apt repo (deploy to mwmai.no VPS)

Target host: `repo.mwmai.no` — Hetzner CX43 (204.168.244.173), already
running Caddy. Caddy vhost for this subdomain ships in
`../caddy/repo.mwmai.no.caddy`.

## One-time VPS setup

Run once as `root` (or the ops user with sudo):

```bash
# 1. Packages
apt-get update
apt-get install -y reprepro gnupg

# 2. Basedir (matches conf/options)
install -d -m 755 /srv/apt-repo
install -d -m 755 /srv/apt-repo/conf
install -d -m 755 /srv/apt-repo/incoming

# 3. Copy config from this repo
rsync -av /path/to/vibeos/infra/apt-repo/conf/ /srv/apt-repo/conf/

# 4. GPG — import the signing subkey ONLY (master stays on workstation).
#    On workstation:
#      gpg --armor --export-secret-subkeys 8F08022E65BC5F8F > vibeos-signing-subkey.asc
#      scp vibeos-signing-subkey.asc vps:/tmp/
#    On VPS:
#      sudo -u reprepro gpg --import /tmp/vibeos-signing-subkey.asc
#      shred -u /tmp/vibeos-signing-subkey.asc

# 5. Bootstrap empty repo (creates dists/noble/ so apt clients don't 404)
cd /srv/apt-repo
reprepro export noble

# 6. Publish the public key at repo.mwmai.no/vibeos.gpg
#    (copy keys/vibeos-pubkey.asc from the repo)
install -m 644 /path/to/vibeos/keys/vibeos-pubkey.asc /srv/apt-repo/vibeos.gpg

# 7. Wire Caddy (see ../caddy/repo.mwmai.no.caddy)
```

## Uploading new .debs

Done automatically by `.github/workflows/release.yml` on a `v2.*` tag,
gated on the `MWMAI_SSH_*` + `MWMAI_REPO_PATH` GitHub secrets being set.

Manual upload (e.g. during VPS bring-up, before CI is wired):

```bash
# From any workstation with the repo checkout:
scp packages/local/vibeos-*.deb ops@repo.mwmai.no:/tmp/
ssh ops@repo.mwmai.no
  cd /srv/apt-repo
  for d in /tmp/vibeos-*.deb; do reprepro includedeb noble "$d"; done
  reprepro export noble
  rm /tmp/vibeos-*.deb
```

## Client side (inside VibeOS ISO)

Shipped via `mkosi/mkosi.extra/etc/apt/sources.list.d/vibeos.list` and
`mkosi/mkosi.extra/etc/apt/trusted.gpg.d/vibeos.gpg` — see that directory
for the baked files.

Outside an already-VibeOS machine (e.g. to install packages on vanilla
Ubuntu 24.04):

```bash
curl -fsSL https://repo.mwmai.no/vibeos.gpg \
  | sudo tee /etc/apt/trusted.gpg.d/vibeos.asc >/dev/null
echo 'deb https://repo.mwmai.no/ noble main' \
  | sudo tee /etc/apt/sources.list.d/vibeos.list
sudo apt-get update
```
