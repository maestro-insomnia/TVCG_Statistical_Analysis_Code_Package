# General ANOVA/ART Analysis

A configurable R workflow for factorial statistical analysis using ANOVA or aligned rank transform ANOVA (ART-ANOVA).

This package is the reusable analysis component of the repository **`TVCG_Statistical_Analysis_Code_Package`**, which accompanies the manuscript **“Virtual Character-Mediated Communication in VR: Effects of Appearance Fidelity and Speech Fidelity.”**

The workflow supports one-, two-, or three-factor experiments with between-subjects, within-subjects, or mixed designs. For each enabled dependent variable, it can automatically select between parametric ANOVA and ART-ANOVA, conduct follow-up comparisons, calculate effect sizes, generate descriptive statistics, optionally perform correlation analysis, and export the results to a structured Excel workbook and multi-page PDF.

> **Synthetic-data notice:** All example workbooks supplied with this package contain synthetic data only. They do not contain original participant data and are not intended to reproduce the numerical results reported in the manuscript.

## Key capabilities

- Configurable **one-, two-, or three-factor designs**.
- Each factor can be declared as **between-subjects** or **within-subjects**.
- Supports:
  - all-between-subjects designs;
  - all-within-subjects designs; and
  - mixed designs.
- Wide- and long-format input support.
- Supported input formats: `.xlsx`, `.xls`, `.csv`, `.tsv`, `.txt`, and `.rds`.
- Automatic per-outcome selection between:
  - Type III ANOVA; and
  - ART-ANOVA.
- Complete factorial models including all enabled main effects and interactions.
- Design-aware assumption diagnostics:
  - residual Shapiro–Wilk tests;
  - Levene tests when between-subject variation is present; and
  - Mauchly sphericity tests for applicable repeated-measures ANOVA effects.
- Greenhouse–Geisser, Huynh–Feldt, or no sphericity correction for repeated-measures parametric ANOVA.
- Partial eta-squared, Cohen's *f*, and qualitative effect-size labels.
- Main-effect pairwise comparisons.
- Interaction-cell comparisons and interaction contrasts.
- Independent configurable p-value adjustment for ANOVA/ART follow-up analyses, with Bonferroni as the default.
- Independent configurable p-value adjustment for correlation analysis, with Benjamini–Hochberg (BH/FDR) as the default.
- Overall, main-effect, and interaction-cell descriptive statistics.
- Optional unified Pearson or Spearman correlation analysis.
- Configuration-level and `run_analysis()`-level overrides for the two p-value adjustment methods.
- Structured Excel output with analysis results, diagnostics, dynamic adjusted-p field names, and column definitions that reflect the active adjustment method.
- Multi-page PDF output with main-effect plots, interaction plots, significance annotations, an optional correlation heatmap, and dynamic p-adjustment annotations.
- Optional reproducibility logs, configuration snapshots, engine copies, session information, and ART diagnostic files.

## Package structure

```text
General_ANOVA_ART_Analysis/
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
└── examples/
    ├── Example_Data_1_Default_TVCG_Format.xlsx
    ├── Example_Data_2_Single_Factor.xlsx
    ├── Example_Data_3_Two_Factor.xlsx
    ├── Example_Data_4_Within_Subjects.xlsx
    └── Example_Data_5_Mixed_Design.xlsx
```

The workflow is separated into two layers:

1. **`TVCG_Factorial_ANOVA_ART_Analysis.R`** is the analysis engine.
2. Files in **`configs/`** contain user-editable settings stored in an object named `CONFIG`.

For normal use, modify a configuration file rather than editing the analysis engine.

## Requirements

A recent installation of R is required. RStudio is optional. The workflow has been tested with **R version 4.5.3**.

The workflow uses the following R packages:

```r
c(
  "readxl", "readr", "dplyr", "tidyr", "purrr", "stringr", "tibble",
  "car", "afex", "lme4", "ARTool", "emmeans", "ggplot2", "openxlsx",
  "fs", "rlang", "patchwork"
)
```

The supplied configurations can automatically install missing CRAN packages:

```r
packages = list(
  auto_install = TRUE,
  repository = "https://cloud.r-project.org"
)
```

Set `auto_install = FALSE` if you prefer to manage packages manually.

## Quick start

Open the `General_ANOVA_ART_Analysis` folder in RStudio or an R console.

To run the default example:

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

## Supplied examples

### Example 1: three-factor between-subjects design

```r
source("run_example_1.R")
```

This example uses a TVCG-style synthetic three-factor between-subjects design and demonstrates the default workflow.

### Example 2: single-factor between-subjects design

```r
source("run_example_2.R")
```

