param(
    [string]$InputDirectory = 'C:\Users\USER.K1109684\Downloads\TestReport',
    [string]$OutputDirectory = (Join-Path $env:TEMP ('ReportSummaryBuilder-Smoke-' + [guid]::NewGuid().ToString('N')))
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$portable = Join-Path $root 'release\portable\ReportSummaryBuilder.exe'
$installer = Join-Path $root 'release\installer\ReportSummaryBuilder-Setup.exe'

if (-not (Test-Path -LiteralPath $portable -PathType Leaf)) { throw "Portable EXE missing: $portable" }
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) { throw "Setup EXE missing: $installer" }
if ((Get-Item -LiteralPath $portable).Length -lt 10MB) { throw 'Portable EXE is too small to be a self-contained Windows build.' }

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$process = Start-Process -FilePath $portable -ArgumentList @('--verify-package', $InputDirectory, $OutputDirectory) -WindowStyle Hidden -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "Verification CLI failed with exit code $($process.ExitCode)" }

$verification = Join-Path $OutputDirectory 'verification.txt'
if (-not (Test-Path -LiteralPath $verification)) { throw 'verification.txt was not generated.' }
if (-not ((Get-Content -LiteralPath $verification -Raw).Contains('Status=PASS'))) { throw 'Verification status is not PASS.' }

$summary = @(Get-ChildItem -LiteralPath $OutputDirectory -Filter '*_Combined_Test_Report.html' -File)
$zip = @(Get-ChildItem -LiteralPath $OutputDirectory -Filter '*_Test_Report.zip' -File)
$details = @(Get-ChildItem -LiteralPath $OutputDirectory -Filter '*.html' -File -Recurse | Where-Object { $_.FullName -notin $summary.FullName })
if ($summary.Count -ne 1) { throw "Expected one summary HTML, found $($summary.Count)." }
if ($zip.Count -ne 1) { throw "Expected one ZIP, found $($zip.Count)." }
if ($details.Count -lt 1) { throw 'No detail HTML files were generated.' }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($zip[0].FullName)
try {
    if ($archive.Entries.Count -ne (1 + $details.Count)) {
        throw "ZIP entry count mismatch: expected $(1 + $details.Count), found $($archive.Entries.Count)."
    }
} finally {
    $archive.Dispose()
}

Write-Output "PASS|Portable=$portable|Installer=$installer|Output=$OutputDirectory|Details=$($details.Count)"
