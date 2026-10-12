# Build box for the Miyoo Mini Flip port: the Miyoo Mini toolchain (gcc 8.3,
# arm-linux-gnueabihf, glibc 2.28 — the device's own libc) plus a pinned Rust
# with the armv7 target, so one image builds both the cores and the frontend.
FROM mholdg16/miyoomini-toolchain:latest

# bc, which the base image lacks. gpSP's Makefile gates -march=armv7ve and
# -static-libgcc behind "$(CC) -dumpversion | bc" comparisons; without bc those
# $(shell) calls return empty and the flags silently take the wrong branch.
# Debian 10 is EOL so its deb.debian.org entries 404 — point apt at the archive.
RUN printf 'deb http://archive.debian.org/debian buster main\n' > /etc/apt/sources.list \
 && apt-get -o Acquire::Check-Valid-Until=false update -qq \
 && apt-get install -y -qq --no-install-recommends bc \
 && rm -rf /var/lib/apt/lists/*

# Pinned to match upstream/slot/rust-toolchain.toml.
ARG RUST_VERSION=1.96
ENV RUSTUP_HOME=/opt/rustup CARGO_HOME=/opt/cargo
# Both toolchains on PATH for every shell. The base image only puts the cross
# toolchain on root's PATH via /etc/profile, and we build as the calling user.
ENV PATH=/opt/cargo/bin:/opt/miyoomini-toolchain/usr/bin:$PATH

# wget, not curl: the base image is Debian 10, whose apt repos are archived, and
# it ships wget but not curl.
RUN wget -qO /tmp/rustup.sh https://sh.rustup.rs \
 && sh /tmp/rustup.sh -y --no-modify-path --profile minimal \
        --default-toolchain "${RUST_VERSION}" \
        --target armv7-unknown-linux-gnueabihf \
 && rustup component add rustfmt clippy \
 && chmod -R a+rwX /opt/rustup /opt/cargo

# The base image only exports CROSS_COMPILE from root's bashrc, so it is missing
# in the non-login shells the build tasks use. Set it here for every shell.
ENV CROSS_COMPILE=arm-linux-gnueabihf-

# Link with the device's own gcc so the binary resolves against glibc 2.28.
ENV CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_LINKER=arm-linux-gnueabihf-gcc \
    CC_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-gcc \
    CXX_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-g++ \
    AR_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-ar \
    CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_RUSTFLAGS="-C target-cpu=cortex-a7"

# /etc/profile rewrites PATH wholesale, and differently for root than for other
# users, so a login shell as the calling uid loses both toolchains. profile.d is
# sourced after that, so put them back for login shells too.
RUN echo 'export PATH=/opt/cargo/bin:/opt/miyoomini-toolchain/usr/bin:$PATH' > /etc/profile.d/zz-rust.sh
