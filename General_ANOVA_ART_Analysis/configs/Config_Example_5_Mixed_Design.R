# ============================================================================
# Configuration: Example 5 (mixed between-/within-subjects design)
# ============================================================================
# TrainingGroup is between subjects; Session is within subjects.
# The object name must remain CONFIG.
# ============================================================================

CONFIG <- list(
  input = list(
    file = "../examples/Example_Data_5_Mixed_Design.xlsx",
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
    column = c("TrainingGroup", "Session"),
    label = c("Training Group", "Session"),
    short_label = c("Group", "Session"),
    role = c("between", "within"),
    enabled = c(TRUE, TRUE),
    stringsAsFactors = FALSE
  ),

  factor_levels = list(
    F1 = c("Control", "Training"),
    F2 = c("Pre", "Post", "FollowUp")
  ),

  outcomes = data.frame(
    column = c("PerformanceScore", "CompletionTimeSec", "MentalWorkload", "UsabilityRating"),
    label = c("Performance", "Completion Time", "Mental Workload", "Usability"),
    category = c("Task Performance", "Task Performance", "Workload", "User Experience"),
    enabled = rep(TRUE, 4),
    include_in_correlation = rep(TRUE, 4),
    stringsAsFactors = FALSE
  ),

  analysis = list(
    alpha = 0.05,
    method_selection = "automatic",
    anova_type = 3,
    levene_center = "median",
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
      F1 = c(Control = "#66C2A5", Training = "#FC8D62"),
      F2 = c(Pre = "#F8766D", Post = "#00BA38", FollowUp = "#619CFF")
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
