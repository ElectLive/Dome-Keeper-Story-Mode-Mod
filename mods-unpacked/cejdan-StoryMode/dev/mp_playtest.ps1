# Runs an online multiplayer playtest on this machine (#223): a host instance
# and a client instance over ENet on 127.0.0.1, each driven by its own scenario.
# Usage (PowerShell):
#   & "<...>\mods-unpacked\cejdan-StoryMode\dev\mp_playtest.ps1" <host scenario> <client scenario> [-Timeout 420] [-Res 960x540]
# Output: ..\playtest_out\<scenario>\ for each, as playtest.ps1.
param(
    [Parameter(Mandatory = $true)][string]$HostScenario,
    [Parameter(Mandatory = $true)][string]$ClientScenario,
    [int]$Timeout = 420,
    [string]$Res = "960x540",
    [string]$Extra = ""
)
$project = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$root = Split-Path $project -Parent
$engine = Join-Path $root "custom_godot_for_windows\godot.windows.editor.x86_64.exe"
if (-not (Test-Path (Join-Path $project "override.cfg"))) { Write-Error "override.cfg missing: refusing to launch"; exit 3 }
$w = [int]($Res.Split("x")[0])
function Start-Instance($scenario, $pos) {
    $out = Join-Path $root "playtest_out\$scenario"
    if (Test-Path $out) { Remove-Item -Recurse -Force $out }
    New-Item -ItemType Directory -Force $out | Out-Null
    $log = Join-Path $out "godot.log"
    $argList = @("--path", "`"$project`"", "--windowed", "--resolution", $Res, "--position", $pos, "--log-file", "`"$log`"", "--", "--scenario=$scenario", "`"--out=$out`"")
    if ($Extra -ne "") { $argList += $Extra.Split(" ") }
    return Start-Process -FilePath $engine -ArgumentList $argList -PassThru
}
$hostProc = Start-Instance $HostScenario "20,40"
Start-Sleep -Seconds 6
$clientProc = Start-Instance $ClientScenario ("{0},40" -f (40 + $w))
$deadline = (Get-Date).AddSeconds($Timeout)
foreach ($p in @($clientProc, $hostProc)) {
    $left = [int][Math]::Max(1, ($deadline - (Get-Date)).TotalMilliseconds)
    if (-not $p.WaitForExit($left)) { Stop-Process -Id $p.Id -Force; $p | Add-Member -NotePropertyName Killed -NotePropertyValue $true }
}
$noise = "localization_|unknown win condition|leaked|Can't create shader cache|Condition `"!res.is_valid\(\)`"|translation"
foreach ($pair in @(@($HostScenario, $hostProc), @($ClientScenario, $clientProc))) {
    $sc = $pair[0]; $p = $pair[1]
    Write-Output "=== $sc"
    if ($p.Killed) { Write-Output "RESULT: TIMEOUT (killed)" } else { Write-Output "RESULT: exit code $($p.ExitCode)" }
    $log = Join-Path $root "playtest_out\$sc\godot.log"
    if (Test-Path $log) {
        $errs = Select-String -CaseSensitive -Path $log -Pattern "SCRIPT ERROR|Parse Error|Failed to load script|^ERROR|Invalid call|Invalid access|Nonexistent function|starting Sentry SDK" | Where-Object { $_.Line -notmatch $noise }
        Write-Output "ERRORS: $($errs.Count)"
        $errs | Select-Object -First 25 | ForEach-Object { Write-Output ("  L" + $_.LineNumber + ": " + $_.Line) }
        Select-String -Path $log -Pattern "^\[harness\] (PASS|FAIL)" | ForEach-Object { Write-Output $_.Line }
    }
}
