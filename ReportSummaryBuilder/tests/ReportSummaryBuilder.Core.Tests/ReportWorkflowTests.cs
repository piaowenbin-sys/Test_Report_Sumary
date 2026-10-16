using ReportSummaryBuilder.Core.Errors;
using ReportSummaryBuilder.Core.Services;

namespace ReportSummaryBuilder.Core.Tests;

public sealed class ReportWorkflowTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), $"ReportWorkflow-{Guid.NewGuid():N}");

    public ReportWorkflowTests() => Directory.CreateDirectory(_root);

    [Fact]
    public async Task RunAsync_ProcessesAnyNumberOfReports()
    {
        var input = CreateInput(("RS4PE", "DRV"), ("RS4PE", "AST"), ("RS4PE", "RR"));
        var output = Path.Combine(_root, "output");

        var result = await new ReportWorkflow().RunAsync(input, output, CancellationToken.None);

        Assert.Equal(3, result.DetailPaths.Count);
        Assert.True(File.Exists(result.SummaryPath));
        Assert.True(File.Exists(result.ZipPath));
    }

    [Fact]
    public async Task RunAsync_WhenProjectsDiffer_DoesNotCreateOutput()
    {
        var input = CreateInput(("RS4PE", "DRV"), ("NE1aW", "RR"));
        var output = Path.Combine(_root, "output");

        var error = await Assert.ThrowsAsync<ReportInputException>(() =>
            new ReportWorkflow().RunAsync(input, output, CancellationToken.None));

        Assert.Equal("리포트 조합 오류", error.Title);
        Assert.Equal("동일 차종의 리포트가 아닙니다.", error.UserMessage);
        Assert.False(Directory.Exists(output));
    }

    [Fact]
    public async Task RunAsync_WhenAlreadyCancelled_DoesNotCreateOutput()
    {
        var input = CreateInput(("RS4PE", "DRV"), ("RS4PE", "RR"));
        var output = Path.Combine(_root, "output");
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            new ReportWorkflow().RunAsync(input, output, cancellation.Token));

        Assert.False(Directory.Exists(output));
    }

    private string CreateInput(params (string Project, string Position)[] reports)
    {
        var input = Path.Combine(_root, "input");
        Directory.CreateDirectory(input);
        foreach (var report in reports)
        {
            File.WriteAllText(Path.Combine(input, $"{report.Position}.html"),
                ReportDiscoveryTests.MinimalVectorReport(report.Project, report.Position));
        }
        return input;
    }

    public void Dispose() => Directory.Delete(_root, recursive: true);
}
