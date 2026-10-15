# RS4PE 4-Position Combined Test Report Design

## 1. Purpose

Create one self-contained HTML report that combines the four RS4PE/LHD test reports for DRV, AST, RL, and RR. The combined report must provide a cross-position overview first, then preserve each position's functional summary and complete original Test Results detail.

The source HTML and XML files are evidence artifacts and must remain unchanged.

## 2. Inputs and identity validation

Expected source directory:

`C:\Users\USER.K1109684\Downloads\TestReport`

Expected HTML inputs, ordered by position:

| Order | Source file | Expected position |
|---:|---|---|
| 1 | `2026-10-08_08-18-49_RS4_Test_Report.html` | DRV |
| 2 | `2026-10-08_10-16-56_RS4_Test_Report.html` | AST |
| 3 | `2026-10-08_10-42-10_RS4_Test_Report.html` | RL |
| 4 | `2026-10-08_11-01-20_RS4_Test_Report.html` | RR |

Every source must declare the same values for:

- `Var_Project`: `RS4PE`
- `Var_Drive_Type`: `LHD`
- `Var_EOL_Variant_Type`: `All_DTC_List (defined in test design)`

`Var_SBCM_Position` must be unique and must produce the exact set `DRV`, `AST`, `RL`, `RR`. Generation stops if a source is missing, a position is duplicated, or common metadata differs.

## 3. Output

Final file:

`C:\Users\USER.K1109684\Downloads\TestReport\RS4PE_LHD_Combined_Test_Report.html`

The generator first creates and verifies the file in the workspace. It copies the verified result to the final directory only after all checks pass. If the final file already exists, it is copied to a timestamped backup before replacement.

The output is standalone HTML: no local source HTML, XML, stylesheet, or script dependency is required for viewing.

## 4. Report structure

### 4.1 Combined overview

The top of the report contains:

1. Title: `RS4PE / LHD / DRV · AST · RL · RR`
2. Common metadata table
3. Position navigation buttons in the order DRV, AST, RL, RR
4. Cross-position result table containing position, test start/end time, executed count, Pass, Fail, Inconclusive, Error, and position verdict

Position verdict rules:

- `Fail`: one or more Fail or Error results
- `Pass`: every executed test has Pass and there are no Fail, Error, or Inconclusive results
- `NA`: the available statistics do not satisfy either rule

The overview does not invent or modify individual test verdicts.

### 4.2 Position sections

Each position section contains, in this order:

1. Position header and source metadata
2. Original position statistics
3. Functional Test Summary
4. Complete original Test Results and detailed content
5. A button returning to the combined overview

The Functional Test Summary reuses the established nine categories:

- Diagnostic: C104
- Diagnostic: 강제구동
- Diagnostic: ECU ID
- Input: PWM
- Input: Switch
- Input: Sensor
- Input: Vbat
- Output: HS
- Output: Motor

Each category is collapsed initially. A category button reveals top-level test items; a second button reveals child TC rows.

Existing result semantics are retained:

- Direct Pass/Fail rows use their recorded verdict.
- A numeric category row is `Fail` if any child is Fail.
- A numeric category row is `Pass` if all applicable children are Pass.
- Otherwise it is `NA`.
- Child rows retain their own Pass/Fail/NA indication.
- C104 child rows appear only under C104.
- IO control child rows appear only beneath their `IO_Control_Check_*` parent and are not duplicated in the top-level list.

## 5. Embedding and namespace isolation

The combined document owns one `<html>`, `<head>`, and `<body>`. From each source, the relevant body content is embedded without its outer document wrapper.

To prevent collisions, every position-local identifier is prefixed:

- `DRV__`
- `AST__`
- `RL__`
- `RR__`

The prefix is applied consistently to:

- `id` attributes
- named anchors
- local `href="#..."` references
- summary/detail target IDs
- JavaScript references used by expand/collapse buttons

External URLs are preserved. Shared CSS and expand/collapse JavaScript are included once at the combined-document level.

## 6. Processing flow

1. Discover the four expected source HTML files.
2. Calculate source hashes for immutability checks.
3. Parse and validate project, drive type, EOL variant, and position metadata.
4. Parse original statistics and test-result hierarchy.
5. Build the per-position Functional Test Summary with the current recursive aggregation and deduplication rules.
6. Rewrite position-local identifiers and references with the position prefix.
7. Embed each complete position report into the master HTML in DRV, AST, RL, RR order.
8. Build the combined overview from the four parsed source statistics.
9. Run structural, count, reference, and source-integrity validation.
10. Back up an existing destination file and publish the verified output.

## 7. Mandatory validation

Generation fails without publishing when any of these checks fails:

- Exactly four unique positions are present.
- Common metadata matches across all positions.
- Each position's summary and full Test Results section exists.
- Source statistics equal the statistics copied into the corresponding position section.
- The number of embedded test-result records equals the source record count for each position.
- Every local fragment link resolves to exactly one target.
- No duplicate `id` or named-anchor value exists in the combined document.
- C104 and IO-control detail rows are not duplicated in their position summary.
- Korean text and symbols decode correctly as UTF-8.
- Source file hashes are unchanged after generation.

Three verification layers are required:

1. Input verification: file set, metadata, hashes, and source statistics
2. Transformation verification: hierarchy, verdict aggregation, deduplication, and prefixed references
3. Output verification: HTML structure, link targets, record counts, displayed statistics, and unchanged sources

## 8. Test strategy

Tests are written before generator changes and must include:

- Failure on one missing position
- Failure on duplicate positions
- Failure on project, drive type, or EOL mismatch
- Exact DRV/AST/RL/RR ordering
- Presence of all nine categories for every position
- Correct Pass/Fail/NA aggregation for direct and numeric parent rows
- No duplicate C104 or IO-control summary rows
- Unique IDs and resolvable local links after prefixing
- Per-position source/result count equality
- Combined overview/statistics equality with the four sources
- Source hashes unchanged
- Successful standalone viewing without source-file dependencies

## 9. Non-goals

- Modifying the four source HTML or XML files
- Recalculating or changing recorded individual verdicts
- Merging XML files
- Removing original Test Results detail
- Changing test execution data or timestamps

## 10. Acceptance criteria

The work is accepted when one standalone HTML opens locally, shows `RS4PE / LHD / DRV · AST · RL · RR`, provides a correct combined overview, and lets the user expand each position's summary and full original details without duplicate sections or broken links. All mandatory validations must pass and the four source hashes must remain unchanged.
