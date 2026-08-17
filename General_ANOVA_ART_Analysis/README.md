# TVCG Analysis Code Package

Statistical analysis code for the TVCG manuscript **“Virtual Character-Mediated Communication in VR: Effects of Appearance Fidelity and Speech Fidelity.”**

The repository provides a reusable R workflow for configurable one-, two-, or three-factor experiments that may be all-between-subjects, all-within-subjects, or mixed. For each dependent variable, the workflow can automatically select between ANOVA and aligned rank transform ANOVA (ART-ANOVA), run follow-up comparisons, calculate effect sizes, generate a structured Excel workbook and multi-page PDF, and optionally conduct a unified Pearson or Spearman correlation analysis.

> **Synthetic-data notice:** The example workbooks contain synthetic data only. They do not contain original participant data and are not intended to reproduce the numerical results reported in the manuscript.

## Features

- Configurable **one-, two-, or three-factor designs**, with each factor declared as `between` or `within`.
- Supports all-between-subjects, all-within-subjects, and mixed designs.
- Wide- and long-format input support.
- Input files: `.xlsx`, `.xls`, `.csv`, `.tsv`, `.txt`, and `.rds`.
- Automatic per-outcome selection between:
  - Type III ANOVA; and
  - ART-ANOVA.
- Complete models containing every enabled main effect and all interactions that exist for multi-factor designs.
- Design-aware residual Shapiro–Wilk diagnostics; Levene tests are reported only when between-subject variation exists, and are omitted entirely from all-within Excel outputs.
- Mauchly sphericity tests plus Greenhouse–Geisser and Huynh–Feldt epsilon/corrected p values for repeated-measures parametric ANOVA effects; the sphericity worksheet is generated only for within/mixed designs.
- Greenhouse–Geisser (default), Huynh–Feldt, or no sphericity correction for repeated-measures/mixed parametric ANOVA.
- Partial eta-squared, Cohen's *f*, and qualitative effect-size labels.
- Main-effect pairwise comparisons, interaction-cell comparisons, and interaction contrasts.
- Configurable multiplicity adjustment, including Bonferroni correction.
- Overall, main-effect, and interaction-cell descriptive statistics.
- Optional correlation analysis using one method for the complete matrix:
  - Pearson only when every included variable satisfies the configured eligibility rule;
  - Spearman otherwise.
- One Excel workbook with analysis results, diagnostics, and column definitions.
- One multi-page PDF with main-effect plots, interaction plots, significance annotations, and a correlation heatmap.
- Optional logs, configuration snapshots, engine copies, session information, and ART diagnostic files.

## Key repository files

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
    ├── data/       # 16 synthetic regression-test workbooks
    ├── configs/    # matching test configurations
    ├── outputs/    # generated when tests run
    └── results/    # PASS/FAIL reports generated when tests run
