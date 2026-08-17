# Usage Guide

This guide documents the configurable analysis workflow in the `TVCG_Analysis_Code_Package` repository. It explains how to run the supplied examples, prepare new datasets, edit configuration files, interpret the automatic statistical decisions, and locate results in the Excel workbook and figures PDF.

For a project overview and quick start, see the repository [README](../README.md).

## 1. Workflow architecture

The repository separates the statistical implementation from study-specific settings:

- `TVCG_Factorial_ANOVA_ART_Analysis.R` is the analysis engine.
- `configs/*.R` files define the data source, factors, outcomes, analysis rules, correlation settings, plots, and output behavior.
- `run_example_1.R` through `run_example_5.R` are launcher scripts covering between-subjects, within-subjects, and mixed designs.
- `examples/*.xlsx` contains synthetic demonstration data.

The configuration object must always be named:

```r
CONFIG
```

For a new analysis, copy and edit `configs/Config_Template.R`. Do not normally edit the engine.

## 2. Repository contents

```text
TVCG_Analysis_Code_Package/
├── README.md
├── TVCG_Factorial_ANOVA_ART_Analysis.R
├── run_example_1.R
├── run_example_2.R
├── run_example_3.R
├── run_example_4.R
├── run_example_5.R
├── configs/
│   ├── Config_Example_1_Default_TVCG.R
│   ├── Config_Example_2_Single_Factor.R
│   ├── Config_Example_3_Two_Factor.R
│   ├── Config_Example_4_Within_Subjects.R
│   ├── Config_Example_5_Mixed_Design.R
│   └── Config_Template.R
├── docs/
│   └── USAGE_GUIDE.md
├── examples/
│   ├── Example_Data_1_Default_TVCG_Format.xlsx
│   ├── Example_Data_2_Single_Factor.xlsx
│   ├── Example_Data_3_Two_Factor.xlsx
│   ├── Example_Data_4_Within_Subjects.xlsx
│   └── Example_Data_5_Mixed_Design.xlsx
└── tests/
    ├── run_design_tests.R
    ├── TEST_CASES.md
    ├── data/
    ├── configs/
    ├── outputs/
    └── results/
```

### Example 1

`Config_Example_1_Default_TVCG.R` analyzes a synthetic `2 × 2 × 4` design using the TVCG-style factor and outcome names.

### Example 2

`Config_Example_2_Single_Factor.R` analyzes a synthetic one-factor between-subjects design with one three-level factor. It demonstrates that the same engine can fit a one-factor ANOVA or ART-ANOVA model and automatically omit interaction-specific analyses and figures.

### Example 3

`Config_Example_3_Two_Factor.R` analyzes a synthetic `2 × 3` between-subjects design with factor and outcome names unrelated to the TVCG study. It demonstrates complete two-factor analysis including both main effects and the two-way interaction.

### Example 4

`Config_Example_4_Within_Subjects.R` analyzes a synthetic `2 × 6` all-within-subjects design. `DisplayMode` has two levels and `TaskPhase` has six ordered levels (`Acquisition 1`, `Acquisition 2`, `Practice 1`, `Practice 2`, `Transfer`, and `Retention`). With 32 participants, the dataset therefore contains 384 repeated-measures rows. `AccuracyPct`, `ResponseTimeMs`, `MentalEffort`, and `ConfidenceRating` are approximately normal continuous outcomes intended to exercise repeated-measures ANOVA under automatic selection, whereas `ErrorCount` is deliberately zero-inflated and positively skewed to exercise pure within-subjects ART-ANOVA in the same run.

### Example 5

`Config_Example_5_Mixed_Design.R` analyzes a synthetic mixed design with one two-level between-subject factor and one three-level within-subject factor.

## 3. R environment and packages

The statistical engine has passed the 16-case synthetic regression suite in the target R environment, and the v37 warning-audit run completed with no unexpected warnings. Version 35 expanded Example 4 to a 2 × 6 fully within-subjects dataset, Version 36 removed deprecated tidyselect `.data` references, Version 37 added full warning auditing, and Version 38 adds isolated smoke execution of all five supplied repository examples without changing the statistical engine. RStudio is optional.

The engine uses:

```r
c(
  "readxl", "readr", "dplyr", "tidyr", "purrr", "stringr", "tibble",
  "car", "afex", "lme4", "ARTool", "emmeans", "ggplot2", "openxlsx", "fs", "rlang",
  "patchwork"
)
```

The supplied configurations use:

```r
packages = list(
  auto_install = TRUE,
  repository = "https://cloud.r-project.org"
)
```

With `auto_install = TRUE`, missing packages are installed from the configured CRAN repository. Set it to `FALSE` when package installation is managed externally.

The script records the R version and session information in the run outputs when logs are enabled.

## 4. Running the supplied examples

### 4.1 RStudio or R console

From the repository folder:

```r
source("run_example_1.R")
```

or:

```r
source("run_example_2.R")
```

or:

```r
source("run_example_3.R")
```

or:

```r
source("run_example_4.R")
```

or:

```r
source("run_example_5.R")
```

The launcher scripts determine their own directory before locating the engine and configuration file. This avoids relying on the active working directory in most RStudio, `source()`, and `Rscript` workflows.

### 4.2 Direct engine call

```r
source("TVCG_Factorial_ANOVA_ART_Analysis.R")
run_analysis("configs/Config_Example_1_Default_TVCG.R")
```

### 4.3 Command line

```bash
Rscript TVCG_Factorial_ANOVA_ART_Analysis.R configs/Config_Example_1_Default_TVCG.R
```

### 4.4 Automated release checks

The default test command now runs both the 16 synthetic regression cases and five smoke tests that execute the actual repository launchers:

