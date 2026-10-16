namespace ReportSummaryBuilder.WinForms;

partial class MainForm
{
    private Label titleLabel = null!;
    private Label inputLabel = null!;
    private TextBox inputPathTextBox = null!;
    private Button browseInputButton = null!;
    private Label outputLabel = null!;
    private TextBox outputPathTextBox = null!;
    private Button browseOutputButton = null!;
    private Label reportCountLabel = null!;
    private Button generateButton = null!;
    private TextBox statusTextBox = null!;

    private void InitializeComponent()
    {
        titleLabel = new Label();
        inputLabel = new Label();
        inputPathTextBox = new TextBox();
        browseInputButton = new Button();
        outputLabel = new Label();
        outputPathTextBox = new TextBox();
        browseOutputButton = new Button();
        reportCountLabel = new Label();
        generateButton = new Button();
        statusTextBox = new TextBox();
        SuspendLayout();

        titleLabel.AutoSize = true;
        titleLabel.Font = new Font("Segoe UI", 18F, FontStyle.Bold);
        titleLabel.ForeColor = Color.FromArgb(11, 79, 156);
        titleLabel.Location = new Point(28, 22);
        titleLabel.Text = "Test Report Summary Builder";

        inputLabel.AutoSize = true;
        inputLabel.Location = new Point(30, 84);
        inputLabel.Text = "원본 HTML 폴더";
        inputPathTextBox.Location = new Point(30, 108);
        inputPathTextBox.ReadOnly = true;
        inputPathTextBox.Size = new Size(536, 27);
        browseInputButton.Location = new Point(577, 107);
        browseInputButton.Size = new Size(94, 29);
        browseInputButton.Text = "찾아보기";
        browseInputButton.Click += BrowseInputButton_Click;

        outputLabel.AutoSize = true;
        outputLabel.Location = new Point(30, 153);
        outputLabel.Text = "생성 결과 폴더";
        outputPathTextBox.Location = new Point(30, 177);
        outputPathTextBox.ReadOnly = true;
        outputPathTextBox.Size = new Size(536, 27);
        browseOutputButton.Location = new Point(577, 176);
        browseOutputButton.Size = new Size(94, 29);
        browseOutputButton.Text = "찾아보기";
        browseOutputButton.Click += BrowseOutputButton_Click;

        reportCountLabel.AutoSize = true;
        reportCountLabel.Location = new Point(30, 225);
        reportCountLabel.Text = "감지된 원본 리포트: 0개";

        generateButton.BackColor = Color.FromArgb(23, 105, 170);
        generateButton.Enabled = false;
        generateButton.FlatStyle = FlatStyle.Flat;
        generateButton.ForeColor = Color.White;
        generateButton.Location = new Point(30, 262);
        generateButton.Size = new Size(641, 44);
        generateButton.Text = "서머리 · ZIP 생성";
        generateButton.UseVisualStyleBackColor = false;
        generateButton.Click += GenerateButton_Click;

        statusTextBox.Location = new Point(30, 327);
        statusTextBox.Multiline = true;
        statusTextBox.ReadOnly = true;
        statusTextBox.ScrollBars = ScrollBars.Vertical;
        statusTextBox.Size = new Size(641, 104);
        statusTextBox.Text = "입력 폴더와 출력 폴더를 선택하세요.";

        AutoScaleDimensions = new SizeF(8F, 20F);
        AutoScaleMode = AutoScaleMode.Font;
        BackColor = Color.White;
        ClientSize = new Size(704, 462);
        Controls.AddRange([titleLabel, inputLabel, inputPathTextBox, browseInputButton, outputLabel, outputPathTextBox, browseOutputButton, reportCountLabel, generateButton, statusTextBox]);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        Text = "Test Report Summary Builder";
        ResumeLayout(false);
        PerformLayout();
    }
}
