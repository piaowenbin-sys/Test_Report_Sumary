using ReportSummaryBuilder.Core.Errors;
using ReportSummaryBuilder.Core.Services;

namespace ReportSummaryBuilder.WinForms;

public partial class MainForm : Form
{
    private readonly ReportWorkflow _workflow = new();

    public MainForm()
    {
        InitializeComponent();
    }

    private void BrowseInputButton_Click(object? sender, EventArgs e)
    {
        using var dialog = new FolderBrowserDialog
        {
            Description = "원본 Vector HTML 리포트가 있는 폴더를 선택하세요.",
            UseDescriptionForTitle = true,
            ShowNewFolderButton = false
        };
        if (dialog.ShowDialog(this) != DialogResult.OK) return;

        inputPathTextBox.Text = dialog.SelectedPath;
        if (string.IsNullOrWhiteSpace(outputPathTextBox.Text))
        {
            outputPathTextBox.Text = Path.Combine(dialog.SelectedPath, "Summary_Output");
        }
        RefreshReportCount();
    }

    private void BrowseOutputButton_Click(object? sender, EventArgs e)
    {
        using var dialog = new FolderBrowserDialog
        {
            Description = "서머리와 ZIP을 저장할 폴더를 선택하세요.",
            UseDescriptionForTitle = true,
            ShowNewFolderButton = true
        };
        if (dialog.ShowDialog(this) == DialogResult.OK) outputPathTextBox.Text = dialog.SelectedPath;
    }

    private void RefreshReportCount()
    {
        try
        {
            var count = _workflow.CountReports(inputPathTextBox.Text);
            reportCountLabel.Text = $"감지된 원본 리포트: {count}개";
            generateButton.Enabled = count > 0 && !string.IsNullOrWhiteSpace(outputPathTextBox.Text);
        }
        catch (ReportInputException)
        {
            reportCountLabel.Text = "감지된 원본 리포트: 0개";
            generateButton.Enabled = false;
        }
    }

    private async void GenerateButton_Click(object? sender, EventArgs e)
    {
        generateButton.Enabled = false;
        browseInputButton.Enabled = false;
        browseOutputButton.Enabled = false;
        statusTextBox.Text = "리포트를 분석하고 있습니다...";

        try
        {
            var result = await Task.Run(() => _workflow.RunAsync(inputPathTextBox.Text, outputPathTextBox.Text, CancellationToken.None));
            statusTextBox.Text = $"완료\r\n서머리: {result.SummaryPath}\r\nZIP: {result.ZipPath}\r\n상세 HTML: {result.DetailPaths.Count}개";
            MessageBox.Show(this, "서머리와 ZIP 생성이 완료되었습니다.", "완료", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (ReportInputException exception)
        {
            statusTextBox.Text = exception.Details;
            var message = string.IsNullOrWhiteSpace(exception.Details)
                ? exception.UserMessage
                : $"{exception.UserMessage}\r\n\r\n{exception.Details}";
            MessageBox.Show(this, message, exception.Title, MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
        catch (Exception exception)
        {
            statusTextBox.Text = exception.Message;
            MessageBox.Show(this, $"생성 중 오류가 발생했습니다.\r\n\r\n{exception.Message}", "생성 오류", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            browseInputButton.Enabled = true;
            browseOutputButton.Enabled = true;
            RefreshReportCount();
        }
    }
}
