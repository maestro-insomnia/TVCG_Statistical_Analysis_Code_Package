# 📊 TVCG Statistical Analysis Code Package

Statistical analysis code accompanying the TVCG manuscript **“Virtual Character-Mediated Communication in VR: Effects of Appearance Fidelity and Speech Fidelity.”**

This repository contains two analysis components with different purposes. The main component, **`General_ANOVA_ART_Analysis/`**, provides a reusable and configurable R workflow for factorial statistical analysis. It is designed to accommodate both data that satisfy the assumptions required for parametric ANOVA and data for which those assumptions are not adequately met, using either ANOVA or [aligned rank transform (ART) ANOVA](https://dl.acm.org/doi/abs/10.1145/1978942.1978963) as appropriate. The second component, **`Statistical_Analysis_Code_for_Pilot_Study/`**, preserves the study-specific analysis used for the manuscript's pilot study.

> **Synthetic-data notice:** The example datasets included in this repository are synthetic. They do not contain original participant data and are not intended to reproduce the numerical results reported in the manuscript. They are provided to demonstrate the expected input structure and analysis workflow.

## Repository structure

```text
TVCG_Statistical_Analysis_Code_Package/
├── README.md
├── General_ANOVA_ART_Analysis/
│   ├── README.md
│   ├── TVCG_Factorial_ANOVA_ART_Analysis.R
│   ├── run_example_1.R
│   ├── run_example_2.R
│   ├── run_example_3.R
│   ├── run_example_4.R
│   ├── run_example_5.R
│   ├── configs/
│   ├── docs/
│   │   └── USAGE_GUIDE.md
│   └── examples/
└── Statistical_Analysis_Code_for_Pilot_Study/
    ├── README.md
    ├── Pilot_Statistical_Analysis_Public.R
    └── Pilot_Example_Data.csv
```

## General ANOVA/ART Analysis

**`General_ANOVA_ART_Analysis/`** is the primary reusable component of this repository. It provides a configurable R workflow for one-, two-, or three-factor experiments and supports **between-subjects, within-subjects, and mixed designs**.

For each enabled dependent variable, the workflow can automatically select between parametric ANOVA and [aligned rank transform ANOVA (ART-ANOVA)](https://dl.acm.org/doi/abs/10.1145/1978942.1978963), perform follow-up analyses, calculate effect sizes and descriptive statistics, optionally conduct correlation analysis, and export the results to a structured Excel workbook and multi-page PDF. Parametric ANOVA is used when the implemented assumption checks support that analysis path; when those assumptions are not adequately met, the workflow can use ART-ANOVA instead.

The [aligned rank transform (ART)](https://dl.acm.org/doi/abs/10.1145/1978942.1978963) is a nonparametric procedure for factorial designs. It aligns observations separately for the effects being tested and then ranks the aligned responses, allowing main effects and interactions to be evaluated using familiar ANOVA-style F tests while avoiding the normality requirements of conventional parametric ANOVA.

### Main capabilities

- Configurable **one-, two-, or three-factor designs**.
- Each factor can be specified as **between-subjects** or **within-subjects**.
- Supports:
  - all-between-subjects designs;
  - all-within-subjects designs; and
  - mixed designs.
- Wide- and long-format input support.
- Automatic per-outcome selection between:
  - Type III ANOVA; and
  - [ART-ANOVA](https://dl.acm.org/doi/abs/10.1145/1978942.1978963).
- Complete factorial models with all enabled main effects and interactions.
- Design-aware assumption diagnostics:
  - residual Shapiro–Wilk tests;
  - Levene tests when between-subject variation is present; and
  - Mauchly sphericity tests for applicable repeated-measures ANOVA effects.
- Greenhouse–Geisser, Huynh–Feldt, or no sphericity correction for repeated-measures parametric ANOVA.
- Partial eta-squared, Cohen's *f*, and qualitative effect-size labels.
- Main-effect pairwise comparisons, interaction-cell comparisons, and interaction contrasts.
- Independent configurable p-value adjustment for ANOVA/ART follow-up analyses, with **Bonferroni** as the default.
- Independent configurable p-value adjustment for correlation analysis, with **Benjamini–Hochberg (BH/FDR)** as the default.
- Configuration-level and function-level overrides for both adjustment methods.
- Overall, main-effect, and interaction-cell descriptive statistics.
- Optional unified Pearson or Spearman correlation analysis.
- Structured Excel output containing statistical results, diagnostics, dynamically named adjusted-p fields, and column definitions that reflect the active adjustment method.
- Multi-page PDF output containing main-effect plots, interaction plots, significance annotations, dynamic p-adjustment labels, and an optional correlation heatmap.

### Supplied examples

Five synthetic examples are included to demonstrate the supported design types:

| Example | Design |
|---|---|
| `run_example_1.R` | Three-factor between-subjects design |
| `run_example_2.R` | Single-factor between-subjects design |
| `run_example_3.R` | Two-factor between-subjects design |
| `run_example_4.R` | Two-factor within-subjects design |
| `run_example_5.R` | Mixed design |

The corresponding configuration files are stored in `General_ANOVA_ART_Analysis/configs/`, and the synthetic input workbooks are stored in `General_ANOVA_ART_Analysis/examples/`.


### Quick start

Enter the general-analysis directory:

```bash
cd General_ANOVA_ART_Analysis
```

Then run one of the supplied examples from R or RStudio:

```r
source("run_example_1.R")
```

Alternatively, run the analysis engine directly with a configuration file:

```r
source("TVCG_Factorial_ANOVA_ART_Analysis.R")
run_analysis("configs/Config_Example_1_Default_TVCG.R")
```

Command-line alternative:

```bash
Rscript TVCG_Factorial_ANOVA_ART_Analysis.R configs/Config_Example_1_Default_TVCG.R
```

For a feature overview and package-level instructions, see:

**[`General_ANOVA_ART_Analysis/README.md`](General_ANOVA_ART_Analysis/README.md)**

For the complete input-format and configuration reference, see:

**[`General_ANOVA_ART_Analysis/docs/USAGE_GUIDE.md`](General_ANOVA_ART_Analysis/docs/USAGE_GUIDE.md)**

## Pilot-study statistical analysis

**`Statistical_Analysis_Code_for_Pilot_Study/`** contains the study-specific R workflow used for the pilot-study validation analyses in the manuscript. It covers perceived-age validation, audio-processing validation, and audiovisual validation, and exports the corresponding results to a structured Excel workbook.

This code follows the specific pilot-study design and analysis plan and is therefore provided primarily for **reproducibility**, rather than as a general-purpose statistical-analysis framework.

For details, see:

**[`Statistical_Analysis_Code_for_Pilot_Study/README.md`](Statistical_Analysis_Code_for_Pilot_Study/README.md)**

## Requirements

A recent installation of **R** is required. **RStudio** is optional. The complete repository, including both analysis components, was tested successfully with **R version 4.5.3**.

Each analysis component documents its own package dependencies and execution instructions in its local README.

## Citation

This repository accompanies the manuscript:

> *Yu Han, Hao Sha, Tongtai Cao, Xin Wang, Yu Miao, Yue Liu, Huyen Nguyen, and Christian Sandor, “Virtual Character-Mediated Communication in VR: Effects of Appearance Fidelity and Speech Fidelity.”*

Complete bibliographic and BibTeX information can be added after publication.
