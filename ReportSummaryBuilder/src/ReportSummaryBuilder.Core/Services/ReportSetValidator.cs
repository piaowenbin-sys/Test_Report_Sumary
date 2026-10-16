using ReportSummaryBuilder.Core.Errors;
using ReportSummaryBuilder.Core.Models;

namespace ReportSummaryBuilder.Core.Services;

public sealed class ReportSetValidator
{
    public IReadOnlyList<ReportModel> Validate(IReadOnlyList<ReportModel> reports)
    {
        if (reports.Count == 0)
        {
            throw new ReportInputException("입력 리포트 오류", "처리할 리포트가 없습니다.");
        }

        var projects = reports.Select(report => report.Project.Trim())
            .Where(value => value.Length > 0)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(value => value, StringComparer.OrdinalIgnoreCase)
            .ToArray();

        if (projects.Length != 1)
        {
            throw new ReportInputException(
                "리포트 조합 오류",
                "동일 차종의 리포트가 아닙니다.",
                $"감지된 차종: {string.Join(", ", projects.Select(value => string.IsNullOrWhiteSpace(value) ? "(없음)" : value))}");
        }

        var duplicates = reports.GroupBy(report => report.Position.Trim(), StringComparer.OrdinalIgnoreCase)
            .Where(group => string.IsNullOrWhiteSpace(group.Key) || group.Count() > 1)
            .Select(group => string.IsNullOrWhiteSpace(group.Key) ? "(없음)" : group.Key)
            .OrderBy(value => value, StringComparer.OrdinalIgnoreCase)
            .ToArray();

        if (duplicates.Length > 0)
        {
            throw new ReportInputException(
                "포지션 중복 오류",
                "동일 포지션 리포트가 중복되었습니다.",
                $"중복 포지션: {string.Join(", ", duplicates)}");
        }

        return reports.OrderBy(report => PositionOrder(report.Position))
            .ThenBy(report => report.Position, StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    private static int PositionOrder(string position) => position.ToUpperInvariant() switch
    {
        "DRV" => 0,
        "AST" => 1,
        "RL" => 2,
        "RR" => 3,
        _ => 100
    };
}
