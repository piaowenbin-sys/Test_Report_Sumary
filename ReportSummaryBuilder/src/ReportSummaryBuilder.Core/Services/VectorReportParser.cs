using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using HtmlAgilityPack;
using ReportSummaryBuilder.Core.Errors;
using ReportSummaryBuilder.Core.Models;

namespace ReportSummaryBuilder.Core.Services;

public sealed class VectorReportParser
{
    public ReportModel Parse(string path)
    {
        if (!File.Exists(path))
        {
            throw new ReportInputException("리포트 읽기 오류", "HTML 리포트를 찾을 수 없습니다.", path);
        }

        try
        {
            var bytes = File.ReadAllBytes(path);
            var document = new HtmlDocument();
            document.Load(new MemoryStream(bytes), detectEncodingFromByteOrderMarks: true);

            var project = ReadLabel(document, "Var_Project:");
            var driveType = ReadLabel(document, "Var_Drive_Type:");
            var position = ReadLabel(document, "Var_SBCM_Position:");
            var eolVariant = ReadLabel(document, "Var_EOL_Variant_Type:");
            var testBegin = ReadLabel(document, "Test begin:");
            var testEnd = ReadLabel(document, "Test end:");

            if (string.IsNullOrWhiteSpace(project) || string.IsNullOrWhiteSpace(position))
            {
                throw new ReportInputException("리포트 형식 오류", "필수 메타데이터를 읽을 수 없습니다.", Path.GetFileName(path));
            }

            var statisticsTable = FindSectionTable(document, "Statistics");
            var resultTable = FindSectionTable(document, "Test Results");
            var statistics = ParseStatistics(statisticsTable);
            var testItems = ParseTestItems(resultTable);

            return new ReportModel(
                Path.GetFullPath(path),
                Path.GetFileName(path),
                project,
                driveType,
                position,
                eolVariant,
                testBegin,
                testEnd,
                statistics,
                testItems,
                Convert.ToHexString(SHA256.HashData(bytes)));
        }
        catch (ReportInputException)
        {
            throw;
        }
        catch (Exception exception)
        {
            throw new ReportInputException("리포트 읽기 오류", "HTML 리포트를 분석할 수 없습니다.", $"{Path.GetFileName(path)}: {exception.Message}");
        }
    }

    private static string ReadLabel(HtmlDocument document, string label)
    {
        var cell = document.DocumentNode.SelectNodes("//td")?
            .FirstOrDefault(node => Normalize(node.InnerText).Equals(Normalize(label), StringComparison.OrdinalIgnoreCase));
        var valueCell = cell?.SelectSingleNode("following-sibling::td[1]");
        return Normalize(valueCell?.InnerText ?? string.Empty);
    }

    private static HtmlNode FindSectionTable(HtmlDocument document, string heading)
    {
        var headingNode = document.DocumentNode.SelectNodes("//div")?
            .FirstOrDefault(node => Normalize(node.InnerText).Equals(heading, StringComparison.OrdinalIgnoreCase));
        var cursor = headingNode?.NextSibling;

        while (cursor is not null)
        {
            if (cursor.NodeType == HtmlNodeType.Element && cursor.Name.Equals("div", StringComparison.OrdinalIgnoreCase)
                && cursor.GetClasses().Contains("Heading4") && !ReferenceEquals(cursor, headingNode))
            {
                break;
            }

            if (cursor.NodeType == HtmlNodeType.Element)
            {
                var table = cursor.Name.Equals("table", StringComparison.OrdinalIgnoreCase)
                    ? cursor
                    : cursor.SelectSingleNode(".//table");
                if (table is not null)
                {
                    return table;
                }
            }

            cursor = cursor.NextSibling;
        }

        throw new ReportInputException("리포트 형식 오류", $"{heading} 표를 읽을 수 없습니다.");
    }

