namespace ReportSummaryBuilder.Core.Errors;

public sealed class ReportInputException : Exception
{
    public ReportInputException(string title, string userMessage, string details = "")
        : base(string.IsNullOrWhiteSpace(details) ? userMessage : $"{userMessage} {details}")
    {
        Title = title;
        UserMessage = userMessage;
        Details = details;
    }

    public string Title { get; }
    public string UserMessage { get; }
    public string Details { get; }
}
