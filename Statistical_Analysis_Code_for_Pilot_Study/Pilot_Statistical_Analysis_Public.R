# =============================================================================
# Pilot-Study Statistical Analysis (Public Reproducibility Version)
# =============================================================================
#
# Purpose
# -------
# This script reproduces the statistical-analysis workflow used for the
# pilot-study validation. It is designed for public release and can be run
# directly with the accompanying synthetic example dataset:
#
#   Pilot_Example_Data.csv
#
# IMPORTANT:
# - The accompanying example dataset is fully synthetic and is provided only
#   to demonstrate the expected data structure and code execution.
# - Replace DATA_FILE below with the path to your own data when reusing the
#   script.
# - Character Identity is balanced by design but is NOT included as a factor
#   in the primary inferential models. Identity-level summaries are exported
#   only as descriptive sensitivity checks.
# - All analysis outputs are written to ONE Excel workbook, with separate
#   worksheets for different stages and analyses.
#
# Experimental structure
# ----------------------
# Stage 1:
#   Perceived-age 2AFC validation.
#   Primary test: exact binomial test against p = .50.
#
# Stage 2:
#   Speech validation, comprising:
#   (a) Audio-processing 2AFC validation.
#   (b) Transcription-based speech-intelligibility validation.
#   Speech Source (Human vs. TTS) is within participant.
#   Scenario (UC vs. BC) is between participant.
#   Primary tests: four pre-specified exact binomial tests against p = .50,
#   with Holm correction.
#   Supplementary audio-processing model: binomial GLMM,
#       FinalMoreArtifacts ~ SpeechSource * Scenario + (1 | ParticipantID)
#
#   Intelligibility model: grouped word-level binomial GLMM,
#       cbind(Correct, Incorrect) ~
#         SpeechFidelity * Scenario +
#         (1 | ParticipantID) +
#         (1 | SentenceID)
#
#   Intelligibility practical equivalence:
#       participant-level bootstrap 90% CI for SH - SL,
#       evaluated against a pre-specified +/-5-percentage-point bound.
#
# Stage 3:
#   Appearance Fidelity (AH vs. AL): within participant.
#   Speech Fidelity (SH vs. SL): within participant.
#   Scenario (UC vs. BC): between participant.
#
#   Dependent variables:
#     1. Lip-Synchronization Naturalness
#     2. Speech--Gesture Match
#
#   Analysis:
#   - Subject-level contrast scores are checked using Shapiro-Wilk tests and
#     Levene tests.
#   - If all checks pass, a 2 x 2 x 2 mixed ANOVA is used.
#   - Otherwise, ART-ANOVA is used.
#   - Planned contrasts are evaluated separately within UC and BC.
#   - For ART models, planned contrasts use ART-C via ARTool::art.con().
#   - Equivalence is evaluated on the ORIGINAL 7-point rating scale.
#
# Equivalence margin
# ------------------
# EQUIV_MARGIN = 0.50 represents an example pre-specified smallest effect size
# of interest (SESOI) of +/-0.5 scale points. If another equivalence margin was
# pre-specified for your study, change EQUIV_MARGIN before analysis.
#
# Output
# ------
# A single workbook:
#   Pilot_Analysis_Results.xlsx
#
# The workbook contains separate sheets for design checks, Stage-1 results,
# Stage-2 results, Stage-3 assumption checks, omnibus tests, planned contrasts,
# equivalence results, descriptive identity checks, and session information.
#
# =============================================================================


# =============================================================================
# 0. PACKAGES AND USER SETTINGS
# =============================================================================

required_packages <- c(
  "dplyr",
  "tidyr",
  "lme4",
  "emmeans",
  "afex",
  "ARTool",
  "car",
  "openxlsx"
)

missing_packages <- required_packages[
  !required_packages %in% rownames(installed.packages())
]

if (length(missing_packages) > 0) {
  install.packages(
    missing_packages,
    repos = "https://cloud.r-project.org"
  )
}

library(dplyr)
library(tidyr)
library(lme4)
library(emmeans)
library(afex)
library(ARTool)
library(car)
library(openxlsx)

# Sum-to-zero contrasts are appropriate for Type-III factorial tests.
options(contrasts = c("contr.sum", "contr.poly"))

# ---------------------------------------------------------------------------
# Files
# ---------------------------------------------------------------------------

# The public package defaults to the accompanying synthetic example dataset.
# Replace this filename/path when analyzing another dataset with the same schema.
DATA_FILE <- "Pilot_Example_Data.csv"

# All results are exported to this single workbook.
OUTPUT_FILE <- "Pilot_Analysis_Results.xlsx"

# ---------------------------------------------------------------------------
# Statistical settings
# ---------------------------------------------------------------------------

ALPHA <- 0.05

# Stage-3 audiovisual equivalence bound on the original 7-point scale.
EQUIV_MARGIN <- 0.50

# Stage-2 speech-intelligibility equivalence bound in accuracy proportion.
# 0.05 corresponds to +/-5 percentage points.
INTELL_EQUIV_MARGIN <- 0.05

BOOTSTRAP_B <- 20000
BOOTSTRAP_SEED <- 20260817


# =============================================================================
# 1. INPUT VALIDATION
# =============================================================================

if (!file.exists(DATA_FILE)) {
  stop(
    paste0(
      "Cannot find input file: ", DATA_FILE, "\n",
      "Place the CSV file in the working directory or edit DATA_FILE."
    )
  )
}

dat <- read.csv(
  DATA_FILE,
  stringsAsFactors = FALSE,
  check.names = FALSE
)

# Only the variables below are required for the analyses.
# Additional demographic/order columns may be present and will be ignored.
required_columns <- c(
  "ParticipantID",
  "CharacterIdentity",
  "Scenario",
  "Stage1_AH_SelectedOlder",
  "Stage2_Human_FinalMoreArtifacts",
  "Stage2_TTS_FinalMoreArtifacts",
  "LipSync_AHSH",
  "LipSync_AHSL",
  "LipSync_ALSH",
  "LipSync_ALSL",
  "Gesture_AHSH",
  "Gesture_AHSL",
  "Gesture_ALSH",
  "Gesture_ALSL"
)


# Intelligibility columns are positioned after the two Stage-2 2AFC
# comparisons in the input dataset, matching the experimental procedure.
intelligibility_required_columns <- c(
  "Intelligibility_Scenario",
  "Intelligibility_SpeechFidelity",
  unlist(
    lapply(
      sprintf("%02d", 1:10),
      function(s) {
        c(
          paste0("Intelligibility_S", s, "_Correct"),
          paste0("Intelligibility_S", s, "_Total")
        )
      }
    )
  ),
  "Intelligibility_TotalCorrect",
  "Intelligibility_TotalWords",
  "Intelligibility_Accuracy"
)

required_columns <- c(
  required_columns,
  intelligibility_required_columns
)

missing_columns <- setdiff(required_columns, names(dat))

if (length(missing_columns) > 0) {
  stop(
    paste0(
      "The input dataset is missing required column(s):\n  ",
      paste(missing_columns, collapse = ", ")
    )
  )
}

# Check factor levels before converting to factors.
allowed_identity <- c("M1", "M2", "F1", "F2")
allowed_scenario <- c("UC", "BC")

unexpected_identity <- setdiff(
  unique(dat$CharacterIdentity),
  allowed_identity
)

unexpected_scenario <- setdiff(
  unique(dat$Scenario),
  allowed_scenario
)

if (length(unexpected_identity) > 0) {
  stop(
    paste0(
      "Unexpected CharacterIdentity value(s): ",
      paste(unexpected_identity, collapse = ", ")
    )
  )
}

