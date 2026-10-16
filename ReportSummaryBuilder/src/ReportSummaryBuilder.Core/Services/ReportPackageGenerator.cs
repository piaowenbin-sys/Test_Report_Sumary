using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using ReportSummaryBuilder.Core.Errors;
using ReportSummaryBuilder.Core.Models;

namespace ReportSummaryBuilder.Core.Services;

public class ReportPackageGenerator
{
    public async Task<PackageResult> GenerateAsync(IReadOnlyList<ReportModel> reports, string outputDirectory, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(reports);
        if (reports.Count == 0) throw new ReportInputException("입력 리포트 오류", "처리할 리포트가 없습니다.");
        if (string.IsNullOrWhiteSpace(outputDirectory)) throw new ReportInputException("출력 폴더 오류", "출력 폴더를 선택해주세요.");

        var outputFullPath = Path.GetFullPath(outputDirectory);
        var parent = Directory.GetParent(outputFullPath)?.FullName ?? throw new ReportInputException("출력 폴더 오류", "출력 폴더의 상위 경로를 확인할 수 없습니다.");
        Directory.CreateDirectory(parent);
        using var outputLock = AcquireOutputLock(outputFullPath);

        var stem = GetPackageStem(reports);
        var summaryName = $"{stem}_Combined_Test_Report.html";
        var detailDirectoryName = $"{stem}_details";
        var zipName = $"{stem}_Test_Report.zip";
        var staging = Path.Combine(parent, $".ReportSummaryBuilder-stage-{Guid.NewGuid():N}");
        var stageDetailDirectory = Path.Combine(staging, detailDirectoryName);

        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            Directory.CreateDirectory(stageDetailDirectory);
            var stageDetails = new List<string>();
            foreach (var report in reports)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var destination = Path.Combine(stageDetailDirectory, GetDetailFileName(report));
                File.Copy(report.SourcePath, destination, overwrite: false);
                var hash = Convert.ToHexString(SHA256.HashData(await File.ReadAllBytesAsync(destination, cancellationToken)));
                if (!hash.Equals(report.SourceHash, StringComparison.OrdinalIgnoreCase))
                {
                    throw new IOException($"상세 리포트 복사 검증 실패: {report.FileName}");
                }
                stageDetails.Add(destination);
            }

            var summaryHtml = new SummaryHtmlGenerator().Generate(reports, detailDirectoryName);
            var stageSummary = Path.Combine(staging, summaryName);
            await File.WriteAllTextAsync(stageSummary, summaryHtml, new UTF8Encoding(false), cancellationToken);
            ValidateDetailLinks(summaryHtml, detailDirectoryName, stageDetails);

            var stageZip = Path.Combine(staging, zipName);
            using (var archive = ZipFile.Open(stageZip, ZipArchiveMode.Create))
            {
                archive.CreateEntryFromFile(stageSummary, summaryName, CompressionLevel.Optimal);
                foreach (var detail in stageDetails)
                {
                    archive.CreateEntryFromFile(detail, $"{detailDirectoryName}/{Path.GetFileName(detail)}", CompressionLevel.Optimal);
                }
            }

            ValidateZip(stageZip, summaryName, detailDirectoryName, stageSummary, stageDetails);
            await BeforePublishAsync(staging, cancellationToken);
            cancellationToken.ThrowIfCancellationRequested();

            Directory.CreateDirectory(outputFullPath);
            var targets = new[]
            {
                (Stage: stageSummary, Target: Path.Combine(outputFullPath, summaryName), IsDirectory: false),
                (Stage: stageDetailDirectory, Target: Path.Combine(outputFullPath, detailDirectoryName), IsDirectory: true),
                (Stage: stageZip, Target: Path.Combine(outputFullPath, zipName), IsDirectory: false)
            };
            var backups = PublishWithRollback(targets, cancellationToken);
            var detailPaths = reports.Select(report => Path.Combine(outputFullPath, detailDirectoryName, GetDetailFileName(report))).ToArray();

