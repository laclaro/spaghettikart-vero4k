# Cross-build environment for SpaghettiKart -> Vero 4k+ (OSMC, Debian bullseye armhf userspace).
#
# The armhf headers/libraries come from the Vero itself (vero-armhf-sysroot.tar.gz),
# installed as CMAKE_SYSROOT at /opt/vero-sysroot. That gives an exact match for
# glibc 2.31, libstdc++ 10.2.1, SDL2 2.0.20+1mali and the Mali GLES/EGL blob in /opt/vero3/lib.
# The bullseye cross compiler is GCC 10.2.1, the same version as the Vero's libstdc++6.

# Pinned to the image the build was tested with; bullseye-slim is no longer updated anyway.
FROM --platform=linux/amd64 debian:bullseye-slim@sha256:e5b6442dd2e9684cf5e87d8338b5968f3b348636fc0be6d7850a381e3731a2bd

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/opt/venv/bin:${PATH}"

# Bullseye is archived. Use its archive repositories.
RUN printf '%s\n' \
    'deb http://archive.debian.org/debian bullseye main contrib non-free' \
    'deb http://archive.debian.org/debian-security bullseye-security main' \
    > /etc/apt/sources.list \
    && apt-get -o Acquire::Check-Valid-Until=false update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        crossbuild-essential-armhf \
        git \
        ninja-build \
        pkg-config \
        python3 \
        python3-venv \
        ca-certificates \
        file \
    && python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir cmake==3.27.9 \
    && git config --system --add safe.directory '*' \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ENV VERO_SYSROOT=/opt/vero-sysroot

COPY vero-armhf-sysroot.tar.gz /tmp/
COPY docker/ /tmp/docker/
RUN mkdir -p "${VERO_SYSROOT}" \
    && tar --numeric-owner -xzf /tmp/vero-armhf-sysroot.tar.gz -C "${VERO_SYSROOT}" \
    && sh /tmp/docker/prepare-sysroot.sh "${VERO_SYSROOT}" /tmp/docker/cmake \
    && rm -rf /tmp/vero-armhf-sysroot.tar.gz /tmp/docker

COPY toolchain/vero-armhf.cmake /opt/toolchain/vero-armhf.cmake

# pkg-config must only see the Vero's .pc files, with paths re-rooted into the sysroot.
ENV PKG_CONFIG_SYSROOT_DIR=${VERO_SYSROOT}
ENV PKG_CONFIG_LIBDIR=${VERO_SYSROOT}/usr/lib/arm-linux-gnueabihf/pkgconfig:${VERO_SYSROOT}/usr/share/pkgconfig

WORKDIR /work

CMD ["/bin/bash"]