if (length(unexpected_scenario) > 0) {
  stop(
    paste0(
      "Unexpected Scenario value(s): ",
      paste(unexpected_scenario, collapse = ", ")
    )
  )
}

# Helper used for simple range validation.
assert_values <- function(x, allowed, variable_name) {
  observed <- unique(x[!is.na(x)])
  invalid <- setdiff(observed, allowed)

  if (length(invalid) > 0) {
    stop(
      paste0(
        "Invalid value(s) in ", variable_name, ": ",
        paste(invalid, collapse = ", "),
        ". Allowed values: ",
        paste(allowed, collapse = ", ")
      )
    )
  }
}

assert_values(
  dat$Stage1_AH_SelectedOlder,
  c(0, 1),
  "Stage1_AH_SelectedOlder"
)

assert_values(
  dat$Stage2_Human_FinalMoreArtifacts,
  c(0, 1),
  "Stage2_Human_FinalMoreArtifacts"
)

assert_values(
  dat$Stage2_TTS_FinalMoreArtifacts,
  c(0, 1),
  "Stage2_TTS_FinalMoreArtifacts"
)


assert_values(
  dat$Intelligibility_Scenario,
  c("UC", "BC"),
  "Intelligibility_Scenario"
)

assert_values(
  dat$Intelligibility_SpeechFidelity,
  c("SH", "SL"),
  "Intelligibility_SpeechFidelity"
)

# The intelligibility segment must come from the other scenario,
# as specified in the pilot procedure.
if (any(dat$Intelligibility_Scenario == dat$Scenario)) {
  stop(
    paste0(
      "Intelligibility_Scenario must be the scenario not used for the ",
      "participant's Stage-2 audio-processing comparisons."
    )
  )
}

for (s in sprintf("%02d", 1:10)) {

  correct_col <- paste0(
    "Intelligibility_S",
    s,
    "_Correct"
  )

  total_col <- paste0(
    "Intelligibility_S",
    s,
    "_Total"
  )

  correct <- suppressWarnings(
    as.numeric(dat[[correct_col]])
  )

  total <- suppressWarnings(
    as.numeric(dat[[total_col]])
  )

  observed <- !is.na(total)

  if (
    any(
      is.na(correct[observed]) |
        correct[observed] < 0 |
        total[observed] <= 0 |
        correct[observed] > total[observed]
    )
  ) {
    stop(
      paste0(
        "Invalid intelligibility count(s) in ",
        correct_col,
        " / ",
        total_col,
        "."
      )
    )
  }
}

if (
  any(
    dat$Intelligibility_TotalCorrect < 0 |
      dat$Intelligibility_TotalWords <= 0 |
      dat$Intelligibility_TotalCorrect >
        dat$Intelligibility_TotalWords
  )
) {
  stop(
    "Invalid Intelligibility_TotalCorrect / Intelligibility_TotalWords values."
  )
}

rating_columns <- c(
  "LipSync_AHSH",
  "LipSync_AHSL",
  "LipSync_ALSH",
  "LipSync_ALSL",
  "Gesture_AHSH",
  "Gesture_AHSL",
  "Gesture_ALSH",
  "Gesture_ALSL"
)

for (v in rating_columns) {
  if (any(is.na(dat[[v]]))) {
    stop(paste0("Missing value(s) detected in required rating column: ", v))
  }

  if (any(dat[[v]] < 1 | dat[[v]] > 7)) {
    stop(
      paste0(
        "Values in ", v,
        " must fall within the 1-7 rating scale."
      )
    )
  }
}

# Convert grouping variables to explicitly ordered factors.
dat <- dat %>%
  mutate(
    ParticipantID = factor(ParticipantID),
    CharacterIdentity = factor(
      CharacterIdentity,
      levels = allowed_identity
    ),
    Scenario = factor(
      Scenario,
      levels = allowed_scenario
    )
  )


# =============================================================================
# 2. UTILITY FUNCTIONS
# =============================================================================

safe_shapiro <- function(x) {
  x <- x[is.finite(x)]

  if (length(x) < 3) {
    return(NA_real_)
  }

  if (sd(x) == 0) {
    return(0)
  }

  shapiro.test(x)$p.value
}


exact_binom_summary <- function(x, p0 = 0.50) {
  x <- as.integer(x)

  bt <- binom.test(
    x = sum(x),
    n = length(x),
    p = p0,
    alternative = "two.sided"
  )

  data.frame(
    Successes = sum(x),
    N = length(x),
    Proportion = mean(x),
    CI_Lower = unname(bt$conf.int[1]),
    CI_Upper = unname(bt$conf.int[2]),
    P_Value = bt$p.value
  )
}


one_sample_tost <- function(
    x,
    delta = 0.50,
    alpha = 0.05
) {

  # Two one-sided tests on the ORIGINAL rating-scale difference.
  #
  # Lower test:
  #   H0: mean <= -delta
  #   H1: mean >  -delta
  #
  # Upper test:
  #   H0: mean >= +delta
  #   H1: mean <  +delta

  x <- x[is.finite(x)]

  n <- length(x)
  m <- mean(x)
  s <- sd(x)
  se <- s / sqrt(n)
  df <- n - 1

  if (n < 2 || !is.finite(se) || se == 0) {
    return(
      data.frame(
        N = n,
        Mean_Difference = m,
        SD_Difference = s,
        CI90_Lower = NA_real_,
        CI90_Upper = NA_real_,
        Lower_TOST_P = NA_real_,
        Upper_TOST_P = NA_real_,
        TOST_P = NA_real_,
        Equivalent = NA
      )
    )
  }

  t_lower <- (m + delta) / se
  p_lower <- 1 - pt(t_lower, df = df)

  t_upper <- (m - delta) / se
  p_upper <- pt(t_upper, df = df)

  tost_p <- max(p_lower, p_upper)

  # A 90% CI corresponds to two one-sided alpha=.05 tests.
  crit <- qt(1 - alpha, df = df)

  data.frame(
    N = n,
    Mean_Difference = m,
    SD_Difference = s,
    CI90_Lower = m - crit * se,
    CI90_Upper = m + crit * se,
    Lower_TOST_P = p_lower,
    Upper_TOST_P = p_upper,
    TOST_P = tost_p,
    Equivalent = tost_p < alpha
  )
}


bootstrap_equivalence <- function(
    x,
    delta = 0.50,
    alpha = 0.05,
    B = 20000,
    seed = 20260817
) {

  # Used when ART-ANOVA is selected.
  # The bootstrap is performed on ORIGINAL participant-level scale-point
  # differences, not on aligned ranks.

  x <- x[is.finite(x)]
  n <- length(x)

  set.seed(seed)

  boot_means <- replicate(
    B,
    mean(
      sample(
        x,
        size = n,
        replace = TRUE
      )
    )
  )

  ci <- quantile(
    boot_means,
    probs = c(alpha, 1 - alpha),
    names = FALSE,
    type = 6
  )

  data.frame(
    N = n,
    Mean_Difference = mean(x),
    SD_Difference = sd(x),
    CI90_Lower = ci[1],
    CI90_Upper = ci[2],
    Equivalent = (ci[1] > -delta) && (ci[2] < delta)
  )
}