```bash
Rscript tests/run_design_tests.R
```

Useful variants are:

```bash
Rscript tests/run_design_tests.R --quick
Rscript tests/run_design_tests.R --smoke-only
Rscript tests/run_design_tests.R --skip-smoke
Rscript tests/run_design_tests.R --case=T07
Rscript tests/run_design_tests.R --case=E04
```

`E01`–`E05` copy the real launcher, engine, matching configuration, and matching example workbook into isolated smoke sandboxes before execution, so relative paths are tested without writing generated files into the repository's `examples/` folder. In addition to workbook/PDF/log creation and workbook-structure checks, Example 4 must preserve the 2 × 6 fully within-subjects design and exercise both repeated-measures ANOVA and ART-ANOVA; Example 5 must exercise both mixed ANOVA and mixed ART-ANOVA. The v37 warning audit remains active for both layers: emitted warning conditions and warnings recorded internally by the engine are collected into `test_warnings.csv` and `test_warning_summary.csv`, and unexpected warnings fail the release gate. See `tests/TEST_CASES.md` for the full matrix.

## 5. Preparing input data

Supported input formats are:

```text
.xlsx
.xls
.csv
.tsv
.txt
.rds
```

For Excel files, specify the worksheet name or number in `input$sheet`.

### 5.1 Wide format

Wide outcome format is recommended. Each dependent variable has its own column. In an all-between-subjects design, each participant normally appears once. In a design with within-subject factors, the same participant appears on multiple rows—one row for each within-condition cell.

```text
ID | FactorA | FactorB | FactorC | Outcome1 | Outcome2
1  | Low     | Text    | C1      | 4.2      | 75
2  | High    | Audio   | C2      | 5.1      | 82
```

Configuration:

```r
input = list(
  file = "../examples/my_data.xlsx",
  sheet = "Sheet1",
  data_format = "wide",
  id_column = "ID",
  long = list(
    outcome_name_column = "OutcomeName",
    outcome_value_column = "OutcomeValue"
  )
)
```

The `long` fields are ignored in wide-format analyses.

### 5.2 Long format

Long format stores outcome names and values in two columns.

```text
ID | FactorA | FactorB | OutcomeName | OutcomeValue
1  | Low     | Text    | Outcome1   | 4.2
1  | Low     | Text    | Outcome2   | 75
```

Configuration:

```r
input = list(
  file = "../examples/my_long_data.csv",
  sheet = NULL,
  data_format = "long",
  id_column = "ID",
  long = list(
    outcome_name_column = "OutcomeName",
    outcome_value_column = "OutcomeValue"
  )
)
```

Each ID/factor/outcome combination must be unique. The engine converts valid long-format input to wide format internally.

### 5.3 Identifier and repeated-row requirements

The ID column identifies the participant or experimental unit. For an all-between-subjects design, each ID must appear once. When one or more factors are configured as `within`, repeated IDs are required: each participant should contribute exactly one row for every configured within-factor condition. Between-subject factor values must remain constant within an ID. Duplicate rows for the same ID and within-condition combination are rejected because the engine expects one already-aggregated observation per repeated cell.

For each dependent variable, participants missing one or more required within-condition cells after outcome-specific missing-value filtering are excluded from that dependent-variable analysis so the repeated-measures cell structure remains complete.

### 5.4 Factor values

Configured factor levels must match the values in the input data after conversion to text. Differences in capitalization, spaces, punctuation, or numeric formatting can cause an unknown-level error.

### 5.5 Outcome values

Outcome columns are converted to numeric. Non-numeric values that cannot be converted become missing and are recorded in the conversion report. Factor-valued outcomes are converted through their displayed text rather than internal factor codes.

## 6. Creating a configuration file

Copy the template:

```text
configs/Config_Template.R
```

Rename it, for example:

```text
configs/Config_My_Study.R
```

Keep the object name unchanged:

```r
CONFIG <- list(...)
```

Relative paths in a configuration are resolved relative to that configuration file.

## 7. Configuration reference

### 7.1 `input`

```r
input = list(
  file = "../examples/your_data.xlsx",
  sheet = "Sheet1",
  data_format = "wide",
  id_column = "ID",
  long = list(
    outcome_name_column = "OutcomeName",
    outcome_value_column = "OutcomeValue"
  )
)
```

#### `input$file`

Path to the input file. Relative paths are evaluated from the configuration directory.

#### `input$sheet`

Excel worksheet name or number. Ignored for CSV, TSV, TXT, and RDS input.

#### `input$data_format`

Accepted values:

```r
"wide"
"long"
```

#### `input$id_column`

Exact name of the participant or experimental-unit identifier column.

#### `input$long`

Used only for long-format data:

- `outcome_name_column`: column containing outcome names;
- `outcome_value_column`: column containing outcome values.

### 7.2 `factors`

Exactly one, two, or three factors must be enabled.

```r
factors = data.frame(
  code = c("X1", "X2", "X3"),
  column = c("Factor1Column", "Factor2Column", "Factor3Column"),
  label = c("Factor 1", "Factor 2", "Factor 3"),
  short_label = c("F1", "F2", "F3"),
  role = c("between", "between", "within"),
  enabled = c(TRUE, TRUE, TRUE),
  stringsAsFactors = FALSE
)
```

#### `code`

Short internal name used in formulas and output tables. Codes must be unique and valid R names. Simple values such as `X1`, `X2`, and `X3` are recommended.

#### `column`

Exact factor-column name in the input data.

#### `label`

Full factor name used in tables, axes, and legends.

#### `short_label`

Compact label used in interaction-plot titles.

#### `role`

Design role of the factor:

```r
"between"
"within"
```

Any combination of roles is supported as long as one to three total factors are enabled. All `between` gives an independent-groups design, all `within` gives a repeated-measures design, and a combination gives a mixed design.

