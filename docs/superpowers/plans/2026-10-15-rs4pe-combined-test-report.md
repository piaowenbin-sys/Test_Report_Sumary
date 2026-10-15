# RS4PE Combined Test Report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and publish one standalone HTML report containing the overview, functional summary, and complete detail of the DRV, AST, RL, and RR RS4PE/LHD reports.

**Architecture:** A focused PowerShell module parses report metadata, statistics, and Test Results, builds the established nested functional summary, prefixes each embedded report's local identifiers, and validates the resulting master document. A thin command script performs the verified build and optional timestamped publication; a custom PowerShell test runner covers unit and real-report integration behavior without adding dependencies.

**Tech Stack:** Windows PowerShell 5.1-compatible PowerShell, .NET regular expressions and file APIs, standalone HTML/CSS/JavaScript

**Spec:** `docs/superpowers/specs/2026-10-15-rs4pe-combined-test-report-design.md`

## Global Constraints

- Treat `C:\Users\USER.K1109684\Downloads\TestReport` source HTML/XML files as immutable evidence.
- Accept exactly one report for each position: `DRV`, `AST`, `RL`, and `RR`, and emit them in that order.
- Require common metadata `RS4PE`, `LHD`, and `All_DTC_List (defined in test design)`.
- Retain the current nine-category summary, recursive Pass/Fail/NA rules, and C104/IO-control deduplication.
- Include full Test Results and detailed content for every position in one dependency-free UTF-8 HTML file.
- Prefix all local anchor and element identifiers with `DRV__`, `AST__`, `RL__`, or `RR__`.
- Stop before publication on metadata, count, statistics, identifier, local-link, encoding, or source-hash validation failure.
- Back up an existing final report with a timestamp before replacement.

## Review Focus

- Attribute rewriting must handle single-quoted and double-quoted `id`, `name`, and fragment `href` values without altering external links.
- Empty statistics cells and non-zero outside-test failures must not be silently interpreted as passing.
- Numbered Test Results hierarchies must not treat unrelated numeric prefixes such as `1.1` and `1.10` as parent/child.
- Re-running publication must create a new backup and never overwrite an earlier timestamped backup.
- A malformed source with one missing closing document tag must fail clearly rather than produce a partially embedded report.

---

### Task 1: Parse and validate source reports

**Files:**
- Create: `src/CombinedTestReport.psm1`
- Create: `tests/test-combined-report.ps1`

**Interfaces:**
- Produces: `Get-ReportModel -Path <string>` returning metadata, times, statistics, TestItems, source hash, source HTML, and body HTML.
- Produces: `Assert-ReportSet -Reports <object[]>` returning the reports ordered DRV, AST, RL, RR or throwing a specific validation error.
- Produces: internal hierarchy and effective-verdict helpers consumed by Task 2.

- [ ] **Step 1: Write failing parser and validation tests**

Add tests named `parses_real_report_metadata_and_statistics`, `rejects_missing_position`, `rejects_duplicate_position`, `rejects_common_metadata_mismatch`, `keeps_decimal_number_hierarchies_distinct`, and `rejects_malformed_document`. Assert literal metadata and RR statistics (`Executed=102`, `Pass=102`, `Inconclusive=0`, `Fail=0`, `Error=0`) from the real RR source; use small temp fixtures for the failure cases.

- [ ] **Step 2: Run the tests to verify RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/test-combined-report.ps1 -Group Parse`

Expected: FAIL because `src/CombinedTestReport.psm1` or its public functions do not exist.

- [ ] **Step 3: Implement parsing and set validation**

Implement `Get-ReportModel` and `Assert-ReportSet` plus private HTML-text, statistics, Test Results row, child-selection, and verdict-resolution helpers. Parse explicit labels rather than depending on fixed line numbers.

- [ ] **Step 4: Run Task 1 tests to verify GREEN**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/test-combined-report.ps1 -Group Parse`

Expected: `PASS: Parse` and exit code 0.

- [ ] **Step 5: Commit Task 1**

Commit only `src/CombinedTestReport.psm1` and `tests/test-combined-report.ps1` with message `feat: parse RS4PE position reports`.

### Task 2: Build and validate the standalone combined HTML

**Files:**
- Modify: `src/CombinedTestReport.psm1`
- Modify: `tests/test-combined-report.ps1`

**Interfaces:**
- Consumes: ordered report models and hierarchy helpers from Task 1.
- Produces: `New-CombinedReport -Reports <object[]> -OutputPath <string>` returning a validation result with output hash, per-position counts, and unresolved-link count.
- Produces: `Test-CombinedReport -Path <string> -Reports <object[]>` throwing on any structural or evidence mismatch.