bootstrap_two_group_equivalence <- function(
    high,
    low,
    delta = 0.05,
    alpha = 0.05,
    B = 20000,
    seed = 20260817
) {

  # Participant-level bootstrap for a between-participant fidelity contrast.
  # The difference is defined as High Fidelity - Low Fidelity and remains
  # on the original accuracy-proportion scale.

  high <- high[is.finite(high)]
  low <- low[is.finite(low)]

  set.seed(seed)

  boot_diff <- replicate(
    B,
    mean(
      sample(
        high,
        size = length(high),
        replace = TRUE
      )
    ) -
      mean(
        sample(
          low,
          size = length(low),
          replace = TRUE
        )
      )
  )

  ci <- quantile(
    boot_diff,
    probs = c(alpha, 1 - alpha),
    names = FALSE,
    type = 6
  )

  data.frame(
    N_High = length(high),
    N_Low = length(low),
    Mean_High = mean(high),
    Mean_Low = mean(low),
    Mean_Difference = mean(high) - mean(low),
    CI90_Lower = ci[1],
    CI90_Upper = ci[2],
    Equivalence_Margin_Lower = -delta,
    Equivalence_Margin_Upper = delta,
    Equivalent =
      (ci[1] > -delta) &&
      (ci[2] < delta)
  )
}



build_contrast_scores <- function(
    data,
    prefix
) {

  AHSH <- data[[paste0(prefix, "_AHSH")]]
  AHSL <- data[[paste0(prefix, "_AHSL")]]
  ALSH <- data[[paste0(prefix, "_ALSH")]]
  ALSL <- data[[paste0(prefix, "_ALSL")]]

  data.frame(
    ParticipantID = data$ParticipantID,
    CharacterIdentity = data$CharacterIdentity,
    Scenario = data$Scenario,

    # Mean of the four repeated conditions.
    GrandMean =
      (AHSH + AHSL + ALSH + ALSL) / 4,

    # Positive value = AH rated higher than AL, averaged over speech fidelity.
    AppearanceDiff =
      ((AHSH + AHSL) / 2) -
      ((ALSH + ALSL) / 2),

    # Positive value = SH rated higher than SL, averaged over appearance fidelity.
    SpeechDiff =
      ((AHSH + ALSH) / 2) -
      ((AHSL + ALSL) / 2),

    # Difference-of-differences for the Appearance x Speech interaction.
    Appearance_x_Speech_Diff =
      AHSH - AHSL - ALSH + ALSL
  )
}


check_stage3_assumptions <- function(
    score_data,
    dv_name
) {

  # Both within-subject factors have two levels, so sphericity correction
  # is not required. We inspect the subject-level contrast scores that map
  # onto the repeated-measures effects.

  score_names <- c(
    "GrandMean",
    "AppearanceDiff",
    "SpeechDiff",
    "Appearance_x_Speech_Diff"
  )

  shapiro_table <- bind_rows(
    lapply(
      score_names,
      function(score) {

        bind_rows(
          lapply(
            levels(score_data$Scenario),
            function(scn) {

              x <- score_data[
                score_data$Scenario == scn,
                score
              ]

              data.frame(
                DV = dv_name,
                Score = score,
                Scenario = scn,
                Shapiro_P = safe_shapiro(x)
              )
            }
          )
        )
      }
    )
  )

  levene_table <- bind_rows(
    lapply(
      score_names,
      function(score) {

        tmp <- data.frame(
          ScoreValue = score_data[[score]],
          Scenario = score_data$Scenario
        )

        lev <- car::leveneTest(
          ScoreValue ~ Scenario,
          data = tmp,
          center = median
        )

        data.frame(
          DV = dv_name,
          Score = score,
          Levene_P = lev[["Pr(>F)"]][1]
        )
      }
    )
  )

  shapiro_pass <- all(
    is.na(shapiro_table$Shapiro_P) |
      shapiro_table$Shapiro_P >= ALPHA
  )

  levene_pass <- all(
    is.na(levene_table$Levene_P) |
      levene_table$Levene_P >= ALPHA
  )

  use_anova <- shapiro_pass && levene_pass

  list(
    Shapiro = shapiro_table,
    Levene = levene_table,
    Shapiro_Pass = shapiro_pass,
    Levene_Pass = levene_pass,
    Use_ANOVA = use_anova,
    Selected_Method =
      ifelse(
        use_anova,
        "Mixed ANOVA",
        "ART-ANOVA"
      )
  )
}


export_with_rownames <- function(
    x,
    rowname_col = "Effect"
) {

  df <- as.data.frame(x)
  rn <- rownames(df)

  # Preserve meaningful row names (e.g., ART-ANOVA effect names) as a column.
  default_rn <- identical(
    rn,
    as.character(seq_len(nrow(df)))
  )

  if (
    !rowname_col %in% names(df) &&
    !default_rn
  ) {
    df <- cbind(
      setNames(
        data.frame(rn, stringsAsFactors = FALSE),
        rowname_col
      ),
      df
    )
  }

  rownames(df) <- NULL
  df
}


# =============================================================================
# 3. DESIGN CHECK
# =============================================================================

design_overview <- data.frame(
  Item = c(
    "Input file",
    "N participants",
    "Character Identity levels",
    "Scenario levels",
    "Alpha",
    "Audiovisual equivalence margin",
    "Intelligibility equivalence margin",
    "Bootstrap iterations",
    "Bootstrap seed"
  ),
  Value = c(
    DATA_FILE,
    nrow(dat),
    paste(levels(dat$CharacterIdentity), collapse = ", "),
    paste(levels(dat$Scenario), collapse = ", "),
    ALPHA,
    EQUIV_MARGIN,
    INTELL_EQUIV_MARGIN,
    BOOTSTRAP_B,
    BOOTSTRAP_SEED
  )
)

design_identity <- as.data.frame(
  table(dat$CharacterIdentity),
  stringsAsFactors = FALSE
)
names(design_identity) <- c(
  "CharacterIdentity",
  "N"
)

design_scenario <- as.data.frame(
  table(dat$Scenario),
  stringsAsFactors = FALSE
)
names(design_scenario) <- c(
  "Scenario",
  "N"
)

design_identity_scenario <- as.data.frame(
  table(
    dat$CharacterIdentity,
    dat$Scenario
  ),
  stringsAsFactors = FALSE
)
names(design_identity_scenario) <- c(
  "CharacterIdentity",
  "Scenario",
  "N"
)


# =============================================================================
# 4. STAGE 1: PERCEIVED-AGE VALIDATION
# =============================================================================

stage1_overall <- exact_binom_summary(
  dat$Stage1_AH_SelectedOlder,
  p0 = 0.50
) %>%
  mutate(
    Group = "Overall",
    .before = 1
  )

# Character Identity is descriptive only.
stage1_identity_desc <- dat %>%
  group_by(CharacterIdentity) %>%
  summarise(
    N = n(),
    AH_SelectedOlder =
      sum(Stage1_AH_SelectedOlder),
    AH_SelectedOlder_Proportion =
      mean(Stage1_AH_SelectedOlder),
    .groups = "drop"
  )


# =============================================================================
# 5. STAGE 2: AUDIO-PROCESSING VALIDATION
# =============================================================================

audio_long <- bind_rows(

  dat %>%
    transmute(
      ParticipantID,
      CharacterIdentity,
      Scenario,
      SpeechSource = "Human",
      FinalMoreArtifacts =
        as.integer(
          Stage2_Human_FinalMoreArtifacts
        )
    ),

  dat %>%
    transmute(
      ParticipantID,
      CharacterIdentity,
      Scenario,
      SpeechSource = "TTS",
      FinalMoreArtifacts =
        as.integer(
          Stage2_TTS_FinalMoreArtifacts
        )
    )

) %>%
  mutate(
    SpeechSource = factor(
      SpeechSource,
      levels = c("Human", "TTS")
    )
  )


# ---------------------------------------------------------------------------
# Stage 2 primary tests:
# Four planned exact-binomial tests against 50% chance.
# ---------------------------------------------------------------------------

