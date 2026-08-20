# Pilot Study Statistical Analysis

A reproducible R workflow for the statistical analyses used in the pilot study accompanying the manuscript **“Virtual Character-Mediated Communication in VR: Effects of Appearance Fidelity and Speech Fidelity.”**

This directory is part of the repository **`TVCG_Statistical_Analysis_Code_Package`** and is located at:

```text
TVCG_Statistical_Analysis_Code_Package/
└── Statistical_Analysis_Code_for_Pilot_Study/
```

The analysis covers three pilot-study validation stages: perceived-age validation, speech validation (audio-processing and speech-intelligibility validation), and audiovisual validation. The script performs the complete analysis workflow and exports all results to a single structured Excel workbook.

> **Synthetic-data notice:** The supplied example datasets contain synthetic data only. They do not contain original participant data and are not intended to reproduce the numerical results reported in the manuscript. They are provided solely to demonstrate the expected input structure and allow the analysis script to be tested.

## Key capabilities

- Reproduces the complete statistical workflow used for the pilot study.
- Validates required input columns, factor levels, binary variables, intelligibility count data, and Stage-3 rating ranges before analysis.
- Stage 1:
  - exact binomial test against 50% chance for the perceived-age 2AFC task;
  - descriptive Character Identity sensitivity check.
- Stage 2 — audio-processing validation:
  - four pre-specified exact binomial tests against 50% chance;
  - Holm correction across the four tests;
  - supplementary binomial generalized linear mixed model (GLMM);
  - descriptive Character Identity sensitivity check.
- Stage 2 — speech-intelligibility validation:
  - grouped word-level binomial GLMM with Speech Fidelity, Scenario, and their interaction as fixed effects;
  - Participant and Sentence random intercepts;
  - model-estimated transcription-accuracy probabilities;
  - participant-level descriptive accuracy summaries;
  - bootstrap 90% confidence intervals for practical equivalence using a pre-specified ±5-percentage-point bound;
  - descriptive Character Identity sensitivity check.
- Stage 3:
  - supports the mixed factorial design with Appearance Fidelity and Speech Fidelity as within-subject factors and Scenario as a between-subject factor;
  - automatically selects mixed ANOVA or aligned rank transform ANOVA (ART-ANOVA) according to the implemented assumption-checking rule;
  - uses ART-C for planned contrasts when ART-ANOVA is selected;
  - performs planned validation contrasts separately within the UC and BC scenarios;
  - performs equivalence analysis on the original 7-point rating scale.
- Exports all analysis results to a **single Excel workbook**, with separate worksheets for the different stages, models, diagnostics, planned comparisons, and equivalence analyses.
- Records `sessionInfo()` for reproducibility.

## Directory structure

```text
Statistical_Analysis_Code_for_Pilot_Study/
├── README.md
├── Pilot_Statistical_Analysis_Public.R
└── Pilot_Example_Data.csv
```

The files are:

- **`Pilot_Statistical_Analysis_Public.R`**  
  Main statistical-analysis script.

- **`Pilot_Example_Data.csv`**  
  Synthetic example dataset used by the R script by default.

Running the script generates:

```text
Pilot_Analysis_Results.xlsx
```

## Requirements

A recent installation of R is required. RStudio is optional. The workflow has been tested successfully with R version 4.5.3.

The script uses the following R packages:

```r
c(
  "dplyr",
  "tidyr",
  "lme4",
  "emmeans",
  "afex",
  "ARTool",
  "car",
  "openxlsx"
)
```

Missing packages are installed automatically from CRAN when the script is first run.

## Quick start

Open the `Statistical_Analysis_Code_for_Pilot_Study` directory in RStudio or set it as the working directory in an R console.

Run:

```r
source("Pilot_Statistical_Analysis_Public.R")
```

Command-line alternative:

```bash
Rscript Pilot_Statistical_Analysis_Public.R
```

By default, the public-release script reads:

```r
DATA_FILE <- "Pilot_Example_Data.csv"
```

and writes:

```r
OUTPUT_FILE <- "Pilot_Analysis_Results.xlsx"
```

To analyze another dataset with the same structure, change `DATA_FILE` near the beginning of the script:

```r
DATA_FILE <- "Your_Data.csv"
```

The two equivalence margins are configured separately:

```r
# Stage-3 audiovisual measures: original 1--7 rating scale
EQUIV_MARGIN <- 0.50

# Stage-2 intelligibility: accuracy proportion
# 0.05 = ±5 percentage points
INTELL_EQUIV_MARGIN <- 0.05
```

## Input data

The analysis script expects **wide-format data with one row per participant**.

Additional demographic or experimental-order columns may be included, but the following columns are required.

### Design variables

| Column | Description | Allowed values |
|---|---|---|
| `ParticipantID` | Participant identifier | Unique participant ID |
| `CharacterIdentity` | Assigned virtual-character identity | `M1`, `M2`, `F1`, `F2` |
| `Scenario` | Participant's assigned communication scenario for the audio-processing and audiovisual stages | `UC`, `BC` |

Character Identity is balanced in the experimental design but is **not included as a factor in the primary inferential analyses**. Identity-level summaries are reported only as descriptive sensitivity checks.

### Stage 1 variables

| Column | Description | Coding |
|---|---|---|
| `Stage1_AH_SelectedOlder` | Whether the high-appearance-fidelity version was selected as appearing older | `1` = AH selected; `0` = AL selected |

The supplied example data also include the human-readable companion column `Stage1_OlderChoice`, but it is not required by the analysis script.

### Stage 2 variables: audio-processing validation

| Column | Description | Coding |
|---|---|---|
| `Stage2_Human_FinalMoreArtifacts` | Whether the final processed Human-speech sample was judged to contain more noticeable artifacts | `1` = Final; `0` = Original |
| `Stage2_TTS_FinalMoreArtifacts` | Whether the final processed TTS-speech sample was judged to contain more noticeable artifacts | `1` = Final; `0` = Original |

The example dataset additionally includes presentation-order and human-readable choice columns for documentation.

### Stage 2 variables: speech-intelligibility validation

Each participant completes the intelligibility assessment using a previously unheard **final** speech segment from the scenario not used for that participant's Stage-2 audio-processing comparisons. The script therefore requires:

| Column | Description | Allowed values / coding |
|---|---|---|
| `Intelligibility_Scenario` | Scenario from which the intelligibility material was drawn | `UC`, `BC`; must differ from `Scenario` |
| `Intelligibility_SpeechFidelity` | Speech Fidelity used for the intelligibility material | `SH`, `SL` |
| `Intelligibility_S01_Correct` ... `Intelligibility_S10_Correct` | Number of correctly transcribed words for each sentence slot | Integer from 0 to the corresponding total |
| `Intelligibility_S01_Total` ... `Intelligibility_S10_Total` | Number of reference words in each sentence slot | Positive integer for presented sentences; unused slots may be blank/`NA` |
| `Intelligibility_TotalCorrect` | Participant-level total correctly transcribed words | Non-negative integer |
| `Intelligibility_TotalWords` | Participant-level total reference words | Positive integer |
| `Intelligibility_Accuracy` | Participant-level transcription accuracy | Proportion |

The current pilot materials contain six sentence units for the UC intelligibility segment and ten sentence units for the BC intelligibility segment. Because the input schema provides ten sentence slots for every participant, unused UC sentence slots remain blank.

The inferential GLMM is constructed from the sentence-level `Correct` and `Total` counts. The participant-level total and accuracy columns are retained as summary/documentation variables in the current input schema.

> **Scenario interpretation:** In the intelligibility analysis, `Scenario` refers to the scenario of the **intelligibility material** after `Intelligibility_Scenario` is converted to the analysis factor. It should not be confused with the participant's original `Scenario` assignment used for the audio-processing and audiovisual stages.

### Stage 3 variables

Stage 3 uses four combinations of Appearance Fidelity and Speech Fidelity:

| Code | Appearance Fidelity | Speech Fidelity |
|---|---|---|
| `AHSH` | High | High |
| `AHSL` | High | Low |
| `ALSH` | Low | High |
| `ALSL` | Low | Low |

Two dependent variables are analyzed:

1. **Lip-Synchronization Naturalness**
2. **Speech--Gesture Match**

Required rating columns are:

```text
LipSync_AHSH
LipSync_AHSL
LipSync_ALSH
LipSync_ALSL

Gesture_AHSH
Gesture_AHSL
Gesture_ALSH
Gesture_ALSL
```

All Stage-3 ratings must be on the 1--7 scale.

## Statistical workflow

### Stage 1: perceived-age validation

