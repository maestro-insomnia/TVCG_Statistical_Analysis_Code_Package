# ============================================================================
# Configuration: Example 4 (two-factor within-subjects design)
# ============================================================================
# Each participant contributes one row for every DisplayMode x TaskPhase cell.
# TaskPhase has six ordered levels, yielding a 2 x 6 repeated-measures design.
# The object name must remain CONFIG.
# ============================================================================

CONFIG <- list(
  input = list(
    file = "../examples/Example_Data_4_Within_Subjects.xlsx",
    sheet = "StudyData",
    data_format = "wide",
    id_column = "ParticipantID",
    long = list(
      outcome_name_column = "MeasureName",
      outcome_value_column = "MeasureValue"
    )
  ),

  factors = data.frame(
    code = c("F1", "F2"),
    column = c("DisplayMode", "TaskPhase"),
    label = c("Display Mode", "Task Phase"),
    short_label = c("Display", "Phase"),
    role = c("within", "within"),
    enabled = c(TRUE, TRUE),
    stringsAsFactors = FALSE
  ),

  factor_levels = list(
    F1 = c("Standard", "Enhanced"),
    F2 = c("Acquisition 1", "Acquisition 2", "Practice 1", "Practice 2", "Transfer", "Retention")
  ),

  # AccuracyPct, ResponseTimeMs, MentalEffort, and ConfidenceRating are
  # simulated as approximately normal continuous outcomes so automatic
  # selection exercises repeated-measures ANOVA. ErrorCount is intentionally
  # zero-inflated and positively skewed so the same example also exercises
  # pure within-subjects ART-ANOVA.
  outcomes = data.frame(
    column = c("AccuracyPct", "ResponseTimeMs", "MentalEffort", "ConfidenceRating", "ErrorCount"),
    label = c("Accuracy", "Response Time", "Mental Effort", "Confidence", "Error Count"),
    category = c("Task Performance", "Task Performance", "Workload", "User Experience", "Task Performance"),
    enabled = rep(TRUE, 5),
    include_in_correlation = rep(TRUE, 5),
    stringsAsFactors = FALSE
  ),

  analysis = list(
    alpha = 0.05,
    method_selection = "automatic",
    anova_type = 3,
    # Greenhouse-Geisser correction for repeated-measures ANOVA.
    # Alternatives: "HF" or "none".
    sphericity_correction = "GG",
    p_adjust_method = "bonferroni",
    minimum_valid_n = 10,
    random_seed = 20260731
  ),

  correlation = list(
    enabled = TRUE,
    minimum_complete_pairs = 10,
    normality_alpha = 0.05,
    p_adjust_method = "BH",
    label_wrap_width = 18
  ),

  plots = list(
    create_pdf = TRUE,
    error_bar = "sd",
    main_alpha = 0.65,
    interaction_alpha = 1.00,
    factor_colors = list(
      F1 = c(Standard = "#66C2A5", Enhanced = "#FC8D62"),
      F2 = c(
        "Acquisition 1" = "#E76F51",
        "Acquisition 2" = "#F4A261",
        "Practice 1" = "#E9C46A",
        "Practice 2" = "#2A9D8F",
        Transfer = "#457B9D",
        Retention = "#6D597A"
      )
    ),
    base_font_size = 11,
    stat_font_size = 9.5,
    title_wrap_width = 58,
    page_title_wrap_width = 70,
    interaction_ncol = 4,
    caption_wrap_width = 58,
    pdf_width = 16,
    pdf_height = 9,
    category_order = c("Task Performance", "Workload", "User Experience"),
    three_way_mapping = NULL,
    three_way_facet_rows = 1
  ),

  output = list(
    directory = NULL,
    save_art_diagnostics = TRUE,
    save_logs = TRUE
  ),

  packages = list(
    auto_install = TRUE,
    repository = "https://cloud.r-project.org"
  )
)