            return new PackageResult(
                Path.Combine(outputFullPath, summaryName),
                Path.Combine(outputFullPath, zipName),
                detailPaths,
                backups,
                new FileInfo(Path.Combine(outputFullPath, summaryName)).Length);
        }
        finally
        {
            if (Directory.Exists(staging)) Directory.Delete(staging, recursive: true);
        }
    }

    protected virtual Task BeforePublishAsync(string stagingDirectory, CancellationToken cancellationToken) => Task.CompletedTask;

    public static string GetDetailFileName(ReportModel report)
    {
        var fileName = report.FileName.StartsWith(report.Position + "_", StringComparison.OrdinalIgnoreCase)
            ? report.FileName
            : $"{report.Position}_{report.FileName}";
        return SanitizeFileName(fileName);
    }

    private static string GetPackageStem(IReadOnlyList<ReportModel> reports)
    {
        var drives = reports.Select(report => report.DriveType).Where(value => !string.IsNullOrWhiteSpace(value)).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        var drive = drives.Length == 1 ? drives[0] : "MIXED";
        return SanitizeFileName($"{reports[0].Project}_{drive}");
    }

    private static string SanitizeFileName(string value)
    {
        var invalid = Path.GetInvalidFileNameChars();
        var chars = value.Select(character => invalid.Contains(character) || char.IsWhiteSpace(character) ? '_' : character).ToArray();
        return new string(chars);
    }

    private static void ValidateDetailLinks(string summary, string detailDirectoryName, IReadOnlyList<string> details)
    {
        foreach (var detail in details)
        {
            var expected = $"{Uri.EscapeDataString(detailDirectoryName)}/{Uri.EscapeDataString(Path.GetFileName(detail))}";
            if (!summary.Contains(expected, StringComparison.Ordinal)) throw new IOException($"서머리 상세 링크 검증 실패: {Path.GetFileName(detail)}");
        }
    }

    private static void ValidateZip(string zipPath, string summaryName, string detailDirectoryName, string summaryPath, IReadOnlyList<string> details)
    {
        using var archive = ZipFile.OpenRead(zipPath);
        var expectedFiles = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            [summaryName] = summaryPath
        };
        foreach (var detail in details) expectedFiles[$"{detailDirectoryName}/{Path.GetFileName(detail)}"] = detail;
        var expected = expectedFiles.Keys.Order(StringComparer.Ordinal).ToArray();
        var actual = archive.Entries.Select(entry => entry.FullName.Replace('\\', '/')).Order(StringComparer.Ordinal).ToArray();
        if (!expected.SequenceEqual(actual, StringComparer.Ordinal)) throw new IOException("ZIP 파일 목록 검증에 실패했습니다.");
        foreach (var entry in archive.Entries)
        {
            var entryName = entry.FullName.Replace('\\', '/');
            using var stream = entry.Open();
            var archivedHash = Convert.ToHexString(SHA256.HashData(stream));
            var sourceHash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(expectedFiles[entryName])));
            if (!archivedHash.Equals(sourceHash, StringComparison.Ordinal)) throw new IOException($"ZIP 내용 검증에 실패했습니다: {entryName}");
        }
    }

    private static IDisposable AcquireOutputLock(string outputDirectory)
    {
        var key = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(outputDirectory.ToUpperInvariant())));
        var semaphore = new Semaphore(1, 1, $"Local\\ReportSummaryBuilder_{key}");
        if (semaphore.WaitOne(0)) return new SemaphoreHandle(semaphore);
        semaphore.Dispose();
        throw new ReportInputException("출력 폴더 사용 중", "같은 출력 폴더에서 다른 생성 작업이 진행 중입니다.");
    }

    private static IReadOnlyList<string> PublishWithRollback((string Stage, string Target, bool IsDirectory)[] targets, CancellationToken cancellationToken)
    {
        var backups = new List<(string Backup, string Target, bool IsDirectory)>();
        var published = new List<(string Target, bool IsDirectory)>();
        try
        {
            foreach (var target in targets)
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (File.Exists(target.Target) || Directory.Exists(target.Target))
                {
                    var backup = UniqueBackupPath(target.Target);
                    if (target.IsDirectory) Directory.Move(target.Target, backup); else File.Move(target.Target, backup);
                    backups.Add((backup, target.Target, target.IsDirectory));
                }

                if (target.IsDirectory) Directory.Move(target.Stage, target.Target); else File.Move(target.Stage, target.Target);
                published.Add((target.Target, target.IsDirectory));
            }
            return backups.Select(item => item.Backup).ToArray();
        }
        catch
        {
            foreach (var item in published.AsEnumerable().Reverse())
            {
                if (item.IsDirectory && Directory.Exists(item.Target)) Directory.Delete(item.Target, recursive: true);
                if (!item.IsDirectory && File.Exists(item.Target)) File.Delete(item.Target);
            }
            foreach (var item in backups.AsEnumerable().Reverse())
            {
                if (item.IsDirectory && Directory.Exists(item.Backup)) Directory.Move(item.Backup, item.Target);
                if (!item.IsDirectory && File.Exists(item.Backup)) File.Move(item.Backup, item.Target);
            }
            throw;
        }
    }

    private static string UniqueBackupPath(string target)
    {
        var basePath = $"{target}.bak_{DateTime.Now:yyyyMMdd_HHmmss}";
        var candidate = basePath;
        var counter = 1;
        while (File.Exists(candidate) || Directory.Exists(candidate)) candidate = $"{basePath}_{counter++}";
        return candidate;
    }

    private sealed class SemaphoreHandle(Semaphore semaphore) : IDisposable
    {
        public void Dispose()
        {
            semaphore.Release();
            semaphore.Dispose();
        }
    }
}
