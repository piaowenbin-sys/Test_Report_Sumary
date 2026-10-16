param([string]$InputDirectory = 'C:\Users\USER.K1109684\Downloads\TestReport')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$setup = Join-Path $root 'release\installer\ReportSummaryBuilder-Setup.exe'
$installRoot = Join-Path $env:TEMP ('ReportSummaryBuilder-InstallSmoke-' + [guid]::NewGuid().ToString('N'))
$output = Join-Path $env:TEMP ('ReportSummaryBuilder-InstalledRun-' + [guid]::NewGuid().ToString('N'))

if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) { throw "Setup EXE missing: $setup" }

try {
    $install = Start-Process -FilePath $setup -ArgumentList @('--silent', '--installto', $installRoot) -WindowStyle Hidden -Wait -PassThru
    if ($install.ExitCode -ne 0) { throw "Silent install failed with exit code $($install.ExitCode)." }

    $app = Get-ChildItem -LiteralPath $installRoot -Filter 'ReportSummaryBuilder.WinForms.exe' -File -Recurse | Select-Object -First 1
    $updater = Get-ChildItem -LiteralPath $installRoot -Filter 'Update.exe' -File -Recurse | Select-Object -First 1
    if ($null -eq $app) { throw 'Installed application executable was not found.' }
    if ($null -eq $updater) { throw 'Installed uninstaller/update executable was not found.' }

    New-Item -ItemType Directory -Path $output -Force | Out-Null
    $verify = Start-Process -FilePath $app.FullName -ArgumentList @('--verify-package', $InputDirectory, $output) -WindowStyle Hidden -Wait -PassThru
    if ($verify.ExitCode -ne 0) { throw "Installed application verification failed with exit code $($verify.ExitCode)." }
    if (-not ((Get-Content -LiteralPath (Join-Path $output 'verification.txt') -Raw).Contains('Status=PASS'))) {
        throw 'Installed application did not report PASS.'
    }

    $uninstall = Start-Process -FilePath $updater.FullName -ArgumentList @('uninstall', '--silent') -WindowStyle Hidden -Wait -PassThru
    if ($uninstall.ExitCode -ne 0) { throw "Silent uninstall failed with exit code $($uninstall.ExitCode)." }
    Start-Sleep -Milliseconds 800
    if (Test-Path -LiteralPath (Join-Path $installRoot 'current\ReportSummaryBuilder.WinForms.exe')) {
        throw 'Installed application remained after uninstall.'
    }

    Write-Output "PASS|InstallRoot=$installRoot|Output=$output"
} finally {
    if (Test-Path -LiteralPath $installRoot) {
        $updater = Get-ChildItem -LiteralPath $installRoot -Filter 'Update.exe' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $updater) {
            Start-Process -FilePath $updater.FullName -ArgumentList @('uninstall', '--silent') -WindowStyle Hidden -Wait | Out-Null
        }
    }
}
