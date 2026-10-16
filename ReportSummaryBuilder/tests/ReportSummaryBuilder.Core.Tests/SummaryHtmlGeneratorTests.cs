using ReportSummaryBuilder.Core.Models;
using ReportSummaryBuilder.Core.Services;

namespace ReportSummaryBuilder.Core.Tests;

public sealed class SummaryHtmlGeneratorTests
{
    [Fact]
    public void Generate_CreatesLightweightExpandableHierarchyAndDetailLinks()
    {
        var reports = new[]
        {
            Report("DRV", "LHD", [
                new TestItem("1.1", "#c104", "C104_SBCM_Input_Status_Check_RS4PE", "NA", "Pass"),
                new TestItem("1.1.1", "#switch", "Door_SW_IN", "Pass", "Pass"),
                new TestItem("1.2", "#force", "IO_Control_Check_DRV", "NA", "Fail"),
                new TestItem("1.2.1", "#force-tc", "Motor_TC", "Fail", "Fail")
            ]),
            Report("RR", "RHD", [new TestItem("1", "#motor", "LIFT_MTR_OUT", "Pass", "Pass")])
        };

        var html = new SummaryHtmlGenerator().Generate(reports, "RS4PE_MIXED_details");

        Assert.Contains("Integrated Functional Test Summary", html);
        Assert.Contains("RS4PE / LHD / DRV", html);
        Assert.Contains("RS4PE / RHD / RR", html);
        Assert.Contains("data-category=\"C104\"", html);
        Assert.Contains("하위 TC 1개", html);
        Assert.Contains("RS4PE_MIXED_details/DRV_report.html#c104", html);
        Assert.Contains("target=\"_blank\"", html);
        Assert.Contains("name=\"report-summary-builder\"", html);
        Assert.Contains("toggleDetails", html);
        Assert.DoesNotContain("TestModuleInfo", html);
        Assert.DoesNotContain("<iframe", html, StringComparison.OrdinalIgnoreCase);
    }

    private static ReportModel Report(string position, string driveType, IReadOnlyList<TestItem> items) => new(
        $"C:\\source\\{position}_report.html", $"{position}_report.html", "RS4PE", driveType, position,
        "All_DTC_List", "begin", "end", new ReportStatistics(1, 1, 0, 0, 0, 0, 0, 0), items, $"HASH-{position}");
}
