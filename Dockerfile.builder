# VibeOS build toolchain — runs mkosi, dpkg-buildpackage, reprepro
# inside a sandboxed container so the host workstation never has any
# VibeOS-specific packages installed. All build artifacts land in
# ./mkosi.output/ (ISO) and ./apt-repo/pool/ (.deb files) via volume
# mounts.
#
# Base image = ubuntu:24.04 because:
#  - Python 3.12 is available (recent mkosi requires >=3.12)
#  - debootstrap noble metadata matches the target distro
#  - same apt+dpkg versions as the built system, no drift
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget git \
    debootstrap \
    dpkg-dev devscripts debhelper dh-python \
    fakeroot \
    librsvg2-bin imagemagick \
    squashfs-tools xorriso mtools \
    dosfstools e2fsprogs \
    cpio zstd xz-utils \
    systemd-container systemd-boot systemd-boot-efi \
    apt-utils gnupg \
    python3 python3-pip python3-venv python3-dev \
    python3-pefile python3-cryptography \
    reprepro \
    qemu-utils \
    locales \
    sudo \
  && locale-gen en_US.UTF-8 \
  && rm -rf /var/lib/apt/lists/*

# Install mkosi from git — not distributed via PyPI. Ubuntu noble has
# mkosi 20.2 in apt but we pin a modern tagged release from upstream for
# current noble + systemd-boot support. The bin/mkosi shim in the repo
# is designed to run directly from a git checkout.
ARG MKOSI_REF=v26
RUN git clone --depth=1 --branch=${MKOSI_REF} \
      https://github.com/systemd/mkosi.git /opt/mkosi \
  && ln -s /opt/mkosi/bin/mkosi /usr/local/bin/mkosi \
  && mkosi --version

WORKDIR /work

# Default entry — invoked by scripts/build.sh with appropriate args
CMD ["mkosi", "--help"]
