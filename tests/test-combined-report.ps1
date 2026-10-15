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

if ($script:Failed -gt 0) {
    Write-Output "FAIL: $Group ($($script:Passed) passed, $($script:Failed) failed)"
    exit 1
}

Write-Output "PASS: $Group ($($script:Passed) tests)"