stage2_cells <- bind_rows(
  lapply(
    levels(audio_long$SpeechSource),
    function(src) {

      bind_rows(
        lapply(
          levels(audio_long$Scenario),
          function(scn) {

            x <- audio_long %>%
              filter(
                SpeechSource == src,
                Scenario == scn
              ) %>%
              pull(FinalMoreArtifacts)

            exact_binom_summary(
              x,
              p0 = 0.50
            ) %>%
              mutate(
                SpeechSource = src,
                Scenario = scn,
                .before = 1
              )
          }
        )
      )
    }
  )
) %>%
  mutate(
    P_Holm = p.adjust(
      P_Value,
      method = "holm"
    )
  )


# ---------------------------------------------------------------------------
# Stage 2 supplementary GLMM:
# Speech Source x Scenario, with a random intercept for participant.
# Character Identity is intentionally excluded from the inferential model.
# ---------------------------------------------------------------------------

audio_glmm <- glmer(
  FinalMoreArtifacts ~
    SpeechSource * Scenario +
    (1 | ParticipantID),
  data = audio_long,
  family = binomial(
    link = "logit"
  ),
  control = glmerControl(
    optimizer = "bobyqa"
  )
)

audio_glmm_fixed <- as.data.frame(
  coef(
    summary(audio_glmm)
  )
)

audio_glmm_fixed <- cbind(
  Term = rownames(audio_glmm_fixed),
  audio_glmm_fixed
)
rownames(audio_glmm_fixed) <- NULL

names(audio_glmm_fixed) <- c(
  "Term",
  "Estimate",
  "Std_Error",
  "z_value",
  "P_Value"
)

audio_glmm_random <- as.data.frame(
  VarCorr(audio_glmm)
)

audio_glmm_fit <- data.frame(
  AIC = AIC(audio_glmm),
  BIC = BIC(audio_glmm),
  LogLik = as.numeric(
    logLik(audio_glmm)
  ),
  Deviance = deviance(audio_glmm),
  N_Observations = nobs(audio_glmm),
  N_Participants =
    nlevels(audio_long$ParticipantID),
  Singular_Fit =
    isSingular(
      audio_glmm,
      tol = 1e-4
    )
)

audio_probabilities <- as.data.frame(
  summary(
    emmeans(
      audio_glmm,
      ~ SpeechSource * Scenario
    ),
    type = "response"
  )
) %>%
  mutate(
    # GLMM response-scale inference uses asymptotic z tests, so emmeans
    # reports df = Inf. Excel cannot store numeric infinity and openxlsx
    # otherwise writes it as #NUM!, so convert only this display field
    # to text before exporting the workbook.
    df = ifelse(
      is.infinite(df),
      "Inf",
      as.character(df)
    )
  )

# Character Identity is descriptive only.
stage2_identity_desc <- audio_long %>%
  group_by(
    CharacterIdentity,
    Scenario,
    SpeechSource
  ) %>%
  summarise(
    N = n(),
    Final_Selected =
      sum(FinalMoreArtifacts),
    Final_Selected_Proportion =
      mean(FinalMoreArtifacts),
    .groups = "drop"
  )



# =============================================================================
# 5B. STAGE 2: SPEECH-INTELLIGIBILITY VALIDATION
# =============================================================================
#
# Each participant heard one previously unheard FINAL speech segment from the
# other scenario. High- and low-speech-fidelity versions were balanced across
# participants. The segment was presented sentence by sentence and each
# sentence was transcribed after a single presentation.
#
# Word-level accuracy is analyzed as grouped binomial counts at the
# Participant x Sentence level:
#
#   cbind(CorrectWords, IncorrectWords) ~
#     SpeechFidelity * Scenario +
#     (1 | ParticipantID) +
#     (1 | SentenceID)
#
# Scenario below refers to the scenario of the INTELLIGIBILITY MATERIAL,
# not the participant's Stage-2/Stage-3 assigned scenario.
# =============================================================================

intelligibility_long <- dat %>%
  select(
    ParticipantID,
    CharacterIdentity,
    Intelligibility_Scenario,
    Intelligibility_SpeechFidelity,
    matches(
      "^Intelligibility_S[0-9]{2}_(Correct|Total)$"
    )
  ) %>%
  pivot_longer(
    cols = matches(
      "^Intelligibility_S[0-9]{2}_(Correct|Total)$"
    ),
    names_to = c(
      "SentenceNumber",
      ".value"
    ),
    names_pattern =
      "Intelligibility_(S[0-9]{2})_(Correct|Total)"
  ) %>%
  filter(
    !is.na(Total),
    Total > 0
  ) %>%
  mutate(
    Correct = as.integer(Correct),
    Total = as.integer(Total),
    Incorrect = Total - Correct,

    Scenario = factor(
      Intelligibility_Scenario,
      levels = c("UC", "BC")
    ),

    SpeechFidelity = factor(
      Intelligibility_SpeechFidelity,
      levels = c("SH", "SL")
    ),

    SentenceID = factor(
      paste(
        Scenario,
        SentenceNumber,
        sep = "_"
      )
    )
  )


# Participant-level accuracy is used for descriptive statistics
# and practical-equivalence bootstrapping.
intelligibility_participant <- intelligibility_long %>%
  group_by(
    ParticipantID,
    CharacterIdentity,
    Scenario,
    SpeechFidelity
  ) %>%
  summarise(
    CorrectWords = sum(Correct),
    TotalWords = sum(Total),
    Accuracy = CorrectWords / TotalWords,
    .groups = "drop"
  )


intelligibility_desc <- intelligibility_participant %>%
  group_by(
    Scenario,
    SpeechFidelity
  ) %>%
  summarise(
    N = n(),
    Mean_Accuracy = mean(Accuracy),
    SD_Accuracy = sd(Accuracy),
    Min_Accuracy = min(Accuracy),
    Max_Accuracy = max(Accuracy),
    Total_Correct_Words = sum(CorrectWords),
    Total_Words = sum(TotalWords),
    Pooled_Accuracy =
      Total_Correct_Words / Total_Words,
    .groups = "drop"
  )


# Primary word-level binomial GLMM.
intelligibility_glmm <- glmer(
  cbind(
    Correct,
    Incorrect
  ) ~
    SpeechFidelity * Scenario +
    (1 | ParticipantID) +
    (1 | SentenceID),
  data = intelligibility_long,
  family = binomial(
    link = "logit"
  ),
  control = glmerControl(
    optimizer = "bobyqa",
    optCtrl = list(
      maxfun = 2e5
    )
  )
)


intelligibility_glmm_fixed <- as.data.frame(
  coef(
    summary(
      intelligibility_glmm
    )
  )
)

intelligibility_glmm_fixed <- cbind(
  Term = rownames(
    intelligibility_glmm_fixed
  ),
  intelligibility_glmm_fixed
)
rownames(
  intelligibility_glmm_fixed
) <- NULL

names(
  intelligibility_glmm_fixed
) <- c(
  "Term",
  "Estimate",
  "Std_Error",
  "z_value",
  "P_Value"
)


intelligibility_glmm_random <- as.data.frame(
  VarCorr(
    intelligibility_glmm
  )
)


intelligibility_glmm_fit <- data.frame(
  AIC = AIC(
    intelligibility_glmm
  ),
  BIC = BIC(
    intelligibility_glmm
  ),
  LogLik = as.numeric(
    logLik(
      intelligibility_glmm
    )
  ),
  Deviance = deviance(
    intelligibility_glmm
  ),
  N_Sentence_Observations =
    nrow(
      intelligibility_long
    ),
  N_Participants =
    nlevels(
      droplevels(
        intelligibility_long$ParticipantID
      )
    ),
  N_Sentences =
    nlevels(
      intelligibility_long$SentenceID
    ),
  Singular_Fit =
    isSingular(
      intelligibility_glmm,
      tol = 1e-4
    )
)


