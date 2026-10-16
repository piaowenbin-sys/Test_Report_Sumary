namespace ReportSummaryBuilder.Core.Models;

public sealed record PackageResult(
    string SummaryPath,
    string ZipPath,
    IReadOnlyList<string> DetailPaths,
    IReadOnlyList<string> BackupPaths,
    long SummarySizeBytes);
