# Reproducible OCI image for the authoritative Project0 Godot game server.
# Runtime boundary per .scratch/container-platform/issues/01-runtime-boundary-and-container-adapter.md:
# pinned Godot 4.3 headless, non-root, UDP 9999, baked import cache, graceful
# shutdown via tini. Runs `server/server_main.gd` exactly like the native
# systemd unit (scripts/project0-server.service) does.

# DT-014: build the Linux wgnetstack GDExtension rather than shipping without
# it. `native/wgnetstack/gdext/build/` is gitignored, so the .so is absent from
# the build context and both Godot processes logged "GDExtension dynamic
# library not found" at every boot. Persistent false-alarm errors in an
# authoritative server's log train operators to ignore startup failures, which
# is exactly how the login-delegation outage stayed hidden.
#
# This stage depends only on native/wgnetstack and the pinned godot-cpp
# revision, so it stays cached while application code changes.
FROM debian:bookworm-slim AS gdext-builder

ENV DEBIAN_FRONTEND=noninteractive

# Pinned to the revision the shipped extension was built against (Slice 035),
# so the image never silently tracks whatever branch 4.3 points at.
ARG GODOT_CPP_REF=d5cc777a89d899665fb61f1650ef0dc0cf6488c4
# Debian's golang-go is too old to parse this module's go directive, so pin the
# upstream toolchain rather than depending on the distro's version.
ARG GO_VERSION=1.23.12

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential scons git ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && curl -sSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" | tar -C /usr/local -xz

ENV PATH="/usr/local/go/bin:${PATH}"

WORKDIR /src
COPY native/wgnetstack /src/native/wgnetstack

RUN git clone --quiet --branch 4.3 https://github.com/godotengine/godot-cpp.git \
        /src/native/wgnetstack/gdext/godot-cpp \
    && git -C /src/native/wgnetstack/gdext/godot-cpp checkout --quiet "${GODOT_CPP_REF}"

# The headless Godot binary is an editor build, so it resolves
# linux.editor.x86_64 -> the template_debug library. Only that target is built.
RUN make -C /src/native/wgnetstack cgoarchive \
    && cd /src/native/wgnetstack/gdext \
    && scons -j"$(nproc)" platform=linux target=template_debug \
    && test -f build/libwgnetstack_gdext.linux.template_debug.x86_64.so

FROM debian:bookworm-slim

# Pinned Godot runtime (provenance = the official 4.3-stable release tag).
ARG GODOT_URL=https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip
ARG GODOT_BINARY=Godot_v4.3-stable_linux.x86_64

ENV DEBIAN_FRONTEND=noninteractive

# Godot headless needs fontconfig for its text server; coreutils (stat/date) and
# grep back the health-file healthcheck; sqlite3 provides the online-backup API
# for consistent DB backups; tini gives correct PID 1 signal forwarding.
RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		ca-certificates wget unzip libfontconfig1 coreutils grep sqlite3 tini \
	&& rm -rf /var/lib/apt/lists/*

RUN wget -q "${GODOT_URL}" -O /tmp/godot.zip \
	&& unzip -q /tmp/godot.zip -d /tmp/godot \
	&& mv "/tmp/godot/${GODOT_BINARY}" /usr/local/bin/godot \
	&& chmod +x /usr/local/bin/godot \
	&& rm -rf /tmp/godot /tmp/godot.zip \
	&& godot --version

WORKDIR /app
COPY . /app

# Placed before the import so the baked cache is built with the extension
# present; otherwise the cache records a failed load.
COPY --from=gdext-builder \
    /src/native/wgnetstack/gdext/build/libwgnetstack_gdext.linux.template_debug.x86_64.so \
    /app/native/wgnetstack/gdext/build/

# Bake the import cache so GDExtensions (godot-sqlite, wgnetstack) and resources
# resolve at runtime without writing res:// on first boot.
RUN godot --headless --path /app --import 2>&1 | tail -n 30 || true

COPY deploy/game-server/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY deploy/game-server/healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh

# Non-root runtime user; owns the source tree (for any runtime reimport) and the
# writable data home where user:// (accounts.db, Canon) lives.
RUN useradd --system --uid 10001 --home-dir /data --create-home godot \
	&& chown -R godot:godot /app /data

USER godot
ENV HOME=/data \
	PROJECT0_SERVER_BIND_ADDRESS=0.0.0.0 \
	PROJECT0_SERVER_PORT=9999 \
	PROJECT0_ACCOUNTS_DB_PATH=accounts.db \
	PROJECT0_HEALTH_FILE=/data/health.json

EXPOSE 9999/udp

# Slice 067: liveness follows the runtime health file the server rewrites each
# tick (fresh + status "healthy"), so a frozen tick loop is caught even while the
# UDP socket stays bound.
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 \
	CMD /usr/local/bin/healthcheck.sh

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
