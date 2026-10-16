using ReportSummaryBuilder.Core.Services;

namespace ReportSummaryBuilder.Core.Tests;

public sealed class VectorReportParserTests : IDisposable
{
    private readonly string _directory = Path.Combine(Path.GetTempPath(), $"VectorParser-{Guid.NewGuid():N}");

    public VectorReportParserTests() => Directory.CreateDirectory(_directory);

    [Fact]
    public void Parse_ReadsMetadataStatisticsAndEffectiveVerdicts()
    {
        var path = Path.Combine(_directory, "sample.html");
        File.WriteAllText(path, ReportDiscoveryTests.MinimalVectorReport("RS4PE", "DRV"));

        var report = new VectorReportParser().Parse(path);

        Assert.Equal("RS4PE", report.Project);
        Assert.Equal("LHD", report.DriveType);
        Assert.Equal("DRV", report.Position);
        Assert.Equal(2, report.Statistics.Executed);
        Assert.Equal(1, report.Statistics.Pass);
        Assert.Equal(1, report.Statistics.Fail);
        Assert.Equal(3, report.TestItems.Count);
        Assert.Equal("Fail", report.TestItems[0].EffectiveVerdict);
        Assert.Equal("Pass", report.TestItems[1].EffectiveVerdict);
        Assert.Equal("Fail", report.TestItems[2].EffectiveVerdict);
        Assert.NotEmpty(report.SourceHash);
    }

    [Theory]
    [InlineData("Executed test cases", "Executed cases renamed")]
    [InlineData("<td>2</td>", "<td>not-a-number</td>")]
    public void Parse_WhenRequiredStatisticsAreInvalid_RejectsReport(string original, string replacement)
    {
        var path = Path.Combine(_directory, "invalid-statistics.html");
        File.WriteAllText(path, ReportDiscoveryTests.MinimalVectorReport("RS4PE", "DRV").Replace(original, replacement));

        var error = Assert.Throws<Errors.ReportInputException>(() => new VectorReportParser().Parse(path));

        Assert.Equal("리포트 형식 오류", error.Title);
    }

    [Theory]
    [InlineData(@"C:\Users\USER.K1109684\Downloads\TestReport\2026-10-08_08-18-49_RS4_Test_Report.html", "DRV", 132, 110, 22, 179)]
    [InlineData(@"C:\Users\USER.K1109684\Downloads\TestReport\2026-10-08_11-01-20_RS4_Test_Report.html", "RR", 102, 102, 0, 149)]
    public void Parse_MatchesKnownOriginalReports(string path, string position, int executed, int passed, int failed, int itemCount)
    {
        Assert.True(File.Exists(path), $"Required read-only integration fixture is missing: {path}");

        var report = new VectorReportParser().Parse(path);

        Assert.Equal("RS4PE", report.Project);
        Assert.Equal("LHD", report.DriveType);
        Assert.Equal(position, report.Position);
        Assert.Equal(executed, report.Statistics.Executed);
        Assert.Equal(passed, report.Statistics.Pass);
        Assert.Equal(failed, report.Statistics.Fail);
        Assert.Equal(itemCount, report.TestItems.Count);
        Assert.Equal("1", report.TestItems[0].Number);
        Assert.Equal("HardwireTest", report.TestItems[0].Text);
    }

    public void Dispose() => Directory.Delete(_directory, recursive: true);
}