intelligibility_probabilities <- as.data.frame(
  summary(
    emmeans(
      intelligibility_glmm,
      ~ SpeechFidelity * Scenario
    ),
    type = "response"
  )
) %>%
  mutate(
    # As above, preserve the asymptotic df information as the text "Inf"
    # so that the Excel export does not convert numeric infinity to #NUM!.
    df = ifelse(
      is.infinite(df),
      "Inf",
      as.character(df)
    )
  )


# Practical equivalence:
# participant-level bootstrap 90% CIs for SH - SL within each scenario.
intelligibility_equivalence <- bind_rows(
  lapply(
    levels(
      intelligibility_participant$Scenario
    ),
    function(scn) {

      high <- intelligibility_participant %>%
        filter(
          Scenario == scn,
          SpeechFidelity == "SH"
        ) %>%
        pull(
          Accuracy
        )

      low <- intelligibility_participant %>%
        filter(
          Scenario == scn,
          SpeechFidelity == "SL"
        ) %>%
        pull(
          Accuracy
        )

      bootstrap_two_group_equivalence(
        high = high,
        low = low,
        delta = INTELL_EQUIV_MARGIN,
        alpha = ALPHA,
        B = BOOTSTRAP_B,
        seed =
          BOOTSTRAP_SEED +
          ifelse(
            scn == "UC",
            101,
            102
          )
      ) %>%
        mutate(
          Scenario = scn,
          Contrast = "SH - SL",
          .before = 1
        )
    }
  )
)


# Descriptive Character-Identity check only.
intelligibility_identity_desc <-
  intelligibility_participant %>%
  group_by(
    CharacterIdentity,
    Scenario,
    SpeechFidelity
  ) %>%
  summarise(
    N = n(),
    Mean_Accuracy =
      mean(
        Accuracy
      ),
    SD_Accuracy =
      sd(
        Accuracy
      ),
    .groups = "drop"
  )


# =============================================================================
# 6. STAGE 3: AUDIOVISUAL VALIDATION
# =============================================================================

# Long-format Stage-3 data.
#
# Public schema:
#   LipSync_AHSH, LipSync_AHSL, LipSync_ALSH, LipSync_ALSL
#   Gesture_AHSH, Gesture_AHSL,
#   Gesture_ALSH, Gesture_ALSL

av_long <- dat %>%
  pivot_longer(
    cols = matches(
      "^(LipSync|Gesture)_(AHSH|AHSL|ALSH|ALSL)$"
    ),
    names_to = c(
      ".value",
      "Condition"
    ),
    names_pattern =
      "(LipSync|Gesture)_(AHSH|AHSL|ALSH|ALSL)"
  ) %>%
  mutate(
    Condition = factor(
      Condition,
      levels = c(
        "AHSH",
        "AHSL",
        "ALSH",
        "ALSL"
      )
    ),

    Appearance = factor(
      ifelse(
        substr(
          as.character(Condition),
          1,
          2
        ) == "AH",
        "AH",
        "AL"
      ),
      levels = c(
        "AH",
        "AL"
      )
    ),

    Speech = factor(
      ifelse(
        substr(
          as.character(Condition),
          3,
          4
        ) == "SH",
        "SH",
        "SL"
      ),
      levels = c(
        "SH",
        "SL"
      )
    )
  )


# ---------------------------------------------------------------------------
# Stage 3 descriptive statistics
# ---------------------------------------------------------------------------

stage3_desc <- av_long %>%
  group_by(
    Scenario,
    Appearance,
    Speech
  ) %>%
  summarise(
    N =
      n_distinct(ParticipantID),

    LipSync_M =
      mean(LipSync),
    LipSync_SD =
      sd(LipSync),

    Gesture_M =
      mean(Gesture),
    Gesture_SD =
      sd(Gesture),

    .groups = "drop"
  )


# ---------------------------------------------------------------------------
# Stage 3 assumption checks and automatic method selection
# ---------------------------------------------------------------------------

lip_scores <- build_contrast_scores(
  dat,
  prefix = "LipSync"
)

match_scores <- build_contrast_scores(
  dat,
  prefix = "Gesture"
)

lip_assumptions <- check_stage3_assumptions(
  lip_scores,
  "Lip-Synchronization Naturalness"
)

match_assumptions <- check_stage3_assumptions(
  match_scores,
  "Speech--Gesture Match"
)

stage3_methods <- data.frame(
  DV = c(
    "Lip-Synchronization Naturalness",
    "Speech--Gesture Match"
  ),
  Shapiro_Pass = c(
    lip_assumptions$Shapiro_Pass,
    match_assumptions$Shapiro_Pass
  ),
  Levene_Pass = c(
    lip_assumptions$Levene_Pass,
    match_assumptions$Levene_Pass
  ),
  Selected_Method = c(
    lip_assumptions$Selected_Method,
    match_assumptions$Selected_Method
  )
)

lip_assumption_export <- bind_rows(
  lip_assumptions$Shapiro %>%
    transmute(
      DV,
      Score,
      Scenario,
      Test = "Shapiro-Wilk",
      P_Value = Shapiro_P
    ),

  lip_assumptions$Levene %>%
    transmute(
      DV,
      Score,
      Scenario = "UC vs BC",
      Test = "Levene",
      P_Value = Levene_P
    )
)

match_assumption_export <- bind_rows(
  match_assumptions$Shapiro %>%
    transmute(
      DV,
      Score,
      Scenario,
      Test = "Shapiro-Wilk",
      P_Value = Shapiro_P
    ),

  match_assumptions$Levene %>%
    transmute(
      DV,
      Score,
      Scenario = "UC vs BC",
      Test = "Levene",
      P_Value = Levene_P
    )
)


# =============================================================================
# 7. STAGE 3A: LIP-SYNCHRONIZATION NATURALNESS
# =============================================================================
#
# Planned validation effect:
#   Appearance Fidelity (AH vs. AL), separately within UC and BC.
#
# NOTE:
# If ART-C is used, the "estimate" returned by art.con() is on the aligned-rank
# analysis scale. It is NOT the original 7-point scale-point difference.
# Original-scale differences are reported in the equivalence sheet below.

if (lip_assumptions$Use_ANOVA) {

  lip_model <- afex::aov_ez(
    id = "ParticipantID",
    dv = "LipSync",
    data = av_long,
    between = "Scenario",
    within = c(
      "Appearance",
      "Speech"
    ),
    type = 3,
    anova_table = list(
      correction = "none",
      es = "pes"
    )
  )

  lip_omnibus <- export_with_rownames(
    afex::nice(
      lip_model,
      correction = "none",
      es = "pes"
    )
  ) %>%
    mutate(
      Analysis_Method = "Mixed ANOVA",
      .before = 1
    )

  lip_planned <- as.data.frame(
    pairs(
      emmeans(
        lip_model,
        ~ Appearance | Scenario
      ),
      adjust = "none"
    )
  ) %>%
    mutate(
      Analysis_Method = "Parametric planned contrast",
      .before = 1
    )

  lip_diagnostics <- data.frame(
    Line = c(
      "Mixed ANOVA selected.",
      "ART diagnostics are not applicable."
    )
  )

} else {

  lip_model <- ARTool::art(
    LipSync ~
      Appearance * Speech * Scenario +
      (1 | ParticipantID),
    data = av_long
  )

  lip_omnibus <- export_with_rownames(
    anova(
      lip_model,
      type = "III"
    )
  ) %>%
    mutate(
      Analysis_Method = "ART-ANOVA",
      .before = 1
    )

  # Planned ART-C contrast within each scenario.
  lip_planned <- bind_rows(
    lapply(
      levels(av_long$Scenario),
      function(scn) {

        subdat <- av_long %>%
          filter(
            Scenario == scn
          )

        m <- ARTool::art(
          LipSync ~
            Appearance * Speech +
            (1 | ParticipantID),
          data = subdat
        )

        out <- ARTool::art.con(
          m,
          "Appearance",
          adjust = "none"
        )

        as.data.frame(
          summary(out)
        ) %>%
          mutate(
            Scenario = scn,
            Analysis_Method = "ART-C planned contrast",
            .before = 1
          )
      }
    )
  )

  lip_diagnostics <- data.frame(
    Line = capture.output(
      summary(lip_model)
    )
  )
}


