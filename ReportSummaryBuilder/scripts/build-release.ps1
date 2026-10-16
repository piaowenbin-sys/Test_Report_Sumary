param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+([-.][0-9A-Za-z.-]+)?$')]
    [string]$Version
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root 'src\ReportSummaryBuilder.WinForms\ReportSummaryBuilder.WinForms.csproj'
$buildId = [guid]::NewGuid().ToString('N')
$buildRoot = Join-Path $root ("artifacts\build-$buildId")
$publish = Join-Path $buildRoot 'publish'
$velopack = Join-Path $buildRoot 'velopack'
$portableTarget = Join-Path $root 'release\portable\ReportSummaryBuilder.exe'
$installerTarget = Join-Path $root 'release\installer\ReportSummaryBuilder-Setup.exe'
$resolvedRoot = [IO.Path]::GetFullPath($root).TrimEnd('\') + '\'

function Assert-SafePath([string]$Path) {
    $resolvedPath = [IO.Path]::GetFullPath($Path)
    if (-not $resolvedPath.StartsWith($resolvedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe release path: $resolvedPath"
    }
}

function Publish-ReleaseFile([string]$Source, [string]$Target) {
    Assert-SafePath $Target
    $targetDirectory = Split-Path -Parent $Target
    New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
    $newPath = "$Target.new_$buildId"
    $backupPath = "$Target.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item -LiteralPath $Source -Destination $newPath
    try {
        if (Test-Path -LiteralPath $Target) { Move-Item -LiteralPath $Target -Destination $backupPath }
        Move-Item -LiteralPath $newPath -Destination $Target
    } catch {
        if ((-not (Test-Path -LiteralPath $Target)) -and (Test-Path -LiteralPath $backupPath)) {
            Move-Item -LiteralPath $backupPath -Destination $Target
        }
        throw
    } finally {
        if (Test-Path -LiteralPath $newPath) { Remove-Item -LiteralPath $newPath -Force }
    }
}

Assert-SafePath $buildRoot
New-Item -ItemType Directory -Path $publish, $velopack -Force | Out-Null

try {
    dotnet restore (Join-Path $root 'ReportSummaryBuilder.slnx') -r win-x64
    if ($LASTEXITCODE -ne 0) { throw 'dotnet restore failed.' }

    dotnet publish $project -c Release -r win-x64 --self-contained true --no-restore `
        -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=None `
        -p:DebugSymbols=false -p:Version=$Version -o $publish
    if ($LASTEXITCODE -ne 0) { throw 'dotnet publish failed.' }

    $publishedExe = Join-Path $publish 'ReportSummaryBuilder.WinForms.exe'
    if (-not (Test-Path -LiteralPath $publishedExe)) { throw "Published executable missing: $publishedExe" }

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

    Publish-ReleaseFile -Source $publishedExe -Target $portableTarget
    Publish-ReleaseFile -Source $setup.FullName -Target $installerTarget

    Write-Output "Portable=$portableTarget"
    Write-Output "Installer=$installerTarget"
} finally {
    if (Test-Path -LiteralPath $buildRoot) {
        Assert-SafePath $buildRoot
        Remove-Item -LiteralPath $buildRoot -Recurse -Force
    }
}