- [ ] **Step 1: Write failing summary, namespace, embedding, and validation tests**

Add tests named `builds_four_position_overview_in_required_order`, `includes_nine_nested_summary_categories_per_position`, `aggregates_numeric_parent_verdicts`, `deduplicates_c104_and_io_control_children`, `prefixes_local_identifiers_and_resolves_links`, `preserves_external_links`, `embeds_complete_test_results_for_each_position`, `matches_source_statistics_and_record_counts`, `rejects_duplicate_ids`, and `keeps_source_hashes_unchanged`.

- [ ] **Step 2: Run Task 2 tests to verify RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/test-combined-report.ps1 -Group Build`

Expected: FAIL because `New-CombinedReport` and `Test-CombinedReport` are not implemented.

- [ ] **Step 3: Implement functional summary generation**

Add private selectors and HTML builders for C104, 강제구동, ECU ID, PWM, Switch, Sensor, Vbat, HS, and Motor. Use position-prefixed expand/collapse target IDs and retain child verdicts.

- [ ] **Step 4: Implement identifier rewriting and master-document generation**

Add private `ConvertTo-PrefixedBody` and master overview/position-section builders. Preserve the first report's inline CSS, add one shared blue-themed combined-report stylesheet and one shared toggle function, and embed all four complete bodies.

- [ ] **Step 5: Implement output validation**

Add duplicate-ID, fragment-resolution, per-position record-count, displayed-statistics, UTF-8 text, and source-hash checks. Empty or malformed statistics must yield `NA` or a validation failure, never Pass.

- [ ] **Step 6: Run Task 2 tests to verify GREEN**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/test-combined-report.ps1 -Group Build`

Expected: `PASS: Build` and exit code 0.

- [ ] **Step 7: Commit Task 2**

Commit the module and test changes with message `feat: build standalone combined test report`.

### Task 3: Add safe publication and run the real four-report build

**Files:**
- Create: `combine-test-reports.ps1`
- Modify: `tests/test-combined-report.ps1`
- Create at runtime: `artifacts/RS4PE_LHD_Combined_Test_Report.html`
- Publish after verification: `C:\Users\USER.K1109684\Downloads\TestReport\RS4PE_LHD_Combined_Test_Report.html`

**Interfaces:**
- Consumes: `Get-ReportModel`, `Assert-ReportSet`, `New-CombinedReport`, and `Test-CombinedReport` from Tasks 1 and 2.
- Produces: command interface `combine-test-reports.ps1 -InputDirectory <string> -OutputPath <string> [-PublishPath <string>]`.

- [ ] **Step 1: Write failing command and backup tests**

Add tests named `command_builds_verified_workspace_artifact`, `publish_creates_timestamped_backup_before_replace`, `second_publish_does_not_overwrite_previous_backup`, and `publication_stops_when_validation_fails`.

- [ ] **Step 2: Run Task 3 tests to verify RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/test-combined-report.ps1 -Group Publish`

Expected: FAIL because `combine-test-reports.ps1` does not exist.

- [ ] **Step 3: Implement the command wrapper and safe publication**

Build to a workspace path, run `Test-CombinedReport`, then copy to the requested publish path. When a destination exists, create a collision-resistant timestamped `.bak_yyyyMMdd_HHmmss_fff` copy before replacement.

- [ ] **Step 4: Run Task 3 tests to verify GREEN**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/test-combined-report.ps1 -Group Publish`

Expected: `PASS: Publish` and exit code 0.

- [ ] **Step 5: Run the complete test suite**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/test-combined-report.ps1 -Group All`

Expected: `PASS: All` with zero failures.

- [ ] **Step 6: Build and publish the real combined report**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File combine-test-reports.ps1 -InputDirectory 'C:\Users\USER.K1109684\Downloads\TestReport' -OutputPath 'artifacts\RS4PE_LHD_Combined_Test_Report.html' -PublishPath 'C:\Users\USER.K1109684\Downloads\TestReport\RS4PE_LHD_Combined_Test_Report.html'`

Expected: reports DRV/AST/RL/RR, output and published paths, a validation success line, and unchanged source hashes.

- [ ] **Step 7: Perform three-layer final verification**

Run the full test suite again; parse the final HTML to check all four metadata/statistics/result counts and local links; compare fresh source hashes with the pre-build hashes. Open the published HTML for user inspection only after these checks pass.

- [ ] **Step 8: Commit Task 3**

Commit the command, tests, module changes, and workspace artifact with message `feat: publish verified RS4PE combined report`.