# =============================================================================
# 8. STAGE 3B: SPEECH--GESTURE MATCH
# =============================================================================
#
# Planned validation effect:
#   Speech Fidelity (SH vs. SL), separately within UC and BC.
#
# NOTE:
# As above, ART-C estimates are aligned-rank-scale values. Original-scale
# differences are reported in the equivalence sheet.

if (match_assumptions$Use_ANOVA) {

  match_model <- afex::aov_ez(
    id = "ParticipantID",
    dv = "Gesture",
    data = av_long,
    between = "Scenario",
    within = c(
      "Appearance",
      "Speech"
    ),
    type = 3,
    anova_table = list(
      correction = "none",
      es = "pes"
    )
  )

  match_omnibus <- export_with_rownames(
    afex::nice(
      match_model,
      correction = "none",
      es = "pes"
    )
  ) %>%
    mutate(
      Analysis_Method = "Mixed ANOVA",
      .before = 1
    )

  match_planned <- as.data.frame(
    pairs(
      emmeans(
        match_model,
        ~ Speech | Scenario
      ),
      adjust = "none"
    )
  ) %>%
    mutate(
      Analysis_Method = "Parametric planned contrast",
      .before = 1
    )

  match_diagnostics <- data.frame(
    Line = c(
      "Mixed ANOVA selected.",
      "ART diagnostics are not applicable."
    )
  )

} else {

  match_model <- ARTool::art(
    Gesture ~
      Appearance * Speech * Scenario +
      (1 | ParticipantID),
    data = av_long
  )

  match_omnibus <- export_with_rownames(
    anova(
      match_model,
      type = "III"
    )
  ) %>%
    mutate(
      Analysis_Method = "ART-ANOVA",
      .before = 1
    )

  # Planned ART-C contrast within each scenario.
  match_planned <- bind_rows(
    lapply(
      levels(av_long$Scenario),
      function(scn) {

        subdat <- av_long %>%
          filter(
            Scenario == scn
          )

        m <- ARTool::art(
          Gesture ~
            Appearance * Speech +
            (1 | ParticipantID),
          data = subdat
        )

        out <- ARTool::art.con(
          m,
          "Speech",
          adjust = "none"
        )

        as.data.frame(
          summary(out)
        ) %>%
          mutate(
            Scenario = scn,
            Analysis_Method = "ART-C planned contrast",
            .before = 1
          )
      }
    )
  )

  match_diagnostics <- data.frame(
    Line = capture.output(
      summary(match_model)
    )
  )
}


# =============================================================================
# 9. STAGE 3C: PLANNED EQUIVALENCE ANALYSES
# =============================================================================
#
# Equivalence is always evaluated using participant-level differences on the
# ORIGINAL 7-point rating scale.
#
# Lip-Synchronization Naturalness:
#   AH - AL, averaged over Speech Fidelity.
#
# Speech--Gesture Match:
#   SH - SL, averaged over Appearance Fidelity.

lip_equiv <- bind_rows(
  lapply(
    levels(lip_scores$Scenario),
    function(scn) {

      x <- lip_scores %>%
        filter(
          Scenario == scn
        ) %>%
        pull(
          AppearanceDiff
        )

      if (lip_assumptions$Use_ANOVA) {

        one_sample_tost(
          x,
          delta = EQUIV_MARGIN,
          alpha = ALPHA
        ) %>%
          mutate(
            Scenario = scn,
            DV = "Lip-Synchronization Naturalness",
            Contrast = "AH - AL",
            Equivalence_Method = "Parametric TOST",
            .before = 1
          )

      } else {

        bootstrap_equivalence(
          x,
          delta = EQUIV_MARGIN,
          alpha = ALPHA,
          B = BOOTSTRAP_B,
          seed =
            BOOTSTRAP_SEED +
            ifelse(
              scn == "UC",
              1,
              2
            )
        ) %>%
          mutate(
            Scenario = scn,
            DV = "Lip-Synchronization Naturalness",
            Contrast = "AH - AL",
            Equivalence_Method =
              "Bootstrap 90% CI equivalence check",
            .before = 1
          )
      }
    }
  )
)


match_equiv <- bind_rows(
  lapply(
    levels(match_scores$Scenario),
    function(scn) {

      x <- match_scores %>%
        filter(
          Scenario == scn
        ) %>%
        pull(
          SpeechDiff
        )

      if (match_assumptions$Use_ANOVA) {

        one_sample_tost(
          x,
          delta = EQUIV_MARGIN,
          alpha = ALPHA
        ) %>%
          mutate(
            Scenario = scn,
            DV = "Speech--Gesture Match",
            Contrast = "SH - SL",
            Equivalence_Method = "Parametric TOST",
            .before = 1
          )

      } else {

        bootstrap_equivalence(
          x,
          delta = EQUIV_MARGIN,
          alpha = ALPHA,
          B = BOOTSTRAP_B,
          seed =
            BOOTSTRAP_SEED +
            ifelse(
              scn == "UC",
              3,
              4
            )
        ) %>%
          mutate(
            Scenario = scn,
            DV = "Speech--Gesture Match",
            Contrast = "SH - SL",
            Equivalence_Method =
              "Bootstrap 90% CI equivalence check",
            .before = 1
          )
      }
    }
  )
)

stage3_equivalence <- bind_rows(
  lip_equiv,
  match_equiv
) %>%
  mutate(
    Equivalence_Margin_Lower =
      -EQUIV_MARGIN,
    Equivalence_Margin_Upper =
      EQUIV_MARGIN
  )


# =============================================================================
# 10. STAGE 3D: CHARACTER-IDENTITY DESCRIPTIVE SENSITIVITY CHECKS
# =============================================================================
#
# No identity-specific inferential tests are performed here.
# These tables are intended only to reveal grossly inconsistent
# identity-specific patterns that might be hidden by the aggregate contrast.

lip_identity <- lip_scores %>%
  group_by(
    CharacterIdentity,
    Scenario
  ) %>%
  summarise(
    N = n(),
    Mean_AH_minus_AL =
      mean(AppearanceDiff),
    SD_AH_minus_AL =
      sd(AppearanceDiff),
    .groups = "drop"
  )

match_identity <- match_scores %>%
  group_by(
    CharacterIdentity,
    Scenario
  ) %>%
  summarise(
    N = n(),
    Mean_SH_minus_SL =
      mean(SpeechDiff),
    SD_SH_minus_SL =
      sd(SpeechDiff),
    .groups = "drop"
  )


# =============================================================================
# 11. EXPORT ALL RESULTS TO ONE EXCEL WORKBOOK
# =============================================================================

# ---------------------------------------------------------------------------
# Workbook styles
# ---------------------------------------------------------------------------