#### `enabled`

- `TRUE`: include the factor;
- `FALSE`: ignore the factor.

### 7.3 `factor_levels`

```r
factor_levels = list(
  X1 = c("Low", "High"),
  X2 = c("Text", "Audio"),
  X3 = c("C1", "C2", "C3")
)
```

The list names must match enabled factor codes. Level order controls:

- factor coding;
- table order;
- axis order;
- legend order; and
- pairwise-comparison direction.

Every observed factor value must appear in the corresponding configured level vector. Configured but unobserved combinations are reported as empty cells.

### 7.4 `outcomes`

```r
outcomes = data.frame(
  column = c("Outcome1Column", "Outcome2Column"),
  label = c("Outcome 1", "Outcome 2"),
  category = c("Category A", "Category B"),
  enabled = c(TRUE, TRUE),
  include_in_correlation = c(TRUE, TRUE),
  stringsAsFactors = FALSE
)
```

#### `column`

Exact source-column name in the input data.

#### `label`

Display name used in tables and figures. Labels must be unique.

#### `category`

Organizational label used to group and order PDF pages. It does not change the statistical model.

#### `enabled`

Controls ANOVA/ART-ANOVA analysis for the variable.

#### `include_in_correlation`

Controls whether the variable is included in the correlation module. This setting is independent of `enabled`.

#### Automatic outcome detection

Set:

```r
outcomes = NULL
```

The engine then detects numeric columns other than the ID and enabled factor columns. Automatically detected outcomes are assigned to `Uncategorized`.

Explicit outcome definitions are recommended for reproducible public code because they preserve labels, categories, order, and correlation inclusion decisions.

### 7.5 `analysis`

```r
analysis = list(
  alpha = 0.05,
  method_selection = "automatic",
  anova_type = 3,
  levene_center = "median",
  p_adjust = "bonferroni",
  minimum_valid_n = 10,
  random_seed = 20260731
)
```

#### `analysis$alpha`

Statistical significance threshold used for assumption decisions, omnibus effects, and plot annotations unless another module has its own threshold.

#### `analysis$method_selection`

Accepted values:

```r
"automatic"
"anova"
"art"
```

- `automatic`: select ANOVA only when both assumption tests are non-significant; otherwise select ART-ANOVA.
- `anova`: always use parametric ANOVA.
- `art`: always use ART-ANOVA.

#### `analysis$anova_type`

Type of sums of squares passed to `car::Anova()` for parametric analyses. The supplied configurations use Type III:

```r
anova_type = 3
```

The engine uses sum-to-zero contrasts while running the analysis.

#### `analysis$levene_center`

Accepted values:

```r
"median"
"mean"
```

The supplied configurations use median-centered Levene tests.

#### `analysis$sphericity_correction`

Used by parametric analyses containing within-subject factors:

```r
"GG"    # Greenhouse-Geisser (default)
"HF"    # Huynh-Feldt
"none"  # uncorrected
```

The setting is ignored for all-between-subjects designs. The repeated/mixed ANOVA path is fitted with `afex::aov_ez`; the configured correction is applied to within-subject effects where relevant.

#### `analysis$p_adjust`

Multiplicity adjustment used for main-effect pairwise comparisons and interaction follow-up analyses. The supplied configurations use:

```r
p_adjust = "bonferroni"
```

Use an adjustment method supported by the underlying R procedures.

#### `analysis$minimum_valid_n`

Minimum valid sample size required before attempting an outcome analysis.

#### Complete model

The engine always uses the complete model implied by all enabled factors. There is no maximum-interaction-order option.

One-factor example:

```r
Y ~ X1
```

Two-factor example:

```r
Y ~ X1 * X2
```

Three-factor example:

```r
Y ~ X1 * X2 * X3
```

All enabled main effects are calculated and exported. For two- and three-factor designs, every available interaction is also calculated and exported. Manuscript reporting decisions remain with the analyst.

For a one-factor design, the interaction-specific Excel worksheets remain in the workbook for structural consistency but contain a no-results note, and no interaction-effects PDF page is created.

#### `analysis$random_seed`

Used for reproducible internal sampling, including Shapiro–Wilk evaluation when more than 5,000 values are available. In that case, a random sample of 5,000 observations is used and documented.

### 7.6 `correlation`

```r
correlation = list(
  enabled = TRUE,
  minimum_complete_pairs = 10,
  normality_alpha = 0.05,
  p_adjust = "bonferroni",
  label_wrap_width = 18
)
```

#### `correlation$enabled`

Master switch for the complete correlation module.

```r
enabled = TRUE
```

When `FALSE`, correlation tests and the heatmap are skipped. The workbook retains the correlation worksheet positions with no computed correlation results so that the workbook structure remains predictable.

#### `correlation$minimum_complete_pairs`

This value has two roles:

- each variable needs at least this many finite observations to be eligible for global Pearson selection;
- each variable pair needs at least this many pairwise-complete observations for a correlation test.

#### `correlation$normality_alpha`

Threshold used for the global Pearson/Spearman decision.

Each included variable is evaluated once using all of its finite observations. Pearson is selected only when every included variable:

1. has at least `minimum_complete_pairs` finite observations;
2. has at least three unique finite values; and
3. has Shapiro–Wilk `p >= normality_alpha`.

If any included variable fails or cannot be evaluated, Spearman is used for all tested pairs.

This global decision ensures that one correlation matrix contains one consistent coefficient type.

#### `correlation$p_adjust`

Multiplicity adjustment applied across all successfully tested variable pairs. The adjusted values determine the significance symbols in the heatmap.

#### `correlation$label_wrap_width`

Approximate character width used to wrap long variable labels on the correlation heatmap axes.