The primary Stage-1 analysis tests whether the high-appearance-fidelity version is selected as appearing older more or less often than expected by chance.

The script performs an exact binomial test:

```text
H0: p = 0.50
```

where success corresponds to selecting the high-appearance-fidelity (`AH`) version as appearing older.

Character-specific selection proportions for M1, M2, F1, and F2 are also exported as descriptive sensitivity checks, but Character Identity is not included in the primary inferential test.

### Stage 2: audio-processing validation

Each participant contributes two binary 2AFC responses:

- one Human-speech comparison; and
- one TTS-speech comparison.

The primary analysis performs four pre-specified exact binomial tests against 50% chance:

```text
Human × UC
Human × BC
TTS × UC
TTS × BC
```

The four p values are adjusted using the Holm method.

A supplementary binomial GLMM is also fitted:

```r
FinalMoreArtifacts ~ SpeechSource * Scenario + (1 | ParticipantID)
```

where:

- `SpeechSource` = Human or TTS;
- `Scenario` = UC or BC; and
- `ParticipantID` is included as a random intercept to account for the two repeated audio-processing responses from each participant.

Character Identity is excluded from the primary model and is summarized descriptively only.

### Stage 2: speech-intelligibility validation

Each participant contributes sentence-level word-transcription counts from one previously unheard final speech segment. High- and low-speech-fidelity versions are assigned between participants.

The wide-format sentence columns are reshaped to the Participant × Sentence level. For each presented sentence:

```text
Incorrect = Total - Correct
```

The primary binomial GLMM is:

```r
cbind(Correct, Incorrect) ~
  SpeechFidelity * Scenario +
  (1 | ParticipantID) +
  (1 | SentenceID)
```

where:

- `SpeechFidelity` = `SH` or `SL`;
- `Scenario` = UC or BC intelligibility material;
- `ParticipantID` is a random intercept for participant-level heterogeneity; and
- `SentenceID` is a random intercept for sentence-level heterogeneity.

`SentenceID` is constructed from Scenario and sentence number, so sentence slots from the two scenarios are treated as distinct sentence units.

The script also exports model-estimated transcription-accuracy probabilities for each Speech Fidelity × Scenario combination using `emmeans`.

Participant-level accuracy is calculated by pooling the correctly transcribed and total words across the sentences heard by each participant. These participant-level accuracy values are used for descriptive statistics and practical-equivalence bootstrapping.

Character Identity is again excluded from the primary inferential model and summarized descriptively only.

### Stage 3: audiovisual validation

Stage 3 follows a mixed factorial design:

```text
2 Appearance Fidelity × 2 Speech Fidelity × 2 Scenario
```

with:

- **Appearance Fidelity** (`AH`, `AL`) as a within-subject factor;
- **Speech Fidelity** (`SH`, `SL`) as a within-subject factor; and
- **Scenario** (`UC`, `BC`) as a between-subject factor.

Each participant therefore contributes four ratings for each Stage-3 dependent variable.

#### Method selection

For each dependent variable, the script constructs participant-level contrast scores corresponding to:

- the grand mean;
- the Appearance Fidelity contrast;
- the Speech Fidelity contrast; and
- the Appearance Fidelity × Speech Fidelity interaction contrast.

Shapiro--Wilk tests are applied to these scores within each scenario, and Levene tests compare their variances across scenarios.

The implemented decision rule is:

```text
All specified Shapiro--Wilk tests p >= .05
AND
All specified Levene tests p >= .05
        |
        v
Mixed ANOVA

Otherwise
        |
        v
ART-ANOVA
```

Because both within-subject factors contain only two levels, no sphericity correction is required for these repeated-measures contrasts.

When ART-ANOVA is selected, the mixed-effects ART model includes a participant random intercept:

```r
DV ~ Appearance * Speech * Scenario + (1 | ParticipantID)
```

#### Lip-Synchronization Naturalness

The omnibus model evaluates:

```text
Appearance
Speech
Scenario
Appearance × Speech
Appearance × Scenario
Speech × Scenario
Appearance × Speech × Scenario
```

The pre-specified validation contrast is:

```text
AH vs. AL
```

evaluated separately within the UC and BC scenarios and averaged over Speech Fidelity.

When ART-ANOVA is selected, this comparison is performed using ART-C through `ARTool::art.con()`.