wb <- createWorkbook(
  creator = "Public pilot-study analysis script",
  title = "Pilot Study Statistical Analysis Results",
  subject = "Reproducible statistical analysis output"
)

header_style <- createStyle(
  fontColour = "#FFFFFF",
  fgFill = "#1F4E78",
  textDecoration = "bold",
  halign = "center",
  valign = "center",
  wrapText = TRUE,
  border = "Bottom",
  borderColour = "#D9E2F3"
)

section_style <- createStyle(
  fontColour = "#1F1F1F",
  fgFill = "#D9EAF7",
  textDecoration = "bold",
  wrapText = TRUE
)

note_style <- createStyle(
  fontColour = "#404040",
  fgFill = "#F2F2F2",
  wrapText = TRUE,
  valign = "top"
)

# Generic worksheet writer.
add_table_sheet <- function(
    wb,
    sheet_name,
    data,
    note = NULL
) {

  addWorksheet(
    wb,
    sheet_name,
    gridLines = FALSE
  )

  start_row <- 1

  if (!is.null(note)) {
    writeData(
      wb,
      sheet = sheet_name,
      x = note,
      startRow = 1,
      startCol = 1,
      colNames = FALSE
    )

    addStyle(
      wb,
      sheet = sheet_name,
      style = note_style,
      rows = 1,
      cols = 1,
      gridExpand = TRUE,
      stack = TRUE
    )

    setColWidths(
      wb,
      sheet = sheet_name,
      cols = 1,
      widths = 90
    )

    start_row <- 3
  }

  writeData(
    wb,
    sheet = sheet_name,
    x = data,
    startRow = start_row,
    startCol = 1,
    rowNames = FALSE,
    headerStyle = header_style,
    withFilter = TRUE
  )

  if (ncol(data) > 0) {
    setColWidths(
      wb,
      sheet = sheet_name,
      cols = seq_len(ncol(data)),
      widths = "auto"
    )
  }

  freezePane(
    wb,
    sheet = sheet_name,
    firstActiveRow = start_row + 1
  )
}


# ---------------------------------------------------------------------------
# README sheet
# ---------------------------------------------------------------------------

addWorksheet(
  wb,
  "README",
  gridLines = FALSE
)

readme_table <- data.frame(
  Item = c(
    "Input dataset",
    "Output workbook",
    "Stage 1 primary analysis",
    "Stage 2 primary analysis",
    "Stage 2 supplementary analysis",
    "Stage 3 design",
    "Stage 3 DV 1",
    "Stage 3 DV 2",
    "Stage 3 method selection",
    "Planned LipSync contrast",
    "Planned Speech--Gesture Match contrast",
    "Equivalence scale",
    "Equivalence margin",
    "ART-C estimate warning",
    "Character Identity"
  ),
  Description = c(
    DATA_FILE,
    OUTPUT_FILE,
    "Exact binomial test against 50% chance.",
    "Four pre-specified exact binomial tests against 50% chance; Holm correction across the four tests.",
    "Binomial GLMM: SpeechSource * Scenario + (1 | ParticipantID).",
    "Appearance (within) x Speech (within) x Scenario (between).",
    "Lip-Synchronization Naturalness.",
    "Speech--Gesture Match.",
    "Mixed ANOVA when all specified assumption checks pass; otherwise ART-ANOVA.",
    "AH vs. AL separately within UC and BC, averaged over Speech Fidelity.",
    "SH vs. SL separately within UC and BC, averaged over Appearance Fidelity.",
    "Original 7-point rating scale.",
    paste0("+/-", EQUIV_MARGIN, " scale points."),
    "ART-C contrast estimates are on an aligned-rank analysis scale. Use the Mean_Difference values in S3_Equivalence for original-scale differences.",
    "Balanced by design; excluded from primary inferential models and reported descriptively only."
  ),
  stringsAsFactors = FALSE
)

readme_table <- bind_rows(
  readme_table,
  data.frame(
    Item = c(
      "Stage 2 intelligibility analysis",
      "Stage 2 intelligibility random effects",
      "Stage 2 intelligibility equivalence"
    ),
    Description = c(
      "Binomial GLMM of grouped word-level transcription accuracy: SpeechFidelity * Scenario.",
      "Random intercepts for ParticipantID and SentenceID.",
      paste0(
        "Participant-level bootstrap 90% CI for SH - SL within each scenario; equivalence bound +/-",
        INTELL_EQUIV_MARGIN * 100,
        " percentage points."
      )
    ),
    stringsAsFactors = FALSE
  )
)

writeData(
  wb,
  sheet = "README",
  x = readme_table,
  headerStyle = header_style
)

setColWidths(
  wb,
  sheet = "README",
  cols = 1,
  widths = 34
)

setColWidths(
  wb,
  sheet = "README",
  cols = 2,
  widths = 95
)

addStyle(
  wb,
  sheet = "README",
  style = note_style,
  rows = 2:(nrow(readme_table) + 1),
  cols = 2,
  gridExpand = TRUE,
  stack = TRUE
)

freezePane(
  wb,
  sheet = "README",
  firstActiveRow = 2
)


# ---------------------------------------------------------------------------
# Design sheet: several compact tables on one worksheet
# ---------------------------------------------------------------------------

addWorksheet(
  wb,
  "Design",
  gridLines = FALSE
)

writeData(
  wb,
  "Design",
  "Analysis settings",
  startRow = 1,
  startCol = 1,
  colNames = FALSE
)

addStyle(
  wb,
  "Design",
  section_style,
  rows = 1,
  cols = 1:2,
  gridExpand = TRUE
)

writeData(
  wb,
  "Design",
  design_overview,
  startRow = 2,
  startCol = 1,
  headerStyle = header_style
)

writeData(
  wb,
  "Design",
  "Character Identity counts",
  startRow = 12,
  startCol = 1,
  colNames = FALSE
)

addStyle(
  wb,
  "Design",
  section_style,
  rows = 12,
  cols = 1:2,
  gridExpand = TRUE
)

writeData(
  wb,
  "Design",
  design_identity,
  startRow = 13,
  startCol = 1,
  headerStyle = header_style
)

writeData(
  wb,
  "Design",
  "Scenario counts",
  startRow = 19,
  startCol = 1,
  colNames = FALSE
)

addStyle(
  wb,
  "Design",
  section_style,
  rows = 19,
  cols = 1:2,
  gridExpand = TRUE
)

writeData(
  wb,
  "Design",
  design_scenario,
  startRow = 20,
  startCol = 1,
  headerStyle = header_style
)

writeData(
  wb,
  "Design",
  "Character Identity x Scenario counts",
  startRow = 25,
  startCol = 1,
  colNames = FALSE
)

addStyle(
  wb,
  "Design",
  section_style,
  rows = 25,
  cols = 1:3,
  gridExpand = TRUE
)

writeData(
  wb,
  "Design",
  design_identity_scenario,
  startRow = 26,
  startCol = 1,
  headerStyle = header_style
)

setColWidths(
  wb,
  "Design",
  cols = 1:3,
  widths = "auto"
)


# ---------------------------------------------------------------------------
# Stage 1 sheets
# ---------------------------------------------------------------------------

add_table_sheet(
  wb,
  "S1_Exact",
  stage1_overall,
  note =
    "Primary Stage-1 validation: exact binomial test of AH-selected-as-older against p = .50."
)

add_table_sheet(
  wb,
  "S1_Identity",
  stage1_identity_desc,
  note =
    "Descriptive sensitivity check only. Character Identity is not tested inferentially."
)