This example uses one three-level between-subjects factor and demonstrates a one-factor model without interaction analysis.

### Example 3: two-factor between-subjects design

```r
source("run_example_3.R")
```

This example uses a 2 × 3 between-subjects design and demonstrates main-effect and two-way interaction analysis.

### Example 4: two-factor within-subjects design

```r
source("run_example_4.R")
```

This example uses a 2 × 6 all-within-subjects design. Each participant contributes one row for every repeated-condition combination. The synthetic outcomes include both approximately normal continuous variables and a deliberately skewed count variable so that the example demonstrates both repeated-measures ANOVA and within-subjects ART-ANOVA paths.

### Example 5: mixed design

```r
source("run_example_5.R")
```

This example combines one between-subjects factor with one three-level within-subjects factor and demonstrates the mixed-design workflow.

## Using your own data

Start from the supplied template:

```text
configs/Config_Template.R
```

A typical workflow is:

1. Copy `Config_Template.R`.
2. Rename the copy, for example `Config_My_Study.R`.
3. Set the input file path.
4. Define the participant ID column.
5. Define one to three factors, including their level order and `between`/`within` roles.
6. Define the dependent variables and display labels.
7. Adjust the analysis, correlation, plotting, and output options as needed.
8. Keep the configuration object name as `CONFIG`.
9. Run the analysis.

Example:

```r
source("TVCG_Factorial_ANOVA_ART_Analysis.R")
run_analysis("configs/Config_My_Study.R")
```

Relative paths are resolved relative to the configuration file.

A minimal outcome specification is:

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

- `enabled` controls whether the variable is included in ANOVA/ART-ANOVA analysis.
- `include_in_correlation` independently controls whether the variable is included in the correlation matrix.

For the complete configuration reference, see **[`docs/USAGE_GUIDE.md`](docs/USAGE_GUIDE.md)**.

## Statistical workflow

For each enabled dependent variable, the engine:

1. validates the configured participant ID, factors, factor roles, levels, columns, and design cells;
2. converts the dependent variable to numeric and reports conversion issues;
3. removes rows that are unusable for that dependent variable;
4. for repeated designs, retains participants with complete valid within-condition cells for that dependent variable;
5. fits the complete factorial model implied by the enabled factors;
6. evaluates residual normality using Shapiro–Wilk;
7. evaluates variance homogeneity using Levene's test when between-subject variation is present;
8. selects ANOVA or ART-ANOVA according to the configured rule;
9. applies repeated-measures sphericity diagnostics and the configured correction when required;
10. exports all enabled main effects and interactions;
11. calculates effect sizes;
12. performs follow-up comparisons and interaction analyses;
13. calculates descriptive statistics;
14. optionally performs the unified correlation analysis; and
15. writes the Excel workbook, figures PDF, and optional reproducibility files.

## Automatic ANOVA/ART-ANOVA selection

With:

```r
method_selection = "automatic"
```

the decision rule is design-aware.

For **all-between-subjects designs**, ANOVA is selected when both the residual Shapiro–Wilk test and Levene test satisfy the configured alpha criterion. Otherwise, ART-ANOVA is selected.

For **all-within-subjects designs**, no Levene test is required; automatic selection is based on the residual-normality diagnostic.

For **mixed designs**, residual normality is combined with within-condition Levene testing of the between-subject groups. The smallest evaluable Levene p value is used as the screening result.

For repeated/mixed parametric ANOVA, sphericity is handled separately through effect-wise Mauchly tests and the configured Greenhouse–Geisser, Huynh–Feldt, or uncorrected p values. Sphericity is not used as the ANOVA-versus-ART selection rule.

The method can also be forced:

```r
method_selection = "anova"
```

or:

```r
method_selection = "art"
```

## Factorial models

The complete model is determined by the enabled factors:

```r
# One factor
Y ~ X1

# Two factors
Y ~ X1 * X2

# Three factors
Y ~ X1 * X2 * X3
```

Each enabled factor is assigned a role:

```r
role = "between"
```

or:

```r
role = "within"
```

When at least one factor is within-subjects, participant IDs repeat across within-condition rows. Between-subject factor values must remain constant within participant.

## P-value adjustment

The workflow uses two independent multiplicity-adjustment settings:

```r
analysis = list(
  # ...
  p_adjust_method = "bonferroni"
)

correlation = list(
  # ...
  p_adjust_method = "BH"
)
```

`analysis$p_adjust_method` controls adjustment for main-effect pairwise comparisons, interaction-cell comparisons, and interaction contrasts. The default is **Bonferroni**.