#### Speech--Gesture Match

The same factorial model is applied to **Speech--Gesture Match**.

The pre-specified validation contrast is:

```text
SH vs. SL
```

evaluated separately within the UC and BC scenarios and averaged over Appearance Fidelity.

When ART-ANOVA is selected, this comparison is also performed using ART-C.

> **ART-C interpretation note:** Estimates returned by ART-C are on the aligned-rank analysis scale. They should not be interpreted as differences in original 1--7 rating points. Original-scale mean differences are reported in the equivalence-analysis output.

## Equivalence analyses

A non-significant difference test does not by itself demonstrate that two conditions are practically equivalent. The workflow therefore includes separate equivalence analyses for Stage-2 intelligibility and Stage-3 audiovisual validation.

### Stage 2: speech-intelligibility equivalence

The default intelligibility setting is:

```r
INTELL_EQUIV_MARGIN <- 0.05
```

This corresponds to an equivalence bound of:

```text
[-5, +5] percentage points
```

for transcription accuracy.

Within each intelligibility scenario, the participant-level contrast is:

```text
SH - SL
```

The script independently bootstraps participants within the SH and SL groups and constructs a 90% confidence interval for the difference in mean participant-level accuracy.

Practical equivalence is supported when the entire 90% confidence interval lies inside the pre-specified ±5-percentage-point bound.

### Stage 3: audiovisual equivalence

The default audiovisual setting is:

```r
EQUIV_MARGIN <- 0.50
```

corresponding to:

```text
[-0.5, +0.5]
```

points on the original 7-point rating scale.

The two equivalence contrasts are:

```text
Lip-Synchronization Naturalness:
AH - AL

Speech--Gesture Match:
SH - SL
```

Each contrast is evaluated separately within UC and BC.

If mixed ANOVA is selected, the script uses a parametric two one-sided tests (TOST) procedure on participant-level original-scale differences.

If ART-ANOVA is selected, the script uses a bootstrap 90% confidence interval for the original-scale participant-level mean difference. Equivalence is supported when the entire interval lies within the configured bounds.

The two margins are study-specific pre-specified values. If different smallest effects of interest were specified for another dataset, change `INTELL_EQUIV_MARGIN` and/or `EQUIV_MARGIN` before running the analysis.

## Excel output

All results are written to:

```text
Pilot_Analysis_Results.xlsx
```

The workbook contains the following worksheets.

### General information

| Worksheet | Contents |
|---|---|
| `README` | Summary of analysis settings and interpretation notes |
| `Design` | Input file, sample size, factor levels, design-cell counts, alpha level, equivalence margins, and bootstrap settings |

### Stage 1

| Worksheet | Contents |
|---|---|
| `S1_Exact` | Overall exact binomial test |
| `S1_Identity` | Character-Identity descriptive sensitivity check |

### Stage 2: audio-processing validation

| Worksheet | Contents |
|---|---|
| `S2_Exact` | Four exact binomial tests and Holm-adjusted p values |
| `S2_GLMM_Fit` | Audio-processing GLMM fit statistics |
| `S2_GLMM_Fixed` | Audio-processing GLMM fixed-effect coefficients |
| `S2_GLMM_Random` | Audio-processing GLMM random-effect variance components |
| `S2_Probabilities` | GLMM-estimated final-audio selection probabilities |
| `S2_Identity` | Character-Identity descriptive sensitivity check |

### Stage 2: speech-intelligibility validation

| Worksheet | Contents |
|---|---|
| `S2_Intell_Desc` | Participant-level transcription-accuracy descriptives |
| `S2_Intell_GLMM_Fit` | Intelligibility GLMM fit statistics |
| `S2_Intell_GLMM_Fixed` | Intelligibility GLMM fixed effects |
| `S2_Intell_GLMM_Random` | Participant and Sentence random-effect variance components |
| `S2_Intell_Prob` | Model-estimated transcription-accuracy probabilities |
| `S2_Intell_Equiv` | Participant-level bootstrap equivalence results for SH - SL |
| `S2_Intell_Identity` | Character-Identity descriptive sensitivity check |

### Stage 3