    private static ReportStatistics ParseStatistics(HtmlNode table)
    {
        var rows = DirectRows(table).Select(RowValues).Where(values => values.Length >= 2).ToArray();
        var outsideIndex = Array.FindIndex(rows, values => LabelEquals(values[0], "Number of failures outside of test cases"));

        int Main(string label)
        {
            var match = rows.FirstOrDefault(values => LabelEquals(values[0], label));
            return ParseInteger(match is { Length: > 1 } ? match[1] : null);
        }
        int Outside(string label)
        {
            if (outsideIndex < 0)
            {
                return 0;
            }

            var match = rows.Skip(outsideIndex + 1).FirstOrDefault(values => LabelEquals(values[0], label));
            return ParseInteger(match is { Length: > 1 } ? match[1] : null);
        }

        return new ReportStatistics(
            Main("Executed test cases"),
            Main("Test cases passed"),
            Main("Test cases failed"),
            Main("Test cases inconclusive"),
            Main("Test cases with error in test system"),
            Outside("Inconclusive"),
            Outside("Fail"),
            Outside("Error in test system"));
    }

    private static IReadOnlyList<TestItem> ParseTestItems(HtmlNode table)
    {
        var raw = new List<MutableTestItem>();
        foreach (var row in DirectRows(table))
        {
            var cells = row.SelectNodes("./td");
            if (cells is null || cells.Count < 2)
            {
                continue;
            }

            var number = Normalize(cells[0].InnerText);
            var anchor = cells[1].SelectSingleNode(".//a[@href]");
            if (!IsTestNumber(number) || anchor is null)
            {
                continue;
            }

            var resultText = string.Join(" ", cells.Skip(2).Select(cell => Normalize(cell.InnerText)));
            var directVerdict = ContainsWord(resultText, "fail") ? "Fail"
                : ContainsWord(resultText, "pass") ? "Pass"
                : "NA";

            raw.Add(new MutableTestItem(number, anchor.GetAttributeValue("href", string.Empty), Normalize(anchor.InnerText), directVerdict));
        }

        foreach (var item in raw.OrderByDescending(item => SegmentCount(item.Number)))
        {
            if (item.DirectVerdict != "NA")
            {
                item.EffectiveVerdict = item.DirectVerdict;
                continue;
            }

            var children = raw.Where(candidate => IsImmediateChild(item.Number, candidate.Number)).ToArray();
            item.EffectiveVerdict = children.Length == 0 ? "NA"
                : children.Any(child => child.EffectiveVerdict == "Fail") ? "Fail"
                : children.All(child => child.EffectiveVerdict == "Pass") ? "Pass"
                : "NA";
        }

        return raw.Select(item => new TestItem(item.Number, item.Href, item.Text, item.DirectVerdict, item.EffectiveVerdict)).ToArray();
    }

    private static IEnumerable<HtmlNode> DirectRows(HtmlNode table) =>
        table.SelectNodes("./tr|./tbody/tr") ?? Enumerable.Empty<HtmlNode>();

    private static string[] RowValues(HtmlNode row) =>
        (row.SelectNodes("./td") ?? Enumerable.Empty<HtmlNode>()).Select(cell => Normalize(cell.InnerText)).ToArray();

    private static int ParseInteger(string? value) => int.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var number) ? number : 0;
    private static bool LabelEquals(string value, string label) => Normalize(value).Equals(label, StringComparison.OrdinalIgnoreCase);
    private static bool ContainsWord(string value, string word) => value.Split([' ', '\r', '\n', '\t'], StringSplitOptions.RemoveEmptyEntries).Contains(word, StringComparer.OrdinalIgnoreCase);
    private static bool IsTestNumber(string value) => value.Length > 0 && value.Split('.').All(segment => int.TryParse(segment, out _));
    private static int SegmentCount(string number) => number.Count(character => character == '.') + 1;
    private static bool IsImmediateChild(string parent, string candidate) => candidate.StartsWith(parent + ".", StringComparison.Ordinal) && SegmentCount(candidate) == SegmentCount(parent) + 1;
    private static string Normalize(string value) => HtmlEntity.DeEntitize(value).Replace('\u00A0', ' ').Trim();

    private sealed class MutableTestItem(string number, string href, string text, string directVerdict)
    {
        public string Number { get; } = number;
        public string Href { get; } = href;
        public string Text { get; } = text;
        public string DirectVerdict { get; } = directVerdict;
        public string EffectiveVerdict { get; set; } = "NA";
    }
}
