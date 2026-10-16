using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using ReportSummaryBuilder.Core.Models;

namespace ReportSummaryBuilder.Core.Services;

public sealed partial class SummaryHtmlGenerator
{
    private sealed record Group(string Area, string Key, string Label, Regex? Pattern);

    private static readonly Group[] Groups =
    [
        new("Diagnostic", "C104", "C104", null),
        new("", "ForceControl", "강제구동", ForceControlPattern()),
        new("", "ECU_ID", "ECU ID", EcuIdPattern()),
        new("Input", "PWM", "PWM", PwmPattern()),
        new("", "Switch", "Switch", SwitchPattern()),
        new("", "Sensor", "Sensor", SensorPattern()),
        new("", "Vbat", "Vbat", VbatPattern()),
        new("Output", "HS", "HS", HsPattern()),
        new("", "Motor", "Motor", MotorPattern())
    ];

    public string Generate(IReadOnlyList<ReportModel> reports, string detailDirectoryName)
    {
        ArgumentNullException.ThrowIfNull(reports);
        if (reports.Count == 0) throw new ArgumentException("At least one report is required.", nameof(reports));

        var html = new StringBuilder(16_384);
        html.Append("""
            <!doctype html><html lang="ko"><head><meta charset="utf-8">
            <meta name="viewport" content="width=device-width,initial-scale=1">
            <title>통합 테스트 리포트 서머리</title>
            <style>
            :root{--blue:#0b4f9c;--line:#b8c8dd;--bg:#f4f7fb;--pass:#137333;--fail:#b3261e}
            *{box-sizing:border-box}body{margin:0;padding:24px;background:var(--bg);font-family:"Segoe UI",Arial,sans-serif;color:#172b4d}
            main{max-width:1500px;margin:auto;background:#fff;border:1px solid var(--line);border-radius:10px;padding:24px;box-shadow:0 2px 10px #1c45781f}
            h1,h2{color:var(--blue)}table{width:100%;border-collapse:collapse;margin:12px 0 24px}th,td{border:1px solid var(--line);padding:8px;text-align:left;vertical-align:top}
            th{background:#eaf2ff}.position{background:#f6f9fe;font-weight:700}.Pass{color:var(--pass);font-weight:700}.Fail{color:var(--fail);font-weight:700}.NA{color:#5f6368}
            button{cursor:pointer;border:1px solid #6689b8;background:#eaf2ff;color:#173b6c;border-radius:4px;padding:5px 9px}.details{display:none;margin-top:8px}.nested{margin:8px 0 0 20px;width:calc(100% - 20px)}
            a{color:#075ca8}.meta{display:flex;gap:20px;flex-wrap:wrap}.meta span{background:#eef4fc;padding:7px 10px;border-radius:5px}
            </style>
            <script>function toggleDetails(id,b){const e=document.getElementById(id);const o=e.style.display!=="block";e.style.display=o?"block":"none";b.setAttribute("aria-expanded",o);}</script>
            </head><body><main><h1>통합 테스트 리포트 서머리</h1>
            """);

        var drives = string.Join(" / ", reports.Select(report => report.DriveType).Distinct(StringComparer.OrdinalIgnoreCase));
        html.Append("<div class=\"meta\"><span><b>차종</b> ").Append(Encode(reports[0].Project))
            .Append("</span><span><b>Drive</b> ").Append(Encode(drives))
            .Append("</span><span><b>리포트</b> ").Append(reports.Count).Append("개</span></div>");

        html.Append("<h2>위치별 결과</h2><table><thead><tr><th>Position</th><th>Executed</th><th>Pass</th><th>Fail</th><th>상세 리포트</th></tr></thead><tbody>");
        foreach (var report in reports)
        {
            var detailFile = ReportPackageGenerator.GetDetailFileName(report);
            html.Append("<tr><td>").Append(Encode(report.Position)).Append("</td><td>").Append(report.Statistics.Executed)
                .Append("</td><td class=\"Pass\">").Append(report.Statistics.Pass).Append("</td><td class=\"Fail\">")
                .Append(report.Statistics.Fail).Append("</td><td><a href=\"").Append(Link(detailDirectoryName, detailFile, null))
                .Append("\">원본 상세 보기</a></td></tr>");
        }
        html.Append("</tbody></table><h2>Integrated Functional Test Summary</h2><table><thead><tr><th>Position</th><th>Area</th><th>Category</th><th>Results and details</th></tr></thead>");

        foreach (var report in reports)
        {
            AppendPosition(html, report, detailDirectoryName);
        }

        html.Append("</table></main></body></html>");
        return html.ToString();
    }