#### Pairwise missing values

After the global method is selected, each correlation is calculated using the finite observations shared by that variable pair. As a result, `N_Complete` may differ among pairs. For repeated/mixed designs, participant-level aggregation preserves the original configured source-column names; the engine now validates those columns before testing so a preparation failure is reported explicitly rather than silently producing `N = 0` correlation rows.

#### Heatmap layout

- lower triangle: correlation coefficients;
- upper triangle: adjusted-*p* significance symbols;
- diagonal: blank;
- unavailable pairs: `NA`.

The title reports the globally selected method.

### 7.7 `plots`

```r
plots = list(
  create_pdf = TRUE,
  error_bar = "sd",
  main_alpha = 0.65,
  interaction_alpha = 1.00,
  factor_colors = list(...),
  base_font_size = 11,
  stat_font_size = 9.5,
  title_wrap_width = 58,
  page_title_wrap_width = 70,
  interaction_ncol = 4,
  caption_wrap_width = 58,
  pdf_width = 16,
  pdf_height = 9,
  category_order = c(...),
  three_way_mapping = list(
    x = "X1",
    color = "X2",
    facet = "X3"
  ),
  three_way_facet_rows = 2
)
```

#### `plots$create_pdf`

Set to `FALSE` to skip PDF generation.

#### `plots$error_bar`

Accepted values:

```r
"sd"
"se"
```

The selected measure is used in main-effect and interaction plots.

#### Transparency

- `main_alpha`: opacity of main-effect bars;
- `interaction_alpha`: opacity of interaction lines, points, and error bars.

#### `plots$factor_colors`

Named colors for each configured factor level.

```r
factor_colors = list(
  X1 = c(Low = "#66C2A5", High = "#FC8D62"),
  X2 = c(Text = "#8DA0CB", Audio = "#E78AC3")
)
```

Names must match configured factor levels. Consistent factor-level colors are reused across plots.

#### Font sizes

- `base_font_size`: general ggplot text size;
- `stat_font_size`: omnibus statistic annotation size.

The script does not require a user-installed custom font. PDF and Excel outputs inherit standard device or workbook defaults unless the engine is modified to specify a font family.

#### Title and caption wrapping

- `title_wrap_width`: individual plot-title wrapping; supplied configurations use `58`.
- `page_title_wrap_width`: category and dependent-variable page heading wrapping.
- `caption_wrap_width`: interaction-caption wrapping.

#### `plots$interaction_ncol`

Number of interaction plots per PDF row.

#### PDF dimensions

`pdf_width` and `pdf_height` are in inches.

#### `plots$category_order`

Controls the order of category sections in the PDF. Categories not listed can still be retained after configured categories, depending on the generated results.

#### Three-way mapping

For exactly three enabled factors, define which factor appears on each visual channel. This setting is ignored for one- and two-factor designs:

```r
three_way_mapping = list(
  x = "X1",
  color = "X2",
  facet = "X3"
)
```

The three entries must be distinct enabled factor codes.

`three_way_facet_rows` controls the number of facet rows.

### 7.8 `output`

```r
output = list(
  directory = NULL,
  save_art_diagnostics = TRUE,
  save_logs = TRUE
)
```

#### `output$directory`

When `NULL`, the engine creates:

```text
<input_file_stem>_analysis_results/
```

next to the input file.

Supply a relative or absolute path to use a custom output directory. Relative output paths are resolved from the configuration directory.

#### `output$save_art_diagnostics`

Controls creation of the `art_diagnostics/` directory and ART diagnostic files.

#### `output$save_logs`

Controls creation of the `logs/` directory and reproducibility files.

### 7.9 `packages`

```r
packages = list(
  auto_install = TRUE,
  repository = "https://cloud.r-project.org"
)
```

Set `auto_install = FALSE` when installation should not be performed by the analysis script.

## 8. Statistical analysis logic

### 8.1 Input and design validation

The engine checks, among other conditions:

- missing input files or worksheets;
- missing ID, factor, or outcome columns;
- invalid or duplicate factor codes;
- duplicate outcome labels;
- conflicting ID, factor, and outcome columns;
- unknown factor levels;
- duplicated IDs;
- empty design cells;
- numeric-conversion failures;
- missing and non-finite outcome values;
- insufficient valid observations;
- constant outcomes;
- rank-deficient models; and
- unavailable residual degrees of freedom.

Warnings and recoverable errors are collected in `Warnings_Errors` (`24` for all-between; `25` for within/mixed) so that one failed follow-up analysis does not necessarily stop every other outcome.

### 8.2 Assumption testing

For each outcome, the engine fits a design-appropriate residual model and evaluates:

- Shapiro–Wilk normality of model residuals;
- Levene homogeneity of variance for designs containing between-subject variation. For mixed designs, the between-group Levene diagnostic is evaluated separately within each repeated-measures condition and the smallest evaluable p-value is reported; for all-within designs Levene testing is not performed and Levene fields are omitted from the Excel output.

When more than 5,000 residuals are available, `safe_shapiro()` uses a reproducible random sample of 5,000.

Cell-level Shapiro–Wilk diagnostics are also exported for inspection. For all-between designs, automatic method selection uses residual normality and Levene's test. For all-within designs, selection uses residual normality and the Excel output omits Levene fields entirely. Mixed designs use residual normality plus the between-group Levene diagnostic. When a repeated/mixed parametric ANOVA is fitted, Mauchly tests are extracted effect-wise for non-trivial within-subject effects together with Greenhouse–Geisser and Huynh–Feldt epsilon/corrected p values. Sphericity controls the repeated-measures correction, not the ANOVA-versus-ART switch.

### 8.3 Automatic method selection

With:

