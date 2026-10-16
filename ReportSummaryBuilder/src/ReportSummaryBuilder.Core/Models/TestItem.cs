namespace ReportSummaryBuilder.Core.Models;

public sealed record TestItem(
    string Number,
    string Href,
    string Text,
    string DirectVerdict,
    string EffectiveVerdict);
