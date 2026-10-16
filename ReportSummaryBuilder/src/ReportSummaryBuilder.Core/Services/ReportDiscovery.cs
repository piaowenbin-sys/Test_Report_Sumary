using ReportSummaryBuilder.Core.Errors;

namespace ReportSummaryBuilder.Core.Services;

public sealed class ReportDiscovery
{
    private static readonly string[] GeneratedNameMarkers =
    [
        "Combined_Test_Report",
        "Summary",
        ".bak_"
    ];

    public IReadOnlyList<string> Find(string inputDirectory)
    {
        if (string.IsNullOrWhiteSpace(inputDirectory) || !Directory.Exists(inputDirectory))
        {
            throw new ReportInputException("입력 폴더 오류", "입력 폴더를 찾을 수 없습니다.", inputDirectory ?? string.Empty);
        }

        var candidates = Directory.EnumerateFiles(inputDirectory, "*.html", SearchOption.TopDirectoryOnly)
            .Where(path => !GeneratedNameMarkers.Any(marker =>
                Path.GetFileName(path).Contains(marker, StringComparison.OrdinalIgnoreCase)))
            .Where(IsOriginalVectorReport)
            .OrderBy(path => path, StringComparer.OrdinalIgnoreCase)
            .ToArray();

        if (candidates.Length == 0)
        {
            throw new ReportInputException("입력 리포트 오류", "원본 Vector HTML 리포트를 찾을 수 없습니다.");
        }

        return candidates;
    }

    private static bool IsOriginalVectorReport(string path)
    {
        using var reader = new StreamReader(path, detectEncodingFromByteOrderMarks: true);
        var text = reader.ReadToEnd();
        return text.Contains("Var_Project:", StringComparison.OrdinalIgnoreCase)
            && text.Contains("Var_SBCM_Position:", StringComparison.OrdinalIgnoreCase)
            && text.Contains(">Statistics<", StringComparison.OrdinalIgnoreCase)
            && text.Contains(">Test Results<", StringComparison.OrdinalIgnoreCase);
    }
}
