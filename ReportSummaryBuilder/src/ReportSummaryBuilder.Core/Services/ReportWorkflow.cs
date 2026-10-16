using ReportSummaryBuilder.Core.Models;

namespace ReportSummaryBuilder.Core.Services;

public sealed class ReportWorkflow
{
    private readonly ReportDiscovery _discovery = new();
    private readonly VectorReportParser _parser = new();
    private readonly ReportSetValidator _validator = new();
    private readonly ReportPackageGenerator _packageGenerator = new();

    public async Task<PackageResult> RunAsync(string inputDirectory, string outputDirectory, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var paths = _discovery.Find(inputDirectory);
        var reports = new List<ReportModel>(paths.Count);
        foreach (var path in paths)
        {
            cancellationToken.ThrowIfCancellationRequested();
            reports.Add(_parser.Parse(path));
        }

        var validated = _validator.Validate(reports);
        cancellationToken.ThrowIfCancellationRequested();
        return await _packageGenerator.GenerateAsync(validated, outputDirectory, cancellationToken);
    }

    public int CountReports(string inputDirectory) => _discovery.Find(inputDirectory).Count;
}
