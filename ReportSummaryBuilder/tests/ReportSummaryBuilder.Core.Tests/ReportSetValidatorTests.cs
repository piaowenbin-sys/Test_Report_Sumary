using ReportSummaryBuilder.Core.Errors;
using ReportSummaryBuilder.Core.Models;
using ReportSummaryBuilder.Core.Services;

namespace ReportSummaryBuilder.Core.Tests;

public sealed class ReportSetValidatorTests
{
    [Fact]
    public void Validate_AllowsDifferentPositionsDriveTypesAndEolVariants()
    {
        var reports = new[]
        {
            Report("RS4PE", "LHD", "DRV", "A"),
            Report("RS4PE", "RHD", "RR", "B")
        };

        var result = new ReportSetValidator().Validate(reports);

        Assert.Equal(2, result.Count);
    }

    [Fact]
    public void Validate_WhenProjectsDiffer_UsesExactRequestedPopupText()
    {
        var error = Assert.Throws<ReportInputException>(() => new ReportSetValidator().Validate([
            Report("RS4PE", "LHD", "DRV", "A"),
            Report("NE1aW", "LHD", "RR", "A")
        ]));

        Assert.Equal("리포트 조합 오류", error.Title);
        Assert.Equal("동일 차종의 리포트가 아닙니다.", error.UserMessage);
        Assert.Contains("NE1aW", error.Details);
        Assert.Contains("RS4PE", error.Details);
    }

    [Fact]
    public void Validate_WhenPositionIsDuplicated_RejectsSetSeparately()
    {
        var error = Assert.Throws<ReportInputException>(() => new ReportSetValidator().Validate([
            Report("RS4PE", "LHD", "DRV", "A"),
            Report("RS4PE", "LHD", "DRV", "A")
        ]));

        Assert.Equal("포지션 중복 오류", error.Title);
    }

    private static ReportModel Report(string project, string driveType, string position, string eol) => new(
        $"{position}.html", $"{position}.html", project, driveType, position, eol, "begin", "end",
        new ReportStatistics(1, 1, 0, 0, 0, 0, 0, 0), [], "hash");
}