```r
method_selection = "automatic"
```

For all-between designs, ANOVA is selected when the required residual-normality and Levene diagnostics have:

```text
p >= analysis$alpha
```

For all-within designs, only the residual-normality diagnostic participates in automatic ANOVA-versus-ART selection. Mixed designs require residual normality plus the between-group Levene screening to pass. ART-ANOVA is selected when any diagnostic required by the configured design rejects the assumption or is unavailable. Mauchly sphericity results are reported separately and, when parametric repeated-measures ANOVA is used, determine whether the configured GG/HF correction is consequential.

The selected method and reason are recorded for every dependent variable and shown in the PDF page titles.

### 8.4 Parametric ANOVA

For all-between designs, the parametric branch uses the complete `lm` model and `car::Anova()` with the configured sums-of-squares type. For within/mixed designs, it uses `afex::aov_ez()`, which in turn uses the repeated-measures `car::Anova` machinery. The supplied configurations use Type III tests with sum-to-zero contrasts.

### 8.5 ART-ANOVA

The nonparametric branch uses `ARTool::art()` and the complete model. The engine checks ART alignment diagnostics and records diagnostic output when enabled.

### 8.6 Omnibus effect sizes

The omnibus output includes:

- effect code and label;
- numerator and denominator degrees of freedom;
- *F* statistic;
- *p* value;
- partial eta-squared;
- Cohen's *f*; and
- qualitative magnitude.

The qualitative partial eta-squared labels use these thresholds:

```text
< .01       negligible
.01–< .06   small
.06–< .14   medium
>= .14      large
```

For ART-ANOVA, effect sizes are calculated from the aligned-rank analysis and identified accordingly.

### 8.7 Main-effect comparisons

- ANOVA branch: estimated marginal means followed by pairwise contrasts.
- ART branch: ART-compatible contrasts.
- Multiplicity adjustment follows `analysis$p_adjust`.
- Significant adjusted comparisons that can be mapped to configured factor levels are drawn as brackets on main-effect plots.

The main-posthoc worksheet includes parsing and annotation-eligibility fields so bracket mapping can be audited.

### 8.8 Interaction follow-up analyses

The engine attempts:

- comparisons among interaction cells;
- difference-of-differences contrasts for two-way interactions; and
- higher-order contrasts for three-way interactions.

Sparse, empty, or non-estimable combinations may prevent some contrasts. These cases are recorded rather than silently replaced with artificial values.

### 8.9 Descriptive statistics

The workbook includes:

- overall descriptive statistics for each outcome;
- descriptive statistics grouped by each main-effect factor; and
- descriptive statistics for each interaction combination.

The configured factor order is enforced in all relevant worksheets.

### 8.10 Significance notation

The PDF uses:

```text
p < 0.001   ***
p < 0.01    **
p < 0.05    *
p < 0.10    .
p >= 0.10   n.s.
```

The dot indicates a trend-level result under this display convention, not significance at `alpha = .05`.

## 9. Output directory and files

Default output structure:

```text
<input_file_stem>_analysis_results/
├── <input_file_stem>_statistical_results.xlsx
├── <input_file_stem>_figures.pdf
├── logs/
└── art_diagnostics/
```

The PDF is omitted when `plots$create_pdf = FALSE` or when no plot can be generated. Log and ART diagnostic directories are created only when their output switches are enabled.

## 10. Excel workbook reference

The workbook is design-adaptive. All-between-subjects designs omit the repeated-measures sphericity worksheet and all sphericity-only columns. All-within-subjects designs omit Levene columns entirely. Mixed designs retain both the between-group Levene diagnostics and repeated-measures sphericity diagnostics.

Worksheet prefixes are assigned after all conditional sheets have been included or omitted, so numbering is always contiguous. The same logical worksheet may therefore have a different numeric prefix in all-between versus repeated designs.

| Logical worksheet | All-between number | Within/mixed number | Purpose |
|---|---:|---:|---|
| `Run_Info` | `00` | `00` | Input, configuration, software, timing, and output-path information; inapplicable design rows are omitted. |
| `Analysis_Summary` | `01` | `01` | One-row summary of method selection and significant effects; diagnostic columns vary by design. |
| `Outcome_Spec` | `02` | `02` | Outcome labels, source columns, categories, and analysis/correlation switches. |
| `Factor_Spec` | `03` | `03` | Factor codes, labels, source columns, roles, and configured levels. |
| `Design_Cell_Counts` | `04` | `04` | Counts for every configured design cell, including empty cells. |
| `Conversion_Report` | `05` | `05` | Numeric-conversion checks for outcome columns. |
| `Missing_Summary` | `06` | `06` | Missing-data counts and percentages by outcome. |
| `Assumption_Tests` | `07` | `07` | Design-specific residual Shapiro--Wilk diagnostics, Levene diagnostics only when between-subject variation exists, repeated correction setting when relevant, and selected method. |
| `Sphericity_Tests` | -- | `08` | Effect-wise Mauchly tests, uncorrected p values, GG/HF epsilon and corrected p values, and the configured applied correction. |
| `Cell_Shapiro` | `08` | `09` | Optional Shapiro--Wilk diagnostics within design cells. |
| `Model_Summary` | `09` | `10` | Formula, sample size, residual degrees of freedom, model summaries, and ART diagnostics; sphericity fields are omitted for all-between designs. |
| `Overall_Desc` | `10` | `11` | Overall descriptive statistics. |
| `Main_Desc` | `11` | `12` | Descriptive statistics by each main-effect factor. |
| `Interaction_Desc` | `12` | `13` | Descriptive statistics by interaction combinations. |
| `Omnibus_Effects` | `13` | `14` | Main effects and interactions with test statistics and effect sizes. |
| `Significant_Effects` | `14` | `15` | Omnibus effects with `p < alpha`, preserving configured order. |
| `Main_Posthoc` | `15` | `16` | Main-effect pairwise comparisons and bracket-mapping diagnostics. |
| `Interaction_Cells` | `16` | `17` | Pairwise comparisons among interaction cells. |
| `Interaction_Contrasts` | `17` | `18` | Difference-of-differences and higher-order interaction contrasts. |
| `Correlation_Normality` | `18` | `19` | Variable-level diagnostics and the global Pearson/Spearman decision. |
| `Correlation_Results` | `19` | `20` | Pairwise correlation tests, sample sizes, method, coefficients, and adjusted p values. |
| `Correlation_Coeff` | `20` | `21` | Symmetric correlation-coefficient matrix. |
| `Correlation_Adj_p` | `21` | `22` | Symmetric adjusted-p matrix. |
| `Correlation_Methods` | `22` | `23` | Matrix confirming the single method used throughout the correlation analysis. |
| `Plot_Index` | `23` | `24` | Figure type and PDF page index. |
| `Warnings_Errors` | `24` | `25` | Captured warnings and recoverable errors. |

