using ReportSummaryBuilder.Core.Errors;
using ReportSummaryBuilder.Core.Services;
using Velopack;

namespace ReportSummaryBuilder.WinForms;

static class Program
{
    [STAThread]
    static int Main(string[] args)
    {
        VelopackApp.Build().Run();

        if (args.Length > 0 && args[0].Equals("--verify-package", StringComparison.OrdinalIgnoreCase))
        {
            return RunVerification(args);
        }

        ApplicationConfiguration.Initialize();
        Application.Run(new MainForm());
        return 0;
    }

    private static int RunVerification(string[] args)
    {
        if (args.Length != 3) return 64;
        try
        {
            var result = new ReportWorkflow().RunAsync(args[1], args[2], CancellationToken.None).GetAwaiter().GetResult();
            Directory.CreateDirectory(args[2]);
            File.WriteAllLines(Path.Combine(args[2], "verification.txt"),
            [
                "Status=PASS",
                $"Summary={result.SummaryPath}",
                $"Zip={result.ZipPath}",
                $"Details={result.DetailPaths.Count}",
                $"SummarySizeBytes={result.SummarySizeBytes}"
            ]);
            return 0;
        }
        catch (ReportInputException exception)
        {
            TryWriteFailure(args[2], exception.Title, exception.UserMessage, exception.Details);
            return 2;
        }
        catch (Exception exception)
        {
            TryWriteFailure(args[2], "검증 오류", exception.Message, exception.ToString());
            return 1;
        }
    }

    private static void TryWriteFailure(string outputDirectory, string title, string message, string details)
    {
        try
        {
            Directory.CreateDirectory(outputDirectory);
            File.WriteAllLines(Path.Combine(outputDirectory, "verification.txt"),
                ["Status=FAIL", $"Title={title}", $"Message={message}", $"Details={details}"]);
        }
        catch
        {
            // Preserve the original failure code even if diagnostics cannot be written.
        }
    }
}
