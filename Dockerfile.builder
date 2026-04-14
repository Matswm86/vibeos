# VibeOS build toolchain — runs mkosi, dpkg-buildpackage, reprepro
# inside a sandboxed container so the host workstation never has any
# VibeOS-specific packages installed. All build artifacts land in
# ./mkosi.output/ (ISO) and ./apt-repo/pool/ (.deb files) via volume
# mounts.
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget git \
    debootstrap \
    dpkg-dev devscripts debhelper dh-python \
    fakeroot \
    squashfs-tools xorriso mtools \
    dosfstools e2fsprogs \
    systemd-container \
    apt-utils gnupg \
    python3 python3-pip python3-venv \
    reprepro \
    qemu-utils \
    locales \
  && locale-gen en_US.UTF-8 \
  && rm -rf /var/lib/apt/lists/*

# Install mkosi from PyPI — the bookworm apt version is old (v14).
# Latest mkosi has proper Ubuntu 24.04 noble support, systemd-repart
# integration, and the `mkosi.conf` format we use in mkosi/mkosi.conf.
RUN python3 -m venv /opt/mkosi \
  && /opt/mkosi/bin/pip install --no-cache-dir mkosi \
  && ln -s /opt/mkosi/bin/mkosi /usr/local/bin/mkosi

WORKDIR /work

# Default entry — invoked by scripts/build.sh with appropriate args
CMD ["mkosi", "--help"]
