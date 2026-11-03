#Requires -Modules Logging

# Create the server ini (DX_INI, default System/Server.ini) from the game's Default.ini on first
# start, then write the DX_* settings into it. It's created through the merged view, so it lands in
# Overlay/ and can be edited there; keys without a DX_* setting are never touched.

$system   = Join-Path $Env:SERVER_ROOT 'System'
$template = Join-Path $system 'Default.ini'
$ini      = Join-Path $system $Env:DX_INI

if (-not (Test-Path -Path $ini)) {
    if (-not (Test-Path -Path $template)) {
        Write-Log -Level Error "$template not found; skipping server configuration"
        return
    }

    Copy-Item -Path $template -Destination $ini
    Write-Log "Created $ini from Default.ini"
}

$text    = [System.IO.File]::ReadAllText($ini)
$newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
$lines   = [System.Collections.Generic.List[string]]::new([string[]]($text -split "\r?\n"))

function Get-SectionRange([string] $Section) {
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -ieq "[$Section]") { $start = $i; break }
    }
    if ($start -lt 0) { return $null }

    $end = $start + 1
    while ($end -lt $lines.Count -and -not $lines[$end].StartsWith('[')) { $end++ }
    return @($start, $end)
}

# Set Key=Value in [Section], replacing the first existing Key= line or appending to the section.
# StartsWith, not -like: keys such as Maps[0] contain wildcard characters.
function Set-IniValue([string] $Section, [string] $Key, [string] $Value) {
    $range = Get-SectionRange $Section
    if (-not $range) {
        if ($lines.Count -and $lines[$lines.Count - 1] -ne '') { $lines.Add('') }
        $lines.Add("[$Section]")
        $lines.Add("$Key=$Value")
        return
    }

    $start, $end = $range
    for ($i = $start + 1; $i -lt $end; $i++) {
        if ($lines[$i].StartsWith("$Key=", [System.StringComparison]::OrdinalIgnoreCase)) {
            $lines[$i] = "$Key=$Value"
            return
        }
    }

    # Insert after the section's last non-blank line
    $at = $end
    while ($at -gt $start + 1 -and [string]::IsNullOrWhiteSpace($lines[$at - 1])) { $at-- }
    $lines.Insert($at, "$Key=$Value")
}

# Victory condition: Frags (kill limit) or Time (time limit, DX_SCORE_TO_WIN is then minutes)
$victory = switch -Regex ($Env:DX_VICTORY_CONDITION) {
    '^(frags?|kills?)$' { 'Frags' }
    '^time$'            { 'Time' }
    '^$'                { '' }
    default             { Write-Log -Level Warning "Unknown DX_VICTORY_CONDITION '$Env:DX_VICTORY_CONDITION' (use Frags or Time)"; '' }
}

# Map cycling: 0 repeat, 1 random, 2 loop
$cycle = switch -Regex ($Env:DX_MAP_CYCLE) {
    '^(0|repeat|static)$' { '0' }
    '^(1|random)$'        { '1' }
    '^(2|loop|cycle)$'    { '2' }
    '^$'                  { '' }
    default               { Write-Log -Level Warning "Unknown DX_MAP_CYCLE '$Env:DX_MAP_CYCLE' (use repeat, random or loop)"; '' }
}

# AdminPassword/GamePassword/MaxPlayers are globalconfig in Engine.GameInfo, so they're read from
# that section for every game type. The DeusExMPGame settings apply to Deathmatch and Custom Team
# Deathmatch (TeamDMGame); Basic and Advanced Team Deathmatch use fixed values.
$settings = @(
    @('URL',                         'Port',              $Env:DX_PORT),
    @('Engine.GameReplicationInfo',  'ServerName',        $Env:DX_SERVER_NAME),
    @('Engine.GameReplicationInfo',  'ShortName',         $Env:DX_SHORT_NAME),
    @('Engine.GameReplicationInfo',  'AdminName',         $Env:DX_ADMIN_NAME),
    @('Engine.GameReplicationInfo',  'AdminEmail',        $Env:DX_ADMIN_EMAIL),
    @('Engine.GameReplicationInfo',  'MOTDLine1',         $Env:DX_MOTD),
    @('Engine.GameInfo',             'MaxPlayers',        $Env:DX_MAX_PLAYERS),
    @('Engine.GameInfo',             'GamePassword',      $Env:DX_GAME_PASSWORD),
    @('Engine.GameInfo',             'AdminPassword',     $Env:DX_ADMIN_PASSWORD),
    @('DeusEx.DeusExMPGame',         'VictoryCondition',  $victory),
    @('DeusEx.DeusExMPGame',         'ScoreToWin',        $Env:DX_SCORE_TO_WIN),
    @('DeusEx.DeusExMPGame',         'SkillsAvail',       $Env:DX_SKILLS_AVAIL),
    @('DeusEx.DeusExMPGame',         'SkillsPerKill',     $Env:DX_SKILLS_PER_KILL),
    @('DeusEx.DeusExMPGame',         'InitialAugs',       $Env:DX_INITIAL_AUGS),
    @('DeusEx.DeusExMPGame',         'AugsPerKill',       $Env:DX_AUGS_PER_KILL),
    @('DeusEx.DeusExMPGame',         'MPSkillStartLevel', $Env:DX_SKILL_START_LEVEL),
    @('DeusEx.DeusExMPGame',         'fFriendlyFireMult', $Env:DX_FRIENDLY_FIRE),
    @('DeusEx.DXMapList',            'CycleType',         $cycle)
)

foreach ($s in $settings) {
    if ($s[2]) { Set-IniValue $s[0] $s[1] $s[2] }
}

# Map rotation. Slots missing from the ini fall back to the built-in list, so all 32 are written.
if ($Env:DX_MAPS) {
    $available = @{}
    Get-ChildItem -Path (Join-Path $Env:SERVER_ROOT 'Maps') -Filter '*.dx' -File -ErrorAction SilentlyContinue |
        ForEach-Object { $available[$_.BaseName.ToLowerInvariant()] = $_.BaseName }

    $maps = @()
    foreach ($m in ($Env:DX_MAPS -split '[,;\s]+' | Where-Object { $_ })) {
        $name = $m -replace '\.dx$', ''
        if ($available.Count -and -not $available.ContainsKey($name.ToLowerInvariant())) {
            Write-Log -Level Warning "Map $name is not in Maps/; left out of the rotation"
            continue
        }
        $maps += $name
    }

    if ($maps.Count -gt 32) {
        Write-Log -Level Warning "DX_MAPS has $($maps.Count) maps; only the first 32 are used"
        $maps = $maps[0..31]
    }

    if ($maps.Count) {
        for ($i = 0; $i -lt 32; $i++) {
            Set-IniValue 'DeusEx.DXMapList' "Maps[$i]" $(if ($i -lt $maps.Count) { $maps[$i] } else { '' })
        }
        Write-Log "Map rotation: $($maps -join ', ')"
    }
}

# GameSpy is gone, so by default drop the master server uplinks (they only fail DNS/heartbeat)
if ($Env:DX_MASTER_SERVER_UPLINK -notin @('true', '1', 'yes')) {
    $removed = $lines.RemoveAll({ param($l) $l -like 'ServerActors=IpServer.UdpServerUplink*' })
    if ($removed) { Write-Log "Removed $removed master server uplink(s) from $Env:DX_INI" }
    Set-IniValue 'IpServer.UdpServerUplink' 'DoUplink' 'False'
}

[System.IO.File]::WriteAllText($ini, ($lines -join $newline))
chown "$($Env:UID):$($Env:GID)" $ini

Write-Log "Applied DX_* settings to $Env:DX_INI"
