# 📊 TVCG Statistical Analysis Code Package

Statistical analysis code accompanying the TVCG manuscript **“Virtual Character-Mediated Communication in VR: Effects of Appearance Fidelity and Speech Fidelity.”**

This repository is organized into two analysis components:

1. **`General_ANOVA_ART_Analysis/`** — a reusable R workflow for configurable one-, two-, or three-factor experiments, including between-subjects, within-subjects, and mixed designs, with automatic selection between ANOVA and aligned rank transform ANOVA (ART-ANOVA).
2. **`Statistical_Analysis_Code_for_Pilot_Study/`** — the study-specific statistical analysis code used for the pilot study associated with the manuscript.

The two folders serve different purposes: the first provides a general-purpose configurable analysis workflow, whereas the second preserves the analysis code used for the pilot study.

> **Synthetic-data notice:** The example workbooks supplied with `General_ANOVA_ART_Analysis/` contain synthetic data only. They do not contain original participant data and are not intended to reproduce the numerical results reported in the manuscript.

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
    └── ...
```

## General ANOVA/ART Analysis

`General_ANOVA_ART_Analysis/` contains the reusable workflow used to configure and run factorial analyses without modifying the statistical engine itself.

Key capabilities include:

- one-, two-, or three-factor designs;
- all-between-subjects, all-within-subjects, and mixed designs;
- wide- and long-format input;
- automatic per-outcome selection between ANOVA and ART-ANOVA;
- design-aware Shapiro–Wilk and Levene diagnostics;
- Mauchly's test and Greenhouse–Geisser/Huynh–Feldt corrections for repeated-measures parametric ANOVA effects;
- partial eta-squared and Cohen's *f*;
- main-effect and interaction follow-up analyses with configurable multiplicity correction;
- descriptive statistics;
- optional Pearson/Spearman correlation analysis;
- structured Excel output and multi-page PDF figures.

For a quick start and feature overview, see:

**[`General_ANOVA_ART_Analysis/README.md`](General_ANOVA_ART_Analysis/README.md)**

For the complete configuration and usage reference, see:

**[`General_ANOVA_ART_Analysis/docs/USAGE_GUIDE.md`](General_ANOVA_ART_Analysis/docs/USAGE_GUIDE.md)**

## Pilot-study analysis code

`Statistical_Analysis_Code_for_Pilot_Study/` contains the analysis code used specifically for the pilot study. It is kept separate from the reusable general workflow so that manuscript-specific pilot analyses and the configurable ANOVA/ART framework are clearly distinguished.

## Quick start for the general workflow

Clone or download the repository and enter the general-analysis folder:

```bash
cd General_ANOVA_ART_Analysis
```

Then, from R or RStudio, run one of the supplied examples:

```r
source("run_example_1.R")
```

or run the analysis engine directly with a configuration file:

```r
source("TVCG_Factorial_ANOVA_ART_Analysis.R")
run_analysis("configs/Config_Example_1_Default_TVCG.R")
```

Command-line alternative:

```bash
Rscript TVCG_Factorial_ANOVA_ART_Analysis.R configs/Config_Example_1_Default_TVCG.R
```

## Citation

This repository accompanies the manuscript:

> *Yu Han, Hao Sha, Tongtai Cao, Xin Wang, Yu Miao, Yue Liu, Huyen Nguyen, and Christian Sandor, “Virtual Character-Mediated Communication in VR: Effects of Appearance Fidelity and Speech Fidelity.”*

Complete bibliographic and BibTeX information can be added here after publication.