`correlation$p_adjust_method` controls adjustment across the successfully tested correlation pairs. The default is **Benjamini–Hochberg (`"BH"`, also commonly referred to as FDR)**.

The methods can also be overridden for an individual call without editing the configuration:

```r
run_analysis(
  "configs/Config_My_Study.R",
  posthoc_p_adjust_method = "holm",
  correlation_p_adjust_method = "BY"
)
```

The selected methods are recorded in the run outputs. Adjusted-p-related Excel column names and definitions are generated from the method actually used (for example, `Bonferroni_Adjusted_p`, `Holm_Adjusted_p`, `BH_Adjusted_p`, or `BY_Adjusted_p`), and the PDF annotations likewise report the active adjustment method.

## Correlation analysis

Correlation analysis is optional. When enabled, one method is used for the complete matrix.

Pearson correlation is selected only when every included variable satisfies the configured eligibility criteria. Otherwise, the complete matrix uses Spearman correlation.

For all-between-subjects designs, correlations are calculated from participant rows. For repeated or mixed designs, each included outcome is first aggregated to one value per participant across repeated conditions so that repeated rows are not treated as independent observations.

Correlation p values are adjusted using `correlation$p_adjust_method`; the supplied configurations use Benjamini–Hochberg (`"BH"`) by default.

In the heatmap:

- the lower triangle shows correlation coefficients;
- the upper triangle shows adjusted-p significance symbols; and
- diagonal cells are blank.

## Outputs

Unless `output$directory` is explicitly set, results are written next to the input file in:

```text
<input_file_stem>_analysis_results/
```

The primary files are:

```text
<input_file_stem>_statistical_results.xlsx
<input_file_stem>_figures.pdf
```

Optional reproducibility files may be stored in:

```text
logs/
art_diagnostics/
```

### Excel workbook

The workbook is design-adaptive.

It contains worksheets for:

- run and configuration information;
- factor and outcome specifications;
- design-cell counts;
- data conversion and missing-data diagnostics;
- assumption tests;
- repeated-measures sphericity diagnostics when applicable;
- model summaries;
- descriptive statistics;
- omnibus effects;
- main-effect follow-up comparisons;
- interaction-cell comparisons and contrasts;
- correlation diagnostics and matrices;
- PDF page indexing; and
- captured warnings and errors.

Worksheet numbering remains contiguous for the sheets that apply to the current design. Each worksheet also contains a right-side column-definition section.

### Figures PDF

For each dependent variable, the PDF can include:

- main-effect plots;
- interaction-effect plots when at least two factors are enabled;
- the analysis method used for that dependent variable;
- mean ± SD or mean ± SE summaries;
- omnibus *F*, *p*, and partial eta-squared annotations;
- significant pairwise-comparison brackets; and
- interaction-contrast information.

When correlation analysis is enabled, the correlation heatmap is appended to the PDF. The heatmap reports the active correlation p-value adjustment method, and follow-up pages report the active post-hoc/contrast adjustment method where applicable.


## Documentation

For detailed information about:

- input formats;
- factor configuration;
- dependent-variable configuration;
- between/within role specification;
- repeated-measures data structure;
- method-selection settings;
- correlation options;
- output customization;
- worksheet contents; and
- troubleshooting,

see:

**[`docs/USAGE_GUIDE.md`](docs/USAGE_GUIDE.md)**

## Scope and limitations

- The current interface supports one, two, or three enabled factors.
- Factors may be between-subjects or within-subjects, allowing all-between, all-within, and mixed designs.
- Repeated/mixed parametric ANOVA uses `afex::aov_ez`.
- Repeated/mixed ART uses an ARTool mixed-effects model with participant random intercept `(1|ID)`.
- Arbitrary nested designs, covariates, crossed random effects, and richer random-slope structures are outside the current configuration interface.
- Automatic ANOVA/ART-ANOVA selection is a predefined reproducible rule and does not replace substantive inspection of the data and model assumptions.
- ART effect sizes are calculated from the ART omnibus F statistics on the aligned-rank analysis scale.
- Repeated-design correlations use participant-level means across repeated conditions rather than treating repeated rows as independent observations.
- The supplied datasets are synthetic examples intended to demonstrate the workflow.

## Citation

This analysis package is distributed as part of **`TVCG_Statistical_Analysis_Code_Package`**, accompanying the manuscript:

> *Yu Han, Hao Sha, Tongtai Cao, Xin Wang, Yu Miao, Yue Liu, Huyen Nguyen, and Christian Sandor, “Virtual Character-Mediated Communication in VR: Effects of Appearance Fidelity and Speech Fidelity.”*

Complete bibliographic and BibTeX information can be added after publication.