Thus, for an all-between design, `07_Assumption_Tests` is followed immediately by `08_Cell_Shapiro`; there is no unused worksheet number. For within/mixed designs, `08_Sphericity_Tests` is present and the downstream sheets shift by one position.

Each worksheet includes a right-side section describing only the columns actually present in that design-specific output. Column order follows a common hierarchy:

1. outcome/variable identifiers and categories;
2. design, factor, effect, contrast, or grouping identifiers;
3. method and sample-size metadata where relevant;
4. test statistics, degrees of freedom, estimates, and confidence intervals;
5. p values, multiplicity adjustment, effect sizes, and significance fields; and
6. diagnostic notes or messages.

Factor columns follow the enabled factor order defined in the configuration. Pairwise factor columns are placed with the contrast identifiers before estimates and test statistics. The writer also checks for unexpected identifier/grouping columns generated upstream and places them before remaining statistical columns rather than appending them at the far right.

For repeated parametric ANOVA, Mauchly tests are inherently effect-specific. A two-level within-subject effect does not require a non-trivial sphericity test; such effects may therefore have no Mauchly row even though their omnibus ANOVA result is present. If ART-ANOVA is selected for a repeated outcome, the sphericity worksheet records that Mauchly testing is not applicable to that ART mixed-effects path.

When correlation analysis is disabled or cannot be performed, the corresponding correlation worksheets remain in their logical positions but contain no computed test results or only the available diagnostic information.

## 11. Figures PDF reference

### 11.1 Category title pages

Each category with generated plots begins with a title page containing the significance notation.

### 11.2 Main-effects pages

The page title contains the dependent variable, page type, and selected method, for example:

```text
Social Presence — Main Effects (ANOVA)
```

Each enabled factor receives a main-effect plot. The plots include:

- mean ± configured error bar;
- omnibus statistic annotation;
- consistent factor-level colors;
- significant adjusted pairwise brackets when available; and
- a caption reporting the number of significant adjusted comparisons.

### 11.3 Interaction-effects pages

Two-way and three-way interaction plots are placed on the interaction page. Plot titles use factor short labels where configured. Captions summarize the number of significant interaction contrasts or direct the user to the warning worksheet when contrasts are unavailable.

### 11.4 Correlation heatmap

When correlation analysis succeeds, the heatmap is appended after the ANOVA/ART-ANOVA pages.

- The title identifies Pearson or Spearman.
- The lower triangle contains coefficients.
- The upper triangle contains significance symbols based on adjusted *p* values.
- The diagonal is blank.

### 11.5 PDF fonts and mathematical symbols

The script controls font sizes but does not require a custom locally installed font family. Standard R PDF-device and ggplot defaults are used.

Partial eta-squared is rendered with R plotmath rather than Unicode subscript characters. This reduces missing-glyph problems in PDF output.

## 12. Adapting the template to a new study

### Step 1: copy the template

```text
configs/Config_Template.R
```

to:

```text
configs/Config_My_Study.R
```

### Step 2: set the input file

```r
input = list(
  file = "../examples/My_Study_Data.xlsx",
  sheet = "Data",
  data_format = "wide",
  id_column = "ParticipantID",
  long = list(
    outcome_name_column = "Measure",
    outcome_value_column = "Value"
  )
)
```

### Step 3: define factors

```r
factors = data.frame(
  code = c("F1", "F2", "F3"),
  column = c("InterfaceStyle", "FeedbackMode", "TaskDifficulty"),
  label = c("Interface Style", "Feedback Mode", "Task Difficulty"),
  short_label = c("Interface", "Feedback", "Difficulty"),
  enabled = c(TRUE, TRUE, TRUE),
  stringsAsFactors = FALSE
)
```

For a two-factor design, enable two rows:

```r
enabled = c(TRUE, TRUE, FALSE)
```

For a one-factor design, enable one row:

```r
enabled = c(TRUE, FALSE, FALSE)
```

Only enabled factors need matching entries in `factor_levels`; unused entries may remain in the template but are ignored.

### Step 4: define factor levels

```r
factor_levels = list(
  F1 = c("Minimal", "Immersive"),
  F2 = c("None", "Visual", "Multimodal"),
  F3 = c("Easy", "Hard")
)
```

### Step 5: define outcomes

```r
outcomes = data.frame(
  column = c(
    "AccuracyPct",
    "CompletionTimeSec",
    "MentalEffort",
    "SystemUsability"
  ),
  label = c(
    "Accuracy",
    "Completion Time",
    "Mental Effort",
    "System Usability"
  ),
  category = c(
    "Task Performance",
    "Task Performance",
    "Workload",
    "User Experience"
  ),
  enabled = rep(TRUE, 4),
  include_in_correlation = rep(TRUE, 4),
  stringsAsFactors = FALSE
)
```

