# syntax=docker/dockerfile:1.7

# Override to build against a locally built base, e.g. lancommander/wine:local
ARG BASE_IMAGE=lancommander/wine:latest
FROM ${BASE_IMAGE}

# ----------------------------
# Server settings
#   - The game files are not downloadable; put a Deus Ex 1.112fm install in /config/Server, or set
#     DX_ARCHIVE_URL to a zip of one
#   - DX_INI is created from System/Default.ini on first start; the DX_* settings below are
#     written into it on every start (empty settings are left alone)
#   - DeusEx.exe is a GUI program, so it runs under Xvfb (WINE_XVFB=auto)
# ----------------------------
ENV DX_ARCHIVE_URL="" \
    DX_MAP="DXMP_Cathedral" \
    DX_GAME_TYPE="DeusEx.DeathMatchGame" \
    DX_PORT="7790" \
    DX_INI="Server.ini" \
    DX_SERVER_NAME="Deus Ex Server" \
    DX_SHORT_NAME="Deus Ex Server" \
    DX_ADMIN_NAME="" \
    DX_ADMIN_EMAIL="" \
    DX_MOTD="" \
    DX_MAX_PLAYERS="16" \
    DX_GAME_PASSWORD="" \
    DX_ADMIN_PASSWORD="" \
    DX_VICTORY_CONDITION="" \
    DX_SCORE_TO_WIN="" \
    DX_SKILLS_AVAIL="" \
    DX_SKILLS_PER_KILL="" \
    DX_INITIAL_AUGS="" \
    DX_AUGS_PER_KILL="" \
    DX_SKILL_START_LEVEL="" \
    DX_FRIENDLY_FIRE="" \
    DX_MAPS="" \
    DX_MAP_CYCLE="" \
    DX_MASTER_SERVER_UPLINK="false" \
    DX_URL_OPTIONS="" \
    START_EXE="/usr/local/bin/dx-server" \
    START_ARGS=""

COPY Scripts/dx-server /usr/local/bin/dx-server
RUN chmod +x /usr/local/bin/dx-server

COPY Hooks/ "${BASE_HOOKS}/"

# 7790/udp: game. 7791/udp: server query (game port + 1). 8777/udp: LAN browser beacon (UdpBeacon
# answers REPORTQUERY broadcasts there).
EXPOSE 7790/udp 7791/udp 8777/udp

WORKDIR /config
ENTRYPOINT ["/usr/local/bin/entrypoint.ps1"]