| Worksheet | Contents |
|---|---|
| `S3_Descriptives` | Original-scale descriptive statistics |
| `S3_Methods` | Selected analysis method for each dependent variable |
| `S3_Lip_Assumptions` | Lip-Synchronization Naturalness assumption checks |
| `S3_Match_Assumptions` | Speech--Gesture Match assumption checks |
| `S3_Lip_Omnibus` | Lip-Synchronization Naturalness omnibus ANOVA/ART-ANOVA |
| `S3_Lip_Planned` | Planned AH vs. AL comparisons |
| `S3_Lip_Diagnostics` | Lip-Synchronization model diagnostics |
| `S3_Match_Omnibus` | Speech--Gesture Match omnibus ANOVA/ART-ANOVA |
| `S3_Match_Planned` | Planned SH vs. SL comparisons |
| `S3_Match_Diagnostics` | Speech--Gesture Match model diagnostics |
| `S3_Equivalence` | Original-scale audiovisual equivalence analyses |
| `S3_Lip_Identity` | Identity-level AH - AL descriptive differences |
| `S3_Match_Identity` | Identity-level SH - SL descriptive differences |

### Reproducibility

| Worksheet | Contents |
|---|---|
| `SessionInfo` | R version, operating system, and package/session information |

## Synthetic example data

`Pilot_Example_Data.csv` contains a fully synthetic 64-participant example with the same input structure expected by the analysis script.

The example preserves the intended experimental organization:

- four Character Identities (`M1`, `M2`, `F1`, `F2`);
- two assigned Scenarios (`UC`, `BC`);
- balanced Character Identity × Scenario assignment;
- binary 2AFC responses for Stage 1 and the Stage-2 audio-processing validation;
- an intelligibility segment drawn from the other scenario;
- balanced high- and low-speech-fidelity intelligibility assignments;
- sentence-level correct/total word counts for the transcription task;
- four repeated audiovisual conditions for Stage 3; and
- 1--7 ratings for Lip-Synchronization Naturalness and Speech--Gesture Match.

The synthetic values are different from the data used to generate the manuscript results and should not be interpreted as empirical findings.

## Using the script with another dataset

A typical reuse workflow is:

1. Copy the required column structure from `Pilot_Example_Data.csv`.
2. Replace the synthetic values with the new dataset.
3. Keep the required column names unchanged.
4. Set `DATA_FILE` in `Pilot_Statistical_Analysis_Public.R`.
5. If applicable, set the pre-specified Stage-2 intelligibility equivalence margin in `INTELL_EQUIV_MARGIN`.
6. If applicable, set the pre-specified Stage-3 audiovisual equivalence margin in `EQUIV_MARGIN`.
7. Run the script.
8. Review `Pilot_Analysis_Results.xlsx`.

The script performs input validation before analysis and stops with an informative error if required columns, factor levels, binary coding, intelligibility counts, the other-scenario intelligibility assignment, or Stage-3 rating ranges are invalid.

## Scope and limitations

- This script is a **study-specific reproducibility workflow**, not a general-purpose statistical-analysis package.
- The implemented design assumes the three-stage pilot-study structure described above.
- Character Identity is balanced by design but intentionally excluded from the primary inferential models.
- For intelligibility validation, the primary GLMM uses grouped word-level correct/incorrect counts at the Participant × Sentence level; participant-level accuracy is used for descriptives and equivalence bootstrapping.
- `Intelligibility_Scenario` is required to differ from the participant's assigned `Scenario`, reflecting the use of a previously unheard segment from the other scenario.
- Stage-3 mixed ANOVA is implemented using `afex::aov_ez`.
- Stage-3 ART-ANOVA is implemented using `ARTool::art` with `(1 | ParticipantID)`.
- ART-C is used for the pre-specified planned contrasts when ART is selected.
- The automatic mixed-ANOVA/ART-ANOVA decision rule reproduces the workflow implemented in this script; it should not be interpreted as a universal model-selection rule.
- Equivalence conclusions depend on the pre-specified margins.
- The supplied example datasets are synthetic and are intended only for code demonstration and reproducibility testing.

## Citation

This analysis code is distributed as part of **`TVCG_Statistical_Analysis_Code_Package`**, accompanying the manuscript:

> Yu Han, Hao Sha, Tongtai Cao, Xin Wang, Yu Miao, Yue Liu, Huyen Nguyen, and Christian Sandor, *“Virtual Character-Mediated Communication in VR: Effects of Appearance Fidelity and Speech Fidelity.”*

Complete bibliographic and BibTeX information can be added after publication.
