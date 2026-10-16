param([string]$Version = '1.0.0')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root 'src\ReportSummaryBuilder.WinForms\ReportSummaryBuilder.WinForms.csproj'
$publish = Join-Path $root 'artifacts\publish'
$velopack = Join-Path $root 'artifacts\velopack'
$portable = Join-Path $root 'release\portable'
$installer = Join-Path $root 'release\installer'

foreach ($path in @($publish, $velopack, $portable, $installer)) {
    $resolvedRoot = [IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
    $resolvedPath = [IO.Path]::GetFullPath($path)
    if (-not $resolvedPath.StartsWith($resolvedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe release path: $resolvedPath"
    }
    if (Test-Path -LiteralPath $resolvedPath) { Remove-Item -LiteralPath $resolvedPath -Recurse -Force }
    New-Item -ItemType Directory -Path $resolvedPath | Out-Null
}

dotnet restore (Join-Path $root 'ReportSummaryBuilder.slnx') -r win-x64
if ($LASTEXITCODE -ne 0) { throw 'dotnet restore failed.' }

dotnet publish $project -c Release -r win-x64 --self-contained true --no-restore `
    -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=None `
    -p:DebugSymbols=false -o $publish
if ($LASTEXITCODE -ne 0) { throw 'dotnet publish failed.' }

$publishedExe = Join-Path $publish 'ReportSummaryBuilder.WinForms.exe'
if (-not (Test-Path -LiteralPath $publishedExe)) { throw "Published executable missing: $publishedExe" }
Copy-Item -LiteralPath $publishedExe -Destination (Join-Path $portable 'ReportSummaryBuilder.exe')

Push-Location $root
try {
    dotnet tool restore
    if ($LASTEXITCODE -ne 0) { throw 'dotnet tool restore failed.' }
    dotnet vpk pack --packId ReportSummaryBuilder --packVersion $Version --packDir $publish `
        --mainExe ReportSummaryBuilder.WinForms.exe --packTitle 'Test Report Summary Builder' `
        --packAuthors 'Internal Automotive Test Team' --runtime win-x64 `
        --shortcuts Desktop,StartMenuRoot --outputDir $velopack --delta None --yes
    if ($LASTEXITCODE -ne 0) { throw 'Velopack packaging failed.' }
} finally {
    Pop-Location
}

$setup = Get-ChildItem -LiteralPath $velopack -Filter '*Setup.exe' -File | Select-Object -First 1
if ($null -eq $setup) { throw 'Velopack Setup.exe was not generated.' }
Copy-Item -LiteralPath $setup.FullName -Destination (Join-Path $installer 'ReportSummaryBuilder-Setup.exe')

Write-Output "Portable=$(Join-Path $portable 'ReportSummaryBuilder.exe')"
Write-Output "Installer=$(Join-Path $installer 'ReportSummaryBuilder-Setup.exe')"