# ---------------------------------------------------------------------------
# Stage 2 sheets
# ---------------------------------------------------------------------------

add_table_sheet(
  wb,
  "S2_Exact",
  stage2_cells,
  note =
    "Four pre-specified exact binomial tests against p = .50. P_Holm adjusts across these four tests."
)

add_table_sheet(
  wb,
  "S2_GLMM_Fit",
  audio_glmm_fit,
  note =
    "Supplementary binomial GLMM model-fit information."
)

add_table_sheet(
  wb,
  "S2_GLMM_Fixed",
  audio_glmm_fixed,
  note =
    "Fixed-effect coefficients from the supplementary binomial GLMM."
)

add_table_sheet(
  wb,
  "S2_GLMM_Random",
  audio_glmm_random,
  note =
    "Random-effect variance components from the supplementary binomial GLMM."
)

add_table_sheet(
  wb,
  "S2_Probabilities",
  audio_probabilities,
  note =
    "Estimated response probabilities from the supplementary GLMM."
)

add_table_sheet(
  wb,
  "S2_Identity",
  stage2_identity_desc,
  note =
    "Descriptive Character-Identity sensitivity check only."
)



# ---------------------------------------------------------------------------
# Stage 2 speech-intelligibility sheets
# ---------------------------------------------------------------------------

add_table_sheet(
  wb,
  "S2_Intell_Desc",
  intelligibility_desc,
  note =
    "Participant-level word-transcription accuracy by intelligibility scenario and Speech Fidelity."
)

add_table_sheet(
  wb,
  "S2_Intell_GLMM_Fit",
  intelligibility_glmm_fit,
  note =
    "Binomial GLMM model-fit information for word-level transcription accuracy."
)

add_table_sheet(
  wb,
  "S2_Intell_GLMM_Fixed",
  intelligibility_glmm_fixed,
  note =
    "Fixed effects from the intelligibility GLMM: Speech Fidelity, Scenario, and their interaction."
)

add_table_sheet(
  wb,
  "S2_Intell_GLMM_Random",
  intelligibility_glmm_random,
  note =
    "Random-intercept variance components for Participant and Sentence."
)

add_table_sheet(
  wb,
  "S2_Intell_Prob",
  intelligibility_probabilities,
  note =
    "Model-estimated transcription-accuracy probabilities from the intelligibility GLMM."
)

add_table_sheet(
  wb,
  "S2_Intell_Equiv",
  intelligibility_equivalence,
  note =
    "Participant-level bootstrap 90% confidence intervals for the SH - SL accuracy difference. Equivalence requires the full interval to lie inside +/-5 percentage points."
)

add_table_sheet(
  wb,
  "S2_Intell_Identity",
  intelligibility_identity_desc,
  note =
    "Descriptive Character-Identity sensitivity check for intelligibility only; no identity-specific inferential tests."
)


# ---------------------------------------------------------------------------
# Stage 3 general sheets
# ---------------------------------------------------------------------------

add_table_sheet(
  wb,
  "S3_Descriptives",
  stage3_desc,
  note =
    "Original-scale descriptive statistics for the four Appearance x Speech conditions within each scenario."
)

add_table_sheet(
  wb,
  "S3_Methods",
  stage3_methods,
  note =
    "Automatic method selection based on the specified Shapiro-Wilk and Levene checks."
)

add_table_sheet(
  wb,
  "S3_Lip_Assumptions",
  lip_assumption_export,
  note =
    "Assumption checks for Lip-Synchronization Naturalness."
)

add_table_sheet(
  wb,
  "S3_Match_Assumptions",
  match_assumption_export,
  note =
    "Assumption checks for Speech--Gesture Match."
)


# ---------------------------------------------------------------------------
# Stage 3 LipSync sheets
# ---------------------------------------------------------------------------

add_table_sheet(
  wb,
  "S3_Lip_Omnibus",
  lip_omnibus,
  note =
    paste0(
      "Omnibus factorial analysis for Lip-Synchronization Naturalness. Selected method: ",
      lip_assumptions$Selected_Method,
      "."
    )
)

add_table_sheet(
  wb,
  "S3_Lip_Planned",
  lip_planned,
  note =
    "Planned AH vs. AL contrast separately within UC and BC. ART-C estimates, when applicable, are NOT original-scale point differences."
)

add_table_sheet(
  wb,
  "S3_Lip_Diagnostics",
  lip_diagnostics,
  note =
    "Model diagnostic text. For ART-ANOVA, this contains the ARTool summary checks."
)


# ---------------------------------------------------------------------------
# Stage 3 Speech--Gesture Match sheets
# ---------------------------------------------------------------------------

add_table_sheet(
  wb,
  "S3_Match_Omnibus",
  match_omnibus,
  note =
    paste0(
      "Omnibus factorial analysis for Speech--Gesture Match. Selected method: ",
      match_assumptions$Selected_Method,
      "."
    )
)

add_table_sheet(
  wb,
  "S3_Match_Planned",
  match_planned,
  note =
    "Planned SH vs. SL contrast separately within UC and BC. ART-C estimates, when applicable, are NOT original-scale point differences."
)

add_table_sheet(
  wb,
  "S3_Match_Diagnostics",
  match_diagnostics,
  note =
    "Model diagnostic text. For ART-ANOVA, this contains the ARTool summary checks."
)


# ---------------------------------------------------------------------------
# Stage 3 equivalence and identity-sensitivity sheets
# ---------------------------------------------------------------------------

add_table_sheet(
  wb,
  "S3_Equivalence",
  stage3_equivalence,
  note =
    paste0(
      "Equivalence is evaluated on participant-level differences on the ORIGINAL 7-point rating scale. Bounds = +/-",
      EQUIV_MARGIN,
      "."
    )
)

add_table_sheet(
  wb,
  "S3_Lip_Identity",
  lip_identity,
  note =
    "Descriptive identity-level AH - AL differences. No identity-specific inferential test is performed."
)

add_table_sheet(
  wb,
  "S3_Match_Identity",
  match_identity,
  note =
    "Descriptive identity-level SH - SL differences. No identity-specific inferential test is performed."
)


# ---------------------------------------------------------------------------
# Session information for reproducibility
# ---------------------------------------------------------------------------

session_info <- data.frame(
  Line = capture.output(
    sessionInfo()
  )
)

add_table_sheet(
  wb,
  "SessionInfo",
  session_info,
  note =
    "R session and package information recorded at analysis time."
)


# ---------------------------------------------------------------------------
# Save the single output workbook
# ---------------------------------------------------------------------------

saveWorkbook(
  wb,
  file = OUTPUT_FILE,
  overwrite = TRUE
)


# =============================================================================
# 12. CONSOLE SUMMARY
# =============================================================================

cat("\n============================================================\n")
cat("PILOT-STUDY ANALYSIS COMPLETE\n")
cat("============================================================\n")
cat("Input file:", DATA_FILE, "\n")
cat("Output workbook:", OUTPUT_FILE, "\n")
cat("Stage 1: overall exact binomial test; Identity descriptive only.\n")
cat("Stage 2 audio processing: four exact binomial tests + supplementary GLMM.\n")
cat("Stage 2 intelligibility: binomial GLMM + participant-level bootstrap equivalence.\n")
cat("Stage 3 LipSync method:", lip_assumptions$Selected_Method, "\n")
cat("Stage 3 Speech--Gesture Match method:", match_assumptions$Selected_Method, "\n")
cat("Stage 3 factorial model: Appearance x Speech x Scenario.\n")
cat("Equivalence margin: +/-", EQUIV_MARGIN, "scale points.\n")
cat("All result tables were written to separate sheets in the output workbook.\n")
