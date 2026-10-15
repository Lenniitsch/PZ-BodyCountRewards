<#
bcr-log.ps1 -- BCR log helper (Body Count Rewards).

Reads the newest Project Zomboid debug log (or console.txt) and prints only
BCR-relevant lines, compacted for quick review.

Usage:
  powershell -ExecutionPolicy Bypass -File bcr-log.ps1                 # digest newest log
  powershell -ExecutionPolicy Bypass -File bcr-log.ps1 -Full           # all BCR lines, raw
  powershell -ExecutionPolicy Bypass -File bcr-log.ps1 -Follow         # live watch
  powershell -ExecutionPolicy Bypass -File bcr-log.ps1 -Path <file>    # specific file
  powershell -ExecutionPolicy Bypass -File bcr-log.ps1 -Out <file>     # save (also prints)

Options:
  -MaxRuntime <n>   Max deduped runtime lines in the digest (default 60).
  -Full             Print every BCR line (no sections, no caps).
  -Follow           Live-watch the newest log, print new BCR lines as they appear.
  -Path <file>      Use a specific log file instead of the newest one.
  -Out <file>       Also write the output to this file (UTF-8, no BOM).
                    In -Follow mode, lines are appended.
#>
param(
    [string]$Path,
    [switch]$Full,
    [switch]$Follow,
    [int]$MaxRuntime = 60,
    [string]$Out
)

$ErrorActionPreference = 'Stop'

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-OutLine([string]$outPath, [string]$line) {
    [System.IO.File]::AppendAllText($outPath, $line + "`r`n", $utf8NoBom)
}