### Step 6: set category order and colors

```r
plots = list(
  # Other fields omitted here.
  factor_colors = list(
    F1 = c(Minimal = "#66C2A5", Immersive = "#FC8D62"),
    F2 = c(None = "#F8766D", Visual = "#00BA38", Multimodal = "#619CFF"),
    F3 = c(Easy = "#8DA0CB", Hard = "#E78AC3")
  ),
  category_order = c("Task Performance", "Workload", "User Experience"),
  three_way_mapping = list(
    x = "F1",
    color = "F2",
    facet = "F3"
  )
)
```

Do not replace the complete `plots` list with only this abbreviated example. Edit the corresponding fields in the template.

### Step 7: validate configuration lengths

All columns in the `factors` data frame must have the same length. All columns in the `outcomes` data frame must also have the same length.

### Step 8: run the analysis

```r
source("TVCG_Factorial_ANOVA_ART_Analysis.R")
run_analysis("configs/Config_My_Study.R")
```

### Step 9: review diagnostics before reporting

At minimum, inspect:

- `04_Design_Cell_Counts`;
- `05_Conversion_Report`;
- `06_Missing_Summary`;
- `07_Assumption_Tests`;
- `Model_Summary` (`09` for all-between; `10` for within/mixed);
- `Omnibus_Effects` (`13` for all-between; `14` for within/mixed);
- relevant post-hoc sheets;
- `Correlation_Normality` (`18` for all-between; `19` for within/mixed) when correlation is enabled; and
- `Warnings_Errors` (`24` for all-between; `25` for within/mixed).

## 13. Default TVCG-style example

The default synthetic workbook contains:

### Factors

- `Appearance-Fidelity`: `H`, `L`;
- `Speech-Fidelity`: `H`, `L`;
- `Character-Identity`: `1(M1)`, `2(M2)`, `3(F1)`, `4(F2)`.

The design contains 16 factorial cells and 160 synthetic rows.

### Outcomes

- Communication Effectiveness;
- Communication Intention;
- Social Presence;
- Interpersonal Trust;
- Perceived Humanness;
- Eeriness;
- Attractiveness;
- Anthropomorphism;
- Animacy;
- Likeability;
- Perceived Intelligence;
- Perceived Safety;
- Perceived Appearance Realism;
- Perceived Speech Realism;
- Perceived Overall Realism.

The workbook contains only the analysis-ready `Sheet1`. It does not contain original participant data.

## 14. Troubleshooting

### Configuration file not found

Check the path passed to `run_analysis()`. Relative paths are interpreted from the current call when locating the configuration, while paths inside the configuration are interpreted from the configuration directory.

### Input file not found

Check `CONFIG$input$file`. For a configuration in `configs/`, an example file in `examples/` is normally referenced with:

```r
file = "../examples/FileName.xlsx"
```

### Excel worksheet not found

Verify `input$sheet` exactly matches the workbook sheet name. Sheet numbers can also be used.

### Input column is missing

Check exact spelling, capitalization, spaces, punctuation, and hyphens in:

- `input$id_column`;
- `factors$column`;
- `outcomes$column`; and
- long-format column settings.

### Unknown factor level

Add every observed value to the relevant `factor_levels` entry or correct the input value. Avoid invisible trailing spaces in spreadsheets.

### Duplicate IDs or repeated-cell errors

Duplicate IDs are invalid only for an all-between-subjects configuration. In within-subjects and mixed designs, repeated IDs are expected, but each ID × within-condition combination must be unique. If the engine reports duplicate repeated cells, aggregate or otherwise resolve those observations before analysis.

### Outcome conversion failures

Inspect `05_Conversion_Report`. Text such as units, symbols, or non-numeric response labels cannot be analyzed directly as numeric outcomes.

### Empty cells or rank deficiency

Inspect `04_Design_Cell_Counts`, `Model_Summary` (`09` for all-between; `10` for within/mixed), and `Warnings_Errors` (`24` for all-between; `25` for within/mixed). Empty design cells can make Type III effects or follow-up contrasts non-estimable.

### ANOVA selected unexpectedly

Inspect `07_Assumption_Tests` and confirm `analysis$method_selection = "automatic"`. All-between designs require both residual Shapiro–Wilk and Levene diagnostics to pass. All-within designs use the residual-normality diagnostic and do not export Levene fields. Mixed designs use residual normality plus the configured between-group Levene diagnostic. For repeated parametric ANOVA, inspect `08_Sphericity_Tests` separately for Mauchly and GG/HF results.

### ART-ANOVA selected unexpectedly

The automatic rule selects ART when any diagnostic required for the configured design fails or cannot be evaluated. Inspect the design-aware selection reason in `07_Assumption_Tests`.

### Main-effect brackets are missing

Inspect `Main_Posthoc` (`15` for all-between; `16` for within/mixed):

- confirm the adjusted `p.value` is below `analysis$alpha`;
- check `Group1` and `Group2`;
- check `Annotation_Eligible`;
- review `Warnings_Errors` (`24` for all-between; `25` for within/mixed) for parsing or post-hoc failures.

### Interaction contrast unavailable

Sparse or non-estimable cells may prevent an interaction contrast. The error is recorded in `Warnings_Errors` (`24` for all-between; `25` for within/mixed), while other valid analyses continue.

### Correlation analysis uses Spearman

Inspect `Correlation_Normality` (`18` for all-between; `19` for within/mixed). Spearman is selected globally when any included variable fails or cannot be evaluated under the Pearson eligibility rule.

