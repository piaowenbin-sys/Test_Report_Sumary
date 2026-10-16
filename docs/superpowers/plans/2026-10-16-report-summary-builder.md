# Test Report Summary Builder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a simple installable Windows app that accepts any number of compatible Vector HTML reports and creates a lightweight summary, copied detail reports, and a verified ZIP.

**Architecture:** A .NET 10 solution separates HTML parsing/validation/package generation into a testable core library and keeps WinForms limited to folder selection, status, and dialogs. Release automation publishes a self-contained Windows x64 app and packages it as a one-click Velopack `Setup.exe`, with the self-contained executable retained as a portable fallback.

**Tech Stack:** C# 14, .NET 10 WinForms, HtmlAgilityPack 1.13.1, xUnit, System.IO.Compression, Velopack 1.2.161

**Spec:** `docs/superpowers/specs/2026-10-16-report-summary-builder-design.md`

## Global Constraints

- Target Windows x64 with `net10.0-windows` and self-contained deployment.
- The installed app must not invoke PowerShell and must not require a .NET runtime on the target PC.
- Only `Var_Project` differences trigger `동일 차종의 리포트가 아닙니다.` and stop generation.
- `Var_Drive_Type`, `Var_SBCM_Position`, and `Var_EOL_Variant_Type` differences do not trigger the vehicle-model popup.
- Duplicate positions and missing required metadata stop generation with separate input-error messages.
- v1 reads HTML only; XML files, generated summaries, detail-output folders, ZIPs, and backups are excluded.
- Existing output is timestamp-backed up before replacement; failed validation never replaces it.
- An active package contains one main summary and one detail HTML per accepted source, and the ZIP contains exactly those files.
- Keep the UI to two folder selectors, detected-count text, one generation button, and status/result text.

## Review Focus

- A folder containing source reports plus prior generated files must select only original Vector reports.
- Mixed `Var_Project` values must show the exact Korean popup and produce no output.
- Mixed LHD/RHD reports with one `Var_Project` must proceed without the vehicle-model popup.
- A source filename containing Korean or spaces must copy, link, and ZIP correctly.
- A failure after staging but before publish must leave the prior report and ZIP unchanged.

---

### Task 1: Development environment and solution skeleton

**Files:**
- Create: `ReportSummaryBuilder/ReportSummaryBuilder.slnx`
- Create: `ReportSummaryBuilder/src/ReportSummaryBuilder.Core/ReportSummaryBuilder.Core.csproj`
- Create: `ReportSummaryBuilder/src/ReportSummaryBuilder.WinForms/ReportSummaryBuilder.WinForms.csproj`
- Create: `ReportSummaryBuilder/tests/ReportSummaryBuilder.Core.Tests/ReportSummaryBuilder.Core.Tests.csproj`
- Create: `ReportSummaryBuilder/global.json`
- Create: `ReportSummaryBuilder/.config/dotnet-tools.json`

**Interfaces:**
- Produces: buildable `net10.0` core/test projects and a `net10.0-windows` WinForms project.

- [ ] **Step 1: Install and verify the .NET 10 SDK**

Run: `winget install --id Microsoft.DotNet.SDK.10 -e --source winget --accept-package-agreements --accept-source-agreements`

Verify: `dotnet --list-sdks` includes a `10.0.*` SDK.

- [ ] **Step 2: Create the solution and projects**

Create the solution, class library, WinForms app, and xUnit project; add project references from WinForms and tests to Core.

- [ ] **Step 3: Pin dependencies and the packaging tool**

Add `HtmlAgilityPack` version `1.13.1` to Core and install local dotnet tool `vpk` version `1.2.161` in the tool manifest.

- [ ] **Step 4: Run the empty suite**

Run: `dotnet test ReportSummaryBuilder/ReportSummaryBuilder.slnx`

Expected: PASS with no build errors.

- [ ] **Step 5: Commit**

Commit message: `build: scaffold report summary builder`

### Task 2: Report discovery, parsing, and vehicle validation

**Files:**
- Create: `ReportSummaryBuilder/src/ReportSummaryBuilder.Core/Models/ReportModel.cs`
- Create: `ReportSummaryBuilder/src/ReportSummaryBuilder.Core/Models/TestItem.cs`
- Create: `ReportSummaryBuilder/src/ReportSummaryBuilder.Core/Services/ReportDiscovery.cs`
- Create: `ReportSummaryBuilder/src/ReportSummaryBuilder.Core/Services/VectorReportParser.cs`
- Create: `ReportSummaryBuilder/src/ReportSummaryBuilder.Core/Services/ReportSetValidator.cs`
- Create: `ReportSummaryBuilder/src/ReportSummaryBuilder.Core/Errors/ReportInputException.cs`
- Create: `ReportSummaryBuilder/tests/ReportSummaryBuilder.Core.Tests/ReportDiscoveryTests.cs`
- Create: `ReportSummaryBuilder/tests/ReportSummaryBuilder.Core.Tests/VectorReportParserTests.cs`
- Create: `ReportSummaryBuilder/tests/ReportSummaryBuilder.Core.Tests/ReportSetValidatorTests.cs`

