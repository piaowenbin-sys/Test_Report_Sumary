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
        [switch]$Malformed
    )
    $closing = if ($Malformed) { '' } else { '</body></html>' }
    return @"
<!DOCTYPE html><html><head><meta charset="utf-8"><style>.x{color:#000}</style></head><body>
<a name="TOP"></a>
<div class="Heading2">Test Overview</div>
<table class="DefaultTable"><tr><td>Test begin: </td><td>2026-10-08 11:02:02</td></tr><tr><td>Test end: </td><td>2026-10-08 11:09:19</td></tr></table>
<div class="Heading4">Statistics</div><table class="OverviewTable">
<tr><td>Executed test cases </td><td>2</td></tr><tr><td>Test cases passed </td><td>1</td></tr>
<tr><td>Test cases inconclusive</td><td>0</td></tr><tr><td>Test cases failed </td><td>1</td></tr>
<tr><td>Test cases with error in test system </td><td>0</td></tr></table>
<div class="Heading4">Test Results</div><table class="OverviewTable">$Rows</table>
<a name="TestModuleInfo"></a>
<div class="Heading4">Variant Properties</div><table>
<tr><td>Var_Drive_Type: </td><td>$DriveType</td></tr><tr><td>Var_SBCM_Position: </td><td>$Position</td></tr>
<tr><td>Var_EOL_Variant_Type: </td><td>$EolVariant</td></tr><tr><td>Var_Project: </td><td>$Project</td></tr></table>
<a name="parent-one"></a><a name="child-one"></a><a name="parent-ten"></a><a name="child-ten"></a>
$closing
"@
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

    Invoke-Test 'includes_nine_nested_summary_categories_per_position' {
        $context = Get-BuildContext
        $categories = @('C104', 'ForceControl', 'ECU_ID', 'PWM', 'Switch', 'Sensor', 'Vbat', 'HS', 'Motor')
        foreach ($position in @('DRV', 'AST', 'RL', 'RR')) {
            $section = Get-PositionSectionHtml -Html $context.Html -Position $position
            foreach ($category in $categories) {
                Assert-Equal ([regex]::Matches($section, 'data-category="' + [regex]::Escape($category) + '"').Count) 1 "Category count error: $position/$category"
            }
            Assert-True ($section.Contains('class="summary-toggle"')) "First-level toggle missing: $position"
            Assert-True ($section.Contains('class="tc-toggle"')) "Second-level toggle missing: $position"
        }
    }

    Invoke-Test 'aggregates_numeric_parent_verdicts' {
        $context = Get-BuildContext
        $section = Get-PositionSectionHtml -Html $context.Html -Position 'RR'
        Assert-True ([regex]::IsMatch($section, 'data-test-name="C104_SBCM_Input_Status_Check_RS4PE"[^>]*data-verdict="Pass"')) 'C104 parent did not aggregate to Pass.'
        Assert-True ([regex]::IsMatch($section, 'data-test-name="AF_Rear_Fold_Limit_SW_IN"[^>]*data-verdict="Pass"')) 'Child verdict missing.'
    }

    Invoke-Test 'deduplicates_c104_and_io_control_children' {
        $context = Get-BuildContext
        $section = Get-PositionSectionHtml -Html $context.Html -Position 'RR'
        $summary = [regex]::Match($section, '<div class="functional-summary".*?<!-- FUNCTIONAL_SUMMARY_END -->', [Text.RegularExpressions.RegexOptions]'Singleline').Value
        Assert-Equal ([regex]::Matches($summary, 'data-test-name="IOCBI_F010"').Count) 1 'IO control child duplicated.'
        Assert-Equal ([regex]::Matches($summary, 'data-test-name="AF_Rear_Fold_Limit_SW_IN"').Count) 1 'C104 child duplicated.'
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

if ($script:Failed -gt 0) {
    Write-Output "FAIL: $Group ($($script:Passed) passed, $($script:Failed) failed)"
    exit 1
}

Write-Output "PASS: $Group ($($script:Passed) tests)"

if ($null -ne $script:BuildContext -and (Test-Path -LiteralPath $script:BuildContext.Root)) {
    Remove-Item -LiteralPath $script:BuildContext.Root -Recurse -Force -ErrorAction SilentlyContinue
}
