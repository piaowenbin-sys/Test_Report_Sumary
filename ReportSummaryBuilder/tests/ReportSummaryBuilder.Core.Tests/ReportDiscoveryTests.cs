using ReportSummaryBuilder.Core.Services;

namespace ReportSummaryBuilder.Core.Tests;

public sealed class ReportDiscoveryTests : IDisposable
{
    private readonly string _directory = Path.Combine(Path.GetTempPath(), $"ReportSummaryBuilder-{Guid.NewGuid():N}");

    public ReportDiscoveryTests() => Directory.CreateDirectory(_directory);

    [Fact]
    public void Find_ReturnsOnlyOriginalVectorReports_WithArbitraryNames()
    {
        var valid = Path.Combine(_directory, "한글 이름 원본.html");
        File.WriteAllText(valid, MinimalVectorReport("RS4PE", "DRV"));
        File.WriteAllText(Path.Combine(_directory, "RS4PE_LHD_Combined_Test_Report.html"), MinimalVectorReport("RS4PE", "RR"));
        File.WriteAllText(Path.Combine(_directory, "report.bak_20261016.html"), MinimalVectorReport("RS4PE", "AST"));
        File.WriteAllText(Path.Combine(_directory, "ordinary.html"), "<html><body>not a Vector report</body></html>");
        File.WriteAllText(Path.Combine(_directory, "report.xml"), "<report />");

        var result = new ReportDiscovery().Find(_directory);

        Assert.Equal([valid], result);
    }

    [Fact]
    public void Find_WhenDirectoryDoesNotExist_ThrowsUserFacingError()
    {
        var error = Assert.Throws<Errors.ReportInputException>(() =>
            new ReportDiscovery().Find(Path.Combine(_directory, "missing")));

        Assert.Equal("입력 폴더 오류", error.Title);
    }

    public void Dispose() => Directory.Delete(_directory, recursive: true);

    internal static string MinimalVectorReport(string project, string position) => $$"""
        <html><body>
        <table>
          <tr><td>Var_Project:</td><td>{{project}}</td></tr>
          <tr><td>Var_Drive_Type:</td><td>LHD</td></tr>
          <tr><td>Var_SBCM_Position:</td><td>{{position}}</td></tr>
          <tr><td>Var_EOL_Variant_Type:</td><td>All_DTC_List</td></tr>
          <tr><td>Test begin:</td><td>2026-10-08 08:18:49</td></tr>
          <tr><td>Test end:</td><td>2026-10-08 09:18:49</td></tr>
        </table>
        <div class="Heading4">Statistics</div>
        <table>
          <tr><td>Executed test cases</td><td>2</td></tr>
          <tr><td>Test cases passed</td><td>1</td></tr>
          <tr><td>Test cases inconclusive</td><td>0</td></tr>
          <tr><td>Test cases failed</td><td>1</td></tr>
          <tr><td>Test cases with error in test system</td><td>0</td></tr>
          <tr><td>Number of failures outside of test cases</td><td></td></tr>
          <tr><td>Inconclusive</td><td>0</td></tr>
          <tr><td>Fail</td><td>0</td></tr>
          <tr><td>Error in test system</td><td>0</td></tr>
        </table>
        <div class="Heading4">Test Results</div>
        <table>
          <tr><td>1</td><td><a href="#tc-1">Category</a></td><td>2</td></tr>
          <tr><td>1.1</td><td><a href="#tc-1-1">Passed TC</a></td><td class="PositiveResultCell">Pass</td></tr>
          <tr><td>1.2</td><td><a href="#tc-1-2">Failed TC</a></td><td class="NegativeResultCell">Fail</td></tr>
        </table>
        <a name="TestModuleInfo"></a>
        </body></html>
        """;
}