**Interfaces:**
- Produces: `IReadOnlyList<string> ReportDiscovery.Find(string inputDirectory)`.
- Produces: `ReportModel VectorReportParser.Parse(string path)` with source path/hash, project, drive type, position, EOL variant, statistics, and hierarchical test items.
- Produces: `IReadOnlyList<ReportModel> ReportSetValidator.Validate(IReadOnlyList<ReportModel> reports)`.
- Failure contract: `ReportInputException` exposes `Title`, `UserMessage`, and `Details`; mixed projects use title `리포트 조합 오류` and message `동일 차종의 리포트가 아닙니다.`.

- [ ] **Step 1: Write failing discovery tests**

Assert that original Vector HTML files are returned while combined summaries, detail directories, `.bak_*`, ZIP, and XML files are excluded; include Korean and spaced filenames.

- [ ] **Step 2: Run discovery tests and verify RED**

Run: `dotnet test --filter FullyQualifiedName~ReportDiscoveryTests`

Expected: FAIL because `ReportDiscovery` does not exist.

- [ ] **Step 3: Implement minimal discovery and verify GREEN**

Identify a source report by required metadata labels and the Test Results section rather than fixed filenames.

- [ ] **Step 4: Write failing parser tests against copied real fixtures**

Assert exact metadata, statistics, source SHA-256, decimal hierarchy, and Pass/Fail/NA aggregation from DRV and RR fixture reports.

- [ ] **Step 5: Implement `VectorReportParser.Parse` and verify GREEN**

Use HtmlAgilityPack for the DOM and preserve the current PowerShell generator's tested category/verdict semantics.

- [ ] **Step 6: Write failing validator tests**

Cover mixed projects with exact popup fields, mixed drive types accepted, duplicate positions rejected separately, missing project rejected, and empty input rejected.

- [ ] **Step 7: Implement `ReportSetValidator.Validate` and verify GREEN**

Order accepted reports by position text while retaining every distinct position.

- [ ] **Step 8: Run core tests and commit**

Run: `dotnet test ReportSummaryBuilder/ReportSummaryBuilder.slnx`

Commit message: `feat: discover and validate vector reports`

### Task 3: Lightweight summary and verified ZIP package

**Files:**
- Create: `ReportSummaryBuilder/src/ReportSummaryBuilder.Core/Models/PackageResult.cs`
- Create: `ReportSummaryBuilder/src/ReportSummaryBuilder.Core/Services/SummaryHtmlGenerator.cs`
- Create: `ReportSummaryBuilder/src/ReportSummaryBuilder.Core/Services/ReportPackageGenerator.cs`
- Create: `ReportSummaryBuilder/tests/ReportSummaryBuilder.Core.Tests/SummaryHtmlGeneratorTests.cs`
- Create: `ReportSummaryBuilder/tests/ReportSummaryBuilder.Core.Tests/ReportPackageGeneratorTests.cs`

**Interfaces:**
- Consumes: validated `IReadOnlyList<ReportModel>` from Task 2.
- Produces: `string SummaryHtmlGenerator.Generate(IReadOnlyList<ReportModel> reports, string detailDirectoryName)`.
- Produces: `Task<PackageResult> ReportPackageGenerator.GenerateAsync(IReadOnlyList<ReportModel> reports, string outputDirectory, CancellationToken cancellationToken)`.
- `PackageResult` exposes `SummaryPath`, `ZipPath`, `DetailPaths`, `BackupPaths`, and `SummarySizeBytes`.

- [ ] **Step 1: Write failing summary tests**

Assert a single lightweight main HTML, Position/Area/Category hierarchy, expandable TC rows, per-position detail links, no embedded full report sections, and mixed-drive labeling without rejection.

- [ ] **Step 2: Run summary tests and verify RED**

Run: `dotnet test --filter FullyQualifiedName~SummaryHtmlGeneratorTests`

Expected: FAIL because the generator does not exist.

- [ ] **Step 3: Implement `SummaryHtmlGenerator.Generate` and verify GREEN**

Port the current C104/forced actuation/ECU ID/PWM/Switch/Sensor/Vbat/HS/Motor grouping and effective-verdict logic without copying full source bodies into the main file.

- [ ] **Step 4: Write failing package tests**

Assert `1 + N` active HTML files, copied-detail hashes equal source hashes, all relative links resolve, ZIP entries exactly match active HTML, existing outputs receive unique timestamp backups, and a forced staging failure preserves previous outputs.

- [ ] **Step 5: Implement staged package generation and verify GREEN**

Generate under a temporary sibling directory, validate hashes/links/counts, then atomically publish the main file, detail directory, and ZIP.

- [ ] **Step 6: Run all tests and commit**

Run: `dotnet test ReportSummaryBuilder/ReportSummaryBuilder.slnx`

Commit message: `feat: generate lightweight report packages`

### Task 4: Simple WinForms workflow

