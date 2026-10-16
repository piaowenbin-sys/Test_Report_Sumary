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

function Get-OutsideStatistics {
    param([string]$StatisticsHtml)
    $marker = 'Number of failures outside of test cases'
    $start = $StatisticsHtml.IndexOf($marker, [StringComparison]::OrdinalIgnoreCase)
    if ($start -lt 0) { throw 'Outside-test statistics are missing.' }
    $outsideHtml = $StatisticsHtml.Substring($start)
    [pscustomobject]@{
        Inconclusive = Get-StatisticValue -StatisticsHtml $outsideHtml -Label 'Inconclusive'
        Fail = Get-StatisticValue -StatisticsHtml $outsideHtml -Label 'Fail'
        Error = Get-StatisticValue -StatisticsHtml $outsideHtml -Label 'Error in test system'
    }
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

    $outside = Get-OutsideStatistics -StatisticsHtml $statisticsHtml
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
            OutsideInconclusive = $outside.Inconclusive
            OutsideFail = $outside.Fail
            OutsideError = $outside.Error
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

function Select-PatternItems {
    param([object[]]$Items, [string]$Pattern)
    return @($Items | Where-Object { $_.Text -match $Pattern })
}

function Select-C104Items {
    param([object[]]$Items)
    $parent = $Items | Where-Object { $_.Text -match '(?i)C104' } | Select-Object -First 1
    if ($null -eq $parent) { return @() }
    return @($parent)
}

function Select-SwitchItems {
    param([object[]]$Items)
    $switchItems = Select-PatternItems -Items $Items -Pattern '(?i)_SW_IN$'
    $c104Parent = $Items | Where-Object { $_.Text -match '(?i)C104' } | Select-Object -First 1
    if ($null -eq $c104Parent) { return @($switchItems) }
    $prefix = $c104Parent.Number + '.'
    return @($switchItems | Where-Object { -not $_.Number.StartsWith($prefix, [StringComparison]::Ordinal) })
}

function Get-PrefixedHref {
    param([string]$Href, [string]$Position)
    if ($Href.StartsWith('#', [StringComparison]::Ordinal)) { return '#' + $Position + '__' + $Href.Substring(1) }
    return $Href
}

function Get-VerdictCellClass {
    param([string]$Verdict)
    if ($Verdict -eq 'Pass') { return 'PositiveResultCell' }
    if ($Verdict -eq 'Fail') { return 'NegativeResultCell' }
    return 'NumberCell'
}

function ConvertTo-SummaryItemRows {
    param([object[]]$Items, [object[]]$AllItems, [string]$Position, [int]$GroupIndex)
    if ($Items.Count -eq 0) { return '<tr><td class="NumberCell" colspan="4">No matching test item</td></tr>' }
    $rows = [Collections.Generic.List[string]]::new()
    for ($itemIndex = 0; $itemIndex -lt $Items.Count; $itemIndex++) {
        $item = $Items[$itemIndex]
        $safeNumber = [Net.WebUtility]::HtmlEncode($item.Number)
        $safeText = [Net.WebUtility]::HtmlEncode($item.Text)
        $safeName = [Net.WebUtility]::HtmlEncode($item.Text)
        $safeHref = [Net.WebUtility]::HtmlEncode((Get-PrefixedHref -Href $item.Href -Position $Position))
        $cellClass = Get-VerdictCellClass $item.EffectiveVerdict
        $descendants = @(Get-Descendants -Items $AllItems -Parent $item)
        $childId = $Position + '__tc-details-' + $GroupIndex + '-' + $itemIndex
        $childButton = ''
        if ($descendants.Count -gt 0) {
            $childButton = '<button type="button" class="tc-toggle" onclick="toggleCombinedReport(''' + $childId + ''', this)">Child TC ' + $descendants.Count + ' - Show details</button>'
        }
        $rows.Add(@"
<tr data-position="$Position" data-test-name="$safeName" data-verdict="$($item.EffectiveVerdict)"><td class="DefineCell">$safeNumber</td><td class="DefaultCell"><a href="$safeHref">$safeText</a></td><td class="$cellClass">$($item.EffectiveVerdict)</td><td class="DefaultCell">$childButton</td></tr>
"@)
        if ($descendants.Count -gt 0) {
            $childRows = [Collections.Generic.List[string]]::new()
            foreach ($child in $descendants) {
                $childNumber = [Net.WebUtility]::HtmlEncode($child.Number)
                $childText = [Net.WebUtility]::HtmlEncode($child.Text)
                $childName = [Net.WebUtility]::HtmlEncode($child.Text)
                $childHref = [Net.WebUtility]::HtmlEncode((Get-PrefixedHref -Href $child.Href -Position $Position))
                $childClass = Get-VerdictCellClass $child.EffectiveVerdict
                $childRows.Add('<tr data-position="' + $Position + '" data-test-name="' + $childName + '" data-verdict="' + $child.EffectiveVerdict + '"><td class="DefineCell">' + $childNumber + '</td><td class="DefaultCell"><a href="' + $childHref + '">' + $childText + '</a></td><td class="' + $childClass + '">' + $child.EffectiveVerdict + '</td></tr>')
            }
            $rows.Add('<tr><td class="DefaultCell" colspan="4"><div id="' + $childId + '" class="tc-details" style="display:none"><table class="OverviewTable nested-table"><tr><td class="DefineCell"><b>Child TC</b></td><td class="DefineCell"><b>Test item</b></td><td class="DefineCell"><b>Verdict</b></td></tr>' + ($childRows -join '') + '</table></div></td></tr>')
        }
    }
    return ($rows -join '')
}

function New-PositionSummaryRowsHtml {
    param([object]$Report)
    $groups = @(
        [pscustomobject]@{ Major = 'Diagnostic'; Key = 'C104'; Label = 'C104'; Pattern = $null },
        [pscustomobject]@{ Major = ''; Key = 'ForceControl'; Label = '&#44053;&#51228;&#44396;&#46041;'; Pattern = '(?i)^IO_Control_Check_' },
        [pscustomobject]@{ Major = ''; Key = 'ECU_ID'; Label = 'ECU ID'; Pattern = '(?i)(^|_)DID_Check$|ECU[ _-]?ID' },
        [pscustomobject]@{ Major = 'Input'; Key = 'PWM'; Label = 'PWM'; Pattern = '(?i)^P_CRASH_UNLOCK_IN$' },
        [pscustomobject]@{ Major = ''; Key = 'Switch'; Label = 'Switch'; Pattern = '(?i)_SW_IN$' },
        [pscustomobject]@{ Major = ''; Key = 'Sensor'; Label = 'Sensor'; Pattern = '(?i)(SNSR_IN|^A_IS_ECM_V_IN$|^P_HALL_)' },
        [pscustomobject]@{ Major = ''; Key = 'Vbat'; Label = 'Vbat'; Pattern = '(?i)^B\+_POWER$|^VBAT$' },
        [pscustomobject]@{ Major = 'Output'; Key = 'HS'; Label = 'HS'; Pattern = '(?i)^(L_DEFOG_OUT|L_ECM_V_OUT)' },
        [pscustomobject]@{ Major = ''; Key = 'Motor'; Label = 'Motor'; Pattern = '(?i)_MTR_' }
    )
    $rows = [Collections.Generic.List[string]]::new()
    for ($index = 0; $index -lt $groups.Count; $index++) {
        $group = $groups[$index]
        $matched = @(if ($group.Key -eq 'C104') {
            @(Select-C104Items -Items $Report.TestItems)
        } elseif ($group.Key -eq 'Switch') {
            @(Select-SwitchItems -Items $Report.TestItems)
        } else {
            @(Select-PatternItems -Items $Report.TestItems -Pattern $group.Pattern)
        })
        $pass = @($matched | Where-Object EffectiveVerdict -eq 'Pass').Count
        $fail = @($matched | Where-Object EffectiveVerdict -eq 'Fail').Count
        $na = @($matched | Where-Object EffectiveVerdict -eq 'NA').Count
        $detailsId = $Report.Position + '__functional-summary-details-' + $index
        $positionCell = if ($index -eq 0) { '<td class="DefineCell position-cell" rowspan="9"><b>' + $Report.Project + ' / ' + $Report.DriveType + ' / ' + $Report.Position + '</b></td>' } else { '' }
        $areaCell = switch ($index) {
            0 { '<td class="DefineCell area-cell" rowspan="3"><b>Diagnostic</b></td>' }
            3 { '<td class="DefineCell area-cell" rowspan="4"><b>Input</b></td>' }
            7 { '<td class="DefineCell area-cell" rowspan="2"><b>Output</b></td>' }
            default { '' }
        }
        $detailRows = ConvertTo-SummaryItemRows -Items $matched -AllItems $Report.TestItems -Position $Report.Position -GroupIndex $index
        $rows.Add(@"
<tr data-category="$($group.Key)">$positionCell$areaCell<td class="DefineCell"><b>$($group.Label)</b></td><td class="DefaultCell"><button type="button" class="summary-toggle" onclick="toggleCombinedReport('$detailsId', this)">$($group.Label) ($($matched.Count)) | Pass $pass | Fail $fail | NA $na - Show details</button><div id="$detailsId" class="summary-details" style="display:none"><table class="OverviewTable"><tr><td class="DefineCell"><b>TC</b></td><td class="DefineCell"><b>Test item</b></td><td class="DefineCell"><b>Verdict</b></td><td class="DefineCell"><b>Children</b></td></tr>$detailRows</table></div></td></tr>
"@)
    }
    return '<tbody data-summary-position="' + $Report.Position + '">' + ($rows -join '') + '</tbody>'
}

function New-CombinedFunctionalSummaryHtml {
    param([object[]]$Reports)
    $positionBodies = @($Reports | ForEach-Object { New-PositionSummaryRowsHtml -Report $_ })
    return '<div class="combined-functional-summary"><div class="Heading4">Integrated Functional Test Summary</div><div class="Indentation"><table class="OverviewTable combined-summary-table"><thead><tr><td class="DefineCell"><b>Position</b></td><td class="DefineCell"><b>Area</b></td><td class="DefineCell"><b>Category</b></td><td class="DefineCell"><b>Results and details</b></td></tr></thead>' + ($positionBodies -join '') + '</table></div></div><!-- COMBINED_FUNCTIONAL_SUMMARY_END -->'
}

function ConvertTo-PositionIdentifier {
    param([string]$Value, [string]$Position)
    $scoped = [regex]::Match($Value, '^(?<scope>s\d+\.)(?<prefix>tbl2_|tbl_|lnk_|div_)(?<rest>.*)$', [Text.RegularExpressions.RegexOptions]'IgnoreCase')
    if ($scoped.Success) {
        return $scoped.Groups['scope'].Value + $scoped.Groups['prefix'].Value + $Position + '__' + $scoped.Groups['rest'].Value
    }
    $known = [regex]::Match($Value, '^(?<prefix>tbl2_|tbl_|lnk_|div_)(?<rest>.*)$', [Text.RegularExpressions.RegexOptions]'IgnoreCase')
    if ($known.Success) { return $known.Groups['prefix'].Value + $Position + '__' + $known.Groups['rest'].Value }
    return $Position + '__' + $Value
}

function ConvertTo-PrefixedBody {
    param([string]$BodyHtml, [string]$Position)
    $seen = @{}
    $canonical = @{}
    $identifierPattern = '(?<![\w:-])(?<attr>(?:id|name))\s*=\s*(?<quote>["''])(?<value>.*?)(?:\k<quote>)'
    $converted = [regex]::Replace($BodyHtml, $identifierPattern, {
        param($match)
        $attr = $match.Groups['attr'].Value.ToLowerInvariant()
        $value = $match.Groups['value'].Value
        $key = $attr + '|' + $value
        if ($seen.ContainsKey($key)) { $seen[$key]++ } else { $seen[$key] = 1 }
        $suffix = if ($seen[$key] -gt 1) { '__dup' + $seen[$key] } else { '' }
        $newValue = (ConvertTo-PositionIdentifier -Value $value -Position $Position) + $suffix
        if (-not $canonical.ContainsKey($value)) { $canonical[$value] = $newValue }
        $match.Groups['attr'].Value + '=' + $match.Groups['quote'].Value + $newValue + $match.Groups['quote'].Value
    }, [Text.RegularExpressions.RegexOptions]'IgnoreCase')
    $hrefPattern = '(?<attr>\bhref)\s*=\s*(?<quote>["''])#(?<value>.*?)(?:\k<quote>)'
    $converted = [regex]::Replace($converted, $hrefPattern, {
        param($match)
        $value = $match.Groups['value'].Value
        $target = if ($canonical.ContainsKey($value)) { $canonical[$value] } else { ConvertTo-PositionIdentifier -Value $value -Position $Position }
        $match.Groups['attr'].Value + '=' + $match.Groups['quote'].Value + '#' + $target + $match.Groups['quote'].Value
    }, [Text.RegularExpressions.RegexOptions]'IgnoreCase')
    $callPattern = '(?<function>showTC|switchAll|showTable|hideTable|switchTable)\(\s*(?<quote>["''])(?<argument>.*?)(?:\k<quote>)'
    $converted = [regex]::Replace($converted, $callPattern, {
        param($match)
        $match.Groups['function'].Value + '(' + $match.Groups['quote'].Value + $Position + '__' + $match.Groups['argument'].Value + $match.Groups['quote'].Value
    }, [Text.RegularExpressions.RegexOptions]'IgnoreCase')
    $documentAllPattern = 'document\.all\[(?<quote>["''])(?<identifier>.*?)(?:\k<quote>)\]'
    return [regex]::Replace($converted, $documentAllPattern, {
        param($match)
        $value = $match.Groups['identifier'].Value
        $target = if ($canonical.ContainsKey($value)) { $canonical[$value] } else { ConvertTo-PositionIdentifier -Value $value -Position $Position }
        'document.all[' + $match.Groups['quote'].Value + $target + $match.Groups['quote'].Value + ']'
    }, [Text.RegularExpressions.RegexOptions]'IgnoreCase')
}

function Get-PositionVerdict {
    param([object]$Statistics)
    if ($Statistics.Fail -gt 0 -or $Statistics.Error -gt 0 -or $Statistics.OutsideFail -gt 0 -or $Statistics.OutsideError -gt 0) { return 'Fail' }
    if ($Statistics.Inconclusive -gt 0 -or $Statistics.OutsideInconclusive -gt 0) { return 'NA' }
    if ($Statistics.Executed -gt 0 -and $Statistics.Pass -eq $Statistics.Executed) { return 'Pass' }
    return 'NA'
}

function New-CombinedOverviewHtml {
    param([object[]]$Reports)
    $rows = foreach ($report in $Reports) {
        $verdict = Get-PositionVerdict $report.Statistics
        $class = Get-VerdictCellClass $verdict
        '<tr data-overview-position="' + $report.Position + '"><td class="DefineCell"><a href="#position-' + $report.Position + '">' + $report.Position + '</a></td><td class="DefaultCell">' + [Net.WebUtility]::HtmlEncode($report.TestBegin) + '</td><td class="DefaultCell">' + [Net.WebUtility]::HtmlEncode($report.TestEnd) + '</td><td class="NumberCell">' + $report.Statistics.Executed + '</td><td class="NumberCellPositiveResult">' + $report.Statistics.Pass + '</td><td class="NumberCell">' + $report.Statistics.Fail + '</td><td class="NumberCell">' + $report.Statistics.Inconclusive + '</td><td class="NumberCell">' + $report.Statistics.Error + '</td><td class="NumberCell">' + $report.Statistics.OutsideInconclusive + '</td><td class="NumberCell">' + $report.Statistics.OutsideFail + '</td><td class="NumberCell">' + $report.Statistics.OutsideError + '</td><td class="' + $class + '">' + $verdict + '</td></tr>'
    }
    return @"
<div id="combined-overview" class="combined-overview">
<h1>RS4PE / LHD / DRV &middot; AST &middot; RL &middot; RR</h1>
<table class="OverviewTable metadata-table"><tr><td class="DefineCell">Project</td><td>RS4PE</td><td class="DefineCell">Drive Type</td><td>LHD</td></tr><tr><td class="DefineCell">Positions</td><td>DRV / AST / RL / RR</td><td class="DefineCell">EOL Variant</td><td>All_DTC_List (defined in test design)</td></tr></table>
<div class="position-navigation"><a href="#position-DRV">DRV</a><a href="#position-AST">AST</a><a href="#position-RL">RL</a><a href="#position-RR">RR</a></div>
<h2>Position Result Overview</h2><table class="OverviewTable"><tr><td class="DefineCell">Position</td><td class="DefineCell">Begin</td><td class="DefineCell">End</td><td class="DefineCell">Executed</td><td class="DefineCell">Pass</td><td class="DefineCell">Fail</td><td class="DefineCell">Inconclusive</td><td class="DefineCell">Error</td><td class="DefineCell">Outside Inconclusive</td><td class="DefineCell">Outside Fail</td><td class="DefineCell">Outside Error</td><td class="DefineCell">Verdict</td></tr>$($rows -join '')</table>
</div>
"@
}

function New-PositionSectionHtml {
    param([object]$Report)
    $body = ConvertTo-PrefixedBody -BodyHtml $Report.BodyHtml -Position $Report.Position
    return @"
<section id="position-$($Report.Position)" class="position-report" data-position="$($Report.Position)" data-source-file="$([Net.WebUtility]::HtmlEncode($Report.FileName))" data-source-record-count="$($Report.TestItems.Count)" data-executed="$($Report.Statistics.Executed)" data-pass="$($Report.Statistics.Pass)" data-fail="$($Report.Statistics.Fail)" data-inconclusive="$($Report.Statistics.Inconclusive)" data-error="$($Report.Statistics.Error)" data-outside-inconclusive="$($Report.Statistics.OutsideInconclusive)" data-outside-fail="$($Report.Statistics.OutsideFail)" data-outside-error="$($Report.Statistics.OutsideError)">
<div class="position-banner"><h2>$($Report.Project) / $($Report.DriveType) / $($Report.Position)</h2><a href="#combined-overview">Back to overview</a></div>
<!-- ORIGINAL_REPORT_$($Report.Position)_BEGIN -->$body<!-- ORIGINAL_REPORT_$($Report.Position)_END -->
<div class="position-footer"><a href="#combined-overview">Back to overview</a></div>
</section><!-- POSITION_$($Report.Position)_END -->
"@
}

function Get-IdentifierValues {
    param([string]$Html, [string]$Attribute)
    $pattern = '(?<![\w:-])' + [regex]::Escape($Attribute) + '\s*=\s*(?:"(?<double>[^"]*)"|''(?<single>[^'']*)'')'
    return @([regex]::Matches($Html, $pattern, [Text.RegularExpressions.RegexOptions]'IgnoreCase') | ForEach-Object {
        if ($_.Groups['double'].Success) { $_.Groups['double'].Value } else { $_.Groups['single'].Value }
    })
}

function Get-PositionSectionFromOutput {
    param([string]$Html, [string]$Position)
    $startToken = '<section id="position-' + $Position + '"'
    $endToken = '<!-- POSITION_' + $Position + '_END -->'
    $start = $Html.IndexOf($startToken, [StringComparison]::Ordinal)
    $end = if ($start -ge 0) { $Html.IndexOf($endToken, $start, [StringComparison]::Ordinal) } else { -1 }
    if ($start -lt 0 -or $end -lt 0) { throw "Position section missing: $Position" }
    return $Html.Substring($start, ($end + $endToken.Length) - $start)
}

function Test-CombinedReport {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object[]]$Reports)
    $ordered = @(Assert-ReportSet -Reports $Reports)
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $html = [IO.File]::ReadAllText($resolved, [Text.Encoding]::UTF8)
    if ($html -notmatch '(?is)<html\b[^>]*>.*</html\s*>' -or -not $html.Contains('RS4PE / LHD / DRV')) { throw 'Combined HTML structure is invalid.' }

    $ids = @(Get-IdentifierValues -Html $html -Attribute 'id')
    $names = @(Get-IdentifierValues -Html $html -Attribute 'name')
    foreach ($collection in @($ids, $names)) {
        $duplicates = @($collection | Group-Object | Where-Object Count -gt 1)
        if ($duplicates.Count -gt 0) { throw "Duplicate identifier: $($duplicates[0].Name)" }
    }
    $targets = @{}
    foreach ($identifier in @($ids + $names)) { $targets[$identifier] = $true }
    $unresolved = [Collections.Generic.List[string]]::new()
    $fragmentMatches = [regex]::Matches($html, '\bhref\s*=\s*(?:"#(?<double>[^"]+)"|''#(?<single>[^'']+)'')', [Text.RegularExpressions.RegexOptions]'IgnoreCase')
    foreach ($match in $fragmentMatches) {
        $target = if ($match.Groups['double'].Success) { $match.Groups['double'].Value } else { $match.Groups['single'].Value }
        if (-not $targets.ContainsKey([Net.WebUtility]::HtmlDecode($target))) { $unresolved.Add($target) }
    }
    if ($unresolved.Count -gt 0) { throw "Unresolved fragment link: $($unresolved[0])" }

    $positionResults = foreach ($report in $ordered) {
        $section = Get-PositionSectionFromOutput -Html $html -Position $report.Position
        $begin = '<!-- ORIGINAL_REPORT_' + $report.Position + '_BEGIN -->'
        $end = '<!-- ORIGINAL_REPORT_' + $report.Position + '_END -->'
        $bodyStart = $section.IndexOf($begin, [StringComparison]::Ordinal)
        $bodyEnd = $section.IndexOf($end, $bodyStart + $begin.Length, [StringComparison]::Ordinal)
        if ($bodyStart -lt 0 -or $bodyEnd -lt 0) { throw "Original report body missing: $($report.Position)" }
        $embedded = $section.Substring($bodyStart + $begin.Length, $bodyEnd - ($bodyStart + $begin.Length))
        $expected = ConvertTo-PrefixedBody -BodyHtml $report.BodyHtml -Position $report.Position
        if ($embedded -ne $expected) { throw "Embedded report body mismatch: $($report.Position)" }

        $expectedAttributes = @{
            'data-source-record-count' = $report.TestItems.Count
            'data-executed' = $report.Statistics.Executed
            'data-pass' = $report.Statistics.Pass
            'data-fail' = $report.Statistics.Fail
            'data-inconclusive' = $report.Statistics.Inconclusive
            'data-error' = $report.Statistics.Error
            'data-outside-inconclusive' = $report.Statistics.OutsideInconclusive
            'data-outside-fail' = $report.Statistics.OutsideFail
            'data-outside-error' = $report.Statistics.OutsideError
        }
        foreach ($key in $expectedAttributes.Keys) {
            if ($section -notmatch ([regex]::Escape($key + '="' + $expectedAttributes[$key] + '"'))) { throw "Displayed statistics mismatch: $($report.Position)/$key" }
        }
        $currentHash = (Get-FileHash -LiteralPath $report.Path -Algorithm SHA256).Hash
        if ($currentHash -ne $report.SourceHash) { throw "Source hash changed: $($report.Position)" }
        [pscustomobject]@{ Position = $report.Position; RecordCount = $report.TestItems.Count; Executed = $report.Statistics.Executed; Verdict = Get-PositionVerdict $report.Statistics }
    }
    [pscustomobject]@{
        Path = $resolved
        OutputHash = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash
        UnresolvedLinkCount = $unresolved.Count
        Positions = @($positionResults)
    }
}

function New-CombinedReport {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object[]]$Reports, [Parameter(Mandatory = $true)][string]$OutputPath)
    $ordered = @(Assert-ReportSet -Reports $Reports)
    $outputFullPath = [IO.Path]::GetFullPath($OutputPath)
    foreach ($report in $ordered) {
        if ([StringComparer]::OrdinalIgnoreCase.Equals([IO.Path]::GetFullPath($report.Path), $outputFullPath)) {
            throw "OutputPath must not match a source report: $($report.FileName)"
        }
    }
    $parent = Split-Path -Parent $outputFullPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $sourceHead = [regex]::Replace($ordered[0].HeadHtml, '(?is)<title\b[^>]*>.*?</title\s*>', '')
    $overview = New-CombinedOverviewHtml -Reports $ordered
    $functionalSummary = New-CombinedFunctionalSummaryHtml -Reports $ordered
    $sections = @($ordered | ForEach-Object { New-PositionSectionHtml -Report $_ })
    $html = @"
<!DOCTYPE html><html><head><meta charset="utf-8"><title>RS4PE LHD Combined Test Report</title>$sourceHead
<style>
html{scroll-behavior:smooth} body{margin:0;background:#f4f7fb;color:#172b4d}.combined-overview,.combined-functional-summary,.position-report{max-width:1500px;margin:18px auto;padding:22px;background:#fff;border:1px solid #b8c8dd;border-radius:8px;box-shadow:0 2px 8px rgba(28,69,120,.12)}.combined-overview h1,.position-banner h2{color:#0b4f9c}.position-navigation{display:flex;gap:10px;margin:18px 0}.position-navigation a,.position-banner a,.position-footer a{background:#1769aa;color:#fff!important;padding:8px 16px;border-radius:5px;text-decoration:none}.position-banner{display:flex;justify-content:space-between;align-items:center;border-bottom:3px solid #1769aa;margin-bottom:15px}.summary-toggle,.tc-toggle{cursor:pointer;border:1px solid #6689b8;background:#eaf2ff;color:#173b6c;border-radius:4px;padding:4px 9px}.nested-table{width:calc(100% - 24px)!important;margin:6px 0 6px 24px}.position-footer{margin-top:24px;padding-top:12px;border-top:1px solid #b8c8dd}.metadata-table{margin-bottom:12px}.combined-summary-table{width:100%}.position-cell,.area-cell{vertical-align:top}.combined-functional-summary .Heading4{font-size:1.35em;color:#0b4f9c;margin-bottom:12px}
</style>
<script>function toggleCombinedReport(id,button){var node=document.getElementById(id);if(!node){return;}var open=node.style.display==='none';node.style.display=open?'block':'none';button.setAttribute('aria-expanded',open?'true':'false');}</script>
</head><body>$overview$functionalSummary$($sections -join '')</body></html>
"@
    $tempPath = Join-Path $parent ('.combined-build-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($tempPath, $html, [Text.UTF8Encoding]::new($false))
        Test-CombinedReport -Path $tempPath -Reports $ordered | Out-Null
        Move-Item -LiteralPath $tempPath -Destination $outputFullPath -Force
        return Test-CombinedReport -Path $outputFullPath -Reports $ordered
    } finally {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }
}

function Publish-VerifiedReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$PublishPath
    )
    $source = (Resolve-Path -LiteralPath $SourcePath).Path
    $publishFullPath = [IO.Path]::GetFullPath($PublishPath)
    if ($source -eq $publishFullPath) { throw 'SourcePath and PublishPath must be different.' }
    $publishDirectory = Split-Path -Parent $publishFullPath
    if (-not (Test-Path -LiteralPath $publishDirectory)) { New-Item -ItemType Directory -Path $publishDirectory -Force | Out-Null }

    $tempPath = Join-Path $publishDirectory ('.combined-report-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $backupPath = $null
    try {
        Copy-Item -LiteralPath $source -Destination $tempPath
        $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        $tempHash = (Get-FileHash -LiteralPath $tempPath -Algorithm SHA256).Hash
        if ($sourceHash -ne $tempHash) { throw 'Staged publish file hash mismatch.' }
        if (Test-Path -LiteralPath $publishFullPath) {
            $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
            $backupPath = $publishFullPath + '.bak_' + $stamp
            $counter = 1
            while (Test-Path -LiteralPath $backupPath) {
                $backupPath = $publishFullPath + '.bak_' + $stamp + '_' + $counter
                $counter++
            }
            Copy-Item -LiteralPath $publishFullPath -Destination $backupPath
        }
        Copy-Item -LiteralPath $tempPath -Destination $publishFullPath -Force
        $publishedHash = (Get-FileHash -LiteralPath $publishFullPath -Algorithm SHA256).Hash
        if ($publishedHash -ne $sourceHash) { throw 'Published file hash mismatch.' }
        [pscustomobject]@{ SourcePath = $source; PublishPath = $publishFullPath; BackupPath = $backupPath; Hash = $publishedHash }
    } finally {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function Get-ReportModel, Assert-ReportSet, New-CombinedReport, Test-CombinedReport, Publish-VerifiedReport
