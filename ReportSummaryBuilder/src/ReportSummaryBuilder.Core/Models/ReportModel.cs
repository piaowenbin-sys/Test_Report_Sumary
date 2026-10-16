namespace ReportSummaryBuilder.Core.Models;

public sealed record ReportStatistics(
    int Executed,
    int Pass,
    int Fail,
    int Inconclusive,
    int Error,
    int OutsideInconclusive,
    int OutsideFail,
    int OutsideError);

public sealed record ReportModel(
    string SourcePath,
    string FileName,
    string Project,
    string DriveType,
    string Position,
    string EolVariant,
    string TestBegin,
    string TestEnd,
    ReportStatistics Statistics,
    IReadOnlyList<TestItem> TestItems,
    string SourceHash);