```

Additional version-specific audit and update notes may also be retained in the code package.

The workflow is separated into two layers:

1. `TVCG_Factorial_ANOVA_ART_Analysis.R` is the fixed analysis engine.
2. Files in `configs/` contain the user-editable settings in an object named `CONFIG`.

For normal use, copy and edit a configuration file rather than modifying the analysis engine.

## Requirements

The v34 statistical engine and its 16-case regression suite were successfully executed with all test cases passing in the target R environment. Version 35 expanded Example 4 from a 2 × 3 to a 2 × 6 all-within-subjects demonstration. Version 36 keeps the statistical behavior unchanged and updates tidyselect-facing column-selection code to remove deprecated `.data` usage under tidyselect 1.2.0 and later. A recent installation of R is required, and RStudio is optional.

The analysis uses these R packages:

```r
c(
  "readxl", "readr", "dplyr", "tidyr", "purrr", "stringr", "tibble",
  "car", "afex", "lme4", "ARTool", "emmeans", "ggplot2", "openxlsx", "fs", "rlang",
  "patchwork"
)
```

The supplied configurations install missing CRAN packages automatically:

```r
packages = list(
  auto_install = TRUE,
  repository = "https://cloud.r-project.org"
)
```

Set `auto_install = FALSE` to manage packages manually.

## Quick start

Clone or download the repository, then open the repository folder in RStudio or an R console.

### Example 1: default TVCG-style synthetic data

```r
source("run_example_1.R")
```

Equivalent direct call:

```r
source("TVCG_Factorial_ANOVA_ART_Analysis.R")
run_analysis("configs/Config_Example_1_Default_TVCG.R")
```

Command-line alternative:

```bash
Rscript TVCG_Factorial_ANOVA_ART_Analysis.R configs/Config_Example_1_Default_TVCG.R
```

### Example 2: single-factor synthetic data

```r
source("run_example_2.R")
```

This example uses one three-level between-subjects factor and demonstrates that the engine automatically fits a one-factor model with no interaction analysis.

### Example 3: two-factor synthetic data

```r
source("run_example_3.R")
```

This example uses a 2 × 3 between-subjects design and demonstrates automatic main-effect and two-way interaction analysis with factor and outcome names unrelated to the TVCG study.

### Example 4: within-subjects synthetic data

```r
source("run_example_4.R")
```

This example uses a 2 × 6 all-within-subjects design. `DisplayMode` has two levels and `TaskPhase` has six ordered levels (`Acquisition 1`, `Acquisition 2`, `Practice 1`, `Practice 2`, `Transfer`, and `Retention`), so each of the 32 participants contributes 12 repeated-condition rows. `AccuracyPct`, `ResponseTimeMs`, `MentalEffort`, and `ConfidenceRating` are simulated as approximately normal continuous outcomes for the repeated-measures ANOVA path, whereas `ErrorCount` is deliberately zero-inflated and positively skewed so automatic method selection also exercises pure within-subjects ART-ANOVA.

### Example 5: mixed synthetic data

```r
source("run_example_5.R")
```

This example combines one between-subject factor with one three-level within-subject factor.

## Automated regression tests

Version 32 adds a dedicated regression suite under `tests/`. From the repository root, run:

```bash
Rscript tests/run_design_tests.R
```

A faster core subset is available with:

```bash
Rscript tests/run_design_tests.R --quick
```

A single case can be run with, for example:

```bash
Rscript tests/run_design_tests.R --case=T07
```

The suite contains valid and intentionally invalid synthetic cases. It checks 1–3 factor between/within/mixed model paths, automatic ANOVA/ART selection, repeated-measures sphericity output, Bonferroni handling, the two-level `F = t^2` identity, complete-factorial effect counts, repeated-cell missing-data handling, participant-level correlation sample sizes, long-format input, contiguous worksheet numbering, design-adaptive worksheet columns, column ordering, right-side column definitions, and expected validation failures. See [`tests/TEST_CASES.md`](tests/TEST_CASES.md) for the case matrix.

## Using your own data

1. Copy `configs/Config_Template.R`.
2. Rename the copy, for example `configs/Config_My_Study.R`.
3. Update the input path, factors, level order, dependent variables, categories, and plotting settings.
4. Keep the object name `CONFIG` unchanged.
5. Run:

```r
source("TVCG_Factorial_ANOVA_ART_Analysis.R")
run_analysis("configs/Config_My_Study.R")
```

Relative paths are resolved relative to the configuration file, not the current working directory.

A minimal outcome definition is:

```r
outcomes = data.frame(
  column = c("Outcome1", "Outcome2"),
  label = c("Outcome 1", "Outcome 2"),
  category = c("Performance", "Experience"),
  enabled = c(TRUE, TRUE),
  include_in_correlation = c(TRUE, TRUE),
  stringsAsFactors = FALSE
)
```

- `enabled` controls ANOVA/ART-ANOVA analysis.
- `include_in_correlation` independently controls inclusion in the correlation matrix.

See the [complete usage guide](docs/USAGE_GUIDE.md) for the input formats and full configuration reference.

## Statistical workflow

For each enabled dependent variable, the engine:

1. validates the configured factors, between/within roles, participant IDs, levels, columns, and design cells;
2. converts the outcome to numeric and reports conversion issues;
3. removes rows missing the outcome or an enabled factor for that outcome analysis;
4. for repeated designs, retains participants with complete valid within-condition cells for that outcome and fits the complete model implied by the enabled factors;
5. tests residual normality using Shapiro–Wilk;
6. tests variance homogeneity using Levene's test only when between-subject variation is present; no Levene fields are exported for all-within designs;
7. selects ANOVA or ART-ANOVA according to the design-aware automatic rule or the forced configuration;
8. uses `lm`/`car::Anova` for all-between parametric models, `afex::aov_ez` for repeated/mixed parametric ANOVA, and ARTool with `(1|ID)` for repeated/mixed ART models;
9. for repeated-measures parametric ANOVA, extracts effect-wise Mauchly tests and GG/HF sphericity corrections from the afex/car repeated-measures model;
10. exports all main effects and every interaction available for the enabled factor count;
11. calculates effect sizes;
12. runs main-effect follow-up analyses and, for multi-factor designs, interaction follow-up analyses;
13. calculates descriptive statistics;
14. optionally conducts the unified correlation analysis; and
15. writes the design-adaptive Excel workbook, figures PDF, logs, and diagnostics.

### Automatic ANOVA/ART-ANOVA selection

With the default setting:

```r
method_selection = "automatic"
```

For all-between-subjects designs, ANOVA is selected when residual Shapiro–Wilk and Levene tests both have `p >= alpha`. For all-within-subjects designs, no Levene test is performed or exported and automatic selection is based on the residual-normality diagnostic. Mixed designs use residual normality plus within-condition-specific Levene tests of the between-subject groups; the smallest evaluable Levene p-value is used as the screening result, so every evaluated repeated-measures cell must pass for automatic ANOVA selection. For repeated/mixed parametric ANOVA, sphericity is evaluated effect-wise with Mauchly tests where non-trivial and the configured GG/HF/none correction determines the reported repeated-measures p values; sphericity is not used as the ANOVA-versus-ART switch.

The method can be forced with:

```r
method_selection = "anova"
```

or:

```r
method_selection = "art"
```

### Complete model and design roles for one to three factors

The engine always fits the complete model implied by all enabled factors:

```r
# One factor
Y ~ X1

