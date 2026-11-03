# Deus Ex Server (Docker)

This repository provides a Dockerized **Deus Ex** multiplayer dedicated server (Ion Storm, 2000, Unreal Engine 1, patch 1.112fm). The image runs the retail Windows game's own dedicated server mode, `DeusEx.exe -server`, under Wine.
The image builds on [`lancommander/wine`](https://github.com/LANCommander/LANCommander.Servers.WINE). It supports file overlaying using OverlayFS.

---

## Features

- Runs the retail game's dedicated server, the same one the in-game **Host Game > Dedicated** option starts (headless under Xvfb; no graphics or sound)
- A separate server ini (`System/Server.ini`) is created from the game's `Default.ini`, and the common settings are environment variables
- Map rotation (`DX_MAPS`) with repeat, random or loop cycling; maps that aren't installed are left out
- The GameSpy master server uplinks are removed by default
- Supports file overlaying using OverlayFS (no file copying required)

## Docker Compose Example

```yaml
services:
  deusex:
    image: lancommander/deusex:latest
    container_name: deusex

    ports:
      - "7790:7790/udp"
      - "7791:7791/udp"
      - "8777:8777/udp"

    volumes:
      - ./config:/config

    environment:
      DX_SERVER_NAME: "My Deus Ex Server"
      DX_MAP: "DXMP_Cathedral"
      DX_GAME_TYPE: "DeusEx.DeathMatchGame"
      DX_MAX_PLAYERS: "16"
      DX_MAPS: "DXMP_Cathedral,DXMP_Smuggler,DXMP_Silo,DXMP_Area51Bunker,DXMP_CMD"
      DX_MAP_CYCLE: "loop"

    user: root
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined

    restart: unless-stopped
```

The in-game LAN browser finds servers by broadcast. That needs the container on the LAN itself (macvlan/ipvlan, or `network_mode: host`). With port mapping, clients join by IP.

---

## Game Files

Deus Ex is retail software with no public download. You must provide a **1.112fm** install (the folder with `System/DeusEx.exe`; the GOG and Steam releases are 1.112fm). Clients must run the same version.

- copy that folder's contents (`System/`, `Maps/`, `Textures/`, `Sounds/`, `Music/`) to `config/Server/`, **or**
- set `DX_ARCHIVE_URL` to a zip of it, e.g. a LANCommander archive. It is downloaded and extracted on first start, if `Server/System/DeusEx.exe` doesn't exist yet.

`Help/`, `Save/` and the manual aren't needed.

## Directory Layout (Host)

```text
.
└── config/
    ├── Server/            # Deus Ex install (System/, Maps/, Textures/ ...)
    ├── Overlay/           # Your files, layered on top of Server/ (System/Server.ini and server.log land here)
    ├── Merged/            # Overlayfs merged view (auto-created, the server runs here)
    ├── wineprefix/        # Wine prefix (auto-created)
    └── Scripts/
        └── Hooks/         # PowerShell scripts run at container lifecycle hooks
```

---

## Environment Variables

These are in addition to the [WINE image's variables](https://github.com/LANCommander/LANCommander.Servers.WINE#environment).
The ini settings are written into `DX_INI` on every start. Settings left empty are not touched, so you can set them in the ini instead.

| Variable | Description | Default |
|----------|-------------|---------|
| `DX_MAP` | Start map, see below | `DXMP_Cathedral` |
| `DX_GAME_TYPE` | Game class, see below | `DeusEx.DeathMatchGame` |
| `DX_URL_OPTIONS` | Extra map URL options, e.g. `MaxPlayers=8` | |
| `DX_INI` | Server ini in `System/`, created from `Default.ini` if missing | `Server.ini` |
| `DX_PORT` | Game port, `[URL] Port`. The query port is this + 1 | `7790` |
| `DX_SERVER_NAME` | `[Engine.GameReplicationInfo] ServerName` | `Deus Ex Server` |
| `DX_SHORT_NAME` | `[Engine.GameReplicationInfo] ShortName` | `Deus Ex Server` |
| `DX_ADMIN_NAME` | `[Engine.GameReplicationInfo] AdminName` | |
| `DX_ADMIN_EMAIL` | `[Engine.GameReplicationInfo] AdminEmail` | |
| `DX_MOTD` | `[Engine.GameReplicationInfo] MOTDLine1` | |
| `DX_MAX_PLAYERS` | `[Engine.GameInfo] MaxPlayers` | `16` |
| `DX_GAME_PASSWORD` | `[Engine.GameInfo] GamePassword` | |
| `DX_ADMIN_PASSWORD` | `[Engine.GameInfo] AdminPassword` (in-game `adminlogin <password>`) | |
| `DX_VICTORY_CONDITION` | `[DeusEx.DeusExMPGame] VictoryCondition`: `Frags` (kill limit) or `Time` (time limit). The game default is `Frags` | |
| `DX_SCORE_TO_WIN` | `[DeusEx.DeusExMPGame] ScoreToWin`: kills to win, or minutes with `Time`. The game default is 20 | |
| `DX_SKILLS_AVAIL` | `[DeusEx.DeusExMPGame] SkillsAvail`: skill points at spawn | |
| `DX_SKILLS_PER_KILL` | `[DeusEx.DeusExMPGame] SkillsPerKill` | |
| `DX_INITIAL_AUGS` | `[DeusEx.DeusExMPGame] InitialAugs`: augmentations at spawn | |
| `DX_AUGS_PER_KILL` | `[DeusEx.DeusExMPGame] AugsPerKill` | |
| `DX_SKILL_START_LEVEL` | `[DeusEx.DeusExMPGame] MPSkillStartLevel` | |
| `DX_FRIENDLY_FIRE` | `[DeusEx.DeusExMPGame] fFriendlyFireMult`: team damage multiplier | |
| `DX_MAPS` | Map rotation, comma separated (`.dx` is optional), up to 32 | |
| `DX_MAP_CYCLE` | `[DeusEx.DXMapList] CycleType`: `repeat`, `random` or `loop` | |
| `DX_MASTER_SERVER_UPLINK` | `true` keeps the `UdpServerUplink` server actors (master server listing) | `false` |
| `DX_ARCHIVE_URL` | Zip of the game folder, used if `Server/System/DeusEx.exe` is missing | |
| `WINE_XVFB` | `DeusEx.exe` is a GUI program and needs a display; `auto` starts Xvfb | `auto` |
| `START_EXE` | Launcher | `/usr/local/bin/dx-server` |
| `START_ARGS` | Appended to the `DeusEx.exe` command line | |

The `DeusExMPGame` settings (victory, skills, augs, friendly fire) apply to Deathmatch and Custom Team Deathmatch. Basic and Advanced Team Deathmatch use fixed values.

Game types:

| `DX_GAME_TYPE` | Mode |
|----------------|------|
| `DeusEx.DeathMatchGame` | Deathmatch |
| `DeusEx.BasicTeamDMGame` | Basic Team Deathmatch (UNATCO vs. NSF, fixed rules) |
| `DeusEx.AdvTeamDMGame` | Advanced Team Deathmatch (fixed rules) |
| `DeusEx.TeamDMGame` | Custom Team Deathmatch (uses the `DeusExMPGame` settings) |

Retail maps (all modes): `DXMP_Area51Bunker`, `DXMP_Cathedral`, `DXMP_CMD`, `DXMP_Silo`, `DXMP_Smuggler`.

See [Documentation/Docker.md](Documentation/Docker.md) for more detail.

---

## Building

The image is built `FROM lancommander/wine:latest` by default. To build against a local base image:

```bash
docker build --build-arg BASE_IMAGE=lancommander/wine:local -t lancommander/deusex:local .
```

---

## License

Deus Ex and Wine are distributed under their respective licenses.
This repository contains only Docker build logic and helper scripts licensed under MIT.
