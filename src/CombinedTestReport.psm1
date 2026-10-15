Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function ConvertFrom-HtmlText {
    param([AllowEmptyString()][string]$Value)
    $plain = [regex]::Replace($Value, '<[^>]+>', '')
    $plain = [Net.WebUtility]::HtmlDecode($plain)
    return ([regex]::Replace($plain, '\s+', ' ')).Trim()
}

function Get-LabeledCellValue {
    param([string]$Html, [string]$Label)
    $pattern = '<td\b[^>]*>\s*' + [regex]::Escape($Label) + '\s*</td>\s*<td\b[^>]*>(?<value>.*?)</td>'
    $match = [regex]::Match($Html, $pattern, [Text.RegularExpressions.RegexOptions]'IgnoreCase,Singleline')
    if (-not $match.Success) { throw "필수 메타데이터를 찾지 못했습니다: $Label" }
    return ConvertFrom-HtmlText $match.Groups['value'].Value
}

function Get-StatisticValue {
    param([string]$StatisticsHtml, [string]$Label)
    $pattern = '<td\b[^>]*>\s*' + [regex]::Escape($Label) + '\s*</td>\s*<td\b[^>]*>(?<value>.*?)</td>'
    $match = [regex]::Match($StatisticsHtml, $pattern, [Text.RegularExpressions.RegexOptions]'IgnoreCase,Singleline')
    if (-not $match.Success) { throw "필수 통계를 찾지 못했습니다: $Label" }
    $text = ConvertFrom-HtmlText $match.Groups['value'].Value
    if ($text -notmatch '^\d+$') { throw "통계 값이 숫자가 아닙니다: $Label='$text'" }
    return [int]$text
}

function Get-TimeValue {
    param([string]$Html, [string]$Label)
    $pattern = '<td\b[^>]*>\s*' + [regex]::Escape($Label) + '\s*</td>\s*<td\b[^>]*>(?<value>.*?)</td>'
    $match = [regex]::Match($Html, $pattern, [Text.RegularExpressions.RegexOptions]'IgnoreCase,Singleline')
    if (-not $match.Success) { throw "시험 시간을 찾지 못했습니다: $Label" }
    return ConvertFrom-HtmlText $match.Groups['value'].Value
}

function Get-ImmediateChildren {
    param([object[]]$Items, [object]$Parent)
    if ([string]::IsNullOrWhiteSpace($Parent.Number)) { return @() }
    $prefix = $Parent.Number + '.'
    return @($Items | Where-Object {
        $_.Number.StartsWith($prefix, [StringComparison]::Ordinal) -and
        $_.Number.Substring($prefix.Length) -notmatch '\.'
    })
}

function Get-Descendants {
    param([object[]]$Items, [object]$Parent)
    if ([string]::IsNullOrWhiteSpace($Parent.Number)) { return @() }
    $prefix = $Parent.Number + '.'
    return @($Items | Where-Object { $_.Number.StartsWith($prefix, [StringComparison]::Ordinal) })
}

function Resolve-ItemVerdict {
    param([object[]]$Items, [object]$Item, [hashtable]$Cache)
    $key = $Item.Number + '|' + $Item.Href
    if ($Cache.ContainsKey($key)) { return $Cache[$key] }
    if ($Item.DirectVerdict -in @('Pass', 'Fail')) {
        $Cache[$key] = $Item.DirectVerdict
        return $Item.DirectVerdict
    }
    $children = @(Get-ImmediateChildren -Items $Items -Parent $Item)
    if ($children.Count -eq 0) {
        $Cache[$key] = 'NA'
        return 'NA'
    }
    $childVerdicts = @($children | ForEach-Object { Resolve-ItemVerdict -Items $Items -Item $_ -Cache $Cache })
    $resolved = if ($childVerdicts -contains 'Fail') {
        'Fail'
    } elseif (@($childVerdicts | Where-Object { $_ -ne 'Pass' }).Count -eq 0) {
        'Pass'
    } else {
        'NA'
    }
    $Cache[$key] = $resolved
    return $resolved
}