    private static void AppendPosition(StringBuilder html, ReportModel report, string detailDirectoryName)
    {
        html.Append("<tbody data-summary-position=\"").Append(Encode(report.Position)).Append("\">");
        for (var index = 0; index < Groups.Length; index++)
        {
            var group = Groups[index];
            var matches = SelectItems(report.TestItems, group).ToArray();
            var id = $"{SafeId(report.Position)}-group-{index}";
            var pass = matches.Count(item => item.EffectiveVerdict == "Pass");
            var fail = matches.Count(item => item.EffectiveVerdict == "Fail");
            var na = matches.Length - pass - fail;

            html.Append("<tr data-category=\"").Append(group.Key).Append("\">");
            if (index == 0) html.Append("<td class=\"position\" rowspan=\"9\">").Append(Encode($"{report.Project} / {report.DriveType} / {report.Position}")).Append("</td>");
            if (index == 0) html.Append("<td rowspan=\"3\"><b>Diagnostic</b></td>");
            if (index == 3) html.Append("<td rowspan=\"4\"><b>Input</b></td>");
            if (index == 7) html.Append("<td rowspan=\"2\"><b>Output</b></td>");
            html.Append("<td><b>").Append(Encode(group.Label)).Append("</b></td><td><button type=\"button\" onclick=\"toggleDetails('")
                .Append(id).Append("',this)\">").Append(Encode(group.Label)).Append(" (").Append(matches.Length)
                .Append(") | Pass ").Append(pass).Append(" | Fail ").Append(fail).Append(" | NA ").Append(na)
                .Append(" - 상세 보기</button><div class=\"details\" id=\"").Append(id).Append("\"><table><tr><th>TC</th><th>Test item</th><th>Verdict</th><th>Children</th></tr>");

            if (matches.Length == 0)
            {
                html.Append("<tr><td colspan=\"4\">매칭된 테스트 항목 없음</td></tr>");
            }
            else
            {
                for (var itemIndex = 0; itemIndex < matches.Length; itemIndex++)
                {
                    AppendItem(html, report, detailDirectoryName, matches[itemIndex], itemIndex, index);
                }
            }
            html.Append("</table></div></td></tr>");
        }
        html.Append("</tbody>");
    }

    private static void AppendItem(StringBuilder html, ReportModel report, string detailDirectoryName, TestItem item, int itemIndex, int groupIndex)
    {
        var descendants = report.TestItems.Where(candidate => candidate.Number.StartsWith(item.Number + ".", StringComparison.Ordinal)).ToArray();
        var detailFile = ReportPackageGenerator.GetDetailFileName(report);
        var childId = $"{SafeId(report.Position)}-children-{groupIndex}-{itemIndex}";
        html.Append("<tr><td>").Append(Encode(item.Number)).Append("</td><td><a href=\"")
            .Append(Link(detailDirectoryName, detailFile, item.Href)).Append("\">").Append(Encode(item.Text))
            .Append("</a></td><td class=\"").Append(item.EffectiveVerdict).Append("\">").Append(item.EffectiveVerdict).Append("</td><td>");
        if (descendants.Length > 0)
        {
            html.Append("<button type=\"button\" onclick=\"toggleDetails('").Append(childId).Append("',this)\">하위 TC ")
                .Append(descendants.Length).Append("개</button>");
        }
        html.Append("</td></tr>");

        if (descendants.Length == 0) return;
        html.Append("<tr><td colspan=\"4\"><div class=\"details\" id=\"").Append(childId).Append("\"><table class=\"nested\"><tr><th>하위 TC</th><th>Test item</th><th>Verdict</th></tr>");
        foreach (var child in descendants)
        {
            html.Append("<tr><td>").Append(Encode(child.Number)).Append("</td><td><a href=\"")
                .Append(Link(detailDirectoryName, detailFile, child.Href)).Append("\">").Append(Encode(child.Text))
                .Append("</a></td><td class=\"").Append(child.EffectiveVerdict).Append("\">").Append(child.EffectiveVerdict).Append("</td></tr>");
        }
        html.Append("</table></div></td></tr>");
    }

    private static IEnumerable<TestItem> SelectItems(IReadOnlyList<TestItem> items, Group group)
    {
        if (group.Key == "C104")
        {
            var parent = items.FirstOrDefault(item => item.Text.Contains("C104", StringComparison.OrdinalIgnoreCase));
            return parent is null ? [] : [parent];
        }

        var matches = items.Where(item => group.Pattern!.IsMatch(item.Text));
        if (group.Key != "Switch") return matches;
        var c104 = items.FirstOrDefault(item => item.Text.Contains("C104", StringComparison.OrdinalIgnoreCase));
        return c104 is null ? matches : matches.Where(item => !item.Number.StartsWith(c104.Number + ".", StringComparison.Ordinal));
    }

    private static string Link(string directory, string file, string? fragment)
    {
        var href = $"{Uri.EscapeDataString(directory)}/{Uri.EscapeDataString(file)}";
        if (!string.IsNullOrWhiteSpace(fragment)) href += fragment.StartsWith('#') ? fragment : "#" + fragment;
        return WebUtility.HtmlEncode(href);
    }

    private static string SafeId(string value) => Regex.Replace(value, "[^A-Za-z0-9_-]", "_");
    private static string Encode(string value) => WebUtility.HtmlEncode(value);

    [GeneratedRegex("^IO_Control_Check_", RegexOptions.IgnoreCase)] private static partial Regex ForceControlPattern();
    [GeneratedRegex("(^|_)DID_Check$|ECU[ _-]?ID", RegexOptions.IgnoreCase)] private static partial Regex EcuIdPattern();
    [GeneratedRegex("^P_CRASH_UNLOCK_IN$", RegexOptions.IgnoreCase)] private static partial Regex PwmPattern();
    [GeneratedRegex("_SW_IN$", RegexOptions.IgnoreCase)] private static partial Regex SwitchPattern();
    [GeneratedRegex("SNSR_IN|^A_IS_ECM_V_IN$|^P_HALL_", RegexOptions.IgnoreCase)] private static partial Regex SensorPattern();
    [GeneratedRegex("^B\\+_POWER$|^VBAT$", RegexOptions.IgnoreCase)] private static partial Regex VbatPattern();
    [GeneratedRegex("^(L_DEFOG_OUT|L_ECM_V_OUT)", RegexOptions.IgnoreCase)] private static partial Regex HsPattern();
    [GeneratedRegex("_MTR_", RegexOptions.IgnoreCase)] private static partial Regex MotorPattern();
}
