param(
    [Parameter(Mandatory = $true)][string]$InputDirectory,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$PublishPath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'src\CombinedTestReport.psm1') -Force

$sourceNames = @(
    '2026-10-08_08-18-49_RS4_Test_Report.html',
    '2026-10-08_10-16-56_RS4_Test_Report.html',
    '2026-10-08_10-42-10_RS4_Test_Report.html',
    '2026-10-08_11-01-20_RS4_Test_Report.html'
)

$reports = foreach ($name in $sourceNames) {
    $path = Join-Path $InputDirectory $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required source report missing: $name" }
    Get-ReportModel -Path $path
}
$reports = @(Assert-ReportSet -Reports @($reports))

$validation = New-CombinedReport -Reports $reports -OutputPath $OutputPath
Write-Output ('Positions: ' + (($validation.Positions | ForEach-Object Position) -join '/'))
Write-Output ('Output: ' + $validation.Path)
Write-Output ('Output SHA256: ' + $validation.OutputHash)
Write-Output ('Validation: PASS; unresolved links=' + $validation.UnresolvedLinkCount)

foreach ($report in $reports) {
    $current = (Get-FileHash -LiteralPath $report.Path -Algorithm SHA256).Hash
    if ($current -ne $report.SourceHash) { throw "Source hash changed after build: $($report.Position)" }
    Write-Output ("Source $($report.Position) SHA256 unchanged: $current")
}

if (-not [string]::IsNullOrWhiteSpace($PublishPath)) {
    $publication = Publish-VerifiedReport -SourcePath $validation.Path -PublishPath $PublishPath
    Write-Output ('Published: ' + $publication.PublishPath)
    if ($null -ne $publication.BackupPath) { Write-Output ('Backup: ' + $publication.BackupPath) }
}