To exclude a problematic variable from the correlation matrix without disabling its ANOVA/ART-ANOVA analysis, set its `include_in_correlation` value to `FALSE`.

### Correlation pair is `NA`

A variable pair may be unavailable because:

- it has fewer than `minimum_complete_pairs` shared finite observations;
- one variable is constant within the shared observations; or
- `cor.test()` returned an error.

Inspect `Correlation_Results` (`19` for all-between; `20` for within/mixed) and `Warnings_Errors` (`24` for all-between; `25` for within/mixed).

### PDF is not created

Check:

```r
plots$create_pdf
```

and inspect `Warnings_Errors` (`24` for all-between; `25` for within/mixed). A PDF is not written when plotting is disabled or no plot can be generated.

### Font-family warning

The default script does not require Arial, Times New Roman, or another custom installed font. Adding a custom font family to the engine or themes can make the workflow dependent on local font availability.

### Excel reports repaired content

Do not manually rename a worksheet header inside an existing structured Excel table without updating the table metadata. The supplied Example 1 workbook has been rebuilt without an Excel table object and contains only `Sheet1`, avoiding stale `/xl/tables/table1.xml` metadata.

### Package built under another R version

A warning that a package was built under a different R version is usually a compatibility warning rather than an analysis result. Update R and reinstall packages when necessary.

## 15. Reproducibility notes

- The engine temporarily uses sum-to-zero contrasts and restores the caller's R options after completion.
- The configured random seed is used for reproducible internal sampling.
- The caller's random-number state is restored after analysis.
- Output paths are derived consistently from the input file unless overridden.
- When logs are enabled, the run records timing, configuration, engine, console output, and R session information.
- Synthetic example data are for software demonstration only.

## 16. Scope and limitations

- One, two, or three enabled factors are supported; each may be between-subjects or within-subjects.
- Classical all-within-subjects and mixed between/within ANOVA designs are supported. Arbitrary nested designs, crossed random effects, trial-level hierarchical models, covariates, and richer random-slope structures are outside the current configuration interface.
- Automatic ANOVA/ART-ANOVA selection is a fixed reproducible decision rule; it does not replace substantive statistical judgment.
- Shapiro–Wilk tests can be sensitive to sample size, and non-significance does not prove normality.
- Levene non-significance does not prove equal variance. In mixed designs, the automatic screening rule requires all evaluable within-condition-specific Levene tests to be non-significant and reports the smallest p-value.
- Repeated/mixed ART uses an ARTool mixed-effects formulation with a participant random intercept `(1|ID)`. This is a general-purpose repeated-observation specification, not a replacement for study-specific random-effects modeling when a richer model is scientifically required.
- Repeated-design correlations use participant-level means across repeated conditions; the engine does not implement repeated-measures correlation. Version 31 retains the source-column-name validation added to the repeated-design correlation path to prevent silent zero-length correlation inputs.
- Pairwise deletion can produce different sample sizes across correlations.
- Multiplicity corrections can substantially reduce power when many comparisons are tested.
- Researchers should inspect diagnostics, effect estimates, confidence intervals, cell sizes, and study design before reporting results.

## v33 repeated-measures diagnostic robustness

For repeated-measures and mixed ANOVA, the workflow obtains Mauchly's sphericity tests and GG/HF corrections from the supported `summary(afex_aov)` output. A direct summary of the underlying `car::Anova` object is used only as a compatibility fallback. Correlation-matrix worksheet headers preserve configured outcome labels exactly, including spaces and punctuation.

## v34 regression-result robustness

The full v33 regression run confirmed that the remaining failures were confined to correlation-matrix header auditing and Mauchly diagnostic extraction. In v34, regression tests read correlation-matrix headers from literal worksheet cells so labels containing spaces are audited exactly as displayed in Excel. For repeated-measures ANOVA, sphericity diagnostics are first taken from the public afex summary, then supplemented from the underlying car summary component-by-component. If a finite Mauchly value is still unavailable for a non-trivial within-subject effect, the workflow recovers the value from the `car::Anova` object's stored repeated-measures matrices using the same calculation used by car's summary method. This recovery is used only for the diagnostic table and does not change the ANOVA model or its inferential results.


## v37 warning-audit regression gate

The regression runner temporarily sets `options(lifecycle_verbosity = "warning")` while tests execute so lifecycle deprecation warnings are signalled consistently. Each warning that reaches the runner is recorded with its test case, phase, condition class, message, and call. Warnings that the analysis engine deliberately captures and muffles are additionally recovered from `Warnings_Errors`, preserving model-level warnings in the audit even when they do not propagate to the console. T12's repeated-measures completeness warning is classified as expected; package-build/environment warnings are retained as environment warnings; all other warnings are treated as unexpected and fail the warning gate.


## v38 actual-example release smoke tests

The release runner now distinguishes `Design regression` and `Actual example smoke` in `test_summary.csv` and `test_report.xlsx`. Full release checking executes `T01`–`T16` plus `E01`–`E05`. Smoke cases validate the real launcher/config/data wiring, output names, workbook/PDF/log generation, design-adaptive worksheet structure, complete factorial effect counts, and warning cleanliness. They run from isolated copies under `tests/outputs/actual_examples/`, so the source example workbooks and repository folders remain unchanged.

### Sphericity effect identifiers

For within-subject and mixed ANOVA results, rows in `Sphericity_Tests` are exported only when the source summary row can be mapped to a configured factorial effect. `Effect_Code` therefore uses the same configured effect notation as the omnibus tables (for example `F2` or `F1:F2`), and `Effect_Label` is reconstructed from the configured factor labels. Automatic spreadsheet/data-frame row numbers such as `1`, `2`, `3`, ... are never valid effect identifiers and are excluded.

