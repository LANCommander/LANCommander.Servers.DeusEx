---
sidebar_label: Docker
---

# Deus Ex Docker Container

This Docker container runs a Deus Ex (1.112fm) multiplayer dedicated server. It is built on the WINE image and runs the retail game in its dedicated server mode, `DeusEx.exe -server`. The container doesn't download the game, so you provide the files.

## Quick Start

```yaml
services:
  deusex:
    image: lancommander/deusex:latest
    container_name: deusex

    ports:
      - 7790:7790/udp
      - 7791:7791/udp
      - 8777:8777/udp

    volumes:
      - "/data/Servers/Deus Ex/Deathmatch:/config"

    environment:
      DX_SERVER_NAME: "My Deus Ex Server"
      DX_MAP: "DXMP_Cathedral"
      DX_GAME_TYPE: "DeusEx.DeathMatchGame"
      DX_ADMIN_PASSWORD: "changeme"
      DX_MAPS: "DXMP_Cathedral,DXMP_Smuggler,DXMP_Silo,DXMP_Area51Bunker,DXMP_CMD"
      DX_MAP_CYCLE: "loop"

    user: root
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined

    restart: unless-stopped
```

Copy a Deus Ex **1.112fm** install (the folder with `System/DeusEx.exe` and `Maps/`) into `Server/` before the first start. You can instead set `DX_ARCHIVE_URL` to a zip of that folder.

## How It Starts

1. `PostInitialization/10-InitializeWinePrefix.ps1` (from the WINE image) creates the Wine prefix in `/config/wineprefix`.
2. `PostInitialization/20-InstallDeusEx.ps1` checks for `Server/System/DeusEx.exe`. If it's missing and `DX_ARCHIVE_URL` is set, the hook downloads the archive, extracts the folder that holds `System/DeusEx.exe`, and remounts the overlay.
3. `PostInitialization/30-ConfigureDeusEx.ps1` copies `System/Default.ini` to `System/Server.ini` (`DX_INI`) if it doesn't exist yet. It does this through `Merged/`, so the file lands in `Overlay/System/`. It then writes the non-empty `DX_*` settings into it, sets the map rotation, and removes the GameSpy master server uplinks.
4. `START_EXE` (`/usr/local/bin/dx-server`) deletes a stale `System/Running.ini` and runs `DeusEx.exe <DX_MAP>?game=<DX_GAME_TYPE> -server ini=Server.ini log=server.log` from `System/` under Wine and Xvfb. This is the command line the game's own **Host Game > Dedicated** menu uses.

The server prints nothing to `docker logs` after Wine starts. Its log is `System/server.log` (in `Overlay/`), and the engine only writes it out in chunks (on map changes and on exit), so it is often empty or behind. Check that the server is up with a query instead (below).

## Configuration Options

### Ports

- **7790/udp**: Game (`DX_PORT`)
- **7791/udp**: Server query, GameSpy protocol (game port + 1). `\status\` returns the name, map, game type, version (`gamever 1100`), player count and rules (`SkillsAvail`, `KillsToWin` ...).
- **8777/udp**: LAN beacon. The in-game LAN browser broadcasts `REPORTQUERY` here, and the server replies `DeusEx 7791`.

### Environment Variables

See the [README](../README.md#environment-variables) for the full table.

### Server ini

`Overlay/System/Server.ini` is yours to edit. Only the keys that have a non-empty `DX_*` variable are rewritten on start. Delete the file to regenerate it from `Default.ini`.

- Server info: `[Engine.GameReplicationInfo]` (`ServerName`, `AdminName`, `MOTDLine1` ...).
- `MaxPlayers`, `MaxSpectators`, `GamePassword` and `AdminPassword` are in `[Engine.GameInfo]`. They apply to every game type.
- Game rules: `[DeusEx.DeusExMPGame]` `VictoryCondition` (`Frags`/`Time`), `ScoreToWin`, `SkillsTotal`, `SkillsAvail`, `SkillsPerKill`, `InitialAugs`, `AugsPerKill`, `MPSkillStartLevel`, `fFriendlyFireMult`. Basic and Advanced Team Deathmatch ignore these and use fixed values.
- Map rotation: `[DeusEx.DXMapList]` `Maps[0]`..`Maps[31]`, `CycleType` (0 repeat, 1 random, 2 loop) and `MapNum` (the current position, saved by the game). Any `Maps[n]` slot missing from the ini falls back to the built-in list (Silo, Area51Bunker, Cathedral, Cmd, Smuggler), so `DX_MAPS` always writes all 32 slots.

The game saves its config back to the server ini on every map change (the full map list, `MapNum` and so on show up there after the first change).

### Hooks

| Hook | When |
|------|------|
| `PreInstallDeusEx` / `PostInstallDeusEx` | Around the game file check/download |
| `PreInitializeWinePrefix` / `PostInitializeWinePrefix` | Around Wine prefix creation (WINE image) |

Put `.ps1` scripts in `config/Scripts/Hooks/<HookName>/`.

## Troubleshooting

- **Nothing in `docker logs` / empty `server.log`**: expected, see [How It Starts](#how-it-starts). Query port 7791 with `\status\` to check the server.
- **Server not in the LAN browser**: the browser finds servers by UDP broadcast to 8777, so the container needs its own LAN address (macvlan/ipvlan) or host networking. Joining by IP works through port mapping.
- **Joining by IP**: the client's default port is 7790. With another `DX_PORT`, join with `open <ip>:<port>` from the console.
- **Clients can't join / version mismatch**: the server reports `gamever 1100` and `minnetver 1100`. Clients need 1.112fm.
- **Settings ignored**: they go into `DX_INI`, not `DeusEx.ini` or `Default.ini`. Check `Overlay/System/Server.ini`. Victory, skill and aug settings have no effect in Basic and Advanced Team Deathmatch.
- **Rotation includes maps you didn't list**: a hand-edited `[DeusEx.DXMapList]` with fewer than 32 `Maps[n]` lines is padded with the built-in list. Set the unused slots to empty (`Maps[5]=`) or use `DX_MAPS`.
- **`DX_MASTER_SERVER_UPLINK=true` has no effect on an existing ini**: the uplink server actors were removed from it on an earlier start. Add `ServerActors=IpServer.UdpServerUplink MasterServerAddress=... MasterServerPort=27900` back under `[DeusEx.DeusExGameEngine]`, or delete the ini.
- **`System/DeusEx.exe not found`**: `Server/` must contain the game folder itself (`Server/System/DeusEx.exe`), not a folder that contains it.
- **Exits right after Wine starts**: `DeusEx.exe` needs a display. Leave `WINE_XVFB` at `auto` (or `true`) unless you provide a `DISPLAY`.