**Files:**
- Create: `ReportSummaryBuilder/src/ReportSummaryBuilder.WinForms/Program.cs`
- Create: `ReportSummaryBuilder/src/ReportSummaryBuilder.WinForms/MainForm.cs`
- Create: `ReportSummaryBuilder/src/ReportSummaryBuilder.WinForms/MainForm.Designer.cs`
- Create: `ReportSummaryBuilder/src/ReportSummaryBuilder.WinForms/ReportWorkflow.cs`
- Create: `ReportSummaryBuilder/tests/ReportSummaryBuilder.Core.Tests/ReportWorkflowTests.cs`

**Interfaces:**
- Consumes: discovery, parser, validator, and package generator from Tasks 2-3.
- Produces: `Task<PackageResult> ReportWorkflow.RunAsync(string inputDirectory, string outputDirectory, CancellationToken cancellationToken)`.
- UI contract: two read-only path fields with Browse buttons, report-count label, `서머리·ZIP 생성` button, and status/result text.

- [ ] **Step 1: Write failing workflow tests**

Assert successful N-report orchestration, exact project-mismatch exception fields, mixed drive types allowed, cancellation before publish, and no output when validation fails.

- [ ] **Step 2: Implement `ReportWorkflow.RunAsync` and verify GREEN**

Keep all UI-independent behavior in `ReportWorkflow` so tests do not automate Windows controls.

- [ ] **Step 3: Implement the minimal form**

Use `FolderBrowserDialog`; rescan after input selection; disable Generate while running; execute asynchronously; show `MessageBox` from `ReportInputException`; show paths and file count on success.

- [ ] **Step 4: Run tests and perform a manual UI smoke test**

Run: `dotnet test ReportSummaryBuilder/ReportSummaryBuilder.slnx`

Run: `dotnet run --project ReportSummaryBuilder/src/ReportSummaryBuilder.WinForms`

Expected: the current four-report folder produces a five-HTML ZIP; mixed-project fixtures show only the requested vehicle popup.

- [ ] **Step 5: Commit**

Commit message: `feat: add report summary desktop app`

### Task 5: Portable release and one-click installer

**Files:**
- Modify: `ReportSummaryBuilder/src/ReportSummaryBuilder.WinForms/Program.cs`
- Create: `ReportSummaryBuilder/scripts/build-release.ps1`
- Create: `ReportSummaryBuilder/README.md`
- Create: `ReportSummaryBuilder/assets/app.ico`
- Create: `ReportSummaryBuilder/tests/release-smoke.ps1`

**Interfaces:**
- Consumes: the WinForms executable from Task 4.
- Produces: `release/portable/ReportSummaryBuilder.exe` and `release/installer/ReportSummaryBuilder-Setup.exe`.

- [ ] **Step 1: Write the failing release smoke test**

Assert release outputs exist, portable EXE is Windows x64/self-contained, installer exists, and a CLI `--verify-package <input> <output>` smoke mode produces a valid package without opening the UI.

- [ ] **Step 2: Add the hidden verification CLI and verify RED/GREEN**

Implement `--verify-package` through `ReportWorkflow` for release testing only; normal launch always opens the minimal UI.

- [ ] **Step 3: Create the release build script**

Run `dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true`, restore local `vpk` 1.2.161, and run `dotnet vpk pack` to create a per-user one-click `Setup.exe` with Start-menu/Desktop shortcuts and Apps & Features uninstall support.

- [ ] **Step 4: Run release verification**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File ReportSummaryBuilder/scripts/build-release.ps1`

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File ReportSummaryBuilder/tests/release-smoke.ps1`

Expected: installer and portable artifacts exist; smoke package has `1 + N` HTML files, zero broken links, matching detail hashes, and one ZIP.

- [ ] **Step 5: Install/uninstall smoke test**

Install `ReportSummaryBuilder-Setup.exe`, launch from its shortcut, generate from the current TestReport folder, uninstall from Apps & Features, and verify no source report changed.

- [ ] **Step 6: Document signing status and commit**

Document that unsigned internal builds may show Windows SmartScreen; do not invent or embed a certificate.

Commit message: `build: package report summary builder`

### Task 6: Final regression and delivery

**Files:**
- Modify: `ReportSummaryBuilder/README.md`
- Create: `ReportSummaryBuilder/release/verification.txt`

**Interfaces:**
- Consumes: all prior tasks.
- Produces: user-ready installer, portable executable, usage instructions, and captured verification evidence.

- [ ] **Step 1: Run the complete automated suite**

Run: `dotnet test ReportSummaryBuilder/ReportSummaryBuilder.slnx -c Release`

Expected: zero failed tests.

- [ ] **Step 2: Run the release smoke suite against 2-report and 4-report fixtures**

Expected: active HTML counts 3 and 5 respectively; both ZIPs match; source hashes remain unchanged.

- [ ] **Step 3: Run the mixed-project negative test through the installed app**

Expected: title `리포트 조합 오류`, message `동일 차종의 리포트가 아닙니다.`, detected project list, and no generated output.

- [ ] **Step 4: Record artifact hashes and commit**

Record SHA-256 for installer and portable executable in `release/verification.txt`.

Commit message: `docs: record report builder release verification`
