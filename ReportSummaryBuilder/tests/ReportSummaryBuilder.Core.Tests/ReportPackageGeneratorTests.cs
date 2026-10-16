using System.IO.Compression;
using System.Security.Cryptography;
using ReportSummaryBuilder.Core.Models;
using ReportSummaryBuilder.Core.Services;

namespace ReportSummaryBuilder.Core.Tests;

public sealed class ReportPackageGeneratorTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), $"ReportPackage-{Guid.NewGuid():N}");

    public ReportPackageGeneratorTests() => Directory.CreateDirectory(_root);

    [Fact]
    public async Task GenerateAsync_CreatesSummaryDetailsAndExactZipEntries()
    {
        var reports = CreateReports("RS4PE");
        var output = Path.Combine(_root, "output");

        var result = await new ReportPackageGenerator().GenerateAsync(reports, output, CancellationToken.None);

        Assert.True(File.Exists(result.SummaryPath));
        Assert.True(File.Exists(result.ZipPath));
        Assert.Equal(2, result.DetailPaths.Count);
        Assert.Equal(3, Directory.EnumerateFiles(output, "*.html", SearchOption.AllDirectories).Count());
        Assert.True(result.SummarySizeBytes < 100_000, $"Summary is unexpectedly large: {result.SummarySizeBytes} bytes");
        foreach (var report in reports)
        {
            var detail = result.DetailPaths.Single(path => Path.GetFileName(path).StartsWith(report.Position + "_", StringComparison.OrdinalIgnoreCase));
            Assert.Equal(report.SourceHash, Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(detail))));
        }

        var summary = await File.ReadAllTextAsync(result.SummaryPath);
        foreach (var detail in result.DetailPaths)
        {
            Assert.Contains(Path.GetFileName(detail), summary);
        }

        using var zip = ZipFile.OpenRead(result.ZipPath);
        var entries = zip.Entries.Select(entry => entry.FullName.Replace('\\', '/')).Order().ToArray();
        Assert.Equal(3, entries.Length);
        Assert.Contains(Path.GetFileName(result.SummaryPath), entries);
        Assert.Equal(2, entries.Count(entry => entry.StartsWith(Path.GetFileName(Path.GetDirectoryName(result.DetailPaths[0])!) + "/")));
    }

    [Fact]
    public async Task GenerateAsync_WhenOutputsExist_CreatesUniqueBackups()
    {
        var reports = CreateReports("RS4PE");
        var output = Path.Combine(_root, "output");
        await new ReportPackageGenerator().GenerateAsync(reports, output, CancellationToken.None);

        var second = await new ReportPackageGenerator().GenerateAsync(reports, output, CancellationToken.None);

        Assert.Equal(3, second.BackupPaths.Count);
        Assert.All(second.BackupPaths, path => Assert.True(File.Exists(path) || Directory.Exists(path), path));
        Assert.Equal(3, second.BackupPaths.Distinct(StringComparer.OrdinalIgnoreCase).Count());
    }

    [Fact]
    public async Task GenerateAsync_WhenStagingFails_PreservesExistingOutputs()
    {
        var reports = CreateReports("RS4PE");
        var output = Path.Combine(_root, "output");
        var first = await new ReportPackageGenerator().GenerateAsync(reports, output, CancellationToken.None);
        var previousHash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(first.SummaryPath)));

        await Assert.ThrowsAsync<IOException>(() => new FailingPackageGenerator().GenerateAsync(reports, output, CancellationToken.None));

        Assert.Equal(previousHash, Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(first.SummaryPath))));
        Assert.True(File.Exists(first.ZipPath));
        Assert.All(first.DetailPaths, path => Assert.True(File.Exists(path)));
    }

    [Fact]
    public async Task GenerateAsync_WhenSameOutputIsAlreadyPublishing_RejectsConcurrentRun()
    {
        var reports = CreateReports("RS4PE");
        var output = Path.Combine(_root, "output");
        var blocking = new BlockingPackageGenerator();
        var first = blocking.GenerateAsync(reports, output, CancellationToken.None);
        await blocking.Entered.Task.WaitAsync(TimeSpan.FromSeconds(5));

        var error = await Assert.ThrowsAsync<Errors.ReportInputException>(() =>
            new ReportPackageGenerator().GenerateAsync(reports, output, CancellationToken.None));

        Assert.Equal("출력 폴더 사용 중", error.Title);
        blocking.Release.SetResult();
        await first;
    }

    private IReadOnlyList<ReportModel> CreateReports(string project)
    {
        var parser = new VectorReportParser();
        return new[] { "DRV", "RR" }.Select(position =>
        {
            var path = Path.Combine(_root, $"{position} report.html");
            File.WriteAllText(path, ReportDiscoveryTests.MinimalVectorReport(project, position));
            return parser.Parse(path);
        }).ToArray();
    }

    public void Dispose() => Directory.Delete(_root, recursive: true);

    private sealed class FailingPackageGenerator : ReportPackageGenerator
    {
        protected override Task BeforePublishAsync(string stagingDirectory, CancellationToken cancellationToken) =>
            throw new IOException("forced staging failure");
    }

    private sealed class BlockingPackageGenerator : ReportPackageGenerator
    {
        public TaskCompletionSource Entered { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public TaskCompletionSource Release { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);

        protected override async Task BeforePublishAsync(string stagingDirectory, CancellationToken cancellationToken)
        {
            Entered.SetResult();
            await Release.Task.WaitAsync(cancellationToken);
        }
    }
}