# Two factors
Y ~ X1 * X2

# Three factors
Y ~ X1 * X2 * X3
```

A one-factor model contains the single main effect only. Two- and three-factor models additionally contain all possible interactions. The script does not suppress higher-order terms; the analyst decides which effects to emphasize in a manuscript.

Each enabled factor also has a `role`:

```r
role = c("between", "within")
```

When at least one factor is `within`, participant IDs repeat across within-condition rows. Between-subject factor values must remain constant within each participant.

### Correlation analysis

Correlation analysis is enabled by default. One common method is used for the complete matrix.

Pearson is selected only when every included variable:

- has at least the configured number of finite observations;
- has at least three unique finite values; and
- has a Shapiro–Wilk `p` value at or above `normality_alpha`.

If any included variable fails or cannot be evaluated, the complete matrix uses Spearman. For all-between designs, correlations are calculated from pairwise-complete participant rows. For repeated/mixed designs, each outcome is first averaged to one value per participant across repeated conditions so repeated rows are not treated as independent observations. The aggregation preserves the configured source-column names and validates them before correlation testing to prevent silent zero-length results. Correlation *p* values are then adjusted together using the configured correction.

In the heatmap:

- the lower triangle shows correlation coefficients;
- the upper triangle shows adjusted-*p* significance symbols; and
- diagonal cells are blank.

## Outputs

Unless `output$directory` is set, outputs are created next to the input file in:

```text
<input_file_stem>_analysis_results/
```

The main files are:

```text
<input_file_stem>_statistical_results.xlsx
<input_file_stem>_figures.pdf
```

Optional reproducibility files are stored in:

```text
logs/
art_diagnostics/
```

### Excel workbook

The workbook structure is design-adaptive and worksheet prefixes are assigned only after the applicable sheet list is known. Consequently, worksheet numbering is always contiguous: all-between designs contain 25 worksheets numbered `00`--`24`, whereas within/mixed designs contain the additional `08_Sphericity_Tests` worksheet and therefore contain 26 worksheets numbered `00`--`25`. For example, an all-between workbook proceeds directly from `07_Assumption_Tests` to `08_Cell_Shapiro`; it does not leave an unused `08` position.

The workbook covers:

- run information and configuration;
- factor and outcome specifications;
- design-cell counts, conversion checks, and missing data;
- design-appropriate assumption tests and model summaries;
- descriptive statistics;
- omnibus effects and follow-up comparisons;
- correlation diagnostics, results, and matrices;
- PDF page indexing; and
- captured warnings and errors.

Every worksheet includes a right-side column-definition section. Assumption-related columns are design-specific: all-within outputs contain no Levene columns, all-between outputs contain no sphericity columns or sphericity worksheet, and mixed outputs contain both relevant diagnostic families. Column order is normalized separately for each worksheet: dependent variables/variable pairs and categories appear first, followed by design/factor/effect or contrast identifiers, then sample-size or method metadata, and finally test statistics, p values, effect sizes, significance fields, and notes. Dynamically generated factor and pairwise columns are explicitly kept ahead of statistical columns instead of being appended to the end. In one-factor analyses, interaction-specific worksheets are retained for a consistent workbook structure and report that no interaction results were generated.

### Figures PDF

For each dependent variable, the PDF contains:

- a main-effects page;
- an interaction-effects page when at least two factors are enabled;
- the method used for that dependent variable in the page title;
- mean ± SD or mean ± SE plots;
- omnibus *F*, *p*, and partial eta-squared annotations;
- significant main-effect comparison brackets; and
- captions summarizing interaction-contrast availability.

Each category begins with a title page and significance key. One-factor analyses contain main-effect pages only; interaction pages are created only for two- or three-factor designs. When correlation analysis is enabled, the correlation heatmap is appended to the PDF.

## Documentation

The full configuration reference, data-format requirements, output-sheet descriptions, adaptation walkthrough, and troubleshooting guidance are provided in:

**[docs/USAGE_GUIDE.md](docs/USAGE_GUIDE.md)**

## Scope and limitations

- The current engine supports one, two, or three enabled factors, each declared as between-subjects or within-subjects; all-between, all-within, and mixed designs are supported.
- Repeated/mixed parametric ANOVA uses `afex::aov_ez`; repeated/mixed ART uses an ARTool mixed-effects model with participant random intercept `(1|ID)`. Arbitrary nested designs, covariates, crossed random effects, and richer random-slope models are outside the current configuration interface.
- Automatic method selection is a predefined reproducible rule, not a substitute for inspecting distributions, residuals, sparse cells, and model appropriateness.
- ART effect sizes are calculated from the ART omnibus F statistics on the aligned-rank analysis scale and are labeled accordingly.
- Repeated-design correlations use participant-level means across repeated conditions rather than treating repeated rows as independent.
- The example datasets demonstrate the software workflow only.

## Citation

This repository accompanies the manuscript:

> *Virtual Character-Mediated Communication in VR: Effects of Appearance Fidelity and Speech Fidelity.*

Complete bibliographic and BibTeX information can be added here after publication.

### Regression-test follow-up (v33)

The first full v32 regression-test run identified two output-layer issues and one test-wording issue. Version 33 preserves correlation-matrix display labels exactly and uses the public `summary(afex_aov)` repeated-measures summary as the primary source for Mauchly and Greenhouse--Geisser/Huynh--Feldt diagnostics, with a compatibility fallback to the underlying `car::Anova` object. The regression suite also verifies agreement between effect-wise GG-corrected p-values and the final omnibus ANOVA p-values when GG correction is configured.

### Regression-test follow-up (v34)

A subsequent full v33 regression run narrowed the remaining failures to two output-audit issues: openxlsx read-back normalization of correlation-matrix display labels and incomplete extraction of Mauchly's sphericity test despite successful GG extraction. Version 34 makes the regression reader validate literal Excel header cells and strengthens repeated-measures sphericity extraction with independent afex/car component merging plus a numerical fallback based on the underlying `car::Anova` repeated-measures object. The fallback is diagnostic only and does not alter the fitted ANOVA, ART-ANOVA, omnibus tests, effect sizes, or post-hoc comparisons.

### v39 release-gate refinement

The warning audit distinguishes car's known Huynh-Feldt cap diagnostic (`HF eps > 1 treated as 1`) from genuine unexpected warnings, but only when it originates from the engine's repeated-measures sphericity-diagnostics registry. The warning remains fully recorded in the raw warning ledger. Version 40 corrects the release-gate interpretation of this diagnostic: car preserves the raw HF epsilon even when it exceeds 1 and applies `min(1, HF epsilon)` only when computing the HF-corrected p-value. E04/E05 therefore verify raw `HF_Epsilon > 1` for affected DVs, equality of HF-corrected and uncorrected p-values for those rows, and continued use of GG as the configured applied correction.


### v40 HF release-gate assertion correction

The v39 runtime smoke report showed that all Huynh--Feldt warnings were correctly classified as expected, but E04/E05 still failed because two newly added assertions incorrectly assumed that car overwrites the reported HF epsilon with 1. Version 40 fixes only those test assertions. The statistical engine remains unchanged.

### v41 release-gate refinement

The statistical engine is unchanged from v40. The E04/E05 HF-cap smoke-test assertion now recomputes the expected Huynh-Feldt p value from the reported F statistic, GG-adjusted degrees of freedom, `GG_Epsilon`, and `min(1, HF_Epsilon)`, instead of requiring the optional `Uncorrected_p` diagnostic field to be finite. This keeps the release gate aligned with the current `car::summary.Anova.mlm()` calculation while preserving full warning auditing.

### v42 sphericity effect-row integrity fix

Version 42 fixes an output-integrity issue in `Sphericity_Tests` that could expose automatic `data.frame` row numbers such as `1`, `2`, `3`, ... as `Effect_Code`/`Effect_Label` when an afex/car summary component had no meaningful row names. These numeric values are row identifiers, not statistical effects. The extractor now detects automatic sequential row names, prefers an explicit effect/term column when available, and exports only rows that map back to configured factorial effects. The regression suite additionally rejects any non-empty sphericity `Effect_Code` outside the configured factorial effect set, verifies the corresponding human-readable `Effect_Label`, and checks that each DV/effect appears at most once. This change affects diagnostic-row extraction/output only; the fitted ANOVA/ART-ANOVA models and their numerical tests are unchanged.

