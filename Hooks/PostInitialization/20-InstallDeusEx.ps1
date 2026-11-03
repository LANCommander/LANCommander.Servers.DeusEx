#Requires -Modules Logging
#Requires -Modules Hooks
#Requires -Modules OverlayFS

# Deus Ex is retail software with no public download. Use an existing install in /config/Server,
# or set DX_ARCHIVE_URL to a zip of the game folder (System/ at the zip root, or in a subfolder),
# e.g. a LANCommander archive.

Invoke-Hook "PreInstallDeusEx"

$exe = Join-Path $Env:SERVER_DIR 'System/DeusEx.exe'

if (Test-Path -Path $exe) {
    Write-Log "Deus Ex found in $Env:SERVER_DIR"
} elseif ($Env:DX_ARCHIVE_URL) {
    Write-Log "Downloading Deus Ex from $Env:DX_ARCHIVE_URL"

    $zip     = '/tmp/deusex.zip'
    $extract = '/tmp/deusex'

    curl -fL --retry 3 --output $zip "$Env:DX_ARCHIVE_URL"
    if ($LASTEXITCODE -ne 0) { throw "Download failed: $Env:DX_ARCHIVE_URL" }

    Remove-Item -Recurse -Force -Path $extract -ErrorAction SilentlyContinue
    unzip -q -o $zip -d $extract
    if ($LASTEXITCODE -ne 0) { throw "Could not extract $zip" }

    # Accept the game at the zip root or in a subfolder
    $root = Get-ChildItem -Path $extract -Filter 'DeusEx.exe' -Recurse -File -Depth 3 |
        Where-Object { $_.Directory.Name -eq 'System' } |
        Select-Object -First 1 -ExpandProperty Directory
    if (-not $root) { throw "System/DeusEx.exe not found in $Env:DX_ARCHIVE_URL" }

    New-Item -ItemType Directory -Path $Env:SERVER_DIR -Force | Out-Null
    Move-Item -Force -Path (Join-Path $root.Parent.FullName '*') -Destination $Env:SERVER_DIR
    chown -R "$($Env:UID):$($Env:GID)" $Env:SERVER_DIR

    Remove-Item -Recurse -Force -Path $zip, $extract

    # The overlay was mounted before Server/ was populated, and overlayfs doesn't reliably show
    # lower-dir changes made while mounted.
    mountpoint -q $Env:SERVER_ROOT
    if ($LASTEXITCODE -eq 0) {
        umount $Env:SERVER_ROOT
        Remove-Item -Path "$Env:WORK_DIR/*" -Recurse -Force -ErrorAction SilentlyContinue
        Mount-Overlay -MountPoint $Env:SERVER_ROOT -LowerDir $Env:SERVER_DIR -UpperDir $Env:OVERLAY_DIR -WorkDir $Env:WORK_DIR -RequireEmptyWorkDir -OverlayOption "xino=on"
        Write-Log "OverlayFS remounted"
    }

    Write-Log "Deus Ex installed"
} else {
    Write-Log -Level Error "System/DeusEx.exe not found in $Env:SERVER_DIR. Copy a Deus Ex install there or set DX_ARCHIVE_URL."
}

Invoke-Hook "PostInstallDeusEx"

Set-Location $Env:SERVER_ROOT