function Get-TestResultItems {
    param([string]$Html)
    $resultsMarker = '<div class="Heading4">Test Results</div>'
    $endMarker = '<a name="TestModuleInfo"></a>'
    $start = $Html.IndexOf($resultsMarker, [StringComparison]::Ordinal)
    $end = if ($start -ge 0) { $Html.IndexOf($endMarker, $start, [StringComparison]::Ordinal) } else { -1 }
    if ($start -lt 0 -or $end -lt 0) { throw 'Test Results 영역을 찾지 못했습니다.' }

    $section = $Html.Substring($start, $end - $start)
    $tableStart = $section.IndexOf('<table class="OverviewTable">', [StringComparison]::Ordinal)
    if ($tableStart -lt 0) { throw 'Test Results 표를 찾지 못했습니다.' }
    $tablePart = $section.Substring($tableStart)
    $tokens = [regex]::Matches($tablePart, '<table\b[^>]*>|</table>|<tr\b[^>]*>|</tr>', [Text.RegularExpressions.RegexOptions]'IgnoreCase')
    $tableDepth = 0
    $rowStart = -1
    $rows = [Collections.Generic.List[string]]::new()
    foreach ($token in $tokens) {
        if ($token.Value -match '^<table\b') {
            $tableDepth++
        } elseif ($token.Value -match '^</table') {
            if ($tableDepth -eq 1) { break }
            $tableDepth--
        } elseif ($token.Value -match '^<tr\b') {
            if ($tableDepth -eq 1 -and $rowStart -lt 0) { $rowStart = $token.Index }
        } elseif ($token.Value -match '^</tr' -and $tableDepth -eq 1 -and $rowStart -ge 0) {
            $rows.Add($tablePart.Substring($rowStart, ($token.Index + $token.Length) - $rowStart))
            $rowStart = -1
        }
    }

    $items = foreach ($row in $rows) {
        $anchor = [regex]::Match($row, '<a\s+href=(?:"|\'')(?<href>[^"\'']+)(?:"|\'')[^>]*>(?<text>.*?)</a>', [Text.RegularExpressions.RegexOptions]'IgnoreCase,Singleline')
        if (-not $anchor.Success) { continue }
        $firstCell = [regex]::Match($row, '<td\b[^>]*>(?<content>.*?)</td>', [Text.RegularExpressions.RegexOptions]'IgnoreCase,Singleline')
        $number = if ($firstCell.Success) { ConvertFrom-HtmlText $firstCell.Groups['content'].Value } else { '' }
        $text = ConvertFrom-HtmlText $anchor.Groups['text'].Value
        $resultCells = [regex]::Matches($row, '<td\b(?=[^>]*\bclass=(?:"|\'')[^"\'']*(?:PositiveResultCell|NegativeResultCell)[^"\'']*(?:"|\''))[^>]*>(?<content>.*?)</td>', [Text.RegularExpressions.RegexOptions]'IgnoreCase,Singleline')
        $resultTexts = @($resultCells | ForEach-Object { (ConvertFrom-HtmlText $_.Groups['content'].Value).ToLowerInvariant() })
        $directVerdict = if ($resultTexts -contains 'fail') { 'Fail' } elseif ($resultTexts -contains 'pass') { 'Pass' } else { 'NA' }
        [pscustomobject]@{
            Number = $number
            Href = $anchor.Groups['href'].Value
            Text = $text
            DirectVerdict = $directVerdict
            EffectiveVerdict = 'NA'
        }
    }
    $items = @($items)
    $cache = @{}
    foreach ($item in $items) { $item.EffectiveVerdict = Resolve-ItemVerdict -Items $items -Item $item -Cache $cache }
    return $items
}

function Get-ReportModel {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $html = [IO.File]::ReadAllText($resolved, [Text.Encoding]::UTF8)
    if ($html -notmatch '(?is)<html\b[^>]*>.*</html\s*>' -or $html -notmatch '(?is)<body\b[^>]*>.*</body\s*>') {
        throw "손상된 HTML 문서입니다. 종료 태그를 확인하십시오: $resolved"
    }
    $bodyMatch = [regex]::Match($html, '(?is)<body\b[^>]*>(?<body>.*)</body\s*>')
    $headMatch = [regex]::Match($html, '(?is)<head\b[^>]*>(?<head>.*)</head\s*>')
    if (-not $bodyMatch.Success -or -not $headMatch.Success) { throw "손상된 HTML 문서입니다: $resolved" }

    $statisticsStart = $html.IndexOf('<div class="Heading4">Statistics</div>', [StringComparison]::Ordinal)
    $resultsStart = $html.IndexOf('<div class="Heading4">Test Results</div>', [StringComparison]::Ordinal)
    if ($statisticsStart -lt 0 -or $resultsStart -le $statisticsStart) { throw "Statistics/Test Results 영역을 찾지 못했습니다: $resolved" }
    $statisticsHtml = $html.Substring($statisticsStart, $resultsStart - $statisticsStart)

    [pscustomobject]@{
        Path = $resolved
        FileName = [IO.Path]::GetFileName($resolved)
        Project = Get-LabeledCellValue -Html $html -Label 'Var_Project:'
        DriveType = Get-LabeledCellValue -Html $html -Label 'Var_Drive_Type:'
        Position = Get-LabeledCellValue -Html $html -Label 'Var_SBCM_Position:'
        EolVariant = Get-LabeledCellValue -Html $html -Label 'Var_EOL_Variant_Type:'
        TestBegin = Get-TimeValue -Html $html -Label 'Test begin:'
        TestEnd = Get-TimeValue -Html $html -Label 'Test end:'
        Statistics = [pscustomobject]@{
            Executed = Get-StatisticValue -StatisticsHtml $statisticsHtml -Label 'Executed test cases'
            Pass = Get-StatisticValue -StatisticsHtml $statisticsHtml -Label 'Test cases passed'
            Inconclusive = Get-StatisticValue -StatisticsHtml $statisticsHtml -Label 'Test cases inconclusive'
            Fail = Get-StatisticValue -StatisticsHtml $statisticsHtml -Label 'Test cases failed'
            Error = Get-StatisticValue -StatisticsHtml $statisticsHtml -Label 'Test cases with error in test system'
        }
        TestItems = @(Get-TestResultItems -Html $html)
        SourceHash = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash
        SourceHtml = $html
        HeadHtml = $headMatch.Groups['head'].Value
        BodyHtml = $bodyMatch.Groups['body'].Value
    }
}

function Assert-ReportSet {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object[]]$Reports)

    if ($Reports.Count -ne 4) { throw "정확히 4개(exactly four)의 Position 보고서가 필요합니다. 현재: $($Reports.Count)" }
    $expected = @('DRV', 'AST', 'RL', 'RR')
    $positions = @($Reports | ForEach-Object { $_.Position })
    if (@($positions | Select-Object -Unique).Count -ne 4) { throw "Position 중복(duplicate)이 있습니다: $($positions -join ', ')" }
    foreach ($position in $expected) {
        if ($positions -notcontains $position) { throw "Position 누락: $position (필수: DRV, AST, RL, RR)" }
    }
    foreach ($report in $Reports) {
        if ($report.Project -ne 'RS4PE') { throw "메타데이터(metadata) Project 불일치: $($report.Position)=$($report.Project)" }
        if ($report.DriveType -ne 'LHD') { throw "메타데이터(metadata) DriveType 불일치: $($report.Position)=$($report.DriveType)" }
        if ($report.EolVariant -ne 'All_DTC_List (defined in test design)') { throw "메타데이터(metadata) EOL 불일치: $($report.Position)=$($report.EolVariant)" }
    }
    $ordered = foreach ($position in $expected) { $Reports | Where-Object Position -eq $position | Select-Object -First 1 }
    return @($ordered)
}

Export-ModuleMember -Function Get-ReportModel, Assert-ReportSet