function Get-NewestLog {
    $logDir = Join-Path $env:USERPROFILE 'Zomboid\Logs'
    if (Test-Path $logDir) {
        $debugLogs = @(Get-ChildItem $logDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*DebugLog*' })
        if ($debugLogs.Count -gt 0) {
            return ($debugLogs | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
        }
    }
    $console = Join-Path $env:USERPROFILE 'Zomboid\console.txt'
    if (Test-Path $console) { return (Get-Item $console) }
    return $null
}

function Read-Text([string]$filePath) {
    $fs = [System.IO.File]::Open($filePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
        return $sr.ReadToEnd()
    } finally {
        $fs.Close()
    }
}

function Read-From([string]$filePath, [long]$offset) {
    $fs = [System.IO.File]::Open($filePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        if ($offset -gt $fs.Length) { $offset = 0 }
        $fs.Seek($offset, [System.IO.SeekOrigin]::Begin) | Out-Null
        $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
        $text = $sr.ReadToEnd()
        $end = $fs.Position
        return @{ Text = $text; Offset = $end }
    } finally {
        $fs.Close()
    }
}

# Strips the PZ log prefix ("... f:123> :<tab>") and the engine's own
# "[BCR] <tab>" event-context prefix, so only the message remains.
function Get-Message([string]$line) {
    $msg = $line
    $ix = $line.IndexOf('> :')
    if ($ix -ge 0) {
        $msg = $line.Substring($ix + 3)
        if ($msg.Length -gt 0 -and $msg[0] -eq [char]9) { $msg = $msg.Substring(1) }
    }
    $msg = $msg -replace '^\[BCR\]\s*\t', ''
    return $msg.TrimEnd()
}

# Language folders present in the repo's newest version tree (for comparison).
function Get-ExpectedLanguages {
    if (-not $PSScriptRoot) { return @() }
    $modRoot = Join-Path $PSScriptRoot '..\BodyCountRewards\Contents\mods\BodyCountRewards'
    if (-not (Test-Path $modRoot)) { return @() }
    $dirs = @(Get-ChildItem $modRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d+\.\d+$' } |
        Sort-Object { [version]$_.Name })
    if ($dirs.Count -eq 0) { return @() }
    $tr = Join-Path $dirs[-1].FullName 'media\lua\shared\Translate'
    if (-not (Test-Path $tr)) { return @() }
    return @(Get-ChildItem $tr -Directory | Select-Object -ExpandProperty Name)
}

# ---------------------------------------------------------------
# Follow mode: live watch
# ---------------------------------------------------------------
if ($Follow) {
    Write-Output "Watching for BCR lines. Ctrl+C to stop."
    if ($Out) { Write-OutLine $Out ("=== BCR follow started {0} ===" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) }
    $current = $null
    $offset = 0
    $remainder = ''
    while ($true) {
        $newest = $null
        if ($Path) {
            $newest = Get-Item $Path -ErrorAction SilentlyContinue
        } else {
            $newest = Get-NewestLog
        }
        if (-not $newest) { Start-Sleep -Milliseconds 1000; continue }

        if ($current -eq $null -or $newest.FullName -ne $current.FullName) {
            $current = $newest
            $offset = $current.Length
            $remainder = ''
            $banner = ("--- watching: {0} ({1} KB already written) ---" -f $current.Name, [int]($current.Length / 1KB))
            Write-Output $banner
            if ($Out) { Write-OutLine $Out $banner }
            Start-Sleep -Milliseconds 500
            continue
        }

        if ($current.Length -lt $offset) { $offset = 0 }
        if ($current.Length -gt $offset) {
            $res = Read-From $current.FullName $offset
            $chunk = $remainder + $res.Text
            $remainder = ''
            $offset = $res.Offset
            $lines = $chunk -split "`r?`n"
            if (-not $chunk.EndsWith("`n")) {
                $remainder = $lines[-1]
                if ($lines.Count -gt 1) { $lines = $lines[0..($lines.Count - 2)] } else { $lines = @() }
                $offset = $offset - [System.Text.Encoding]::UTF8.GetByteCount($remainder)
            }
            foreach ($l in $lines) {
                if ($l -match 'BCR') {
                    $msg = Get-Message $l
                    if ($msg.Length -gt 0) {
                        $stamp = Get-Date -Format 'HH:mm:ss'
                        if ($l.Length -ge 21 -and $l[0] -eq '[') { $stamp = $l.Substring(11, 8) }
                        $lineOut = ("[{0}] {1}" -f $stamp, $msg)
                        Write-Output $lineOut
                        if ($Out) { Write-OutLine $Out $lineOut }
                    }
                }
            }
        }
        Start-Sleep -Milliseconds 1000
    }
}

# ---------------------------------------------------------------
# One-shot mode
# ---------------------------------------------------------------
$file = $null
if ($Path) {
    $file = Get-Item $Path -ErrorAction SilentlyContinue
    if (-not $file) { Write-Output "File not found: $Path"; exit 1 }
} else {
    $file = Get-NewestLog
}
if (-not $file) { Write-Output "No log found in $env:USERPROFILE\Zomboid\Logs"; exit 1 }

$text = Read-Text $file.FullName
$allLines = $text -split "`r?`n"

$records = New-Object System.Collections.ArrayList
foreach ($l in $allLines) {
    if ($l -match 'BCR') {
        [void]$records.Add([pscustomobject]@{ Msg = (Get-Message $l) })
    }
}

if ($Full) {
    Write-Output ("=== ALL BCR lines: {0} ===" -f $file.Name)
    foreach ($r in $records) { Write-Output $r.Msg }
    exit 0
}

$tests = @($records | Where-Object { $_.Msg -match '^\[BCR\] \[Tests\]' })
$dump = @($records | Where-Object { $_.Msg -match '^\[BCR\] \[Dump\]' })
$runtime = @($records | Where-Object { $_.Msg -match '^\[BCR\] \[(Client|Server|Core|Sandbox|Addon)\]' })
$overrides = @($records | Where-Object { $_.Msg -match ' overrides ' })
$other = @($records | Where-Object { $_.Msg -notmatch '^\[BCR\]' -and $_.Msg -notmatch ' overrides ' })

$digest = {
Write-Output "=== BCR log digest ==="
Write-Output ("File : {0}" -f $file.FullName)
Write-Output ("When : {0}  ({1:N0} KB)" -f $file.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'), ($file.Length / 1KB))
Write-Output ""

# --- Runtime (consecutive duplicates collapsed) ---
$collapsed = New-Object System.Collections.ArrayList
$prevMsg = $null
$prevN = 0
foreach ($r in $runtime) {
    if ($r.Msg -eq $prevMsg) { $prevN++; continue }
    if ($prevMsg -ne $null) {
        if ($prevN -gt 1) { [void]$collapsed.Add(("{0}  (x{1})" -f $prevMsg, $prevN)) } else { [void]$collapsed.Add($prevMsg) }
    }
    $prevMsg = $r.Msg
    $prevN = 1
}
if ($prevMsg -ne $null) {
    if ($prevN -gt 1) { [void]$collapsed.Add(("{0}  (x{1})" -f $prevMsg, $prevN)) } else { [void]$collapsed.Add($prevMsg) }
}
Write-Output ("--- Runtime ({0} line(s), {1} after dedup) ---" -f $runtime.Count, $collapsed.Count)
$i = 0
foreach ($c in $collapsed) {
    if ($i -ge $MaxRuntime) { Write-Output ("... {0} more (use -Full)" -f ($collapsed.Count - $MaxRuntime)); break }
    Write-Output $c
    $i++
}
Write-Output ""

# --- Tests ---
Write-Output ("--- Tests ({0} line(s)) ---" -f $tests.Count)
if ($tests.Count -eq 0) {
    Write-Output "no test run in this log"
} else {
    $total = $tests | Where-Object { $_.Msg -match 'Total: ' } | Select-Object -Last 1
    if ($total) { Write-Output ($total.Msg -replace '^\[BCR\] \[Tests\] ', '') } else { Write-Output "no totals line found" }
    $fails = @($tests | Where-Object { $_.Msg -cmatch '\[Tests\] FAIL:|SUITE CRASH' })
    if ($fails.Count -eq 0) {
        Write-Output "failures: none"
    } else {
        Write-Output ("FAILURES ({0}):" -f $fails.Count)
        foreach ($f in $fails) { Write-Output ("  " + ($f.Msg -replace '^\[BCR\] \[Tests\] ', '')) }
    }
    $suites = @($tests | Where-Object { $_.Msg -match '=== SUITE' }).Count
    Write-Output ("suites: {0}" -f $suites)
}
Write-Output ""

# --- Dump ---
Write-Output ("--- Dump ({0} line(s)) ---" -f $dump.Count)
if ($dump.Count -eq 0) {
    Write-Output "no dump in this log"
} else {
    foreach ($d in ($dump | Where-Object { $_.Msg -match '===|missing from engine|Player traits' })) {
        Write-Output ($d.Msg -replace '^\[BCR\] \[Dump\] ', '')
    }
    Write-Output ("(per-trait rows hidden; {0} dump lines total - use -Full to see them)" -f $dump.Count)
}
Write-Output ""

# --- Other BCR mentions (mod loader, sandbox, errors) ---
Write-Output ("--- Other BCR mentions ({0}) ---" -f $other.Count)
$i = 0
foreach ($o in $other) {
    if ($i -ge 15) { Write-Output ("... {0} more (use -Full)" -f ($other.Count - 15)); break }
    Write-Output $o.Msg
    $i++
}
Write-Output ""

# --- Mod file overrides (proof that translations/files loaded) ---
Write-Output ("--- Mod overrides ({0} line(s)) ---" -f $overrides.Count)
if ($overrides.Count -eq 0) {
    Write-Output "none"
} else {
    $langCounts = @{}
    $otherOv = New-Object System.Collections.ArrayList
    $seenOv = @{}
    foreach ($o in $overrides) {
        $m = [regex]::Match($o.Msg, 'mod "([^"]+)" overrides (.+)$')
        if (-not $m.Success) { [void]$otherOv.Add($o.Msg); continue }
        $modName = $m.Groups[1].Value
        $ovPath = $m.Groups[2].Value.Trim()
        $ovKey = "$modName|$ovPath"
        if ($seenOv.ContainsKey($ovKey)) { continue }
        $seenOv[$ovKey] = $true
        $lm = [regex]::Match($ovPath, 'shared/translate/([^/]+)/')
        if ($lm.Success) {
            $key = $lm.Groups[1].Value.ToLower()
            if (-not $langCounts.ContainsKey($key)) { $langCounts[$key] = 0 }
            $langCounts[$key]++
        } else {
            [void]$otherOv.Add(("{0}: {1}" -f $modName, $ovPath))
        }
    }
    if ($langCounts.Count -gt 0) {
        $totalFiles = ($langCounts.Values | Measure-Object -Sum).Sum
        Write-Output ("translate files: {0} in {1} language(s)" -f $totalFiles, $langCounts.Count)
        $parts = @()
        foreach ($k in ($langCounts.Keys | Sort-Object)) { $parts += ("{0}({1})" -f $k, $langCounts[$k]) }
        Write-Output ("  " + ($parts -join ' '))
        $expected = @(Get-ExpectedLanguages)
        if ($expected.Count -gt 0) {
            $loadedLower = @{}
            foreach ($k in $langCounts.Keys) { $loadedLower[$k.ToLower()] = $true }
            $expectedLower = @($expected | ForEach-Object { $_.ToLower() })
            $missingL = @($expected | Where-Object { -not $loadedLower.ContainsKey($_.ToLower()) })
            $extraL = @($langCounts.Keys | Where-Object { $expectedLower -notcontains $_.ToLower() })
            Write-Output ("  expected in repo: {0} ({1})" -f $expected.Count, (($expected | Sort-Object) -join ', '))
            if ($missingL.Count -gt 0) { Write-Output ("  MISSING: " + ($missingL -join ', ')) }
            if ($extraL.Count -gt 0) { Write-Output ("  NOT IN REPO: " + ($extraL -join ', ')) }
        }
    }
    if ($otherOv.Count -gt 0) {
        Write-Output ("other overrides ({0}):" -f $otherOv.Count)
        foreach ($x in ($otherOv | Select-Object -First 10)) { Write-Output ("  " + $x) }
        if ($otherOv.Count -gt 10) { Write-Output ("  ... {0} more" -f ($otherOv.Count - 10)) }
    }
}
}

if ($Out) {
    $outFull = [System.IO.Path]::GetFullPath($Out)
    $outLines = @(& $digest)
    [System.IO.File]::WriteAllLines($outFull, $outLines, $utf8NoBom)
    foreach ($ol in $outLines) { Write-Output $ol }
    Write-Output ("--- saved: {0} ---" -f $outFull)
} else {
    & $digest
}
