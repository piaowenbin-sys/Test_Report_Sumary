param(
    [ValidateSet('Parse', 'Build', 'Publish', 'All')]
    [string]$Group = 'All'
)

$ErrorActionPreference = 'Stop'
$script:Passed = 0
$script:Failed = 0

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) { throw "$Message (expected='$Expected', actual='$Actual')" }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Pattern, [string]$Message)
    try { & $Action } catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw "$Message (unexpected='$($_.Exception.Message)')" }
        return
    }
    throw "$Message (no exception)"
}

function Invoke-Test {
    param([string]$Name, [scriptblock]$Body)
    try {
        & $Body
        $script:Passed++
        Write-Output "PASS: $Name"
    } catch {
        $script:Failed++
        Write-Output "FAIL: $Name - $($_.Exception.Message)"
        Write-Output $_.ScriptStackTrace
    }
}

function New-MinimalReportHtml {
    param(
        [string]$Position = 'RR',
        [string]$Project = 'RS4PE',
        [string]$DriveType = 'LHD',
        [string]$EolVariant = 'All_DTC_List (defined in test design)',
        [string]$Rows = '',
        [int]$Executed = 2,
        [int]$Passed = 1,
        [int]$Failed = 1,
        [int]$Inconclusive = 0,
        [int]$ErrorCount = 0,
        [int]$OutsideInconclusive = 0,
        [int]$OutsideFail = 0,
        [int]$OutsideError = 0,
        [switch]$Malformed
    )
    $closing = if ($Malformed) { '' } else { '</body></html>' }
    return @"
<!DOCTYPE html><html><head><meta charset="utf-8"><style>.x{color:#000}</style></head><body>
<a name="TOP"></a>
<div class="Heading2">Test Overview</div>
<table class="DefaultTable"><tr><td>Test begin: </td><td>2026-10-08 11:02:02</td></tr><tr><td>Test end: </td><td>2026-10-08 11:09:19</td></tr></table>
<div class="Heading4">Statistics</div><table class="OverviewTable">
<tr><td>Executed test cases </td><td>$Executed</td></tr><tr><td>Test cases passed </td><td>$Passed</td></tr>
<tr><td>Test cases inconclusive</td><td>$Inconclusive</td></tr><tr><td>Test cases failed </td><td>$Failed</td></tr>
<tr><td>Test cases with error in test system </td><td>$ErrorCount</td></tr>
<tr><td>Number of failures outside of test cases</td><td></td></tr>
<tr><td style="text-indent: 20px;">Inconclusive</td><td>$OutsideInconclusive</td></tr>
<tr><td style="text-indent: 20px;">Fail</td><td>$OutsideFail</td></tr>
<tr><td style="text-indent: 20px;">Error in test system</td><td>$OutsideError</td></tr></table>
<div class="Heading4">Test Results</div><table class="OverviewTable">$Rows</table>
<a name="TestModuleInfo"></a>
<div class="Heading4">Variant Properties</div><table>
<tr><td>Var_Drive_Type: </td><td>$DriveType</td></tr><tr><td>Var_SBCM_Position: </td><td>$Position</td></tr>
<tr><td>Var_EOL_Variant_Type: </td><td>$EolVariant</td></tr><tr><td>Var_Project: </td><td>$Project</td></tr></table>
<a name="parent-one"></a><a name="child-one"></a><a name="parent-ten"></a><a name="child-ten"></a>
$closing
"@
}

function New-MinimalReportSet {
    param([string]$Directory, [string]$OutsideFailPosition = '')
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $rows = '<tr><td>1</td><td><a href="#parent-one">Minimal_Test</a></td><td class="PositiveResultCell">pass</td></tr>'
    $names = @{
        DRV = '2026-10-08_08-18-49_RS4_Test_Report.html'
        AST = '2026-10-08_10-16-56_RS4_Test_Report.html'
        RL = '2026-10-08_10-42-10_RS4_Test_Report.html'
        RR = '2026-10-08_11-01-20_RS4_Test_Report.html'
    }
    $reports = foreach ($position in @('DRV', 'AST', 'RL', 'RR')) {
        $outsideFail = if ($position -eq $OutsideFailPosition) { 1 } else { 0 }
        $path = Join-Path $Directory $names[$position]
        $html = New-MinimalReportHtml -Position $position -Rows $rows -Executed 2 -Passed 2 -Failed 0 -OutsideFail $outsideFail
        [IO.File]::WriteAllText($path, $html, [Text.UTF8Encoding]::new($false))
        Get-ReportModel -Path $path
    }
    return @(Assert-ReportSet -Reports @($reports))
}

function New-ReportStub {
    param([string]$Position, [string]$Project = 'RS4PE', [string]$DriveType = 'LHD', [string]$EolVariant = 'All_DTC_List (defined in test design)')
    [pscustomobject]@{ Position = $Position; Project = $Project; DriveType = $DriveType; EolVariant = $EolVariant }
}

function Get-RealReportSet {
    $root = 'C:\Users\USER.K1109684\Downloads\TestReport'
    $names = @(
        '2026-10-08_08-18-49_RS4_Test_Report.html',
        '2026-10-08_10-16-56_RS4_Test_Report.html',
        '2026-10-08_10-42-10_RS4_Test_Report.html',
        '2026-10-08_11-01-20_RS4_Test_Report.html'
    )
    $reports = @($names | ForEach-Object { Get-ReportModel -Path (Join-Path $root $_) })
    return @(Assert-ReportSet -Reports $reports)
}

function Get-BuildContext {
    if ($null -ne $script:BuildContext) { return $script:BuildContext }
    $root = Join-Path ([IO.Path]::GetTempPath()) ('combined-report-build-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $path = Join-Path $root 'combined.html'
    $reports = @(Get-RealReportSet)
    $reports[0].BodyHtml += '<a href="https://example.com/external-doc">External reference</a>'
    $before = @{}
    foreach ($report in $reports) { $before[$report.Position] = (Get-FileHash -LiteralPath $report.Path -Algorithm SHA256).Hash }
    $result = New-CombinedReport -Reports $reports -OutputPath $path
    $html = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    $script:BuildContext = [pscustomobject]@{ Root = $root; Path = $path; Reports = $reports; Before = $before; Result = $result; Html = $html }
    return $script:BuildContext
}

function Get-PositionSectionHtml {
    param([string]$Html, [string]$Position)
    $match = [regex]::Match($Html, '<section\b[^>]*id="position-' + [regex]::Escape($Position) + '"[^>]*>(?<section>.*?)</section>', [Text.RegularExpressions.RegexOptions]'IgnoreCase,Singleline')
    if (-not $match.Success) { throw "Position section missing: $Position" }
    return $match.Value
}

function Get-CombinedSummaryHtml {
    param([string]$Html)
    $match = [regex]::Match($Html, '<div class="combined-functional-summary".*?<!-- COMBINED_FUNCTIONAL_SUMMARY_END -->', [Text.RegularExpressions.RegexOptions]'IgnoreCase,Singleline')
    if (-not $match.Success) { throw 'Combined functional summary missing.' }
    return $match.Value
}

$modulePath = Join-Path $PSScriptRoot '..\src\CombinedTestReport.psm1'
Import-Module $modulePath -Force

if ($Group -in @('Parse', 'All')) {
    Invoke-Test 'parses_real_report_metadata_and_statistics' {
        $path = 'C:\Users\USER.K1109684\Downloads\TestReport\2026-10-08_11-01-20_RS4_Test_Report.html'
        $report = Get-ReportModel -Path $path
        Assert-Equal $report.Project 'RS4PE' '프로젝트 파싱 오류'
        Assert-Equal $report.DriveType 'LHD' 'Drive Type 파싱 오류'
        Assert-Equal $report.Position 'RR' 'Position 파싱 오류'
        Assert-Equal $report.EolVariant 'All_DTC_List (defined in test design)' 'EOL 파싱 오류'
        Assert-Equal $report.Statistics.Executed 102 'Executed 통계 오류'
        Assert-Equal $report.Statistics.Pass 102 'Pass 통계 오류'
        Assert-Equal $report.Statistics.Inconclusive 0 'Inconclusive 통계 오류'
        Assert-Equal $report.Statistics.Fail 0 'Fail 통계 오류'
        Assert-Equal $report.Statistics.Error 0 'Error 통계 오류'
        Assert-Equal $report.Statistics.OutsideInconclusive 0 'Outside Inconclusive 통계 오류'
        Assert-Equal $report.Statistics.OutsideFail 0 'Outside Fail 통계 오류'
        Assert-Equal $report.Statistics.OutsideError 0 'Outside Error 통계 오류'
        Assert-True ($report.TestItems.Count -gt 0) 'Test Results 항목이 없습니다.'
        Assert-True (-not [string]::IsNullOrWhiteSpace($report.SourceHash)) '원본 해시가 없습니다.'
    }

    Invoke-Test 'rejects_missing_position' {
        $reports = @((New-ReportStub 'DRV'), (New-ReportStub 'AST'), (New-ReportStub 'RL'))
        Assert-Throws { Assert-ReportSet -Reports $reports } 'exactly four' '누락 Position을 허용했습니다.'
    }

    Invoke-Test 'rejects_duplicate_position' {
        $reports = @((New-ReportStub 'DRV'), (New-ReportStub 'AST'), (New-ReportStub 'RL'), (New-ReportStub 'RL'))
        Assert-Throws { Assert-ReportSet -Reports $reports } 'duplicate|중복|DRV.*AST.*RL.*RR' '중복 Position을 허용했습니다.'
    }

    Invoke-Test 'rejects_common_metadata_mismatch' {
        $reports = @((New-ReportStub 'DRV'), (New-ReportStub 'AST'), (New-ReportStub 'RL'), (New-ReportStub 'RR' -Project 'OTHER'))
        Assert-Throws { Assert-ReportSet -Reports $reports } 'metadata|메타데이터|Project' '프로젝트 불일치를 허용했습니다.'
    }

    Invoke-Test 'keeps_decimal_number_hierarchies_distinct' {
        $temp = Join-Path ([IO.Path]::GetTempPath()) ('combined-report-hierarchy-' + [guid]::NewGuid().ToString('N') + '.html')
        $rows = @'
<tr><td>1.1</td><td><a href="#parent-one">ParentOne</a></td><td class="NumberCell">1</td></tr>
<tr><td>1.1.1</td><td><a href="#child-one">ChildOne</a></td><td class="NegativeResultCell">fail</td></tr>
<tr><td>1.10</td><td><a href="#parent-ten">ParentTen</a></td><td class="NumberCell">1</td></tr>
<tr><td>1.10.1</td><td><a href="#child-ten">ChildTen</a></td><td class="PositiveResultCell">pass</td></tr>
'@
        try {
            [IO.File]::WriteAllText($temp, (New-MinimalReportHtml -Rows $rows), [Text.UTF8Encoding]::new($false))
            $report = Get-ReportModel -Path $temp
            $parentOne = $report.TestItems | Where-Object Number -eq '1.1' | Select-Object -First 1
            $parentTen = $report.TestItems | Where-Object Number -eq '1.10' | Select-Object -First 1
            Assert-Equal $parentOne.EffectiveVerdict 'Fail' '1.1 부모 판정 오류'
            Assert-Equal $parentTen.EffectiveVerdict 'Pass' '1.10 부모 판정 오류'
        } finally { Remove-Item -LiteralPath $temp -ErrorAction SilentlyContinue }
    }

    Invoke-Test 'rejects_malformed_document' {
        $temp = Join-Path ([IO.Path]::GetTempPath()) ('combined-report-malformed-' + [guid]::NewGuid().ToString('N') + '.html')
        try {
            [IO.File]::WriteAllText($temp, (New-MinimalReportHtml -Malformed), [Text.UTF8Encoding]::new($false))
        Assert-Throws { Get-ReportModel -Path $temp } 'HTML' '손상 HTML을 허용했습니다.'
        } finally { Remove-Item -LiteralPath $temp -ErrorAction SilentlyContinue }
    }
}

if ($Group -in @('Build', 'All')) {
    Invoke-Test 'builds_four_position_overview_in_required_order' {
        $context = Get-BuildContext
        Assert-True ($context.Html.Contains('RS4PE / LHD / DRV')) 'Combined title missing.'
        $previous = -1
        foreach ($position in @('DRV', 'AST', 'RL', 'RR')) {
            $index = $context.Html.IndexOf('id="position-' + $position + '"', [StringComparison]::Ordinal)
            Assert-True ($index -gt $previous) "Position order incorrect: $position"
            $previous = $index
        }
    }

    Invoke-Test 'integrates_all_position_summaries_at_top' {
        $context = Get-BuildContext
        $summary = Get-CombinedSummaryHtml -Html $context.Html
        $categories = @('C104', 'ForceControl', 'ECU_ID', 'PWM', 'Switch', 'Sensor', 'Vbat', 'HS', 'Motor')
        foreach ($position in @('DRV', 'AST', 'RL', 'RR')) {
            $positionBlock = [regex]::Match($summary, '<tbody\b[^>]*data-summary-position="' + $position + '"[^>]*>.*?</tbody>', [Text.RegularExpressions.RegexOptions]'IgnoreCase,Singleline').Value
            Assert-True (-not [string]::IsNullOrWhiteSpace($positionBlock)) "Integrated position summary missing: $position"
            Assert-True ($positionBlock.Contains('rowspan="9"') -and $positionBlock.Contains('RS4PE / LHD / ' + $position)) "Position hierarchy missing: $position"
            foreach ($category in $categories) {
                Assert-Equal ([regex]::Matches($positionBlock, 'data-category="' + [regex]::Escape($category) + '"').Count) 1 "Category count error: $position/$category"
            }
            Assert-True ($positionBlock.Contains('class="summary-toggle"')) "First-level toggle missing: $position"
            Assert-True ($positionBlock.Contains('class="tc-toggle"')) "Second-level toggle missing: $position"
        }
        Assert-Equal ([regex]::Matches($summary, 'data-category=').Count) 36 'Integrated category total is not 36.'
    }

    Invoke-Test 'removes_functional_summary_from_position_sections' {
        $context = Get-BuildContext
        foreach ($position in @('DRV', 'AST', 'RL', 'RR')) {
            $section = Get-PositionSectionHtml -Html $context.Html -Position $position
            Assert-True (-not $section.Contains('functional-summary')) "Position summary still present: $position"
        }
    }

    Invoke-Test 'aggregates_numeric_parent_verdicts' {
        $context = Get-BuildContext
        $summary = Get-CombinedSummaryHtml -Html $context.Html
        Assert-True ([regex]::IsMatch($summary, 'data-position="RR"[^>]*data-test-name="C104_SBCM_Input_Status_Check_RS4PE"[^>]*data-verdict="Pass"')) 'C104 parent did not aggregate to Pass.'
        Assert-True ([regex]::IsMatch($summary, 'data-position="RR"[^>]*data-test-name="AF_Rear_Fold_Limit_SW_IN"[^>]*data-verdict="Pass"')) 'Child verdict missing.'
    }

    Invoke-Test 'deduplicates_c104_and_io_control_children' {
        $context = Get-BuildContext
        $summary = Get-CombinedSummaryHtml -Html $context.Html
        $rr = [regex]::Match($summary, '<tbody\b[^>]*data-summary-position="RR"[^>]*>.*?</tbody>', [Text.RegularExpressions.RegexOptions]'IgnoreCase,Singleline').Value
        Assert-Equal ([regex]::Matches($rr, 'data-test-name="IOCBI_F010"').Count) 1 'IO control child duplicated.'
        Assert-Equal ([regex]::Matches($rr, 'data-test-name="AF_Rear_Fold_Limit_SW_IN"').Count) 1 'C104 child duplicated.'
    }

    Invoke-Test 'prefixes_local_identifiers_and_resolves_links' {
        $context = Get-BuildContext
        Assert-True ($context.Html.Contains('name="RR__TOP"')) 'RR TOP anchor was not prefixed.'
        Assert-True (-not $context.Html.Contains('name="TOP"')) 'Unprefixed TOP anchor remains.'
        Assert-Equal $context.Result.UnresolvedLinkCount 0 'Unresolved fragment links remain.'
    }

    Invoke-Test 'preserves_external_links' {
        $context = Get-BuildContext
        Assert-True ($context.Html.Contains('href="https://example.com/external-doc"')) 'External link was changed.'
    }

    Invoke-Test 'rewrites_original_javascript_id_references' {
        $context = Get-BuildContext
        foreach ($position in @('DRV', 'AST', 'RL', 'RR')) {
            $section = Get-PositionSectionHtml -Html $context.Html -Position $position
            Assert-True ($section.Contains('id="lnk_' + $position + '__1"')) "Prefixed link ID missing: $position"
            Assert-True ($section.Contains("switchAll('$position" + "__1',document.all['lnk_$position" + "__1'].text)")) "switchAll reference mismatch: $position"
            $report = @($context.Reports | Where-Object Position -eq $position)[0]
            if ($report.BodyHtml -match 'onclick\s*=\s*["'']showTC\(') {
                $showPattern = 'onclick="showTC\(''{0}__[^'']+''\)"' -f $position
                Assert-True ([regex]::IsMatch($section, $showPattern)) "showTC reference mismatch: $position"
            }
        }
    }

    Invoke-Test 'outside_failure_prevents_pass_verdict' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('combined-report-outside-' + [guid]::NewGuid().ToString('N'))
        try {
            $reports = @(New-MinimalReportSet -Directory $root -OutsideFailPosition 'DRV')
            Assert-Equal $reports[0].Statistics.OutsideFail 1 'Outside Fail was not parsed.'
            $output = Join-Path $root 'combined.html'
            New-CombinedReport -Reports $reports -OutputPath $output | Out-Null
            $html = [IO.File]::ReadAllText($output, [Text.Encoding]::UTF8)
            Assert-True ([regex]::IsMatch($html, '<tr[^>]*data-overview-position="DRV"[^>]*>.*?<td class="NegativeResultCell">Fail</td>', [Text.RegularExpressions.RegexOptions]'Singleline')) 'Outside Fail did not make DRV verdict Fail.'
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    Invoke-Test 'refuses_output_path_that_matches_source' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('combined-report-collision-' + [guid]::NewGuid().ToString('N'))
        try {
            $reports = @(New-MinimalReportSet -Directory $root)
            $sourcePath = $reports[0].Path
            $before = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
            Assert-Throws { New-CombinedReport -Reports $reports -OutputPath $sourcePath } 'source|input|evidence|same' 'Source/output collision was accepted.'
            $after = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
            Assert-Equal $after $before 'Source was modified before collision rejection.'
        } finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    Invoke-Test 'embeds_complete_test_results_for_each_position' {
        $context = Get-BuildContext
        foreach ($report in $context.Reports) {
            $section = Get-PositionSectionHtml -Html $context.Html -Position $report.Position
            Assert-True ($section.Contains('<div class="Heading4">Test Results</div>')) "Test Results missing: $($report.Position)"
            Assert-True ($section.Contains('data-source-record-count="' + $report.TestItems.Count + '"')) "Record count marker missing: $($report.Position)"
        }
    }

    Invoke-Test 'matches_source_statistics_and_record_counts' {
        $context = Get-BuildContext
        $validation = Test-CombinedReport -Path $context.Path -Reports $context.Reports
        Assert-Equal $validation.UnresolvedLinkCount 0 'Link validation failed.'
        foreach ($report in $context.Reports) {
            $actual = $validation.Positions | Where-Object Position -eq $report.Position | Select-Object -First 1
            Assert-Equal $actual.RecordCount $report.TestItems.Count "Record mismatch: $($report.Position)"
            Assert-Equal $actual.Executed $report.Statistics.Executed "Statistics mismatch: $($report.Position)"
        }
    }

    Invoke-Test 'rejects_duplicate_ids' {
        $context = Get-BuildContext
        $badPath = Join-Path $context.Root 'duplicate-id.html'
        $badHtml = $context.Html.Replace('</body>', '<div id="position-DRV"></div></body>')
        [IO.File]::WriteAllText($badPath, $badHtml, [Text.UTF8Encoding]::new($false))
        Assert-Throws { Test-CombinedReport -Path $badPath -Reports $context.Reports } 'duplicate|Duplicate' 'Duplicate ID was accepted.'
    }

    Invoke-Test 'keeps_source_hashes_unchanged' {
        $context = Get-BuildContext
        foreach ($report in $context.Reports) {
            $after = (Get-FileHash -LiteralPath $report.Path -Algorithm SHA256).Hash
            Assert-Equal $after $context.Before[$report.Position] "Source changed: $($report.Position)"
        }
    }
}

if ($Group -in @('Publish', 'All')) {
    $script:PublishRoot = Join-Path ([IO.Path]::GetTempPath()) ('combined-report-publish-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:PublishRoot -Force | Out-Null
    $commandPath = Join-Path $PSScriptRoot '..\combine-test-reports.ps1'

    Invoke-Test 'command_builds_verified_workspace_artifact' {
        Assert-True (Test-Path -LiteralPath $commandPath) 'Command script does not exist.'
        $output = Join-Path $script:PublishRoot 'workspace\combined.html'
        & $commandPath -InputDirectory 'C:\Users\USER.K1109684\Downloads\TestReport' -OutputPath $output | Out-Null
        Assert-True (Test-Path -LiteralPath $output) 'Workspace artifact was not created.'
        $reports = @(Get-RealReportSet)
        $validation = Test-CombinedReport -Path $output -Reports $reports
        Assert-Equal $validation.Positions.Count 4 'Verified position count is not four.'
    }

    Invoke-Test 'publish_creates_timestamped_backup_before_replace' {
        $source = Join-Path $script:PublishRoot 'source-one.html'
        $destination = Join-Path $script:PublishRoot 'published\report.html'
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        [IO.File]::WriteAllText($source, 'new-content-one', [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($destination, 'old-content', [Text.UTF8Encoding]::new($false))
        $publish = Publish-VerifiedReport -SourcePath $source -PublishPath $destination
        Assert-True (Test-Path -LiteralPath $publish.BackupPath) 'Backup was not created.'
        Assert-True ($publish.BackupPath -match '\.bak_\d{8}_\d{6}_\d{3}') 'Backup name has no timestamp.'
        Assert-Equal ([IO.File]::ReadAllText($publish.BackupPath)) 'old-content' 'Backup content changed.'
        Assert-Equal ([IO.File]::ReadAllText($destination)) 'new-content-one' 'Published content mismatch.'
    }

    Invoke-Test 'second_publish_does_not_overwrite_previous_backup' {
        $source = Join-Path $script:PublishRoot 'source-two.html'
        $destination = Join-Path $script:PublishRoot 'published\report.html'
        $before = @(Get-ChildItem -LiteralPath (Split-Path -Parent $destination) -Filter 'report.html.bak_*' -File)
        [IO.File]::WriteAllText($source, 'new-content-two', [Text.UTF8Encoding]::new($false))
        $publish = Publish-VerifiedReport -SourcePath $source -PublishPath $destination
        $after = @(Get-ChildItem -LiteralPath (Split-Path -Parent $destination) -Filter 'report.html.bak_*' -File)
        Assert-Equal $after.Count ($before.Count + 1) 'Second backup was not preserved separately.'
        Assert-True (Test-Path -LiteralPath $publish.BackupPath) 'Second backup path is missing.'
        Assert-Equal ([IO.File]::ReadAllText($publish.BackupPath)) 'new-content-one' 'Second backup did not preserve previous report.'
        Assert-Equal ([IO.File]::ReadAllText($destination)) 'new-content-two' 'Second publish content mismatch.'
    }

    Invoke-Test 'publication_stops_when_validation_fails' {
        Assert-True (Test-Path -LiteralPath $commandPath) 'Command script does not exist.'
        $input = Join-Path $script:PublishRoot 'incomplete-input'
        New-Item -ItemType Directory -Path $input -Force | Out-Null
        foreach ($name in @('2026-10-08_08-18-49_RS4_Test_Report.html', '2026-10-08_10-16-56_RS4_Test_Report.html', '2026-10-08_10-42-10_RS4_Test_Report.html')) {
            [IO.File]::WriteAllText((Join-Path $input $name), '<html></html>', [Text.UTF8Encoding]::new($false))
        }
        $output = Join-Path $script:PublishRoot 'invalid-output.html'
        $publish = Join-Path $script:PublishRoot 'invalid-published.html'
        $process = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $commandPath, '-InputDirectory', $input, '-OutputPath', $output, '-PublishPath', $publish) -Wait -PassThru -WindowStyle Hidden
        Assert-True ($process.ExitCode -ne 0) 'Invalid source set returned success.'
        Assert-True (-not (Test-Path -LiteralPath $publish)) 'Invalid report was published.'
    }
}

if ($script:Failed -gt 0) {
    Write-Output "FAIL: $Group ($($script:Passed) passed, $($script:Failed) failed)"
    exit 1
}

Write-Output "PASS: $Group ($($script:Passed) tests)"

if ($null -ne $script:BuildContext -and (Test-Path -LiteralPath $script:BuildContext.Root)) {
    Remove-Item -LiteralPath $script:BuildContext.Root -Recurse -Force -ErrorAction SilentlyContinue
}
if ($null -ne $script:PublishRoot -and (Test-Path -LiteralPath $script:PublishRoot)) {
    Remove-Item -LiteralPath $script:PublishRoot -Recurse -Force -ErrorAction SilentlyContinue
}
