# ============================================================================
# Reusable Factorial ANOVA / ART-ANOVA Analysis Engine
# ============================================================================
#
# This file is the analysis engine. Do not replace sections inside this file.
# All user-editable settings are stored in a separate configuration file.
#
# Run from a terminal:
#   Rscript TVCG_Factorial_ANOVA_ART_Analysis.R configs/Config_Example_1_Default_TVCG.R
#
# Run from RStudio:
#   source("TVCG_Factorial_ANOVA_ART_Analysis.R")
#   run_analysis("configs/Config_Example_1_Default_TVCG.R")
#
# Supported factorial designs:
#   - one, two, or three enabled factors;
#   - all between-subjects factors;
#   - all within-subjects factors;
#   - mixed between-/within-subjects factors.
#
# Each factor is marked as role = "between" or role = "within" in CONFIG$factors.
# For between-subjects-only designs, each participant/experimental unit should
# appear once. When at least one within-subject factor is enabled, the data must
# contain repeated rows: one row per participant x within-factor condition.
# Between-subject factors must remain constant within each participant.
#
# "wide" input means dependent variables are stored in separate columns.
# This can still contain repeated rows when within-subject factors are present.
# "long" input stores outcome names and values in two columns and is pivoted
# internally before analysis.
#
# ANOVA and ART-ANOVA always fit the complete fixed-effects model implied by all
# enabled factors. Between-subjects ANOVA uses lm/car::Anova. Designs containing
# within-subject factors use afex::aov_ez with the configured sphericity
# correction. ART-ANOVA with repeated observations uses an ARTool mixed-effects
# model with a participant random intercept, preserving Type-II/III tests.
#
# Factor names, roles, levels, dependent variables, categories, file names, and
# sheet names are supplied by the configuration. For repeated-observation
# designs, the optional correlation module aggregates each dependent variable
# to one participant-level mean before correlation analysis so repeated rows are
# not treated as independent observations.
# ============================================================================

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0L || all(is.na(x))) y else x
}

normalize_p_adjust_method <- function(method, default = "bonferroni") {
  method <- as.character(method %||% default)
  if (length(method) != 1L || is.na(method) || !nzchar(trimws(method))) {
    stop("A p-value adjustment method must be one non-empty character value.", call. = FALSE)
  }
  method <- trimws(method)
  # stats::p.adjust() documents "fdr" as an alias of Benjamini-Hochberg.
  if (tolower(method) == "fdr") return("BH")
  known <- c(
    none = "none", bonferroni = "bonferroni", holm = "holm",
    hochberg = "hochberg", hommel = "hommel", bh = "BH", by = "BY",
    tukey = "tukey", sidak = "sidak", scheffe = "scheffe", mvt = "mvt"
  )
  key <- tolower(method)
  if (key %in% names(known)) return(unname(known[[key]]))
  method
}

p_adjustment_info <- function(method, default = "bonferroni") {
  method <- normalize_p_adjust_method(method, default = default)
  key <- tolower(method)
  labels <- c(
    none = "None (unadjusted)",
    bonferroni = "Bonferroni",
    holm = "Holm",
    hochberg = "Hochberg",
    hommel = "Hommel",
    bh = "Benjamini-Hochberg (BH/FDR)",
    by = "Benjamini-Yekutieli (BY)",
    tukey = "Tukey",
    sidak = "Sidak",
    scheffe = "Scheffe",
    mvt = "Multivariate t (MVT)"
  )
  prefixes <- c(
    none = "No_Adjustment", bonferroni = "Bonferroni", holm = "Holm",
    hochberg = "Hochberg", hommel = "Hommel", bh = "BH", by = "BY",
    tukey = "Tukey", sidak = "Sidak", scheffe = "Scheffe", mvt = "MVT"
  )
  display_label <- if (key %in% names(labels)) unname(labels[[key]]) else method
  column_prefix <- if (key %in% names(prefixes)) unname(prefixes[[key]]) else safe_path_component(method)
  list(
    method = method,
    display_label = display_label,
    column_prefix = column_prefix,
    adjusted_p_column = if (identical(method, "none")) "No_Adjustment_p" else paste0(column_prefix, "_Adjusted_p"),
    significance_column = paste0(column_prefix, "_Significance"),
    significant_column = paste0(column_prefix, "_Significant")
  )
}

get_posthoc_p_adjust_method <- function(config) {
  normalize_p_adjust_method(
    config$analysis$p_adjust_method %||% config$analysis$p_adjust %||% "bonferroni",
    default = "bonferroni"
  )
}

get_posthoc_p_adjust_info <- function(config) {
  p_adjustment_info(get_posthoc_p_adjust_method(config), default = "bonferroni")
}

get_engine_path <- function() {
  source_frames <- sys.frames()
  if (length(source_frames) > 0L) {
    for (frame_index in rev(seq_along(source_frames))) {
      source_file <- source_frames[[frame_index]]$ofile
      if (!is.null(source_file) && nzchar(source_file)) {
        return(normalizePath(source_file, winslash = "/", mustWork = FALSE))
      }
    }
  }

  command_args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", command_args, value = TRUE)
  if (length(file_arg) > 0L) {
    return(normalizePath(sub("^--file=", "", file_arg[[1]]), winslash = "/", mustWork = FALSE))
  }

  if (requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable()) {
    active_path <- tryCatch(
      rstudioapi::getActiveDocumentContext()$path,
      error = function(e) ""
    )
    if (nzchar(active_path)) {
      return(normalizePath(active_path, winslash = "/", mustWork = FALSE))
    }
  }

  normalizePath(file.path(getwd(), "TVCG_Factorial_ANOVA_ART_Analysis.R"), winslash = "/", mustWork = FALSE)
}

ENGINE_PATH <- get_engine_path()
ENGINE_DIR <- dirname(ENGINE_PATH)

safe_path_component <- function(x) {
  x <- gsub("[^A-Za-z0-9_-]+", "_", as.character(x))
  x <- gsub("_+", "_", x)
  x <- gsub("^_+|_+$", "", x)
  if (!nzchar(x)) "analysis" else x
}

resolve_relative_path <- function(path, base_dir) {
  if (is.null(path) || !nzchar(path)) return(path)
  if (grepl("^[A-Za-z]:[/\\\\]", path) || startsWith(path, "/") || startsWith(path, "~")) {
    return(normalizePath(path.expand(path), winslash = "/", mustWork = FALSE))
  }
  normalizePath(file.path(base_dir, path), winslash = "/", mustWork = FALSE)
}

load_configuration <- function(config_file) {
  config_path <- resolve_relative_path(config_file, getwd())
  if (!file.exists(config_path)) {
    alternative <- resolve_relative_path(config_file, ENGINE_DIR)
    if (file.exists(alternative)) config_path <- alternative
  }
  if (!file.exists(config_path)) {
    stop("Configuration file not found: ", config_file, call. = FALSE)
  }

  config_environment <- new.env(parent = baseenv())
  sys.source(config_path, envir = config_environment, keep.source = TRUE)
  if (!exists("CONFIG", envir = config_environment, inherits = FALSE)) {
    stop("The configuration file must create an object named CONFIG.", call. = FALSE)
  }

  config <- get("CONFIG", envir = config_environment, inherits = FALSE)
  if (!is.list(config)) stop("CONFIG must be a list.", call. = FALSE)

  # Backward compatibility: configurations created before v28 did not include
  # a factor role. Such factors are between-subjects by default.
  if (is.data.frame(config$factors) && !"role" %in% names(config$factors)) {
    config$factors$role <- "between"
  }
  if (is.data.frame(config$factors) && "role" %in% names(config$factors)) {
    config$factors$role <- tolower(trimws(as.character(config$factors$role)))
  }

  attr(config, "config_path") <- normalizePath(config_path, winslash = "/", mustWork = TRUE)
  attr(config, "config_dir") <- dirname(attr(config, "config_path"))
  config
}


validate_configuration <- function(config) {
  required_sections <- c("input", "factors", "factor_levels", "outcomes", "analysis", "plots", "output", "packages")
  missing_sections <- setdiff(required_sections, names(config))
  if (length(missing_sections) > 0L) {
    stop("CONFIG is missing sections: ", paste(missing_sections, collapse = ", "), call. = FALSE)
  }

  if (is.null(config$input$file) || length(config$input$file) != 1L || !nzchar(config$input$file)) {
    stop("CONFIG$input$file must be a non-empty file path.", call. = FALSE)
  }
  if (is.null(config$input$id_column) || length(config$input$id_column) != 1L || !nzchar(config$input$id_column)) {
    stop("CONFIG$input$id_column must be a non-empty column name.", call. = FALSE)
  }

  factor_spec <- config$factors
  if (!is.data.frame(factor_spec)) stop("CONFIG$factors must be a data.frame.", call. = FALSE)
  required_factor_columns <- c("code", "column", "label", "short_label", "role", "enabled")
  missing_factor_columns <- setdiff(required_factor_columns, names(factor_spec))
  if (length(missing_factor_columns) > 0L) {
    stop("CONFIG$factors is missing columns: ", paste(missing_factor_columns, collapse = ", "), call. = FALSE)
  }

  if (!is.logical(factor_spec$enabled) || any(is.na(factor_spec$enabled))) {
    stop("CONFIG$factors$enabled must contain only TRUE or FALSE values.", call. = FALSE)
  }
  enabled_factors <- factor_spec[factor_spec$enabled %in% TRUE, , drop = FALSE]
  if (any(!enabled_factors$role %in% c("between", "within"))) {
    stop(
      "Enabled factors must use role = 'between' or role = 'within'.",
      call. = FALSE
    )
  }
  if (nrow(enabled_factors) < 1L || nrow(enabled_factors) > 3L) {
    stop("Enable one, two, or three factors.", call. = FALSE)
  }

  required_text_fields <- c("code", "column", "label", "short_label")
  for (field in required_text_fields) {
    values <- as.character(enabled_factors[[field]])
    if (any(is.na(values) | !nzchar(trimws(values)))) {
      stop("Enabled factors contain an empty or missing ", field, " value.", call. = FALSE)
    }
  }

  if (anyDuplicated(enabled_factors$code)) stop("Factor codes must be unique.", call. = FALSE)
  if (anyDuplicated(enabled_factors$column)) stop("Factor source-column names must be unique.", call. = FALSE)
  if (any(enabled_factors$code %in% c("ID", "Y"))) {
    stop("Factor codes cannot be ID or Y because those names are reserved internally.", call. = FALSE)
  }
  if (config$input$id_column %in% enabled_factors$column) {
    stop("The ID column cannot also be used as a factor source column.", call. = FALSE)
  }
  if (!all(make.names(enabled_factors$code) == enabled_factors$code)) {
    stop("Factor codes must be valid R names, such as X1, X2, and X3.", call. = FALSE)
  }

  for (code in enabled_factors$code) {
    configured_levels <- config$factor_levels[[code]]
    if (is.null(configured_levels) || length(configured_levels) < 2L) {
      stop("CONFIG$factor_levels must define at least two levels for factor code ", code, ".", call. = FALSE)
    }
    configured_levels <- as.character(configured_levels)
    if (any(is.na(configured_levels) | !nzchar(trimws(configured_levels)))) {
      stop("factor_levels$", code, " contains an empty or missing level.", call. = FALSE)
    }
    if (anyDuplicated(configured_levels)) {
      stop("factor_levels$", code, " contains duplicated levels.", call. = FALSE)
    }
  }

  if (!is.null(config$outcomes)) {
    if (!is.data.frame(config$outcomes)) stop("CONFIG$outcomes must be NULL or a data.frame.", call. = FALSE)
    required_outcome_columns <- c("column", "label", "category", "enabled")
    missing_outcome_columns <- setdiff(required_outcome_columns, names(config$outcomes))
    if (length(missing_outcome_columns) > 0L) {
      stop("CONFIG$outcomes is missing columns: ", paste(missing_outcome_columns, collapse = ", "), call. = FALSE)
    }

    if (!is.logical(config$outcomes$enabled) || any(is.na(config$outcomes$enabled))) {
      stop("CONFIG$outcomes$enabled must contain only TRUE or FALSE values.", call. = FALSE)
    }
    if ("include_in_correlation" %in% names(config$outcomes)) {
      if (!is.logical(config$outcomes$include_in_correlation) ||
          any(is.na(config$outcomes$include_in_correlation))) {
        stop(
          "CONFIG$outcomes$include_in_correlation must contain only TRUE or FALSE values.",
          call. = FALSE
        )
      }
    }
    enabled_outcomes <- config$outcomes[config$outcomes$enabled %in% TRUE, , drop = FALSE]
    if (nrow(enabled_outcomes) == 0L) stop("Enable at least one dependent variable.", call. = FALSE)
    for (field in c("column", "label", "category")) {
      values <- as.character(enabled_outcomes[[field]])
      if (any(is.na(values) | !nzchar(trimws(values)))) {
        stop("Enabled outcomes contain an empty or missing ", field, " value.", call. = FALSE)
      }
    }
    if (anyDuplicated(enabled_outcomes$column)) {
      stop("Enabled outcome source-column names must be unique.", call. = FALSE)
    }
    conflicting_outcomes <- intersect(
      enabled_outcomes$column,
      c(config$input$id_column, enabled_factors$column)
    )
    if (length(conflicting_outcomes) > 0L) {
      stop(
        "Outcome source columns cannot also be ID or factor columns: ",
        paste(conflicting_outcomes, collapse = ", "),
        call. = FALSE
      )
    }
    if (anyDuplicated(enabled_outcomes$label)) {
      stop(
        "Enabled outcome display labels must be unique because labels are used as result-list keys.",
        call. = FALSE
      )
    }
  }

  data_format <- tolower(config$input$data_format %||% "wide")
  if (!data_format %in% c("wide", "long")) stop("input$data_format must be 'wide' or 'long'.", call. = FALSE)
  if (data_format == "long") {
    if (is.null(config$input$long$outcome_name_column) || !nzchar(config$input$long$outcome_name_column)) {
      stop("Long-format input requires input$long$outcome_name_column.", call. = FALSE)
    }
    if (is.null(config$input$long$outcome_value_column) || !nzchar(config$input$long$outcome_value_column)) {
      stop("Long-format input requires input$long$outcome_value_column.", call. = FALSE)
    }
  }

  alpha <- config$analysis$alpha
  if (length(alpha) != 1L || !is.numeric(alpha) || !is.finite(alpha) || alpha <= 0 || alpha >= 1) {
    stop("analysis$alpha must be one finite number strictly between 0 and 1.", call. = FALSE)
  }

  method_selection <- tolower(config$analysis$method_selection %||% "automatic")
  if (!method_selection %in% c("automatic", "anova", "art")) {
    stop("analysis$method_selection must be 'automatic', 'anova', or 'art'.", call. = FALSE)
  }

  anova_type <- as.integer(config$analysis$anova_type %||% 3L)
  if (!anova_type %in% c(2L, 3L)) {
    stop("analysis$anova_type must be 2 or 3 for car::Anova().", call. = FALSE)
  }

  levene_center <- tolower(config$analysis$levene_center %||% "median")
  if (!levene_center %in% c("median", "mean")) {
    stop("analysis$levene_center must be 'median' or 'mean'.", call. = FALSE)
  }

  sphericity_correction <- toupper(config$analysis$sphericity_correction %||% "GG")
  if (!sphericity_correction %in% c("GG", "HF", "NONE")) {
    stop("analysis$sphericity_correction must be 'GG', 'HF', or 'none'.", call. = FALSE)
  }

  minimum_valid_n <- as.integer(config$analysis$minimum_valid_n %||% 10L)
  if (!is.finite(minimum_valid_n) || minimum_valid_n < 3L) {
    stop("analysis$minimum_valid_n must be an integer of at least 3.", call. = FALSE)
  }

  correlation_config <- config$correlation %||% list()
  correlation_enabled <- correlation_config$enabled %||% TRUE
  if (length(correlation_enabled) != 1L || !is.logical(correlation_enabled) ||
      is.na(correlation_enabled)) {
    stop("correlation$enabled must be TRUE or FALSE.", call. = FALSE)
  }

  correlation_minimum_n <- as.integer(correlation_config$minimum_complete_pairs %||% 10L)
  if (!is.finite(correlation_minimum_n) || correlation_minimum_n < 3L) {
    stop("correlation$minimum_complete_pairs must be an integer of at least 3.", call. = FALSE)
  }

  correlation_normality_alpha <- as.numeric(correlation_config$normality_alpha %||% alpha)
  if (length(correlation_normality_alpha) != 1L ||
      !is.finite(correlation_normality_alpha) ||
      correlation_normality_alpha <= 0 || correlation_normality_alpha >= 1) {
    stop("correlation$normality_alpha must be strictly between 0 and 1.", call. = FALSE)
  }

  correlation_p_adjust <- normalize_p_adjust_method(
    correlation_config$p_adjust_method %||% correlation_config$p_adjust %||% "BH",
    default = "BH"
  )
  if (!correlation_p_adjust %in% stats::p.adjust.methods) {
    stop(
      "correlation$p_adjust_method must be one of the methods supported by stats::p.adjust(): ",
      paste(stats::p.adjust.methods, collapse = ", "),
      ".",
      call. = FALSE
    )
  }

  correlation_label_wrap_width <- as.integer(correlation_config$label_wrap_width %||% 18L)
  if (!is.finite(correlation_label_wrap_width) || correlation_label_wrap_width <= 0L) {
    stop("correlation$label_wrap_width must be a positive integer.", call. = FALSE)
  }

  error_bar <- tolower(config$plots$error_bar %||% "sd")
  if (!error_bar %in% c("sd", "se")) {
    stop("plots$error_bar must be 'sd' or 'se'.", call. = FALSE)
  }

  posthoc_p_adjust <- get_posthoc_p_adjust_method(config)
  supported_posthoc_adjustments <- unique(c(
    stats::p.adjust.methods, "tukey", "sidak", "scheffe", "mvt"
  ))
  if (!posthoc_p_adjust %in% supported_posthoc_adjustments) {
    stop(
      "analysis$p_adjust_method must be one of: ",
      paste(supported_posthoc_adjustments, collapse = ", "),
      ".",
      call. = FALSE
    )
  }

  random_seed <- config$analysis$random_seed %||% 20260731L
  if (length(random_seed) != 1L || !is.numeric(random_seed) || !is.finite(random_seed)) {
    stop("analysis$random_seed must be one finite numeric value.", call. = FALSE)
  }

  for (setting_name in c("main_alpha", "interaction_alpha")) {
    setting_value <- config$plots[[setting_name]]
    if (!is.null(setting_value) &&
        (length(setting_value) != 1L || !is.numeric(setting_value) ||
         !is.finite(setting_value) || setting_value < 0 || setting_value > 1)) {
      stop("plots$", setting_name, " must be between 0 and 1.", call. = FALSE)
    }
  }

  positive_plot_settings <- c(
    "base_font_size", "stat_font_size", "title_wrap_width",
    "page_title_wrap_width", "interaction_ncol", "caption_wrap_width",
    "pdf_width", "pdf_height", "three_way_facet_rows"
  )
  for (setting_name in positive_plot_settings) {
    setting_value <- config$plots[[setting_name]]
    if (!is.null(setting_value) &&
        (length(setting_value) != 1L || !is.numeric(setting_value) ||
         !is.finite(setting_value) || setting_value <= 0)) {
      stop("plots$", setting_name, " must be one positive numeric value.", call. = FALSE)
    }
  }

  if (!is.null(config$output$directory) &&
      (length(config$output$directory) != 1L || !is.character(config$output$directory) ||
       is.na(config$output$directory))) {
    stop("output$directory must be NULL or one path string.", call. = FALSE)
  }
  if (!is.null(config$plots$create_pdf) &&
      (length(config$plots$create_pdf) != 1L || !is.logical(config$plots$create_pdf) ||
       is.na(config$plots$create_pdf))) {
    stop("plots$create_pdf must be TRUE or FALSE.", call. = FALSE)
  }
  for (setting_name in c("save_art_diagnostics", "save_logs")) {
    setting_value <- config$output[[setting_name]]
    if (!is.null(setting_value) &&
        (length(setting_value) != 1L || !is.logical(setting_value) || is.na(setting_value))) {
      stop("output$", setting_name, " must be TRUE or FALSE.", call. = FALSE)
    }
  }

  if (!is.null(config$plots$factor_colors)) {
    for (code in enabled_factors$code) {
      configured_colors <- config$plots$factor_colors[[code]]
      if (is.null(configured_colors)) next
      configured_levels <- as.character(config$factor_levels[[code]])
      if (is.null(names(configured_colors)) || any(!nzchar(names(configured_colors)))) {
        if (length(configured_colors) != length(configured_levels)) {
          stop("Unnamed colors for factor ", code, " must contain one color per configured level.", call. = FALSE)
        }
      } else {
        missing_color_levels <- setdiff(configured_levels, names(configured_colors))
        if (length(missing_color_levels) > 0L) {
          stop(
            "Missing colors for factor ", code, ": ",
            paste(missing_color_levels, collapse = ", "),
            call. = FALSE
          )
        }
      }
      invalid_color <- vapply(
        as.character(configured_colors),
        function(value) inherits(try(grDevices::col2rgb(value), silent = TRUE), "try-error"),
        logical(1)
      )
      if (any(invalid_color)) {
        stop("Invalid color value(s) configured for factor ", code, ".", call. = FALSE)
      }
    }
  }

  if (length(config$packages$auto_install) != 1L ||
      !is.logical(config$packages$auto_install) || is.na(config$packages$auto_install)) {
    stop("packages$auto_install must be TRUE or FALSE.", call. = FALSE)
  }
  if (length(config$packages$repository) != 1L ||
      !is.character(config$packages$repository) || is.na(config$packages$repository) ||
      !nzchar(trimws(config$packages$repository))) {
    stop("packages$repository must be one non-empty repository URL.", call. = FALSE)
  }

  if (nrow(enabled_factors) == 3L && !is.null(config$plots$three_way_mapping)) {
    mapping_values <- unlist(config$plots$three_way_mapping[c("x", "color", "facet")], use.names = FALSE)
    if (length(mapping_values) != 3L || anyDuplicated(mapping_values) ||
        !all(mapping_values %in% enabled_factors$code)) {
      stop(
        "plots$three_way_mapping must assign three distinct enabled factor codes to x, color, and facet.",
        call. = FALSE
      )
    }
  }

  invisible(TRUE)
}

install_and_load_packages <- function(config) {
  required_packages <- c(
    "readxl", "readr", "dplyr", "tidyr", "purrr", "stringr", "tibble",
    "car", "afex", "lme4", "ARTool", "emmeans", "ggplot2", "openxlsx", "fs", "rlang", "patchwork"
  )

  missing_packages <- required_packages[
    !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
  ]

  auto_install <- isTRUE(config$packages$auto_install)
  if (length(missing_packages) > 0L && !auto_install) {
    stop(
      "Missing R packages: ", paste(missing_packages, collapse = ", "),
      ". Install them or set packages$auto_install = TRUE.",
      call. = FALSE
    )
  }

  if (length(missing_packages) > 0L) {
    install.packages(
      missing_packages,
      repos = config$packages$repository %||% "https://cloud.r-project.org",
      dependencies = TRUE
    )
  }

  invisible(lapply(required_packages, library, character.only = TRUE))
}

read_input_file <- function(file_path, sheet = NULL) {
  extension <- tolower(tools::file_ext(file_path))
  if (extension %in% c("xlsx", "xls")) {
    return(readxl::read_excel(file_path, sheet = sheet %||% 1))
  }
  if (extension == "csv") {
    return(readr::read_csv(file_path, show_col_types = FALSE, progress = FALSE))
  }
  if (extension %in% c("tsv", "txt")) {
    return(readr::read_tsv(file_path, show_col_types = FALSE, progress = FALSE))
  }
  if (extension == "rds") {
    return(readRDS(file_path))
  }
  stop("Unsupported input-file extension: ", extension, call. = FALSE)
}

prepare_input_data <- function(raw_data, config) {
  factor_spec <- config$factors[config$factors$enabled %in% TRUE, , drop = FALSE]
  id_column <- config$input$id_column
  data_format <- tolower(config$input$data_format %||% "wide")

  if (data_format == "long") {
    outcome_name_column <- config$input$long$outcome_name_column
    outcome_value_column <- config$input$long$outcome_value_column
    required_long_columns <- c(id_column, factor_spec$column, outcome_name_column, outcome_value_column)
    missing_long_columns <- setdiff(required_long_columns, names(raw_data))
    if (length(missing_long_columns) > 0L) {
      stop("Long-format input is missing columns: ", paste(missing_long_columns, collapse = ", "), call. = FALSE)
    }

    duplicate_keys <- raw_data |>
      dplyr::count(dplyr::across(dplyr::all_of(c(id_column, factor_spec$column, outcome_name_column)))) |>
      dplyr::filter(.data$n > 1L)
    if (nrow(duplicate_keys) > 0L) {
      stop("Long-format input contains duplicate ID/factor/outcome rows.", call. = FALSE)
    }

    raw_data <- raw_data |>
      tidyr::pivot_wider(
        id_cols = dplyr::all_of(c(id_column, factor_spec$column)),
        names_from = dplyr::all_of(outcome_name_column),
        values_from = dplyr::all_of(outcome_value_column)
      )
  }

  required_base_columns <- c(id_column, factor_spec$column)
  missing_base_columns <- setdiff(required_base_columns, names(raw_data))
  if (length(missing_base_columns) > 0L) {
    stop("Input data is missing ID or factor columns: ", paste(missing_base_columns, collapse = ", "), call. = FALSE)
  }

  outcome_spec <- config$outcomes
  if (is.null(outcome_spec)) {
    excluded_columns <- c(id_column, factor_spec$column)
    candidate_columns <- setdiff(names(raw_data), excluded_columns)
    numeric_columns <- candidate_columns[vapply(raw_data[candidate_columns], is.numeric, logical(1))]
    outcome_spec <- data.frame(
      column = numeric_columns,
      label = numeric_columns,
      category = "Uncategorized",
      enabled = TRUE,
      include_in_correlation = TRUE,
      stringsAsFactors = FALSE
    )
  }
  if (!"include_in_correlation" %in% names(outcome_spec)) {
    outcome_spec$include_in_correlation <- TRUE
  }
  outcome_spec <- outcome_spec[outcome_spec$enabled %in% TRUE, , drop = FALSE]
  if (nrow(outcome_spec) == 0L) stop("No dependent variables are enabled.", call. = FALSE)

  missing_outcomes <- setdiff(outcome_spec$column, names(raw_data))
  if (length(missing_outcomes) > 0L) {
    stop("Input data is missing outcome columns: ", paste(missing_outcomes, collapse = ", "), call. = FALSE)
  }

  analysis_data <- tibble::tibble(ID = raw_data[[id_column]])
  for (i in seq_len(nrow(factor_spec))) {
    code <- factor_spec$code[[i]]
    source_column <- factor_spec$column[[i]]
    configured_levels <- as.character(config$factor_levels[[code]])
    observed_levels <- unique(as.character(raw_data[[source_column]]))
    unknown_levels <- setdiff(observed_levels[!is.na(observed_levels)], configured_levels)
    if (length(unknown_levels) > 0L) {
      stop(
        "Factor ", source_column, " contains levels not listed in factor_levels$", code,
        ": ", paste(unknown_levels, collapse = ", "),
        call. = FALSE
      )
    }
    analysis_data[[code]] <- factor(as.character(raw_data[[source_column]]), levels = configured_levels)
  }

  conversion_report <- list()
  for (i in seq_len(nrow(outcome_spec))) {
    source_column <- outcome_spec$column[[i]]
    original_values <- raw_data[[source_column]]

    # Converting a factor directly with as.numeric() returns its internal level
    # codes rather than the displayed values. Convert character/factor columns
    # through as.character() so values such as "4.5" remain 4.5.
    numeric_values <- if (is.numeric(original_values)) {
      as.numeric(original_values)
    } else {
      suppressWarnings(as.numeric(as.character(original_values)))
    }

    failed_conversion <- sum(!is.na(original_values) & is.na(numeric_values))
    non_finite_values <- sum(!is.na(numeric_values) & !is.finite(numeric_values))
    analysis_data[[source_column]] <- numeric_values
    conversion_report[[length(conversion_report) + 1L]] <- tibble::tibble(
      DV = outcome_spec$label[[i]],
      Category = outcome_spec$category[[i]],
      Source_Column = source_column,
      Non_Numeric_Values_Converted_to_NA = failed_conversion,
      Non_Finite_Numeric_Values = non_finite_values
    )
  }

  list(
    data = analysis_data,
    factor_spec = factor_spec,
    outcome_spec = outcome_spec,
    conversion_report = dplyr::bind_rows(conversion_report)
  )
}

p_to_label <- function(p) {
  dplyr::case_when(
    is.na(p) ~ "",
    p < 0.001 ~ "***",
    p < 0.01 ~ "**",
    p < 0.05 ~ "*",
    p < 0.10 ~ ".",
    TRUE ~ "n.s."
  )
}

category_page_significance_note <- function() {
  paste(
    "p < 0.001: ***",
    "p < 0.01: **",
    "p < 0.05: *",
    "p < 0.10: .",
    "p >= 0.10: n.s.",
    sep = "\n"
  )
}

format_p_for_plot <- function(p) {
  if (is.na(p)) return("p=NA")
  if (p < 0.001) return("p<.001")
  paste0("p=", sub("^0", "", sprintf("%.3f", p)))
}

partial_eta2_from_f <- function(f_value, df1, df2) {
  ifelse(
    is.finite(f_value) & is.finite(df1) & is.finite(df2) & f_value >= 0,
    (f_value * df1) / (f_value * df1 + df2),
    NA_real_
  )
}

cohens_f_from_eta2 <- function(eta2) {
  ifelse(is.finite(eta2) & eta2 >= 0 & eta2 < 1, sqrt(eta2 / (1 - eta2)), NA_real_)
}

eta2_magnitude <- function(eta2) {
  dplyr::case_when(
    is.na(eta2) ~ NA_character_,
    eta2 < 0.01 ~ "negligible",
    eta2 < 0.06 ~ "small",
    eta2 < 0.14 ~ "medium",
    TRUE ~ "large"
  )
}

capture_warnings <- function(expression) {
  warning_messages <- character(0)
  value <- withCallingHandlers(
    expression,
    warning = function(w) {
      warning_messages <<- c(warning_messages, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  list(value = value, warnings = unique(warning_messages))
}

safe_shapiro <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) < 3L) return(list(W = NA_real_, p = NA_real_, note = "Fewer than three observations"))
  if (length(unique(x)) < 2L) return(list(W = NA_real_, p = NA_real_, note = "Constant values"))
  sampled <- FALSE
  if (length(x) > 5000L) {
    x <- sample(x, 5000L)
    sampled <- TRUE
  }
  result <- tryCatch(stats::shapiro.test(x), error = function(e) e)
  if (inherits(result, "error")) return(list(W = NA_real_, p = NA_real_, note = conditionMessage(result)))
  list(
    W = unname(result$statistic),
    p = unname(result$p.value),
    note = if (sampled) "Random sample of 5,000 observations" else ""
  )
}

get_correlation_config <- function(config) {
  correlation_config <- config$correlation %||% list()
  list(
    enabled = isTRUE(correlation_config$enabled %||% TRUE),
    minimum_complete_pairs = as.integer(correlation_config$minimum_complete_pairs %||% 10L),
    normality_alpha = as.numeric(correlation_config$normality_alpha %||% config$analysis$alpha),
    p_adjust_method = normalize_p_adjust_method(
      correlation_config$p_adjust_method %||% correlation_config$p_adjust %||% "BH",
      default = "BH"
    ),
    label_wrap_width = as.integer(correlation_config$label_wrap_width %||% 18L)
  )
}


get_correlation_p_adjust_info <- function(config) {
  p_adjustment_info(get_correlation_config(config)$p_adjust_method, default = "BH")
}

make_correlation_matrix_frame <- function(matrix_object, variable_labels) {
  # Preserve human-readable outcome labels exactly. In particular, do not let
  # data.frame/cbind convert spaces to syntactic dots (e.g., "Outcome 1" ->
  # "Outcome.1"), because the main matrix and its column-definition panel must
  # use identical names.
  frame <- as.data.frame(
    matrix_object,
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  names(frame) <- variable_labels
  out <- data.frame(
    Variable = variable_labels,
    frame,
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  names(out) <- c("Variable", variable_labels)
  rownames(out) <- NULL
  out
}

make_correlation_heatmap <- function(
    coefficient_matrix,
    adjusted_p_matrix,
    variable_labels,
    selected_method,
    config,
    p_adjust_method = NULL) {
  if (length(variable_labels) < 2L) return(NULL)

  correlation_config <- get_correlation_config(config)
  p_adjust_info <- p_adjustment_info(
    p_adjust_method %||% correlation_config$p_adjust_method,
    default = "BH"
  )
  heatmap_frame <- expand.grid(
    Row = variable_labels,
    Column = variable_labels,
    stringsAsFactors = FALSE
  )
  heatmap_frame$Row_Index <- match(heatmap_frame$Row, variable_labels)
  heatmap_frame$Column_Index <- match(heatmap_frame$Column, variable_labels)
  heatmap_frame$Coefficient <- mapply(
    function(row_label, column_label) coefficient_matrix[row_label, column_label],
    heatmap_frame$Row,
    heatmap_frame$Column
  )
  heatmap_frame$Adjusted_p <- mapply(
    function(row_label, column_label) adjusted_p_matrix[row_label, column_label],
    heatmap_frame$Row,
    heatmap_frame$Column
  )

  # Use complementary halves of the matrix to prevent coefficient,
  # significance, and method labels from overlapping in the same cell.
  # The lower triangle contains only coefficients, the upper triangle contains
  # only adjusted-p significance labels, and the diagonal is intentionally blank.
  significance_label <- p_to_label(heatmap_frame$Adjusted_p)
  significance_label[is.na(heatmap_frame$Adjusted_p)] <- "NA"
  coefficient_label <- ifelse(
    is.na(heatmap_frame$Coefficient),
    "NA",
    sprintf("%.2f", heatmap_frame$Coefficient)
  )
  heatmap_frame$Cell_Label <- dplyr::case_when(
    heatmap_frame$Row_Index > heatmap_frame$Column_Index ~ coefficient_label,
    heatmap_frame$Row_Index < heatmap_frame$Column_Index ~ significance_label,
    TRUE ~ ""
  )
  heatmap_frame$Text_Color <- ifelse(
    is.finite(heatmap_frame$Coefficient) & abs(heatmap_frame$Coefficient) >= 0.55,
    "white",
    "black"
  )

  display_labels <- setNames(
    stringr::str_wrap(variable_labels, width = correlation_config$label_wrap_width),
    variable_labels
  )
  heatmap_frame$Column <- factor(heatmap_frame$Column, levels = variable_labels)
  heatmap_frame$Row <- factor(heatmap_frame$Row, levels = rev(variable_labels))

  coefficient_symbol <- if (identical(selected_method, "Pearson")) "r" else "rho"

  ggplot2::ggplot(
    heatmap_frame,
    ggplot2::aes(x = .data$Column, y = .data$Row, fill = .data$Coefficient)
  ) +
    ggplot2::geom_tile(color = "white", linewidth = 0.35) +
    ggplot2::geom_text(
      ggplot2::aes(label = .data$Cell_Label, color = .data$Text_Color),
      size = 3.1,
      lineheight = 0.92,
      na.rm = TRUE
    ) +
    ggplot2::scale_color_identity() +
    ggplot2::scale_fill_gradient2(
      low = "#B2182B",
      mid = "#F7F7F7",
      high = "#2166AC",
      midpoint = 0,
      limits = c(-1, 1),
      na.value = "grey90",
      name = "Correlation"
    ) +
    ggplot2::scale_x_discrete(labels = display_labels, drop = FALSE) +
    ggplot2::scale_y_discrete(labels = display_labels, drop = FALSE) +
    ggplot2::coord_fixed() +
    ggplot2::labs(
      title = paste0("Correlation Heatmap (", selected_method, ")"),
      subtitle = paste0(
        "Lower triangle: correlation coefficients; upper triangle: ",
        p_adjust_info$column_prefix, "-adjusted p significance symbols"
      ),
      caption = paste0(
        "Lower triangle reports ", coefficient_symbol,
        "; p-value adjustment: ", p_adjust_info$display_label,
        "; diagonal cells are omitted"
      ),
      x = NULL,
      y = NULL
    ) +
    ggplot2::theme_minimal(base_size = config$plots$base_font_size %||% 11) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 18, face = "bold", hjust = 0.5),
      plot.subtitle = ggplot2::element_text(size = 11, hjust = 0.5),
      plot.caption = ggplot2::element_text(size = 9, hjust = 0),
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1, vjust = 1, size = 8.5),
      axis.text.y = ggplot2::element_text(size = 8.5),
      panel.grid = ggplot2::element_blank(),
      plot.margin = ggplot2::margin(20, 25, 20, 25)
    )
}

analyze_correlations <- function(
    analysis_data, outcome_spec, config, factor_spec = NULL, p_adjust_method = NULL) {
  correlation_config <- get_correlation_config(config)
  correlation_config$p_adjust_method <- normalize_p_adjust_method(
    p_adjust_method %||% correlation_config$p_adjust_method, default = "BH"
  )
  if (!correlation_config$p_adjust_method %in% stats::p.adjust.methods) {
    stop(
      "Correlation p_adjust_method must be supported by stats::p.adjust(): ",
      correlation_config$p_adjust_method,
      call. = FALSE
    )
  }
  correlation_p_adjust_info <- p_adjustment_info(
    correlation_config$p_adjust_method, default = "BH"
  )
  empty_result <- list(
    enabled = correlation_config$enabled,
    included_outcomes = tibble::tibble(),
    selected_method = NA_character_,
    method_selection_reason = NA_character_,
    p_adjust_method = correlation_config$p_adjust_method,
    p_adjust_label = correlation_p_adjust_info$display_label,
    variable_normality = tibble::tibble(),
    results = tibble::tibble(),
    coefficient_matrix = tibble::tibble(),
    method_matrix = tibble::tibble(),
    adjusted_p_matrix = tibble::tibble(),
    heatmap = NULL,
    warnings_errors = tibble::tibble()
  )
  if (!correlation_config$enabled) return(empty_result)

  correlation_spec <- outcome_spec |>
    dplyr::filter(.data$include_in_correlation %in% TRUE)
  empty_result$included_outcomes <- correlation_spec

  if (nrow(correlation_spec) < 2L) {
    empty_result$warnings_errors <- tibble::tibble(
      DV = NA_character_,
      Category = "Correlation Analysis",
      Stage = "Correlation analysis",
      Type = "Warning",
      Message = "Fewer than two enabled dependent variables were selected for correlation analysis."
    )
    return(empty_result)
  }

  variable_labels <- as.character(correlation_spec$label)
  variable_columns <- as.character(correlation_spec$column)
  variable_categories <- as.character(correlation_spec$category)
  names(variable_columns) <- variable_labels
  names(variable_categories) <- variable_labels

  design <- if (!is.null(factor_spec)) get_design_info(factor_spec) else list(has_repeated = FALSE)
  correlation_data <- analysis_data
  correlation_data_unit <- "observation"
  if (isTRUE(design$has_repeated)) {
    # Repeated rows from the same participant are not independent. For the
    # generic correlation module, collapse each enabled variable to one
    # participant-level mean before pairwise correlations.
    correlation_data <- analysis_data |>
      dplyr::group_by(.data$ID) |>
      dplyr::summarise(
        dplyr::across(
          # variable_columns is named by the display labels below. Passing the
          # named vector directly to tidyselect::all_of() would rename the
          # aggregated columns to those labels, after which later lookups by
          # source-column name would silently return NULL. Strip the names so
          # participant-level aggregation preserves the original source names.
          dplyr::all_of(unname(variable_columns)),
          ~ if (all(is.na(.x) | !is.finite(.x))) NA_real_ else mean(.x[is.finite(.x)], na.rm = TRUE)
        ),
        .groups = "drop"
      )
    correlation_data_unit <- "participant mean across repeated conditions"
  }

  required_correlation_columns <- unname(variable_columns)
  missing_correlation_columns <- setdiff(required_correlation_columns, names(correlation_data))
  if (length(missing_correlation_columns) > 0L) {
    empty_result$warnings_errors <- tibble::tibble(
      DV = NA_character_,
      Category = "Correlation Analysis",
      Stage = "Correlation data preparation",
      Type = "Error",
      Message = paste0(
        "Correlation data preparation lost required source column(s): ",
        paste(missing_correlation_columns, collapse = ", "),
        ". Analysis was stopped instead of returning silent zero-length results."
      )
    )
    return(empty_result)
  }

  # Select one common method for the complete correlation analysis. Normality
  # is evaluated once for every included variable using all of its finite
  # observations. Pearson is used only when every variable passes the same
  # eligibility rule; otherwise every tested pair uses Spearman.
  variable_normality_records <- lapply(seq_along(variable_labels), function(index) {
    variable_label <- variable_labels[[index]]
    variable_column <- variable_columns[[variable_label]]
    values <- as.numeric(correlation_data[[variable_column]])
    finite_values <- values[is.finite(values)]
    n_finite <- length(finite_values)
    n_unique <- length(unique(finite_values))
    shapiro_result <- safe_shapiro(finite_values)
    pearson_eligible <-
      n_finite >= correlation_config$minimum_complete_pairs &&
      n_unique >= 3L &&
      is.finite(shapiro_result$p) &&
      shapiro_result$p >= correlation_config$normality_alpha

    eligibility_reason <- if (n_finite < correlation_config$minimum_complete_pairs) {
      paste0(
        "Fewer than ", correlation_config$minimum_complete_pairs,
        " finite observations."
      )
    } else if (n_unique < 3L) {
      "Fewer than three unique finite values."
    } else if (!is.finite(shapiro_result$p)) {
      "Shapiro-Wilk normality could not be evaluated."
    } else if (shapiro_result$p < correlation_config$normality_alpha) {
      paste0(
        "Shapiro-Wilk p < ", correlation_config$normality_alpha, "."
      )
    } else {
      paste0(
        "Shapiro-Wilk p >= ", correlation_config$normality_alpha,
        " and at least three unique values."
      )
    }

    tibble::tibble(
      Variable = variable_label,
      Category = variable_categories[[variable_label]],
      Data_Unit = correlation_data_unit,
      N_Finite = n_finite,
      N_Unique = n_unique,
      Shapiro_W = shapiro_result$W,
      Shapiro_p = shapiro_result$p,
      Normality_Alpha = correlation_config$normality_alpha,
      Shapiro_Decision = if (is.finite(shapiro_result$p)) {
        ifelse(
          shapiro_result$p >= correlation_config$normality_alpha,
          "Pass",
          "Fail"
        )
      } else {
        "Not evaluable"
      },
      Pearson_Eligible = pearson_eligible,
      Eligibility_Reason = eligibility_reason,
      Note = shapiro_result$note
    )
  })
  variable_normality <- dplyr::bind_rows(variable_normality_records)

  all_variables_pearson_eligible <-
    nrow(variable_normality) > 0L &&
    all(variable_normality$Pearson_Eligible %in% TRUE)
  selected_method <- if (all_variables_pearson_eligible) "Pearson" else "Spearman"

  if (identical(selected_method, "Pearson")) {
    method_selection_reason <- paste0(
      "Pearson was selected uniformly because every included variable passed ",
      "Shapiro-Wilk normality at alpha = ", correlation_config$normality_alpha,
      " and contained at least three unique finite values. Data unit: ", correlation_data_unit, "."
    )
  } else {
    method_selection_reason <- paste0(
      "Spearman was selected uniformly because at least one included variable ",
      "failed or could not be evaluated under the Pearson eligibility rule. ",
      "See 19_Correlation_Normality for variable-level diagnostics. Data unit: ", correlation_data_unit, "."
    )
  }

  variable_normality <- variable_normality |>
    dplyr::mutate(
      Correlation_Method = selected_method,
      Correlation_Method_Selection_Reason = method_selection_reason
    )

  pair_indexes <- utils::combn(seq_along(variable_labels), 2L, simplify = FALSE)
  pair_results <- vector("list", length(pair_indexes))
  warning_records <- list()

  for (pair_index in seq_along(pair_indexes)) {
    indexes <- pair_indexes[[pair_index]]
    label_1 <- variable_labels[[indexes[[1]]]]
    label_2 <- variable_labels[[indexes[[2]]]]
    column_1 <- variable_columns[[label_1]]
    column_2 <- variable_columns[[label_2]]

    normality_1 <- variable_normality |>
      dplyr::filter(.data$Variable == .env$label_1) |>
      dplyr::slice(1L)
    normality_2 <- variable_normality |>
      dplyr::filter(.data$Variable == .env$label_2) |>
      dplyr::slice(1L)

    x <- as.numeric(correlation_data[[column_1]])
    y <- as.numeric(correlation_data[[column_2]])
    complete_rows <- is.finite(x) & is.finite(y)
    x_complete <- x[complete_rows]
    y_complete <- y[complete_rows]
    n_complete <- length(x_complete)
    pair_unique_1 <- length(unique(x_complete))
    pair_unique_2 <- length(unique(y_complete))

    method <- selected_method
    method_reason <- method_selection_reason
    coefficient <- NA_real_
    statistic_name <- NA_character_
    statistic <- NA_real_
    parameter <- NA_real_
    p_value <- NA_real_
    note <- ""

    if (n_complete < correlation_config$minimum_complete_pairs) {
      method <- NA_character_
      method_reason <- paste0(
        "Not tested: ", n_complete,
        " complete pairs, below minimum ", correlation_config$minimum_complete_pairs,
        ". The globally selected method was ", selected_method, "."
      )
    } else if (pair_unique_1 < 2L || pair_unique_2 < 2L) {
      method <- NA_character_
      method_reason <- paste0(
        "Not tested: at least one variable is constant in the pairwise-complete sample. ",
        "The globally selected method was ", selected_method, "."
      )
    } else if (
      identical(selected_method, "Pearson") &&
      (pair_unique_1 < 3L || pair_unique_2 < 3L)
    ) {
      method <- NA_character_
      method_reason <- paste0(
        "Not tested: the uniform Pearson rule requires at least three unique values ",
        "for both variables in the pairwise-complete sample."
      )
    } else {
      test_capture <- tryCatch(
        capture_warnings(
          if (identical(selected_method, "Pearson")) {
            stats::cor.test(x_complete, y_complete, method = "pearson")
          } else {
            stats::cor.test(x_complete, y_complete, method = "spearman", exact = FALSE)
          }
        ),
        error = function(e) e
      )

      if (inherits(test_capture, "error")) {
        note <- conditionMessage(test_capture)
        warning_records[[length(warning_records) + 1L]] <- tibble::tibble(
          DV = paste(label_1, "vs", label_2),
          Category = "Correlation Analysis",
          Stage = "Correlation test",
          Type = "Error",
          Message = conditionMessage(test_capture)
        )
      } else {
        test_result <- test_capture$value
        coefficient <- unname(test_result$estimate[[1]])
        statistic_names <- names(test_result$statistic)
        statistic_name <- if (length(statistic_names) > 0L) statistic_names[[1]] else NA_character_
        statistic <- unname(test_result$statistic[[1]])
        parameter <- if (!is.null(test_result$parameter)) {
          unname(test_result$parameter[[1]])
        } else {
          NA_real_
        }
        p_value <- unname(test_result$p.value)
        if (length(test_capture$warnings) > 0L) {
          note <- paste(test_capture$warnings, collapse = " | ")
          warning_records[[length(warning_records) + 1L]] <- tibble::tibble(
            DV = paste(label_1, "vs", label_2),
            Category = "Correlation Analysis",
            Stage = "Correlation test",
            Type = "Warning",
            Message = note
          )
        }
      }
    }

    pair_results[[pair_index]] <- tibble::tibble(
      Variable_1 = label_1,
      Category_1 = variable_categories[[label_1]],
      Variable_2 = label_2,
      Category_2 = variable_categories[[label_2]],
      Data_Unit = correlation_data_unit,
      N_Complete = n_complete,
      Variable_1_Unique = normality_1$N_Unique[[1]],
      Variable_2_Unique = normality_2$N_Unique[[1]],
      Variable_1_Shapiro_W = normality_1$Shapiro_W[[1]],
      Variable_1_Shapiro_p = normality_1$Shapiro_p[[1]],
      Variable_2_Shapiro_W = normality_2$Shapiro_W[[1]],
      Variable_2_Shapiro_p = normality_2$Shapiro_p[[1]],
      Normality_Alpha = correlation_config$normality_alpha,
      Method = method,
      Method_Selection_Reason = method_reason,
      Coefficient = coefficient,
      Statistic_Name = statistic_name,
      Statistic = statistic,
      Parameter = parameter,
      p_value = p_value,
      Note = note
    )
  }

  result_frame <- dplyr::bind_rows(pair_results)
  result_frame$p_adjusted <- NA_real_
  valid_p <- is.finite(result_frame$p_value)
  if (any(valid_p)) {
    result_frame$p_adjusted[valid_p] <- stats::p.adjust(
      result_frame$p_value[valid_p],
      method = correlation_config$p_adjust_method
    )
  }
  result_frame <- result_frame |>
    dplyr::mutate(
      P_Adjustment = correlation_config$p_adjust_method,
      Significance = p_to_label(.data$p_adjusted),
      Significant = !is.na(.data$p_adjusted) & .data$p_adjusted < config$analysis$alpha
    )

  coefficient_matrix <- matrix(
    NA_real_,
    nrow = length(variable_labels),
    ncol = length(variable_labels),
    dimnames = list(variable_labels, variable_labels)
  )
  adjusted_p_matrix <- coefficient_matrix
  method_matrix <- matrix(
    NA_character_,
    nrow = length(variable_labels),
    ncol = length(variable_labels),
    dimnames = list(variable_labels, variable_labels)
  )
  diag(coefficient_matrix) <- 1
  diag(adjusted_p_matrix) <- NA_real_
  diag(method_matrix) <- "Self"

  for (row_index in seq_len(nrow(result_frame))) {
    label_1 <- result_frame$Variable_1[[row_index]]
    label_2 <- result_frame$Variable_2[[row_index]]
    coefficient_matrix[label_1, label_2] <- result_frame$Coefficient[[row_index]]
    coefficient_matrix[label_2, label_1] <- result_frame$Coefficient[[row_index]]
    adjusted_p_matrix[label_1, label_2] <- result_frame$p_adjusted[[row_index]]
    adjusted_p_matrix[label_2, label_1] <- result_frame$p_adjusted[[row_index]]
    method_matrix[label_1, label_2] <- result_frame$Method[[row_index]]
    method_matrix[label_2, label_1] <- result_frame$Method[[row_index]]
  }

  heatmap <- make_correlation_heatmap(
    coefficient_matrix,
    adjusted_p_matrix,
    variable_labels,
    selected_method,
    config,
    p_adjust_method = correlation_config$p_adjust_method
  )

  list(
    enabled = TRUE,
    included_outcomes = correlation_spec,
    selected_method = selected_method,
    method_selection_reason = method_selection_reason,
    p_adjust_method = correlation_config$p_adjust_method,
    p_adjust_label = correlation_p_adjust_info$display_label,
    variable_normality = variable_normality,
    results = result_frame,
    coefficient_matrix = make_correlation_matrix_frame(coefficient_matrix, variable_labels),
    method_matrix = make_correlation_matrix_frame(method_matrix, variable_labels),
    adjusted_p_matrix = make_correlation_matrix_frame(adjusted_p_matrix, variable_labels),
    heatmap = heatmap,
    warnings_errors = dplyr::bind_rows(warning_records)
  )
}


get_design_info <- function(factor_spec) {
  between_codes <- as.character(factor_spec$code[factor_spec$role == "between"])
  within_codes <- as.character(factor_spec$code[factor_spec$role == "within"])
  design_type <- if (length(within_codes) == 0L) {
    "between-subjects"
  } else if (length(between_codes) == 0L) {
    "within-subjects"
  } else {
    "mixed"
  }
  list(
    type = design_type,
    between = between_codes,
    within = within_codes,
    has_repeated = length(within_codes) > 0L
  )
}

validate_subject_factor_structure <- function(data, factor_spec) {
  design <- get_design_info(factor_spec)
  issues <- character(0)

  if (!design$has_repeated) {
    duplicate_count <- sum(duplicated(data$ID))
    if (duplicate_count > 0L) {
      issues <- c(
        issues,
        paste0(
          duplicate_count,
          " duplicated ID occurrence(s) were found in a between-subjects-only design."
        )
      )
    }
    return(issues)
  }

  if (length(design$between) > 0L) {
    for (code in design$between) {
      inconsistent_ids <- data |>
        dplyr::group_by(.data$ID) |>
        dplyr::summarise(
          N_Levels = dplyr::n_distinct(.data[[code]][!is.na(.data[[code]])]),
          .groups = "drop"
        ) |>
        dplyr::filter(.data$N_Levels > 1L)
      if (nrow(inconsistent_ids) > 0L) {
        issues <- c(
          issues,
          paste0(
            nrow(inconsistent_ids),
            " participant(s) have more than one level of between-subject factor ",
            code, "."
          )
        )
      }
    }
  }

  duplicate_cells <- data |>
    dplyr::count(
      dplyr::across(dplyr::all_of(c("ID", design$within))),
      name = "N"
    ) |>
    dplyr::filter(.data$N > 1L)
  if (nrow(duplicate_cells) > 0L) {
    issues <- c(
      issues,
      paste0(
        nrow(duplicate_cells),
        " duplicated participant/within-condition cell(s) were found. ",
        "The engine expects one row per participant x within-factor condition."
      )
    )
  }

  issues
}

retain_complete_repeated_subjects <- function(data, within_codes, factor_levels) {
  if (length(within_codes) == 0L) {
    return(list(data = data, excluded_ids = character(0), expected_cells = 1L))
  }

  expected_cells <- prod(vapply(
    within_codes,
    function(code) length(factor_levels[[code]]),
    integer(1)
  ))

  counted_data <- data
  counted_data$.Within_Cell <- do.call(
    interaction,
    c(as.list(counted_data[within_codes]), list(drop = TRUE, lex.order = TRUE))
  )
  subject_counts <- counted_data |>
    dplyr::group_by(.data$ID) |>
    dplyr::summarise(
      N_Valid_Cells = dplyr::n(),
      N_Distinct_Cells = dplyr::n_distinct(.data$.Within_Cell),
      .groups = "drop"
    )

  complete_ids <- subject_counts |>
    dplyr::filter(
      .data$N_Valid_Cells == expected_cells,
      .data$N_Distinct_Cells == expected_cells
    ) |>
    dplyr::pull("ID")

  excluded_ids <- setdiff(unique(as.character(data$ID)), as.character(complete_ids))
  retained <- data |>
    dplyr::filter(as.character(.data$ID) %in% as.character(complete_ids)) |>
    droplevels()

  list(
    data = retained,
    excluded_ids = excluded_ids,
    expected_cells = expected_cells
  )
}

safe_design_levene <- function(data, between_codes, within_codes, center_name) {
  if (length(between_codes) == 0L) {
    return(list(
      F = NA_real_, df1 = NA_real_, df2 = NA_real_, p = NA_real_,
      note = "Not applicable: the design contains no between-subject factors.",
      required = FALSE
    ))
  }

  # All-between designs require only one Levene test across the configured
  # between-subject cells.
  if (length(within_codes) == 0L) {
    result <- safe_levene(data, between_codes, center_name)
    result$required <- TRUE
    return(result)
  }

  # For mixed designs, assess between-group homogeneity separately within each
  # repeated-measures condition. The minimum finite p-value is retained as the
  # screening statistic, so the automatic ANOVA branch is selected only when
  # every evaluable within-condition-specific Levene test is non-significant.
  within_key <- do.call(
    interaction,
    c(as.list(data[within_codes]), list(drop = TRUE, lex.order = TRUE, sep = " | "))
  )
  split_data <- split(data, within_key, drop = TRUE)
  cell_results <- lapply(names(split_data), function(cell_name) {
    res <- safe_levene(split_data[[cell_name]], between_codes, center_name)
    res$cell <- cell_name
    res
  })

  finite_index <- which(vapply(
    cell_results,
    function(x) is.finite(x$p),
    logical(1)
  ))
  if (length(finite_index) == 0L) {
    return(list(
      F = NA_real_, df1 = NA_real_, df2 = NA_real_, p = NA_real_,
      note = paste0(
        "No evaluable within-condition-specific ", tolower(center_name),
        "-centered Levene test was available across ", length(split_data),
        " repeated-measures condition(s)."
      ),
      required = TRUE
    ))
  }

  finite_ps <- vapply(cell_results[finite_index], function(x) x$p, numeric(1))
  worst_local <- finite_index[[which.min(finite_ps)]]
  worst <- cell_results[[worst_local]]
  worst$required <- TRUE
  worst$note <- paste0(
    tolower(center_name),
    "-centered Levene screening performed separately in ", length(split_data),
    " within-condition cell(s); reported statistics correspond to the smallest p-value (",
    worst$cell,
    "). All evaluable cell-specific Levene tests must be non-significant for automatic ANOVA selection."
  )
  worst$cell <- NULL
  worst
}

fit_repeated_residual_model <- function(data, factor_codes) {
  fixed_text <- paste(factor_codes, collapse = " * ")
  formula <- stats::as.formula(paste0("Y ~ ", fixed_text, " + (1|ID)"))
  lme4::lmer(formula, data = data, REML = TRUE)
}

fit_afex_anova <- function(data, design, anova_type, correction) {
  correction <- toupper(correction %||% "GG")
  if (correction == "NONE") correction <- "none"
  afex::aov_ez(
    id = "ID",
    dv = "Y",
    data = data,
    between = if (length(design$between) > 0L) design$between else NULL,
    within = if (length(design$within) > 0L) design$within else NULL,
    type = as.integer(anova_type),
    anova_table = list(correction = correction, es = "pes"),
    factorize = FALSE
  )
}

extract_afex_anova_table <- function(
    model, outcome_label, category, factor_spec, anova_type, correction, alpha) {
  correction_value <- toupper(correction %||% "GG")
  correction_arg <- if (correction_value == "NONE") "none" else correction_value
  table <- as.data.frame(
    stats::anova(model, correction = correction_arg, es = "pes"),
    check.names = FALSE
  )

  effect_codes <- if ("Effect" %in% names(table)) {
    as.character(table$Effect)
  } else {
    rownames(table)
  }
  rownames(table) <- NULL

  df1_candidates <- grep("num.*Df|num.*df|^Df$|^df$", names(table), ignore.case = TRUE, value = TRUE)
  df2_candidates <- grep("den.*Df|den.*df|Df\\.res|df\\.res", names(table), ignore.case = TRUE, value = TRUE)
  f_candidates <- grep("^F$|^F value$|^F\\.value$", names(table), ignore.case = TRUE, value = TRUE)
  p_candidates <- grep("Pr\\(>F\\)|p\\.value|^p$", names(table), ignore.case = TRUE, value = TRUE)
  pes_candidates <- grep("^pes$|partial.*eta", names(table), ignore.case = TRUE, value = TRUE)
  mse_candidates <- grep("^MSE$", names(table), ignore.case = TRUE, value = TRUE)

  if (length(df1_candidates) == 0L || length(df2_candidates) == 0L ||
      length(f_candidates) == 0L || length(p_candidates) == 0L) {
    stop(
      "Could not identify numerator df, denominator df, F, or p-value columns in the afex ANOVA table.",
      call. = FALSE
    )
  }

  df1 <- as.numeric(table[[df1_candidates[[1]]]])
  df2 <- as.numeric(table[[df2_candidates[[1]]]])
  f_value <- as.numeric(table[[f_candidates[[1]]]])
  p_value <- as.numeric(table[[p_candidates[[1]]]])
  partial_eta2 <- if (length(pes_candidates) > 0L) {
    as.numeric(table[[pes_candidates[[1]]]])
  } else {
    partial_eta2_from_f(f_value, df1, df2)
  }
  mse <- if (length(mse_candidates) > 0L) {
    as.numeric(table[[mse_candidates[[1]]]])
  } else {
    rep(NA_real_, length(effect_codes))
  }

  correction_label <- if (correction_value == "NONE") {
    "uncorrected within-subject df"
  } else {
    paste0(correction_value, " correction for within-subject effects")
  }
  model_label <- paste0(
    if (get_design_info(factor_spec)$type == "within-subjects") {
      "Repeated-measures ANOVA"
    } else {
      "Mixed ANOVA"
    },
    " (Type ", anova_type, "; ", correction_label, ")"
  )

  tibble::tibble(
    DV = outcome_label,
    Category = category,
    Model_Method = model_label,
    Effect_Code = effect_codes,
    Effect_Label = vapply(effect_codes, effect_label, character(1), factor_spec = factor_spec),
    df1 = df1,
    df2 = df2,
    Sum_Squares = NA_real_,
    Mean_Square = NA_real_,
    Error_MSE = mse,
    F_value = f_value,
    p_value = p_value,
    Partial_Eta2 = partial_eta2
  ) |>
    dplyr::mutate(
      Cohens_f = cohens_f_from_eta2(.data$Partial_Eta2),
      Effect_Size_Magnitude = eta2_magnitude(.data$Partial_Eta2),
      Effect_Size_Scale = "raw response",
      Significance = p_to_label(.data$p_value),
      Significant = !is.na(.data$p_value) & .data$p_value < alpha
    )
}

safe_levene <- function(data, factor_codes, center_name) {
  group <- do.call(
    interaction,
    c(as.list(data[factor_codes]), list(drop = TRUE, lex.order = TRUE))
  )
  center_function <- if (tolower(center_name) == "mean") base::mean else stats::median
  result <- tryCatch(
    car::leveneTest(data$Y, group, center = center_function),
    error = function(e) e
  )
  if (inherits(result, "error")) {
    return(list(F = NA_real_, df1 = NA_real_, df2 = NA_real_, p = NA_real_, note = conditionMessage(result)))
  }
  result_frame <- as.data.frame(result, check.names = FALSE)
  f_column <- grep("F", names(result_frame), value = TRUE)[[1]]
  p_column <- grep("Pr", names(result_frame), value = TRUE)[[1]]
  list(
    F = as.numeric(result_frame[[f_column]][[1]]),
    df1 = as.numeric(result_frame$Df[[1]]),
    df2 = as.numeric(result_frame$Df[[nrow(result_frame)]]),
    p = as.numeric(result_frame[[p_column]][[1]]),
    note = paste0(tolower(center_name), "-centered Levene test")
  )
}

generate_effect_codes <- function(factor_codes, max_order) {
  factor_codes <- as.character(factor_codes)
  if (length(factor_codes) == 0L) return(character(0))
  max_order <- min(length(factor_codes), as.integer(max_order))
  unlist(lapply(seq_len(max_order), function(order) {
    combinations <- utils::combn(factor_codes, order, simplify = FALSE)
    vapply(combinations, paste, character(1), collapse = ":")
  }), use.names = FALSE)
}

factor_label <- function(code, factor_spec, short = FALSE) {
  row <- factor_spec[factor_spec$code == code, , drop = FALSE]
  if (nrow(row) == 0L) return(code)
  if (short) row$short_label[[1]] else row$label[[1]]
}

effect_label <- function(effect_code, factor_spec, short = FALSE) {
  codes <- strsplit(effect_code, ":", fixed = TRUE)[[1]]
  paste(vapply(codes, factor_label, character(1), factor_spec = factor_spec, short = short), collapse = " × ")
}

wrap_plot_title <- function(text, config, page = FALSE) {
  configured_width <- if (isTRUE(page)) {
    config$plots$page_title_wrap_width %||% 70L
  } else {
    config$plots$title_wrap_width %||% 58L
  }
  stringr::str_wrap(as.character(text), width = configured_width)
}

summarise_groups <- function(data, grouping_variables, outcome_label, category, effect_code, factor_spec) {
  data |>
    dplyr::group_by(dplyr::across(dplyr::all_of(grouping_variables))) |>
    dplyr::summarise(
      N = sum(!is.na(.data$Y)),
      N_Subjects = dplyr::n_distinct(.data$ID[!is.na(.data$Y)]),
      Mean = mean(.data$Y, na.rm = TRUE),
      SD = stats::sd(.data$Y, na.rm = TRUE),
      SE = .data$SD / sqrt(.data$N),
      Median = stats::median(.data$Y, na.rm = TRUE),
      IQR = stats::IQR(.data$Y, na.rm = TRUE),
      Min = min(.data$Y, na.rm = TRUE),
      Max = max(.data$Y, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      DV = outcome_label,
      Category = category,
      Effect_Code = effect_code,
      Effect_Label = effect_label(effect_code, factor_spec),
      .before = 1
    )
}


extract_anova_table <- function(model, outcome_label, category, factor_spec, anova_type, alpha) {
  table <- as.data.frame(car::Anova(model, type = anova_type), check.names = FALSE)
  table$Effect_Code <- rownames(table)
  rownames(table) <- NULL

  f_candidates <- grep("^F", names(table), value = TRUE)
  p_candidates <- grep("Pr", names(table), value = TRUE)
  ss_candidates <- grep("Sum Sq", names(table), value = TRUE)
  if (length(f_candidates) == 0L || length(p_candidates) == 0L || length(ss_candidates) == 0L) {
    stop(
      "Could not identify the F, p-value, or sum-of-squares columns in the car::Anova() table.",
      call. = FALSE
    )
  }

  f_column <- f_candidates[[1]]
  p_column <- p_candidates[[1]]
  ss_column <- ss_candidates[[1]]
  residual_df <- stats::df.residual(model)

  table |>
    dplyr::filter(.data$Effect_Code != "(Intercept)") |>
    dplyr::transmute(
      DV = outcome_label,
      Category = category,
      Model_Method = paste0("ANOVA (Type ", anova_type, ")"),
      Effect_Code = .data$Effect_Code,
      Effect_Label = vapply(.data$Effect_Code, effect_label, character(1), factor_spec = factor_spec),
      df1 = as.numeric(.data$Df),
      df2 = residual_df,
      Sum_Squares = as.numeric(.data[[ss_column]]),
      Mean_Square = .data$Sum_Squares / .data$df1,
      F_value = as.numeric(.data[[f_column]]),
      p_value = as.numeric(.data[[p_column]])
    ) |>
    dplyr::mutate(
      Partial_Eta2 = partial_eta2_from_f(.data$F_value, .data$df1, .data$df2),
      Cohens_f = cohens_f_from_eta2(.data$Partial_Eta2),
      Effect_Size_Magnitude = eta2_magnitude(.data$Partial_Eta2),
      Effect_Size_Scale = "raw response",
      Significance = p_to_label(.data$p_value),
      Significant = !is.na(.data$p_value) & .data$p_value < alpha
    )
}


extract_sphericity_tests <- function(
    model, outcome_label, category, factor_spec, correction, alpha) {
  correction_value <- toupper(correction %||% "GG")
  if (correction_value == "NONE") correction_value <- "NONE"

  unavailable_row <- function(decision, note) {
    tibble::tibble(
      DV = outcome_label,
      Category = category,
      Effect_Code = NA_character_,
      Effect_Label = NA_character_,
      Mauchly_W = NA_real_,
      Mauchly_p = NA_real_,
      Sphericity_Decision = decision,
      Uncorrected_p = NA_real_,
      GG_Epsilon = NA_real_,
      GG_Corrected_p = NA_real_,
      HF_Epsilon = NA_real_,
      HF_Corrected_p = NA_real_,
      Applied_Correction = correction_value,
      Applied_p = NA_real_,
      Note = note
    )
  }

  # afex documents summary(afex_aov) as the supported route for the complete
  # univariate repeated-measures output (uncorrected tests, Mauchly tests, and
  # GG/HF corrections). Use that public method first. The direct car::Anova
  # summary remains a fallback for compatibility with older/newer afex objects.
  summary_candidates <- list(
    tryCatch(summary(model), error = function(e) NULL),
    tryCatch(
      if (!is.null(model$Anova)) summary(model$Anova, multivariate = FALSE) else NULL,
      error = function(e) NULL
    )
  )

  normalize_key <- function(x) {
    x <- trimws(as.character(x))
    x <- gsub("`", "", x, fixed = TRUE)
    x <- gsub("\\s+", "", x, perl = TRUE)
    x <- gsub("\\*", ":", x, perl = TRUE)
    x <- gsub("^\\(|\\)$", "", x, perl = TRUE)
    tolower(x)
  }

  component_by_name <- function(object, candidates) {
    if (is.null(object) || !is.list(object) || is.null(names(object))) return(NULL)
    object_names <- names(object)
    norm_names <- gsub("[^a-z0-9]", "", tolower(object_names))
    for (candidate in candidates) {
      target <- gsub("[^a-z0-9]", "", tolower(candidate))
      hit <- which(norm_names == target)
      if (length(hit) > 0L) return(object[[hit[1L]]])
    }
    NULL
  }

  find_column <- function(data, exact = character(0), regex = character(0)) {
    if (is.null(data) || ncol(data) == 0L) return(NA_character_)
    nms <- names(data)
    for (candidate in exact) {
      hit <- which(tolower(nms) == tolower(candidate))
      if (length(hit) > 0L) return(nms[hit[1L]])
    }
    for (pattern in regex) {
      hit <- grep(pattern, nms, ignore.case = TRUE, perl = TRUE)
      if (length(hit) > 0L) return(nms[hit[1L]])
    }
    NA_character_
  }

  extract_tables <- function(summary_object) {
    if (is.null(summary_object)) return(NULL)
    list(
      sphericity = component_by_name(
        summary_object,
        c("sphericity.tests", "sphericity_tests", "Mauchly Tests for Sphericity")
      ),
      adjustments = component_by_name(
        summary_object,
        c("pval.adjustments", "pval_adjustments", "sphericity.corrections")
      ),
      univariate = component_by_name(
        summary_object,
        c("univariate.tests", "univariate_tests")
      )
    )
  }

  # The afex summary and the underlying car::Anova summary are allowed to
  # expose different subsets of the repeated-measures diagnostics. Do not stop
  # at the first summary object that contains *any* useful table: doing so can
  # retain GG/HF adjustments while silently missing the Mauchly table. Instead,
  # merge the three components independently, preferring the public afex summary
  # and filling only missing components from the direct car fallback.
  extracted <- list(sphericity = NULL, adjustments = NULL, univariate = NULL)
  for (candidate in summary_candidates) {
    tables <- extract_tables(candidate)
    if (is.null(tables)) next
    if ((is.null(extracted$sphericity) || NROW(extracted$sphericity) == 0L) &&
        !is.null(tables$sphericity) && NROW(tables$sphericity) > 0L) {
      extracted$sphericity <- tables$sphericity
    }
    if ((is.null(extracted$adjustments) || NROW(extracted$adjustments) == 0L) &&
        !is.null(tables$adjustments) && NROW(tables$adjustments) > 0L) {
      extracted$adjustments <- tables$adjustments
    }
    if ((is.null(extracted$univariate) || NROW(extracted$univariate) == 0L) &&
        !is.null(tables$univariate) && NROW(tables$univariate) > 0L) {
      extracted$univariate <- tables$univariate
    }
  }

  has_any_extracted <-
    (!is.null(extracted$sphericity) && NROW(extracted$sphericity) > 0L) ||
    (!is.null(extracted$adjustments) && NROW(extracted$adjustments) > 0L) ||
    (!is.null(extracted$univariate) && NROW(extracted$univariate) > 0L)

  if (!has_any_extracted) {
    return(unavailable_row(
      "Not required",
      paste0(
        "No non-trivial repeated-measures sphericity table was returned by afex/car. ",
        "This is expected when all within-subject effects have two levels; otherwise ",
        "the model or package-version-specific summary should be inspected."
      )
    ))
  }

  to_effect_frame <- function(x) {
    if (is.null(x) || NROW(x) == 0L) {
      return(data.frame(Effect_Raw = character(0), Effect_Key = character(0), check.names = FALSE))
    }
    out <- as.data.frame(x, check.names = FALSE, stringsAsFactors = FALSE)
    raw <- rownames(out)

    # as.data.frame() assigns automatic row names "1", "2", ... when the
    # source component has no meaningful row names. Those are row identifiers,
    # not statistical effect names. Treat them as missing and prefer an
    # explicit effect/term column when one is available.
    automatic_row_names <- !is.null(raw) &&
      length(raw) == nrow(out) &&
      identical(as.character(raw), as.character(seq_len(nrow(out))))

    if (is.null(raw) || length(raw) != nrow(out) || all(!nzchar(raw)) || automatic_row_names) {
      effect_col <- find_column(out, exact = c("Effect", "Term", "Effect_Code"))
      raw <- if (!is.na(effect_col)) as.character(out[[effect_col]]) else rep(NA_character_, nrow(out))
    }
    out$Effect_Raw <- as.character(raw)
    out$Effect_Key <- normalize_key(out$Effect_Raw)
    rownames(out) <- NULL
    out
  }

  sph <- to_effect_frame(extracted$sphericity)
  adj <- to_effect_frame(extracted$adjustments)
  uni <- to_effect_frame(extracted$univariate)

  # The p-value adjustment table can legitimately exist even in package versions
  # where the Mauchly table is omitted for a particular effect. Build the result
  # from the union of effect keys, but remove the intercept/error-only rows.
  effect_rows <- dplyr::bind_rows(
    if (nrow(sph) > 0L) tibble::tibble(Effect_Key = sph$Effect_Key, Effect_Raw = sph$Effect_Raw) else NULL,
    if (nrow(adj) > 0L) tibble::tibble(Effect_Key = adj$Effect_Key, Effect_Raw = adj$Effect_Raw) else NULL,
    if (nrow(uni) > 0L) tibble::tibble(Effect_Key = uni$Effect_Key, Effect_Raw = uni$Effect_Raw) else NULL
  ) |>
    dplyr::filter(
      !is.na(.data$Effect_Key), nzchar(.data$Effect_Key),
      !grepl("intercept|residual|error", .data$Effect_Key, ignore.case = TRUE)
    ) |>
    dplyr::distinct(.data$Effect_Key, .keep_all = TRUE)

  if (nrow(effect_rows) == 0L) {
    return(unavailable_row(
      "Not required",
      "No non-trivial within-subject effect requiring a sphericity diagnostic was returned."
    ))
  }

  result <- tibble::tibble(
    Effect_Key = effect_rows$Effect_Key,
    Effect_Code = effect_rows$Effect_Raw,
    Mauchly_W = NA_real_, Mauchly_p = NA_real_,
    Uncorrected_p = NA_real_,
    GG_Epsilon = NA_real_, GG_Corrected_p = NA_real_,
    HF_Epsilon = NA_real_, HF_Corrected_p = NA_real_
  )

  if (nrow(sph) > 0L) {
    w_col <- find_column(
      sph,
      exact = c("Test statistic", "W"),
      regex = c("test.*stat", "mauchly.*w", "^w$")
    )
    p_col <- find_column(
      sph,
      exact = c("p-value", "p.value", "Pr(>Chi)"),
      regex = c("^p[-._ ]?value$", "^p$", "pr\\(>")
    )

    # car currently names the two Mauchly columns "Test statistic" and
    # "p-value". Keep a positional numeric fallback because older/newer
    # package versions may attach different labels to the same two-column
    # table. The fallback is used only when name matching fails.
    sph_data_columns <- setdiff(names(sph), c("Effect_Raw", "Effect_Key"))
    sph_numeric_columns <- sph_data_columns[vapply(
      sph[sph_data_columns],
      function(x) any(is.finite(suppressWarnings(as.numeric(as.character(x))))),
      logical(1)
    )]
    if (is.na(w_col) && length(sph_numeric_columns) >= 1L) {
      w_col <- sph_numeric_columns[[1L]]
    }
    if (is.na(p_col)) {
      remaining_numeric <- setdiff(sph_numeric_columns, w_col)
      if (length(remaining_numeric) >= 1L) p_col <- remaining_numeric[[1L]]
    }

    sph_values <- tibble::tibble(
      Effect_Key = sph$Effect_Key,
      Mauchly_W_sph = if (!is.na(w_col)) suppressWarnings(as.numeric(sph[[w_col]])) else NA_real_,
      Mauchly_p_sph = if (!is.na(p_col)) suppressWarnings(as.numeric(sph[[p_col]])) else NA_real_
    )
    result <- result |>
      dplyr::left_join(sph_values, by = "Effect_Key") |>
      dplyr::mutate(
        Mauchly_W = dplyr::coalesce(.data$Mauchly_W_sph, .data$Mauchly_W),
        Mauchly_p = dplyr::coalesce(.data$Mauchly_p_sph, .data$Mauchly_p)
      ) |>
      dplyr::select(-dplyr::any_of(c("Mauchly_W_sph", "Mauchly_p_sph")))
  }

  # Final Mauchly fallback: if the public afex/car summaries did not yield a
  # finite test for a non-trivial repeated-measures effect, recover the same
  # quantities directly from the underlying car::Anova repeated-measures
  # object. car stores the error SSP matrix (SSPE), within-effect projection
  # matrix (P), residual df, and singularity flag for every effect. The
  # calculation below follows the same equations used by car's
  # summary.Anova.mlm() and is therefore a diagnostic-extraction fallback, not
  # a different statistical test.
  if (any(!is.finite(result$Mauchly_W) | !is.finite(result$Mauchly_p))) {
    anova_object <- tryCatch(model$Anova, error = function(e) NULL)
    can_recover_mauchly <- !is.null(anova_object) &&
      isTRUE(anova_object$repeated) &&
      !is.null(anova_object$SSPE) && !is.null(anova_object$P) &&
      !is.null(anova_object$error.df) && !is.null(anova_object$terms)

    if (can_recover_mauchly) {
      singular_flags <- anova_object$singular
      if (is.null(singular_flags)) singular_flags <- rep(FALSE, length(anova_object$terms))

      recovered_rows <- lapply(seq_along(anova_object$terms), function(i) {
        if (isTRUE(singular_flags[[i]])) return(NULL)
        sspe_i <- tryCatch(anova_object$SSPE[[i]], error = function(e) NULL)
        p_i <- tryCatch(anova_object$P[[i]], error = function(e) NULL)
        if (is.null(sspe_i) || is.null(p_i) || NROW(sspe_i) < 2L) return(NULL)

        values <- tryCatch({
          psi <- crossprod(p_i)
          u <- solve(psi, sspe_i)
          pp <- nrow(sspe_i)
          p_dim <- nrow(p_i)
          n_df <- as.numeric(anova_object$error.df)
          trace_u <- sum(diag(u))
          det_u <- determinant(u, logarithm = TRUE)
          if (!isTRUE(det_u$sign > 0) || !is.finite(trace_u) || trace_u <= 0 ||
              !is.finite(n_df) || n_df <= 0) {
            return(NULL)
          }
          log_w <- as.numeric(det_u$modulus) - pp * log(trace_u / pp)
          rho <- 1 - (2 * pp^2 + pp + 2) / (6 * pp * n_df)
          w2 <- (pp + 2) * (pp - 1) * (pp - 2) *
            (2 * pp^3 + 6 * pp^2 + 3 * p_dim + 2) /
            (288 * (n_df * pp * rho)^2)
          z_value <- -n_df * rho * log_w
          chi_df <- pp * (pp + 1) / 2 - 1
          p1 <- stats::pchisq(z_value, chi_df, lower.tail = FALSE)
          p2 <- stats::pchisq(z_value, chi_df + 4, lower.tail = FALSE)
          p_value <- p1 + w2 * (p2 - p1)
          c(W = exp(log_w), p = p_value)
        }, error = function(e) NULL)

        if (is.null(values) || !all(is.finite(values))) return(NULL)
        tibble::tibble(
          Effect_Key = normalize_key(anova_object$terms[[i]]),
          Mauchly_W_recovered = unname(values[["W"]]),
          Mauchly_p_recovered = unname(values[["p"]])
        )
      })
      recovered <- dplyr::bind_rows(recovered_rows)

      if (nrow(recovered) > 0L) {
        result <- result |>
          dplyr::left_join(recovered, by = "Effect_Key") |>
          dplyr::mutate(
            Mauchly_W = dplyr::if_else(
              is.finite(.data$Mauchly_W), .data$Mauchly_W, .data$Mauchly_W_recovered
            ),
            Mauchly_p = dplyr::if_else(
              is.finite(.data$Mauchly_p), .data$Mauchly_p, .data$Mauchly_p_recovered
            )
          ) |>
          dplyr::select(-dplyr::any_of(c("Mauchly_W_recovered", "Mauchly_p_recovered")))
      }
    }
  }

  if (nrow(adj) > 0L) {
    gg_eps_col <- find_column(adj, exact = c("GG eps"), regex = c("GG.*eps", "Greenhouse.*eps"))
    gg_p_col <- find_column(adj, exact = c("Pr(>F[GG])"), regex = c("Pr.*GG", "GG.*p"))
    hf_eps_col <- find_column(adj, exact = c("HF eps"), regex = c("HF.*eps", "Huynh.*eps"))
    hf_p_col <- find_column(adj, exact = c("Pr(>F[HF])"), regex = c("Pr.*HF", "HF.*p"))
    adj_values <- tibble::tibble(
      Effect_Key = adj$Effect_Key,
      GG_Epsilon_adj = if (!is.na(gg_eps_col)) suppressWarnings(as.numeric(adj[[gg_eps_col]])) else NA_real_,
      GG_Corrected_p_adj = if (!is.na(gg_p_col)) suppressWarnings(as.numeric(adj[[gg_p_col]])) else NA_real_,
      HF_Epsilon_adj = if (!is.na(hf_eps_col)) suppressWarnings(as.numeric(adj[[hf_eps_col]])) else NA_real_,
      HF_Corrected_p_adj = if (!is.na(hf_p_col)) suppressWarnings(as.numeric(adj[[hf_p_col]])) else NA_real_
    )
    result <- result |>
      dplyr::left_join(adj_values, by = "Effect_Key") |>
      dplyr::mutate(
        GG_Epsilon = dplyr::coalesce(.data$GG_Epsilon_adj, .data$GG_Epsilon),
        GG_Corrected_p = dplyr::coalesce(.data$GG_Corrected_p_adj, .data$GG_Corrected_p),
        HF_Epsilon = dplyr::coalesce(.data$HF_Epsilon_adj, .data$HF_Epsilon),
        HF_Corrected_p = dplyr::coalesce(.data$HF_Corrected_p_adj, .data$HF_Corrected_p)
      ) |>
      dplyr::select(-dplyr::any_of(c(
        "GG_Epsilon_adj", "GG_Corrected_p_adj",
        "HF_Epsilon_adj", "HF_Corrected_p_adj"
      )))
  }

  if (nrow(uni) > 0L) {
    p_col <- find_column(uni, exact = c("Pr(>F)"), regex = c("^Pr\\(>F\\)$", "^p[-._ ]?value$"))
    if (!is.na(p_col)) {
      uni_values <- tibble::tibble(
        Effect_Key = uni$Effect_Key,
        Uncorrected_p_uni = suppressWarnings(as.numeric(uni[[p_col]]))
      )
      result <- result |>
        dplyr::left_join(uni_values, by = "Effect_Key") |>
        dplyr::mutate(Uncorrected_p = dplyr::coalesce(.data$Uncorrected_p_uni, .data$Uncorrected_p)) |>
        dplyr::select(-dplyr::any_of("Uncorrected_p_uni"))
    }
  }

  # Map car/afex effect labels back onto configured factor codes. Match both the
  # internal codes (F1:F2) and configured labels/source columns after normalization.
  configured_codes <- generate_effect_codes(factor_spec$code, length(factor_spec$code))
  effect_aliases <- lapply(configured_codes, function(code) {
    parts <- strsplit(code, ":", fixed = TRUE)[[1]]
    idx <- match(parts, factor_spec$code)
    labels <- factor_spec$label[idx]
    sources <- factor_spec$column[idx]
    shorts <- factor_spec$short_label[idx]
    unique(normalize_key(c(
      code,
      paste(labels, collapse = ":"),
      paste(sources, collapse = ":"),
      paste(shorts, collapse = ":")
    )))
  })
  names(effect_aliases) <- configured_codes

  mapped_code <- vapply(result$Effect_Key, function(key) {
    hits <- names(effect_aliases)[vapply(effect_aliases, function(x) key %in% x, logical(1))]
    if (length(hits) > 0L) hits[1L] else NA_character_
  }, character(1))

  # Only configured factorial effects are allowed into the exported
  # Sphericity_Tests table. This is a second defensive layer against
  # package-version-specific summary structures: even if a helper table
  # contributes an unexpected row identifier, it cannot leak into
  # Effect_Code/Effect_Label as values such as "1", "2", "3", ....
  unmapped_raw <- as.character(result$Effect_Code[is.na(mapped_code)])
  meaningful_unmapped <- unique(unmapped_raw[
    !is.na(unmapped_raw) & nzchar(trimws(unmapped_raw)) &
      !grepl("^\\d+$", trimws(unmapped_raw))
  ])
  if (length(meaningful_unmapped) > 0L) {
    warning(
      paste0(
        "Some repeated-measures sphericity summary rows could not be mapped to configured factorial effects and were excluded: ",
        paste(meaningful_unmapped, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  keep_mapped <- !is.na(mapped_code)
  result <- result[keep_mapped, , drop = FALSE]
  mapped_code <- mapped_code[keep_mapped]

  if (nrow(result) == 0L) {
    return(unavailable_row(
      "Unavailable / not required",
      paste0(
        "Repeated-measures sphericity summary components were returned, but no rows could be mapped ",
        "to the configured factorial effects."
      )
    ))
  }

  result$Effect_Code <- mapped_code

  result |>
    dplyr::mutate(
      DV = outcome_label,
      Category = category,
      Effect_Label = vapply(
        .data$Effect_Code,
        function(x) if (is.na(x) || !nzchar(x)) NA_character_ else effect_label(x, factor_spec),
        character(1)
      ),
      Sphericity_Decision = dplyr::case_when(
        is.na(.data$Mauchly_p) ~ "Unavailable / not required",
        .data$Mauchly_p >= alpha ~ "Sphericity not rejected",
        TRUE ~ "Sphericity rejected"
      ),
      Applied_Correction = correction_value,
      Applied_p = dplyr::case_when(
        correction_value == "GG" ~ .data$GG_Corrected_p,
        correction_value == "HF" ~ .data$HF_Corrected_p,
        TRUE ~ .data$Uncorrected_p
      ),
      Note = paste0(
        "Mauchly's test and GG/HF corrections were extracted from the supported afex repeated-measures summary, ",
        "with a direct car::Anova summary used only as a compatibility fallback. ",
        "Mauchly is non-trivial only for within-subject effects with more than two levels."
      )
    ) |>
    dplyr::select(dplyr::all_of(c(
      "DV", "Category", "Effect_Code", "Effect_Label",
      "Mauchly_W", "Mauchly_p", "Sphericity_Decision",
      "Uncorrected_p", "GG_Epsilon", "GG_Corrected_p",
      "HF_Epsilon", "HF_Corrected_p",
      "Applied_Correction", "Applied_p", "Note"
    )))
}


extract_art_table <- function(model, outcome_label, category, factor_spec, alpha, anova_type = 3L) {
  table <- as.data.frame(
    stats::anova(model, type = as.integer(anova_type), test = "F"),
    check.names = FALSE
  )
  effect_codes <- if ("Term" %in% names(table)) as.character(table$Term) else rownames(table)

  f_candidates <- intersect(c("F", "F value", "F.value"), names(table))
  if (length(f_candidates) == 0L) f_candidates <- grep("^F", names(table), value = TRUE)
  p_candidates <- grep("Pr", names(table), value = TRUE)
  df1_candidates <- intersect(c("Df", "df"), names(table))
  df2_candidates <- intersect(c("Df.res", "Df.residual", "df.res"), names(table))

  if (length(f_candidates) == 0L || length(p_candidates) == 0L ||
      length(df1_candidates) == 0L || length(df2_candidates) == 0L) {
    stop(
      "Could not identify the F, p-value, or degrees-of-freedom columns in the ART ANOVA table.",
      call. = FALSE
    )
  }

  tibble::tibble(
    DV = outcome_label,
    Category = category,
    Model_Method = paste0("ART-ANOVA (Type ", anova_type, ")"),
    Effect_Code = effect_codes,
    Effect_Label = vapply(effect_codes, effect_label, character(1), factor_spec = factor_spec),
    df1 = as.numeric(table[[df1_candidates[[1]]]]),
    df2 = as.numeric(table[[df2_candidates[[1]]]]),
    Sum_Squares = NA_real_,
    Mean_Square = NA_real_,
    F_value = as.numeric(table[[f_candidates[[1]]]]),
    p_value = as.numeric(table[[p_candidates[[1]]]])
  ) |>
    dplyr::mutate(
      Partial_Eta2 = partial_eta2_from_f(.data$F_value, .data$df1, .data$df2),
      Cohens_f = cohens_f_from_eta2(.data$Partial_Eta2),
      Effect_Size_Magnitude = eta2_magnitude(.data$Partial_Eta2),
      Effect_Size_Scale = "aligned-rank response",
      Significance = p_to_label(.data$p_value),
      Significant = !is.na(.data$p_value) & .data$p_value < alpha
    )
}

add_contrast_metadata <- function(result, outcome_label, category, method, effect_code, contrast_type, estimate_scale, factor_spec, p_adjust_method, alpha) {
  if (is.null(result) || nrow(result) == 0L) return(tibble::tibble())
  frame <- tibble::as_tibble(as.data.frame(result, check.names = FALSE))
  if ("p.value" %in% names(frame)) {
    frame$Significance <- p_to_label(frame$p.value)
    frame$Significant <- !is.na(frame$p.value) & frame$p.value < alpha
  }
  frame |>
    dplyr::mutate(
      DV = outcome_label,
      Category = category,
      Model_Method = method,
      Effect_Code = effect_code,
      Effect_Label = effect_label(effect_code, factor_spec),
      Contrast_Type = contrast_type,
      P_Adjustment = p_adjust_method,
      Estimate_Scale = estimate_scale,
      .before = 1
    )
}


parse_pairwise_groups <- function(frame, factor_levels = NULL) {
  if (nrow(frame) == 0L) {
    frame$Group1 <- character(0)
    frame$Group2 <- character(0)
    frame$Group_Parse_Method <- character(0)
    return(frame)
  }

  frame$Group1 <- NA_character_
  frame$Group2 <- NA_character_
  frame$Group_Parse_Method <- "unresolved"

  if (!"contrast" %in% names(frame)) return(frame)

  contrast_text <- as.character(frame$contrast)
  normalized_text <- stringr::str_squish(
    stringr::str_replace_all(contrast_text, "[\u2212\u2013\u2014]", "-")
  )

  if (!is.null(factor_levels)) {
    factor_levels <- as.character(factor_levels)
    expected_pairs <- if (length(factor_levels) >= 2L) {
      as.data.frame(t(utils::combn(factor_levels, 2L)), stringsAsFactors = FALSE)
    } else {
      data.frame(V1 = character(0), V2 = character(0))
    }

    # First match exact labels generated from configured levels. This is more
    # reliable than splitting on a dash when factor levels themselves contain
    # punctuation or when one level name is a substring of another.
    if (nrow(expected_pairs) > 0L) {
      for (row_index in seq_len(nrow(frame))) {
        current_text <- normalized_text[[row_index]]
        for (pair_index in seq_len(nrow(expected_pairs))) {
          first_level <- expected_pairs$V1[[pair_index]]
          second_level <- expected_pairs$V2[[pair_index]]
          forward_label <- stringr::str_squish(paste(first_level, "-", second_level))
          reverse_label <- stringr::str_squish(paste(second_level, "-", first_level))

          if (identical(current_text, forward_label)) {
            frame$Group1[[row_index]] <- first_level
            frame$Group2[[row_index]] <- second_level
            frame$Group_Parse_Method[[row_index]] <- "exact configured-pair label"
            break
          }
          if (identical(current_text, reverse_label)) {
            frame$Group1[[row_index]] <- second_level
            frame$Group2[[row_index]] <- first_level
            frame$Group_Parse_Method[[row_index]] <- "exact configured-pair label"
            break
          }
        }
      }
    }
  }

  unresolved <- is.na(frame$Group1) | is.na(frame$Group2)
  if (any(unresolved)) {
    pieces <- stringr::str_split_fixed(normalized_text[unresolved], "\\s+-\\s+", 2L)
    frame$Group1[unresolved] <- stringr::str_trim(pieces[, 1])
    frame$Group2[unresolved] <- stringr::str_trim(pieces[, 2])
    frame$Group_Parse_Method[unresolved] <- "normalized contrast text"
  }

  if (!is.null(factor_levels)) {
    valid_parse <- frame$Group1 %in% factor_levels & frame$Group2 %in% factor_levels

    # Standard pairwise output follows the combination order of the configured
    # levels. Use this deterministic fallback only when all possible pairwise
    # comparisons are present.
    if (any(!valid_parse) && nrow(frame) == nrow(expected_pairs)) {
      frame$Group1[!valid_parse] <- expected_pairs$V1[!valid_parse]
      frame$Group2[!valid_parse] <- expected_pairs$V2[!valid_parse]
      frame$Group_Parse_Method[!valid_parse] <- "configured-level order fallback"
    }
  }

  frame
}

make_stat_annotation <- function(effect_row) {
  if (is.null(effect_row) || nrow(effect_row) == 0L) return("Effect not available")

  # Build the annotation with R plotmath syntax instead of Unicode characters.
  # This prevents eta and the subscript p from becoming missing-glyph dots in
  # PDF devices whose default fonts do not contain those Unicode glyphs.
  df1_text <- format(round(effect_row$df1[[1]], 3), trim = TRUE)
  df2_text <- format(round(effect_row$df2[[1]], 3), trim = TRUE)
  f_text <- sprintf("%.3f", effect_row$F_value[[1]])
  eta_text <- sprintf("%.3f", effect_row$Partial_Eta2[[1]])
  significance_text <- p_to_label(effect_row$p_value[[1]])
  p_value <- effect_row$p_value[[1]]

  if (is.na(p_value)) {
    p_expression <- "italic(p)==plain(NA)"
  } else if (p_value < 0.001) {
    p_expression <- "italic(p)<.001"
  } else {
    p_expression <- paste0(
      "italic(p)==",
      sub("^0", "", sprintf("%.3f", p_value))
    )
  }

  annotation_text <- paste0(
    "italic(F)(", df1_text, ",", df2_text, ")==", f_text,
    "*','~~", p_expression,
    "*','~~eta[p]^2==", eta_text,
    "~~'", significance_text, "'"
  )

  parse(text = annotation_text)[[1]]
}

get_effect_row <- function(effect_table, effect_code) {
  effect_table |>
    dplyr::filter(.data$Effect_Code == effect_code) |>
    dplyr::slice_head(n = 1L)
}

add_significance_brackets <- function(plot_object, pairwise_frame, x_levels, raw_y, alpha) {
  if (is.null(pairwise_frame) || nrow(pairwise_frame) == 0L || !all(c("Group1", "Group2", "p.value") %in% names(pairwise_frame))) {
    return(plot_object)
  }

  significant <- pairwise_frame |>
    dplyr::mutate(
      Group1 = as.character(.data$Group1),
      Group2 = as.character(.data$Group2),
      p.value = suppressWarnings(as.numeric(.data$p.value))
    ) |>
    dplyr::filter(!is.na(.data$p.value), .data$p.value < alpha) |>
    dplyr::mutate(
      xmin = match(.data$Group1, as.character(x_levels)),
      xmax = match(.data$Group2, as.character(x_levels))
    ) |>
    dplyr::filter(!is.na(.data$xmin), !is.na(.data$xmax), .data$xmin != .data$xmax) |>
    dplyr::arrange(abs(.data$xmax - .data$xmin), .data$p.value)

  if (nrow(significant) == 0L) return(plot_object)
  y_values <- raw_y[is.finite(raw_y)]
  y_min <- min(y_values)
  y_max <- max(y_values)
  y_span <- y_max - y_min
  if (!is.finite(y_span) || y_span == 0) y_span <- max(abs(y_values), 1)

  significant <- significant |>
    dplyr::mutate(
      y_position = y_max + 0.10 * y_span + (dplyr::row_number() - 1L) * 0.11 * y_span,
      label = p_to_label(.data$p.value)
    )
  tick <- 0.025 * y_span

  plot_object +
    ggplot2::geom_segment(
      data = significant,
      ggplot2::aes(x = .data$xmin, xend = .data$xmax, y = .data$y_position, yend = .data$y_position),
      inherit.aes = FALSE,
      linewidth = 0.45
    ) +
    ggplot2::geom_segment(
      data = significant,
      ggplot2::aes(x = .data$xmin, xend = .data$xmin, y = .data$y_position, yend = .data$y_position - tick),
      inherit.aes = FALSE,
      linewidth = 0.45
    ) +
    ggplot2::geom_segment(
      data = significant,
      ggplot2::aes(x = .data$xmax, xend = .data$xmax, y = .data$y_position, yend = .data$y_position - tick),
      inherit.aes = FALSE,
      linewidth = 0.45
    ) +
    ggplot2::geom_text(
      data = significant,
      ggplot2::aes(x = (.data$xmin + .data$xmax) / 2, y = .data$y_position + 0.015 * y_span, label = .data$label),
      inherit.aes = FALSE,
      size = 4
    ) +
    ggplot2::expand_limits(y = max(significant$y_position) + 0.08 * y_span)
}


get_factor_colors <- function(factor_code, data, config) {
  factor_levels <- levels(data[[factor_code]])
  configured <- config$plots$factor_colors[[factor_code]]
  if (is.null(configured)) {
    configured <- grDevices::hcl.colors(length(factor_levels), palette = "Dark 3")
    names(configured) <- factor_levels
    return(configured)
  }
  configured <- as.character(configured)
  if (is.null(names(configured)) || any(!nzchar(names(configured)))) {
    if (length(configured) != length(factor_levels)) {
      stop("An unnamed factor color vector must have one color per factor level for ", factor_code, ".", call. = FALSE)
    }
    names(configured) <- factor_levels
  }
  missing_colors <- setdiff(factor_levels, names(configured))
  if (length(missing_colors) > 0L) {
    stop("Missing configured colors for factor ", factor_code, ": ", paste(missing_colors, collapse = ", "), call. = FALSE)
  }
  configured[factor_levels]
}

make_main_effect_plot <- function(data, factor_code, outcome_label, effect_row, pairwise_frame, config, factor_spec, p_adjust_method = NULL) {
  p_adjust_info <- p_adjustment_info(
    p_adjust_method %||% get_posthoc_p_adjust_method(config), default = "bonferroni"
  )
  summary_data <- data |>
    dplyr::group_by(.data[[factor_code]]) |>
    dplyr::summarise(
      N = sum(!is.na(.data$Y)),
      Mean = mean(.data$Y, na.rm = TRUE),
      SD = stats::sd(.data$Y, na.rm = TRUE),
      .groups = "drop"
    )

  error_amount <- if (tolower(config$plots$error_bar) == "se") summary_data$SD / sqrt(summary_data$N) else summary_data$SD
  summary_data$Error <- error_amount

  factor_colors <- get_factor_colors(factor_code, data, config)

  total_pairwise <- if (is.null(pairwise_frame)) 0L else nrow(pairwise_frame)
  significant_pairwise <- if (
    total_pairwise == 0L || !"p.value" %in% names(pairwise_frame)
  ) {
    0L
  } else {
    sum(
      suppressWarnings(as.numeric(pairwise_frame$p.value)) < config$analysis$alpha,
      na.rm = TRUE
    )
  }
  pairwise_caption <- if (total_pairwise == 0L) {
    "Pairwise comparisons were unavailable; see 25_Warnings_Errors."
  } else {
    paste0(
      "Significant pairwise comparisons after ", p_adjust_info$display_label,
      " adjustment: ", significant_pairwise, "/", total_pairwise, "."
    )
  }

  plot_object <- ggplot2::ggplot(
    summary_data,
    ggplot2::aes(x = .data[[factor_code]], y = .data$Mean, fill = .data[[factor_code]], color = .data[[factor_code]])
  ) +
    ggplot2::geom_col(
      width = 0.64,
      alpha = config$plots$main_alpha %||% 0.65,
      linewidth = 0.35,
      show.legend = FALSE
    ) +
    ggplot2::geom_errorbar(
      ggplot2::aes(ymin = .data$Mean - .data$Error, ymax = .data$Mean + .data$Error),
      width = 0.14,
      linewidth = 0.55,
      color = "black",
      show.legend = FALSE
    ) +
    ggplot2::geom_point(size = 2.4, show.legend = FALSE) +
    ggplot2::scale_fill_manual(values = factor_colors, drop = FALSE) +
    ggplot2::scale_color_manual(values = factor_colors, drop = FALSE) +
    ggplot2::labs(
      title = wrap_plot_title(factor_label(factor_code, factor_spec), config),
      subtitle = make_stat_annotation(effect_row),
      x = factor_label(factor_code, factor_spec),
      y = paste0(outcome_label, " (Mean ± ", toupper(config$plots$error_bar %||% "SD"), ")"),
      caption = stringr::str_wrap(
        pairwise_caption,
        width = config$plots$caption_wrap_width %||% 58L
      )
    ) +
    ggplot2::theme_bw(base_size = config$plots$base_font_size %||% 11) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold"),
      plot.subtitle = ggplot2::element_text(size = config$plots$stat_font_size %||% 9.5),
      plot.caption = ggplot2::element_text(hjust = 0, size = 8.2, lineheight = 1.05),
      plot.margin = ggplot2::margin(12, 14, 12, 14, unit = "pt"),
      panel.grid.minor = ggplot2::element_blank(),
      legend.position = "none"
    )

  x_levels <- levels(data[[factor_code]])
  annotation_y_values <- c(
    data$Y,
    summary_data$Mean - summary_data$Error,
    summary_data$Mean + summary_data$Error
  )
  add_significance_brackets(
    plot_object,
    pairwise_frame,
    x_levels,
    annotation_y_values,
    config$analysis$alpha
  )
}

choose_two_way_mapping <- function(effect_codes, data) {
  first <- effect_codes[[1]]
  second <- effect_codes[[2]]
  first_levels <- nlevels(data[[first]])
  second_levels <- nlevels(data[[second]])
  if (first_levels <= second_levels) {
    list(x = first, legend = second)
  } else {
    list(x = second, legend = first)
  }
}

make_two_way_plot <- function(data, effect_code, outcome_label, effect_row, contrast_frame, config, factor_spec, p_adjust_method = NULL) {
  p_adjust_info <- p_adjustment_info(
    p_adjust_method %||% get_posthoc_p_adjust_method(config), default = "bonferroni"
  )
  codes <- strsplit(effect_code, ":", fixed = TRUE)[[1]]
  mapping <- choose_two_way_mapping(codes, data)
  x_code <- mapping$x
  legend_code <- mapping$legend

  summary_data <- data |>
    dplyr::group_by(dplyr::across(dplyr::all_of(c(x_code, legend_code)))) |>
    dplyr::summarise(
      N = sum(!is.na(.data$Y)),
      Mean = mean(.data$Y, na.rm = TRUE),
      SD = stats::sd(.data$Y, na.rm = TRUE),
      .groups = "drop"
    )
  summary_data$Error <- if (tolower(config$plots$error_bar) == "se") summary_data$SD / sqrt(summary_data$N) else summary_data$SD

  significant_contrasts <- if (is.null(contrast_frame) || nrow(contrast_frame) == 0L || !"p.value" %in% names(contrast_frame)) {
    0L
  } else {
    sum(contrast_frame$p.value < config$analysis$alpha, na.rm = TRUE)
  }
  total_contrasts <- if (is.null(contrast_frame)) 0L else nrow(contrast_frame)
  caption <- if (total_contrasts == 0L) {
    "Interaction contrasts were unavailable; see 25_Warnings_Errors."
  } else {
    stringr::str_wrap(
      paste0(
        "Significant interaction contrasts after ", p_adjust_info$display_label,
        " adjustment: ", significant_contrasts, "/", total_contrasts, "."
      ),
      width = config$plots$caption_wrap_width %||% 58L
    )
  }
  legend_colors <- get_factor_colors(legend_code, data, config)

  ggplot2::ggplot(
    summary_data,
    ggplot2::aes(
      x = .data[[x_code]],
      y = .data$Mean,
      color = .data[[legend_code]],
      shape = .data[[legend_code]],
      group = .data[[legend_code]]
    )
  ) +
    ggplot2::geom_line(linewidth = 0.85, alpha = config$plots$interaction_alpha %||% 1) +
    ggplot2::geom_point(size = 2.8, alpha = config$plots$interaction_alpha %||% 1) +
    ggplot2::geom_errorbar(
      ggplot2::aes(ymin = .data$Mean - .data$Error, ymax = .data$Mean + .data$Error),
      width = 0.10,
      linewidth = 0.50,
      alpha = config$plots$interaction_alpha %||% 1
    ) +
    ggplot2::scale_color_manual(values = legend_colors, drop = FALSE) +
    ggplot2::labs(
      title = wrap_plot_title(effect_label(effect_code, factor_spec, short = TRUE), config),
      subtitle = make_stat_annotation(effect_row),
      x = factor_label(x_code, factor_spec),
      y = paste0(outcome_label, " (Mean ± ", toupper(config$plots$error_bar %||% "SD"), ")"),
      color = factor_label(legend_code, factor_spec),
      shape = factor_label(legend_code, factor_spec),
      caption = caption
    ) +
    ggplot2::guides(
      color = ggplot2::guide_legend(
        title.position = "top",
        title.hjust = 0.5,
        nrow = 1,
        byrow = TRUE
      ),
      shape = ggplot2::guide_legend(
        title.position = "top",
        title.hjust = 0.5,
        nrow = 1,
        byrow = TRUE
      )
    ) +
    ggplot2::theme_bw(base_size = config$plots$base_font_size %||% 11) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold"),
      plot.subtitle = ggplot2::element_text(size = config$plots$stat_font_size %||% 9.5),
      plot.caption = ggplot2::element_text(hjust = 0, size = 8.2, lineheight = 1.05),
      plot.margin = ggplot2::margin(14, 10, 12, 10, unit = "pt"),
      legend.position = "top",
      legend.direction = "horizontal",
      legend.box = "vertical",
      legend.title = ggplot2::element_text(hjust = 0.5, margin = ggplot2::margin(b = 2, unit = "pt")),
      panel.grid.minor = ggplot2::element_blank()
    )
}

make_three_way_plot <- function(data, effect_code, outcome_label, effect_row, contrast_frame, config, factor_spec, p_adjust_method = NULL) {
  p_adjust_info <- p_adjustment_info(
    p_adjust_method %||% get_posthoc_p_adjust_method(config), default = "bonferroni"
  )
  codes <- strsplit(effect_code, ":", fixed = TRUE)[[1]]
  mapping <- config$plots$three_way_mapping
  x_code <- mapping$x %||% codes[[1]]
  color_code <- mapping$color %||% codes[[2]]
  facet_code <- mapping$facet %||% codes[[3]]
  if (!all(c(x_code, color_code, facet_code) %in% codes)) {
    stop("plots$three_way_mapping must use the enabled three-way factor codes.", call. = FALSE)
  }

  summary_data <- data |>
    dplyr::group_by(dplyr::across(dplyr::all_of(c(x_code, color_code, facet_code)))) |>
    dplyr::summarise(
      N = sum(!is.na(.data$Y)),
      Mean = mean(.data$Y, na.rm = TRUE),
      SD = stats::sd(.data$Y, na.rm = TRUE),
      .groups = "drop"
    )
  summary_data$Error <- if (tolower(config$plots$error_bar) == "se") summary_data$SD / sqrt(summary_data$N) else summary_data$SD

  significant_contrasts <- if (is.null(contrast_frame) || nrow(contrast_frame) == 0L || !"p.value" %in% names(contrast_frame)) {
    0L
  } else {
    sum(contrast_frame$p.value < config$analysis$alpha, na.rm = TRUE)
  }
  total_contrasts <- if (is.null(contrast_frame)) 0L else nrow(contrast_frame)
  caption <- if (total_contrasts == 0L) {
    "Three-way interaction contrasts were unavailable; see 25_Warnings_Errors."
  } else {
    stringr::str_wrap(
      paste0(
        "Significant three-way interaction contrasts after ", p_adjust_info$display_label,
        " adjustment: ", significant_contrasts, "/", total_contrasts, "."
      ),
      width = config$plots$caption_wrap_width %||% 58L
    )
  }
  color_values <- get_factor_colors(color_code, data, config)

  ggplot2::ggplot(
    summary_data,
    ggplot2::aes(
      x = .data[[x_code]],
      y = .data$Mean,
      color = .data[[color_code]],
      shape = .data[[color_code]],
      group = .data[[color_code]]
    )
  ) +
    ggplot2::geom_line(linewidth = 0.85, alpha = config$plots$interaction_alpha %||% 1) +
    ggplot2::geom_point(size = 2.7, alpha = config$plots$interaction_alpha %||% 1) +
    ggplot2::geom_errorbar(
      ggplot2::aes(ymin = .data$Mean - .data$Error, ymax = .data$Mean + .data$Error),
      width = 0.10,
      linewidth = 0.50,
      alpha = config$plots$interaction_alpha %||% 1
    ) +

    ggplot2::facet_wrap(ggplot2::vars(!!rlang::sym(facet_code)), nrow = config$plots$three_way_facet_rows %||% 2L) +
    ggplot2::scale_color_manual(values = color_values, drop = FALSE) +
    ggplot2::labs(
      title = wrap_plot_title(effect_label(effect_code, factor_spec, short = TRUE), config),
      subtitle = make_stat_annotation(effect_row),
      x = factor_label(x_code, factor_spec),
      y = paste0(outcome_label, " (Mean ± ", toupper(config$plots$error_bar %||% "SD"), ")"),
      color = factor_label(color_code, factor_spec),
      shape = factor_label(color_code, factor_spec),
      caption = caption
    ) +
    ggplot2::guides(
      color = ggplot2::guide_legend(
        title.position = "top",
        title.hjust = 0.5,
        nrow = 1,
        byrow = TRUE
      ),
      shape = ggplot2::guide_legend(
        title.position = "top",
        title.hjust = 0.5,
        nrow = 1,
        byrow = TRUE
      )
    ) +
    ggplot2::theme_bw(base_size = config$plots$base_font_size %||% 11) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold"),
      plot.subtitle = ggplot2::element_text(size = config$plots$stat_font_size %||% 9.5),
      plot.caption = ggplot2::element_text(hjust = 0, size = 8.2, lineheight = 1.05),
      plot.margin = ggplot2::margin(14, 10, 12, 10, unit = "pt"),
      legend.position = "top",
      legend.direction = "horizontal",
      legend.box = "vertical",
      legend.title = ggplot2::element_text(hjust = 0.5, margin = ggplot2::margin(b = 2, unit = "pt")),
      panel.grid.minor = ggplot2::element_blank(),
      strip.text = ggplot2::element_text(face = "bold")
    )
}

column_description <- function(column_name, factor_codes = character(0), config = NULL, sheet_name = NULL) {
  logical_sheet <- if (!is.null(sheet_name)) sub("^[0-9]+_", "", as.character(sheet_name)) else ""
  adjustment_info <- NULL
  if (!is.null(config)) {
    if (logical_sheet %in% c("Main_Posthoc", "Interaction_Cells", "Interaction_Contrasts")) {
      adjustment_info <- get_posthoc_p_adjust_info(config)
    } else if (logical_sheet %in% c("Correlation_Results", "Correlation_Adj_p")) {
      adjustment_info <- get_correlation_p_adjust_info(config)
    }
  }
  if (!is.null(adjustment_info)) {
    if (identical(column_name, adjustment_info$adjusted_p_column)) {
      context_text <- if (startsWith(logical_sheet, "Correlation")) "correlation" else "post-hoc/contrast"
      return(paste0(
        context_text, " p value after ", adjustment_info$display_label, " adjustment."
      ))
    }
    if (identical(column_name, adjustment_info$significance_column)) {
      return(paste0(
        "Significance symbol based on the ", adjustment_info$display_label,
        "-adjusted p value: ***, **, *, ., or n.s."
      ))
    }
    if (identical(column_name, adjustment_info$significant_column)) {
      return(paste0(
        "TRUE when the ", adjustment_info$display_label,
        "-adjusted p value is below the configured alpha threshold."
      ))
    }
  }
  if (!is.null(adjustment_info) && identical(logical_sheet, "Correlation_Results") &&
      identical(column_name, "p_value")) {
    return(paste0(
      "Raw unadjusted correlation p value before ",
      adjustment_info$display_label, " multiplicity adjustment."
    ))
  }
  if (identical(column_name, "P_Adjustment_Method")) {
    return("P-value multiplicity-adjustment method actually applied to this output table.")
  }
  if (!is.null(adjustment_info) && identical(logical_sheet, "Correlation_Adj_p") &&
      !identical(column_name, "Variable")) {
    return(paste0(
      adjustment_info$display_label,
      "-adjusted correlation p values for the row variable versus ",
      column_name, "."
    ))
  }

  descriptions <- c(
    Item = "Run-information item.",
    Value = "Value or description associated with the run-information item.",
    DV = "Dependent-variable display name.",
    Category = "User-defined dependent-variable category used for organization only.",
    Source_Column = "Original column name in the input data.",
    Enabled = "Whether the dependent variable was enabled for analysis.",
    Factor_Code = "Internal syntactic factor code used in statistical formulas.",
    Factor_Role = "Design role of the factor: between-subjects or within-subjects.",
    Factor_Label = "Full factor label used in tables and axis labels.",
    Factor_Short_Label = "Short factor label used in compact interaction-plot titles.",
    Level_Order = "Configured order of factor levels.",
    Level = "Factor level stored in the input data.",
    N = "Number of non-missing observations.",
    N_Total = "Total number of rows in the prepared analysis data.",
    N_Subjects = "Number of unique participants represented in the analysis or design cell.",
    N_Subjects_Total = "Total number of unique participants in the prepared analysis data.",
    N_Subjects_With_Valid_Data = "Number of unique participants with at least one finite value for the dependent variable before outcome-specific repeated-cell completeness filtering.",
    N_Valid = "Number of valid observations included in the outcome analysis.",
    N_Missing = "Number of missing outcome observations.",
    Missing_Percent = "Percentage of missing outcome observations.",
    Empty_Cell = "TRUE when a configured design cell has zero observations.",
    Design_Type = "Configured design classification: between-subjects, within-subjects, or mixed.",
    Between_Factors = "Enabled between-subject factor codes.",
    Within_Factors = "Enabled within-subject factor codes.",
    Sphericity_Correction = "Sphericity correction requested for repeated-measures parametric ANOVA (GG, HF, or none).",
    Sphericity_Tests = "Number of Mauchly sphericity tests available for the dependent variable.",
    Sphericity_Violations = "Number of available Mauchly tests with p below the configured alpha level.",
    Minimum_Mauchly_p = "Smallest available Mauchly sphericity-test p value for the dependent variable.",
    Mauchly_W = "Mauchly test statistic for the repeated-measures effect.",
    Mauchly_p = "P value from Mauchly's test of sphericity.",
    Sphericity_Decision = "Decision from Mauchly's test at the configured alpha level.",
    Uncorrected_p = "Uncorrected univariate repeated-measures ANOVA p value assuming sphericity.",
    GG_Epsilon = "Greenhouse-Geisser epsilon estimate for departure from sphericity.",
    GG_Corrected_p = "Greenhouse-Geisser-corrected p value.",
    HF_Epsilon = "Huynh-Feldt epsilon estimate for departure from sphericity.",
    HF_Corrected_p = "Huynh-Feldt-corrected p value.",
    Applied_Correction = "Sphericity correction selected in the configuration for the final parametric repeated-measures ANOVA.",
    Applied_p = "P value corresponding to the configured sphericity correction.",
    Levene_Note = "Additional note describing how or why the Levene test was evaluated.",
    Error_MSE = "Mean squared error reported by the repeated-measures/mixed ANOVA table when available.",
    Data_Unit = "Unit of observation used by the correlation module; repeated designs use participant-level means.",
    Mean = "Arithmetic mean.",
    SD = "Sample standard deviation.",
    SE = "Standard error of the estimate or mean, as applicable.",
    std.error = "Standard error of the estimated contrast.",
    Median = "Sample median.",
    IQR = "Interquartile range.",
    Min = "Minimum observed value.",
    Max = "Maximum observed value.",
    Effect_Code = "Internal effect code; colon-separated codes indicate interactions.",
    Effect_Label = "Human-readable effect label.",
    Model_Method = "Statistical method selected for the dependent variable.",
    Formula = "Model formula fitted for the dependent variable.",
    Residual_df = "Residual degrees of freedom for the fitted model.",
    R_squared = "Coefficient of determination for the ordinary linear model.",
    Adjusted_R_squared = "R-squared adjusted for the number of model parameters.",
    ART_Max_Absolute_Aligned_Sum = "Maximum absolute column sum of ART aligned responses; values should be close to zero.",
    ART_Diagnostic_File = "Relative path to the saved ART diagnostic text file, when enabled.",
    df1 = "Numerator degrees of freedom.",
    df2 = "Denominator degrees of freedom.",
    df = "Degrees of freedom for a post-hoc contrast.",
    Sum_Squares = "Effect sum of squares; unavailable for some ART outputs.",
    Mean_Square = "Effect mean square.",
    F_value = "F statistic.",
    p_value = "Unadjusted omnibus p value.",
    p.value = "P value reported by the post-hoc contrast procedure.",
    Minimum_Omnibus_p = "Smallest omnibus p value for the dependent variable.",
    Partial_Eta2 = "Partial eta-squared effect-size estimate.",
    Cohens_f = "Cohen's f derived from partial eta-squared.",
    Effect_Size_Magnitude = "Qualitative effect-size magnitude.",
    Effect_Size_Scale = "Response scale on which the reported effect size is based.",
    Significance = "Significance label: ***, **, *, ., or n.s.",
    Significant = "TRUE when the corresponding p value is below alpha.",
    Residual_Shapiro_W = "Shapiro-Wilk W statistic for residual normality.",
    Shapiro_p = "P value from the Shapiro-Wilk residual-normality test.",
    Shapiro_Decision = "Decision from the residual-normality test at the configured alpha level.",
    Levene_F = "F statistic from the Levene variance-homogeneity test.",
    Levene_df1 = "Numerator degrees of freedom for the Levene test.",
    Levene_df2 = "Denominator degrees of freedom for the Levene test.",
    Levene_p = "P value from the Levene homogeneity-of-variance test.",
    Levene_Decision = "Decision from the variance-homogeneity test at the configured alpha level.",
    Selected_Method = "ANOVA or ART-ANOVA selected according to the configuration and assumption checks.",
    Selection_Reason = "Reason the reported analysis method was selected.",
    W = "Shapiro-Wilk W statistic for a design cell.",
    Decision = "Decision associated with the diagnostic test.",
    Note = "Additional diagnostic or output note.",
    Contrast_Type = "Type of post-hoc comparison or interaction contrast.",
    contrast = "Contrast label generated by emmeans or ARTool.",
    Group1 = "First configured factor level in a main-effect pairwise comparison.",
    Group2 = "Second configured factor level in a main-effect pairwise comparison.",
    Group_Parse_Method = "Method used to map the contrast label to configured factor levels for plot annotation.",
    Annotation_Eligible = "TRUE when the comparison can be mapped to the plot x-axis and annotated if significant.",
    estimate = "Estimated contrast on the scale stated in Estimate_Scale.",
    lower.CL = "Lower confidence limit for the estimated contrast.",
    upper.CL = "Upper confidence limit for the estimated contrast.",
    asymp.LCL = "Lower asymptotic confidence limit for the estimated contrast.",
    asymp.UCL = "Upper asymptotic confidence limit for the estimated contrast.",
    t.ratio = "T statistic for a post-hoc contrast.",
    z.ratio = "Z statistic for a post-hoc contrast.",
    null = "Null-hypothesis contrast value, usually zero.",
    P_Adjustment = "Internal multiple-comparison adjustment method before workbook-specific relabeling.",
    P_Adjustment_Method = "P-value multiplicity-adjustment method actually applied to the exported table.",
    Estimate_Scale = "Scale on which the contrast estimate is expressed.",
    Plot_Type = "Type of plots shown on the indexed PDF page.",
    PDF_File = "Name of the generated figures PDF.",
    PDF_Page = "Page number in the generated figures PDF.",
    Stage = "Analysis stage that produced the warning or error.",
    Type = "Warning or error classification.",
    Message = "Captured warning or error message.",
    N_Significant_Main_Effects = "Number of significant omnibus main effects for the dependent variable.",
    N_Significant_Interactions = "Number of significant omnibus interaction effects for the dependent variable.",
    Non_Numeric_Values_Converted_to_NA = "Count of non-missing source values that could not be converted to numeric values.",
    Non_Finite_Numeric_Values = "Count of numeric values equal to Inf, -Inf, or NaN.",
    Correlation_Enabled = "TRUE when the dependent variable is included in correlation analysis.",
    Variable_1 = "First dependent variable in the correlation pair.",
    Category_1 = "Category of the first dependent variable in the correlation pair.",
    Variable_2 = "Second dependent variable in the correlation pair.",
    Category_2 = "Category of the second dependent variable in the correlation pair.",
    N_Complete = "Number of rows with finite values for both variables in the correlation pair.",
    Variable_1_Unique = "Number of unique finite values for the first variable across all available finite observations.",
    Variable_2_Unique = "Number of unique finite values for the second variable across all available finite observations.",
    Variable_1_Shapiro_W = "Shapiro-Wilk W statistic for the first variable across all available finite observations.",
    Variable_1_Shapiro_p = "Shapiro-Wilk p value for the first variable across all available finite observations.",
    Variable_2_Shapiro_W = "Shapiro-Wilk W statistic for the second variable across all available finite observations.",
    Variable_2_Shapiro_p = "Shapiro-Wilk p value for the second variable across all available finite observations.",
    Normality_Alpha = "Alpha threshold used for Pearson-versus-Spearman automatic method selection.",
    Method = "Uniform correlation method selected for the complete analysis: Pearson or Spearman.",
    Method_Selection_Reason = "Reason one common Pearson or Spearman method was selected for all tested variable pairs.",
    Coefficient = "Pearson r or Spearman rho correlation coefficient.",
    Statistic_Name = "Name of the test statistic returned by cor.test().",
    Statistic = "Correlation-test statistic returned by cor.test().",
    Parameter = "Test degrees of freedom when supplied by cor.test(); unavailable for some methods.",
    p_adjusted = "Correlation p value after the configured multiplicity adjustment.",
    Variable = "Dependent variable included in the correlation analysis or row variable in a correlation matrix.",
    N_Finite = "Number of finite observations available for the variable-level correlation-method diagnostic.",
    N_Unique = "Number of unique finite values available for the variable-level correlation-method diagnostic.",
    Pearson_Eligible = "TRUE when the variable satisfies all configured requirements for global Pearson selection.",
    Eligibility_Reason = "Variable-level reason for passing or failing the Pearson eligibility rule.",
    Correlation_Method = "Single Pearson or Spearman method selected for the complete correlation analysis.",
    Correlation_Method_Selection_Reason = "Reason the same Pearson or Spearman method was selected for every tested variable pair."
  )

  if (column_name %in% names(descriptions)) return(descriptions[[column_name]])
  if (column_name %in% factor_codes) {
    return(paste0("Observed level of configured factor ", column_name, "."))
  }
  if (grepl("_pairwise$", column_name)) {
    factor_code <- sub("_pairwise$", "", column_name)
    return(paste0("Pairwise level contrast for configured factor ", factor_code, "."))
  }
  "Output field generated by the analysis procedure."
}

sheet_key <- function(sheet_name) {
  sub("^[0-9]+_", "", as.character(sheet_name))
}


prepare_adjustment_output_frame <- function(frame, sheet_name, config) {
  if (is.null(frame) || nrow(frame) == 0L) return(frame)
  frame <- as.data.frame(frame, check.names = FALSE, stringsAsFactors = FALSE)
  logical_sheet <- sheet_key(sheet_name)

  if (logical_sheet %in% c("Main_Posthoc", "Interaction_Cells", "Interaction_Contrasts")) {
    info <- get_posthoc_p_adjust_info(config)
    rename_map <- c(
      "p.value" = info$adjusted_p_column,
      "Significance" = info$significance_column,
      "Significant" = info$significant_column,
      "P_Adjustment" = "P_Adjustment_Method"
    )
    for (source_name in names(rename_map)) {
      if (source_name %in% names(frame)) names(frame)[names(frame) == source_name] <- rename_map[[source_name]]
    }
    if ("P_Adjustment_Method" %in% names(frame)) frame$P_Adjustment_Method <- info$display_label
  }

  if (identical(logical_sheet, "Correlation_Results")) {
    info <- get_correlation_p_adjust_info(config)
    rename_map <- c(
      "p_adjusted" = info$adjusted_p_column,
      "Significance" = info$significance_column,
      "Significant" = info$significant_column,
      "P_Adjustment" = "P_Adjustment_Method"
    )
    for (source_name in names(rename_map)) {
      if (source_name %in% names(frame)) names(frame)[names(frame) == source_name] <- rename_map[[source_name]]
    }
    if ("P_Adjustment_Method" %in% names(frame)) frame$P_Adjustment_Method <- info$display_label
  }

  frame
}

renumber_sheet_data <- function(sheet_data) {
  if (is.null(names(sheet_data)) || any(!nzchar(names(sheet_data)))) {
    stop("Every output worksheet entry must have a non-empty logical name.", call. = FALSE)
  }
  if (anyDuplicated(names(sheet_data))) {
    stop("Output worksheet logical names must be unique before numbering.", call. = FALSE)
  }
  names(sheet_data) <- paste0(
    sprintf("%02d", seq_along(sheet_data) - 1L),
    "_",
    names(sheet_data)
  )
  sheet_data
}

sheet_purpose <- function(sheet_name, config = NULL) {
  sheet_name <- sheet_key(sheet_name)

  if (!is.null(config)) {
    if (sheet_name %in% c("Main_Posthoc", "Interaction_Cells", "Interaction_Contrasts")) {
      info <- get_posthoc_p_adjust_info(config)
      return(paste0(
        if (sheet_name == "Main_Posthoc") "Pairwise comparisons for all enabled main effects" else if (sheet_name == "Interaction_Cells") "Pairwise comparisons among interaction-cell combinations" else "Difference-of-differences and higher-order interaction contrasts",
        ", using ", info$display_label, " p-value adjustment."
      ))
    }
    if (sheet_name == "Correlation_Results") {
      info <- get_correlation_p_adjust_info(config)
      return(paste0(
        "Correlation tests using one common Pearson or Spearman method; multiplicity is controlled with ",
        info$display_label, "."
      ))
    }
    if (sheet_name == "Correlation_Adj_p") {
      info <- get_correlation_p_adjust_info(config)
      return(paste0("Symmetric matrix of ", info$display_label, "-adjusted correlation p values."))
    }
  }

  purposes <- c(
    `Run_Info` = "Input, configuration, software, and output-path information.",
    `Analysis_Summary` = "One-row summary of method selection and significant effects for each dependent variable.",
    `Outcome_Spec` = "Enabled dependent variables analyzed by the script, with source columns and categories.",
    `Factor_Spec` = "Factor codes, between/within roles, source columns, labels, and configured levels.",
    `Design_Cell_Counts` = "Observation and unique-participant counts for every configured design cell, including empty cells.",
    `Missing_Summary` = "Missing-data counts for each dependent variable.",
    `Assumption_Tests` = "Design-specific assumption diagnostics and selected analysis method; irrelevant tests are omitted from the worksheet columns.",
    `Sphericity_Tests` = "Mauchly sphericity tests plus Greenhouse-Geisser and Huynh-Feldt corrections for repeated-measures ANOVA effects; present only for within/mixed designs.",
    `Cell_Shapiro` = "Optional Shapiro-Wilk diagnostics within design cells.",
    `Model_Summary` = "Model-level summary information and ART diagnostics.",
    `Omnibus_Effects` = "Omnibus main-effect and interaction tests with effect sizes.",
    `Significant_Effects` = "Subset of omnibus effects with p below alpha, retaining the configured outcome and effect order.",
    `Overall_Desc` = "Overall descriptive statistics for each dependent variable.",
    `Main_Desc` = "Descriptive statistics grouped by each main-effect factor.",
    `Interaction_Desc` = "Descriptive statistics grouped by each interaction combination.",
    `Main_Posthoc` = "Pairwise comparisons for all enabled main effects.",
    `Interaction_Cells` = "Pairwise comparisons among interaction-cell combinations.",
    `Interaction_Contrasts` = "Difference-of-differences and higher-order interaction contrasts.",
    `Plot_Index` = "Index of figure types and page numbers in the PDF.",
    `Warnings_Errors` = "Warnings and errors captured during analysis.",
    `Conversion_Report` = "Numeric-conversion checks for dependent-variable columns.",
    `Correlation_Results` = "Correlation tests using one automatically selected common Pearson or Spearman method, with normality diagnostics and adjusted p values.",
    `Correlation_Coeff` = "Symmetric matrix of coefficients calculated using the single method selected for the complete correlation analysis.",
    `Correlation_Methods` = "Symmetric matrix confirming the single Pearson or Spearman method used throughout the correlation analysis.",
    `Correlation_Adj_p` = "Symmetric matrix of multiplicity-adjusted correlation p values.",
    `Correlation_Normality` = "Variable-level normality diagnostics and the global Pearson-versus-Spearman method decision."
  )
  purposes[[sheet_name]] %||% "Analysis output table."
}

output_column_template <- function(sheet_name, factor_codes, config = NULL) {
  sheet_name <- sheet_key(sheet_name)
  factor_pairwise_columns <- paste0(factor_codes, "_pairwise")
  posthoc_info <- if (!is.null(config)) get_posthoc_p_adjust_info(config) else p_adjustment_info("bonferroni")
  correlation_info <- if (!is.null(config)) get_correlation_p_adjust_info(config) else p_adjustment_info("BH", default = "BH")
  contrast_statistics <- c(
    "contrast", "Group1", "Group2", "Group_Parse_Method", "Annotation_Eligible",
    "Estimate_Scale", "estimate", "SE", "std.error", "df", "lower.CL", "upper.CL",
    "asymp.LCL", "asymp.UCL", "t.ratio", "z.ratio", "null",
    posthoc_info$adjusted_p_column, "P_Adjustment_Method",
    posthoc_info$significance_column, posthoc_info$significant_column
  )

  templates <- list(
    `Run_Info` = c("Item", "Value"),
    `Analysis_Summary` = c(
      "DV", "Category", "Design_Type", "Selected_Method", "Selection_Reason",
      "N_Valid", "N_Subjects", "Shapiro_p", "Levene_p",
      "Sphericity_Correction", "Sphericity_Tests", "Sphericity_Violations",
      "Minimum_Mauchly_p", "N_Significant_Main_Effects",
      "N_Significant_Interactions", "Minimum_Omnibus_p"
    ),
    `Outcome_Spec` = c(
      "DV", "Category", "Source_Column", "Enabled", "Correlation_Enabled"
    ),
    `Factor_Spec` = c(
      "Factor_Code", "Factor_Label", "Factor_Short_Label", "Source_Column", "Factor_Role",
      "Level", "Level_Order"
    ),
    `Design_Cell_Counts` = c(factor_codes, "N", "N_Subjects", "Empty_Cell"),
    `Missing_Summary` = c(
      "DV", "Category", "N_Total", "N_Subjects_Total", "N_Valid",
      "N_Subjects_With_Valid_Data", "N_Missing", "Missing_Percent"
    ),
    `Assumption_Tests` = c(
      "DV", "Category", "Design_Type", "Between_Factors", "Within_Factors",
      "N_Valid", "N_Subjects", "Residual_Shapiro_W", "Shapiro_p",
      "Shapiro_Decision", "Levene_F", "Levene_df1", "Levene_df2",
      "Levene_p", "Levene_Decision", "Levene_Note", "Sphericity_Correction",
      "Selected_Method", "Selection_Reason"
    ),
    `Sphericity_Tests` = c(
      "DV", "Category", "Effect_Code", "Effect_Label", "Applied_Correction",
      "Mauchly_W", "Mauchly_p", "Sphericity_Decision", "Uncorrected_p",
      "GG_Epsilon", "GG_Corrected_p", "HF_Epsilon", "HF_Corrected_p",
      "Applied_p", "Note"
    ),
    `Cell_Shapiro` = c(
      "DV", "Category", factor_codes, "N", "W", "p_value", "Decision", "Note"
    ),
    `Model_Summary` = c(
      "DV", "Category", "Design_Type", "Model_Method", "Formula", "Sphericity_Correction",
      "N", "N_Subjects", "Residual_df", "R_squared", "Adjusted_R_squared",
      "ART_Max_Absolute_Aligned_Sum", "ART_Diagnostic_File"
    ),
    `Omnibus_Effects` = c(
      "DV", "Category", "Model_Method", "Effect_Code", "Effect_Label",
      "df1", "df2", "Sum_Squares", "Mean_Square", "F_value", "p_value",
      "Partial_Eta2", "Cohens_f", "Effect_Size_Magnitude", "Effect_Size_Scale", "Error_MSE",
      "Significance", "Significant"
    ),
    `Significant_Effects` = c(
      "DV", "Category", "Model_Method", "Effect_Code", "Effect_Label",
      "df1", "df2", "Sum_Squares", "Mean_Square", "F_value", "p_value",
      "Partial_Eta2", "Cohens_f", "Effect_Size_Magnitude", "Effect_Size_Scale", "Error_MSE",
      "Significance", "Significant"
    ),
    `Overall_Desc` = c(
      "DV", "Category", "N", "N_Subjects", "Mean", "SD", "SE", "Median", "IQR", "Min", "Max"
    ),
    `Main_Desc` = c(
      "DV", "Category", "Effect_Code", "Effect_Label", factor_codes,
      "N", "N_Subjects", "Mean", "SD", "SE", "Median", "IQR", "Min", "Max"
    ),
    `Interaction_Desc` = c(
      "DV", "Category", "Effect_Code", "Effect_Label", factor_codes,
      "N", "N_Subjects", "Mean", "SD", "SE", "Median", "IQR", "Min", "Max"
    ),
    `Main_Posthoc` = c(
      "DV", "Category", "Model_Method", "Effect_Code", "Effect_Label",
      "Contrast_Type", factor_codes, factor_pairwise_columns, contrast_statistics
    ),
    `Interaction_Cells` = c(
      "DV", "Category", "Model_Method", "Effect_Code", "Effect_Label",
      "Contrast_Type", factor_codes, factor_pairwise_columns, contrast_statistics
    ),
    `Interaction_Contrasts` = c(
      "DV", "Category", "Model_Method", "Effect_Code", "Effect_Label",
      "Contrast_Type", factor_codes, factor_pairwise_columns, contrast_statistics
    ),
    `Plot_Index` = c("DV", "Category", "Plot_Type", "PDF_File", "PDF_Page"),
    `Warnings_Errors` = c("DV", "Category", "Stage", "Type", "Message"),
    `Conversion_Report` = c(
      "DV", "Category", "Source_Column",
      "Non_Numeric_Values_Converted_to_NA", "Non_Finite_Numeric_Values"
    ),
    `Correlation_Results` = c(
      "Variable_1", "Category_1", "Variable_2", "Category_2",
      "Data_Unit", "Method", "Method_Selection_Reason", "N_Complete",
      "Variable_1_Unique", "Variable_2_Unique",
      "Variable_1_Shapiro_W", "Variable_1_Shapiro_p",
      "Variable_2_Shapiro_W", "Variable_2_Shapiro_p", "Normality_Alpha",
      "Coefficient", "Statistic_Name", "Statistic", "Parameter",
      "p_value", correlation_info$adjusted_p_column, "P_Adjustment_Method",
      correlation_info$significance_column, correlation_info$significant_column, "Note"
    ),
    `Correlation_Coeff` = c("Variable"),
    `Correlation_Methods` = c("Variable"),
    `Correlation_Adj_p` = c("Variable"),
    `Correlation_Normality` = c(
      "Variable", "Category", "Data_Unit", "N_Finite", "N_Unique",
      "Shapiro_W", "Shapiro_p", "Normality_Alpha", "Shapiro_Decision",
      "Pearson_Eligible", "Eligibility_Reason", "Correlation_Method",
      "Correlation_Method_Selection_Reason", "Note"
    )
  )

  unique(templates[[sheet_name]] %||% c("DV", "Category", factor_codes, factor_pairwise_columns))
}

standardize_output_frame <- function(frame, sheet_name, factor_codes, config = NULL) {
  if (is.null(frame) || nrow(frame) == 0L) {
    return(data.frame(Note = "No results were generated for this table.", check.names = FALSE))
  }

  frame <- as.data.frame(frame, check.names = FALSE)
  column_names <- names(frame)
  blank_columns <- which(is.na(column_names) | !nzchar(trimws(column_names)))
  if (length(blank_columns) > 0L) {
    column_names[blank_columns] <- paste0("Unnamed_Column_", blank_columns)
  }
  names(frame) <- make.unique(column_names, sep = "_")

  requested_order <- output_column_template(sheet_name, factor_codes, config = config)
  requested_order <- requested_order[requested_order %in% names(frame)]
  remaining_columns <- setdiff(names(frame), requested_order)

  # Keep any unexpected identifier/grouping fields ahead of statistical fields.
  # This prevents dynamically generated factor/variable columns from being
  # appended after F/p/effect-size columns when upstream package output changes.
  identifier_patterns <- c(
    "^DV$", "^Category", "^Variable(_[12])?$", "^Factor_", "^Source_Column$",
    "^Effect_", "^Contrast_", "^Group[12]$", "^Group_Parse_Method$",
    "^Annotation_Eligible$", "^Design_Type$", "^Between_Factors$", "^Within_Factors$",
    "^Model_Method$", "^Selected_Method$", "^Formula$", "^Data_Unit$", "^Method$",
    "^Method_Selection_Reason$", "^Selection_Reason$", "_pairwise$"
  )
  is_identifier_name <- function(column_name) {
    column_name %in% factor_codes ||
      any(vapply(identifier_patterns, grepl, logical(1), x = column_name))
  }
  statistic_patterns <- c(
    "^N($|_)", "^Mean$", "^SD$", "^SE$", "^Median$", "^IQR$", "^Min$", "^Max$",
    "Shapiro", "Levene", "Mauchly", "Epsilon", "(^|[_.])p($|[_.])", "^p_value$", "^p\\.value$",
    "^df", "^Residual_df$", "^F_value$", "^Sum_Squares$", "^Mean_Square$", "^Error_MSE$",
    "^estimate$", "^std\\.error$", "^lower\\.CL$", "^upper\\.CL$", "^asymp\\.",
    "^t\\.ratio$", "^z\\.ratio$", "^Coefficient$", "^Statistic", "^Parameter$",
    "^Partial_Eta2$", "^Cohens_f$", "^Effect_Size_", "^Minimum_", "^R_squared$",
    "^Adjusted_R_squared$", "^ART_Max_", "(^|_)Adjusted_p$", "^No_Adjustment_p$",
    "_Significance$", "_Significant$", "^Significance$", "^Significant$"
  )
  is_statistic_name <- function(column_name) {
    any(vapply(statistic_patterns, grepl, logical(1), x = column_name))
  }

  remaining_identifier_columns <- remaining_columns[
    vapply(remaining_columns, is_identifier_name, logical(1))
  ]
  remaining_other_columns <- setdiff(remaining_columns, remaining_identifier_columns)

  # Insert unexpected identifiers immediately before the first statistical
  # quantity in the template, rather than after the complete template.
  first_statistic <- which(vapply(requested_order, is_statistic_name, logical(1)))[1]
  if (length(remaining_identifier_columns) > 0L && !is.na(first_statistic)) {
    prefix <- if (first_statistic > 1L) requested_order[seq_len(first_statistic - 1L)] else character(0)
    suffix <- requested_order[first_statistic:length(requested_order)]
    final_order <- c(prefix, remaining_identifier_columns, suffix, remaining_other_columns)
  } else {
    final_order <- c(requested_order, remaining_identifier_columns, remaining_other_columns)
  }

  frame[unique(final_order)]
}

write_results_workbook <- function(sheet_data, output_file, alpha, factor_codes, config) {
  workbook <- openxlsx::createWorkbook(creator = "Reusable ANOVA / ART-ANOVA analysis")
  header_style <- openxlsx::createStyle(
    fontColour = "#FFFFFF", fgFill = "#1F4E78", textDecoration = "bold",
    halign = "center", valign = "center", border = "Bottom"
  )
  definition_title_style <- openxlsx::createStyle(
    fontColour = "#FFFFFF", fgFill = "#548235", textDecoration = "bold",
    halign = "left", valign = "center"
  )
  definition_purpose_style <- openxlsx::createStyle(
    fgFill = "#E2F0D9", fontColour = "#375623", textDecoration = "italic",
    wrapText = TRUE, valign = "top"
  )
  definition_header_style <- openxlsx::createStyle(
    fontColour = "#FFFFFF", fgFill = "#70AD47", textDecoration = "bold",
    halign = "center", valign = "center"
  )
  definition_body_style <- openxlsx::createStyle(
    wrapText = TRUE, valign = "top", border = "TopBottomLeftRight",
    borderColour = "#D9EAD3"
  )
  significant_style <- openxlsx::createStyle(fgFill = "#FFF2CC")
  p_style <- openxlsx::createStyle(numFmt = "0.000000")
  integer_style <- openxlsx::createStyle(numFmt = "0")
  number_style <- openxlsx::createStyle(numFmt = "0.000")

  integer_column_names <- c(
    "N", "N_Total", "N_Valid", "N_Missing", "N_Subjects", "N_Subjects_Total",
    "N_Subjects_With_Valid_Data", "Level_Order", "PDF_Page",
    "N_Significant_Main_Effects", "N_Significant_Interactions",
    "Sphericity_Tests", "Sphericity_Violations",
    "Non_Numeric_Values_Converted_to_NA", "Non_Finite_Numeric_Values",
    "N_Complete", "Variable_1_Unique", "Variable_2_Unique",
    "N_Finite", "N_Unique"
  )
  p_column_names <- c(
    "p_value", "p.value", "p_adjusted", "Shapiro_p", "Levene_p",
    "Minimum_Omnibus_p", "Minimum_Mauchly_p", "Mauchly_p", "Uncorrected_p",
    "GG_Corrected_p", "HF_Corrected_p", "Applied_p",
    "Variable_1_Shapiro_p", "Variable_2_Shapiro_p"
  )

  for (index in seq_along(sheet_data)) {
    sheet_name <- names(sheet_data)[[index]]
    frame <- prepare_adjustment_output_frame(sheet_data[[index]], sheet_name, config)
    frame <- standardize_output_frame(frame, sheet_name, factor_codes, config = config)

    openxlsx::addWorksheet(workbook, sheet_name, gridLines = FALSE)
    openxlsx::writeDataTable(
      workbook, sheet = sheet_name, x = frame,
      tableStyle = "TableStyleMedium2",
      tableName = paste0("tbl_", sprintf("%02d", index))
    )
    openxlsx::addStyle(
      workbook, sheet = sheet_name, style = header_style,
      rows = 1, cols = seq_len(ncol(frame)), gridExpand = TRUE, stack = TRUE
    )
    openxlsx::freezePane(workbook, sheet = sheet_name, firstRow = TRUE)

    widths <- vapply(seq_along(frame), function(column_index) {
      values <- c(names(frame)[[column_index]], as.character(frame[[column_index]]))
      values[is.na(values)] <- ""
      min(max(nchar(values, type = "width"), na.rm = TRUE) + 2, 38)
    }, numeric(1))
    openxlsx::setColWidths(
      workbook, sheet = sheet_name, cols = seq_len(ncol(frame)),
      widths = pmax(widths, 10)
    )

    p_columns <- which(
      names(frame) %in% p_column_names |
        grepl("(_Adjusted_p|No_Adjustment_p)$", names(frame))
    )
    if (identical(sheet_key(sheet_name), "Correlation_Adj_p")) {
      p_columns <- which(vapply(frame, is.numeric, logical(1)))
    }
    if (length(p_columns) > 0L && nrow(frame) > 0L) {
      openxlsx::addStyle(
        workbook, sheet = sheet_name, style = p_style,
        rows = 2:(nrow(frame) + 1L), cols = p_columns,
        gridExpand = TRUE, stack = TRUE
      )
      for (p_column in p_columns) {
        numeric_p <- suppressWarnings(as.numeric(as.character(frame[[p_column]])))
        significant_rows <- which(!is.na(numeric_p) & numeric_p < alpha) + 1L
        if (length(significant_rows) > 0L) {
          openxlsx::addStyle(
            workbook, sheet = sheet_name, style = significant_style,
            rows = significant_rows, cols = p_column,
            gridExpand = TRUE, stack = TRUE
          )
        }
      }
    }

    integer_columns <- which(names(frame) %in% integer_column_names & vapply(frame, is.numeric, logical(1)))
    if (length(integer_columns) > 0L && nrow(frame) > 0L) {
      openxlsx::addStyle(
        workbook, sheet = sheet_name, style = integer_style,
        rows = 2:(nrow(frame) + 1L), cols = integer_columns,
        gridExpand = TRUE, stack = TRUE
      )
    }

    numeric_columns <- setdiff(
      which(vapply(frame, is.numeric, logical(1))),
      union(p_columns, integer_columns)
    )
    if (length(numeric_columns) > 0L && nrow(frame) > 0L) {
      openxlsx::addStyle(
        workbook, sheet = sheet_name, style = number_style,
        rows = 2:(nrow(frame) + 1L), cols = numeric_columns,
        gridExpand = TRUE, stack = TRUE
      )
    }

    definition_start_column <- ncol(frame) + 3L
    definition_frame <- data.frame(
      Column = names(frame),
      Description = vapply(
        names(frame), column_description, character(1),
        factor_codes = factor_codes, config = config, sheet_name = sheet_name
      ),
      stringsAsFactors = FALSE
    )

    openxlsx::mergeCells(
      workbook, sheet = sheet_name,
      cols = definition_start_column:(definition_start_column + 1L), rows = 1
    )
    openxlsx::writeData(
      workbook, sheet_name, "Column Definitions",
      startRow = 1, startCol = definition_start_column, colNames = FALSE
    )
    openxlsx::addStyle(
      workbook, sheet = sheet_name, style = definition_title_style,
      rows = 1, cols = definition_start_column:(definition_start_column + 1L),
      gridExpand = TRUE, stack = TRUE
    )

    openxlsx::mergeCells(
      workbook, sheet = sheet_name,
      cols = definition_start_column:(definition_start_column + 1L), rows = 2
    )
    openxlsx::writeData(
      workbook, sheet_name, paste0("Sheet purpose: ", sheet_purpose(sheet_name, config = config)),
      startRow = 2, startCol = definition_start_column, colNames = FALSE
    )
    openxlsx::addStyle(
      workbook, sheet = sheet_name, style = definition_purpose_style,
      rows = 2, cols = definition_start_column:(definition_start_column + 1L),
      gridExpand = TRUE, stack = TRUE
    )

    openxlsx::writeDataTable(
      workbook, sheet = sheet_name, x = definition_frame,
      startRow = 4, startCol = definition_start_column,
      tableStyle = "TableStyleMedium4",
      tableName = paste0("def_", sprintf("%02d", index))
    )
    openxlsx::addStyle(
      workbook, sheet = sheet_name, style = definition_header_style,
      rows = 4, cols = definition_start_column:(definition_start_column + 1L),
      gridExpand = TRUE, stack = TRUE
    )
    if (nrow(definition_frame) > 0L) {
      openxlsx::addStyle(
        workbook, sheet = sheet_name, style = definition_body_style,
        rows = 5:(nrow(definition_frame) + 4L),
        cols = definition_start_column:(definition_start_column + 1L),
        gridExpand = TRUE, stack = TRUE
      )
      openxlsx::setRowHeights(
        workbook, sheet = sheet_name,
        rows = 5:(nrow(definition_frame) + 4L), heights = 34
      )
    }
    openxlsx::setColWidths(workbook, sheet_name, cols = definition_start_column, widths = 26)
    openxlsx::setColWidths(workbook, sheet_name, cols = definition_start_column + 1L, widths = 58)
    openxlsx::setRowHeights(workbook, sheet_name, rows = 2, heights = 35)
  }

  openxlsx::saveWorkbook(workbook, output_file, overwrite = TRUE)
}

analyze_outcome <- function(analysis_data, outcome_row, factor_spec, config, output_paths, p_adjust_method = NULL) {
  outcome_column <- outcome_row$column[[1]]
  outcome_label <- outcome_row$label[[1]]
  category <- outcome_row$category[[1]]
  posthoc_p_adjust_method <- normalize_p_adjust_method(
    p_adjust_method %||% get_posthoc_p_adjust_method(config), default = "bonferroni"
  )
  posthoc_p_adjust_info <- p_adjustment_info(posthoc_p_adjust_method, default = "bonferroni")
  factor_codes <- as.character(factor_spec$code)
  design <- get_design_info(factor_spec)

  # Always analyze the complete structure implied by all enabled factors.
  effect_codes <- generate_effect_codes(factor_codes, length(factor_codes))
  interaction_codes <- effect_codes[grepl(":", effect_codes, fixed = TRUE)]

  warnings_errors <- list()
  selected_data <- analysis_data |>
    dplyr::select(ID, dplyr::all_of(factor_codes), dplyr::all_of(outcome_column)) |>
    dplyr::rename(Y = dplyr::all_of(outcome_column))

  non_finite_n <- sum(!is.na(selected_data$Y) & !is.finite(selected_data$Y))
  if (non_finite_n > 0L) {
    warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
      DV = outcome_label, Category = category, Stage = "Data validation", Type = "Warning",
      Message = paste0(non_finite_n, " non-finite outcome value(s) were excluded.")
    )
  }

  data <- selected_data |>
    dplyr::filter(is.finite(.data$Y)) |>
    tidyr::drop_na(dplyr::all_of(factor_codes)) |>
    droplevels()

  # Repeated-observation ANOVAs require a complete within-subject cell set for
  # each retained participant. Exclude incomplete participants outcome by
  # outcome rather than treating the remaining rows as independent.
  if (design$has_repeated) {
    repeated_filter <- retain_complete_repeated_subjects(
      data,
      design$within,
      config$factor_levels
    )
    if (length(repeated_filter$excluded_ids) > 0L) {
      warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
        DV = outcome_label, Category = category,
        Stage = "Repeated-measures completeness", Type = "Warning",
        Message = paste0(
          length(repeated_filter$excluded_ids),
          " participant(s) were excluded because they did not have exactly ",
          repeated_filter$expected_cells,
          " valid within-subject condition row(s) for this dependent variable."
        )
      )
    }
    data <- repeated_filter$data
    data$ID <- factor(data$ID)
  }

  minimum_valid_n <- as.integer(config$analysis$minimum_valid_n %||% 10L)
  n_subjects <- dplyr::n_distinct(data$ID)
  effective_n <- if (design$has_repeated) n_subjects else nrow(data)

  observed_level_counts <- vapply(data[factor_codes], nlevels, integer(1))
  configured_level_counts <- vapply(
    factor_codes,
    function(code) length(config$factor_levels[[code]]),
    integer(1)
  )
  missing_factor_levels <- factor_codes[observed_level_counts < configured_level_counts]
  if (length(missing_factor_levels) > 0L) {
    warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
      DV = outcome_label, Category = category, Stage = "Data validation", Type = "Error",
      Message = paste0(
        "Outcome-specific missing-data handling eliminated one or more configured levels of factor(s): ",
        paste(missing_factor_levels, collapse = ", "),
        "."
      )
    )
    return(list(warnings_errors = dplyr::bind_rows(warnings_errors)))
  }

  if (effective_n < minimum_valid_n || any(observed_level_counts < 2L)) {
    warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
      DV = outcome_label, Category = category, Stage = "Data validation", Type = "Error",
      Message = paste0(
        "Insufficient valid ",
        if (design$has_repeated) "participants" else "observations",
        " or fewer than two levels for an enabled factor."
      )
    )
    return(list(warnings_errors = dplyr::bind_rows(warnings_errors)))
  }

  if (length(unique(data$Y)) < 2L) {
    warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
      DV = outcome_label, Category = category, Stage = "Data validation", Type = "Error",
      Message = "The dependent variable is constant after missing and non-finite values are removed."
    )
    return(list(warnings_errors = dplyr::bind_rows(warnings_errors)))
  }

  complete_cell_counts <- data |>
    dplyr::count(dplyr::across(dplyr::all_of(factor_codes)), name = "N", .drop = FALSE)
  empty_cells <- complete_cell_counts |>
    dplyr::filter(.data$N == 0L)
  if (nrow(empty_cells) > 0L) {
    warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
      DV = outcome_label, Category = category, Stage = "Design-cell validation", Type = "Error",
      Message = paste0(
        nrow(empty_cells),
        " empty factorial design cell(s) remain after outcome-specific missing-data handling."
      )
    )
    return(list(warnings_errors = dplyr::bind_rows(warnings_errors)))
  }

  # Complete fixed-effects model used by both parametric and ART branches.
  formula_text <- paste("Y ~", paste(factor_codes, collapse = " * "))
  model_formula <- stats::as.formula(formula_text)

  # Fit a model used for residual normality diagnostics. For repeated designs,
  # a subject random intercept preserves within-subject dependence in the
  # residual model; the final parametric significance tests are fitted with
  # afex::aov_ez below.
  residual_model_capture <- tryCatch(
    capture_warnings(
      if (design$has_repeated) {
        fit_repeated_residual_model(data, factor_codes)
      } else {
        stats::lm(model_formula, data = data)
      }
    ),
    error = function(e) e
  )

  residual_model <- NULL
  if (inherits(residual_model_capture, "error")) {
    shapiro_result <- list(
      W = NA_real_, p = NA_real_,
      note = paste0("Residual model unavailable: ", conditionMessage(residual_model_capture))
    )
    warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
      DV = outcome_label, Category = category, Stage = "Residual model", Type = "Warning",
      Message = conditionMessage(residual_model_capture)
    )
  } else {
    residual_model <- residual_model_capture$value
    residual_values <- tryCatch(
      as.numeric(stats::residuals(residual_model)),
      error = function(e) numeric(0)
    )
    shapiro_result <- safe_shapiro(residual_values)
    if (length(residual_model_capture$warnings) > 0L) {
      warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
        DV = outcome_label, Category = category, Stage = "Residual model", Type = "Warning",
        Message = paste(residual_model_capture$warnings, collapse = " | ")
      )
    }
  }

  # Levene's test is used only when between-subject variation is present. In
  # mixed designs it is evaluated separately within each repeated-measures cell,
  # and the smallest p-value is used as the conservative screening statistic.
  levene_result <- safe_design_levene(
    data,
    design$between,
    design$within,
    config$analysis$levene_center %||% "median"
  )

  shapiro_ok <- is.finite(shapiro_result$p) &&
    shapiro_result$p >= config$analysis$alpha
  levene_ok <- !isTRUE(levene_result$required) ||
    (is.finite(levene_result$p) && levene_result$p >= config$analysis$alpha)
  assumptions_met <- shapiro_ok && levene_ok

  method_selection <- tolower(config$analysis$method_selection %||% "automatic")
  selected_method <- if (method_selection == "anova") {
    "ANOVA"
  } else if (method_selection == "art") {
    "ART-ANOVA"
  } else if (assumptions_met) {
    "ANOVA"
  } else {
    "ART-ANOVA"
  }

  selection_reason <- if (method_selection != "automatic") {
    paste0("Method forced by configuration: ", selected_method, ".")
  } else if (assumptions_met) {
    if (isTRUE(levene_result$required) && design$has_repeated) {
      "Residual Shapiro-Wilk and between-subject Levene screening were non-significant; sphericity is evaluated effect-wise for the repeated-measures ANOVA and handled using the configured correction."
    } else if (isTRUE(levene_result$required)) {
      "Residual Shapiro-Wilk and between-subject Levene tests were both non-significant."
    } else {
      "Residual Shapiro-Wilk was non-significant; sphericity is evaluated effect-wise for the repeated-measures ANOVA and handled using the configured correction."
    }
  } else if (isTRUE(levene_result$required)) {
    paste0(
      "At least one required assumption diagnostic was significant or unavailable: ",
      format_p_for_plot(shapiro_result$p), " (Shapiro); ",
      format_p_for_plot(levene_result$p), " (Levene)."
    )
  } else {
    paste0(
      "Residual Shapiro-Wilk was significant or unavailable: ",
      format_p_for_plot(shapiro_result$p),
      ". Sphericity is evaluated separately only when the parametric repeated-measures ANOVA path is used."
    )
  }

  correction_value <- toupper(config$analysis$sphericity_correction %||% "GG")
  assumption_table <- tibble::tibble(
    DV = outcome_label,
    Category = category,
    Design_Type = design$type,
    Between_Factors = if (length(design$between) > 0L) paste(design$between, collapse = " × ") else NA_character_,
    Within_Factors = if (length(design$within) > 0L) paste(design$within, collapse = " × ") else NA_character_,
    N_Valid = nrow(data),
    N_Subjects = n_subjects,
    Residual_Shapiro_W = shapiro_result$W,
    Shapiro_p = shapiro_result$p,
    Shapiro_Decision = ifelse(
      is.na(shapiro_result$p),
      "Unavailable",
      ifelse(shapiro_result$p >= config$analysis$alpha, "Normality not rejected", "Normality rejected")
    ),
    Levene_F = levene_result$F,
    Levene_df1 = levene_result$df1,
    Levene_df2 = levene_result$df2,
    Levene_p = levene_result$p,
    Levene_Decision = if (!isTRUE(levene_result$required)) {
      "Not applicable"
    } else if (is.na(levene_result$p)) {
      "Unavailable"
    } else if (levene_result$p >= config$analysis$alpha) {
      "Homogeneity not rejected"
    } else {
      "Homogeneity rejected"
    },
    Levene_Note = levene_result$note,
    Sphericity_Correction = if (design$has_repeated && identical(selected_method, "ANOVA")) {
      correction_value
    } else if (design$has_repeated) {
      "Not applicable to ART-ANOVA"
    } else {
      "Not applicable"
    },
    Selected_Method = selected_method,
    Selection_Reason = selection_reason
  )

  cell_shapiro <- data |>
    dplyr::group_by(dplyr::across(dplyr::all_of(factor_codes))) |>
    dplyr::group_modify(function(group_data, group_keys) {
      result <- safe_shapiro(group_data$Y)
      tibble::tibble(
        N = nrow(group_data), W = result$W, p_value = result$p,
        Decision = ifelse(
          is.na(result$p),
          "Unavailable",
          ifelse(result$p >= config$analysis$alpha, "Normality not rejected", "Normality rejected")
        ),
        Note = result$note
      )
    }) |>
    dplyr::ungroup() |>
    dplyr::mutate(DV = outcome_label, Category = category, .before = 1)

  overall_descriptive <- tibble::tibble(
    DV = outcome_label, Category = category, N = nrow(data), N_Subjects = n_subjects,
    Mean = mean(data$Y), SD = stats::sd(data$Y), SE = stats::sd(data$Y) / sqrt(nrow(data)),
    Median = stats::median(data$Y), IQR = stats::IQR(data$Y), Min = min(data$Y), Max = max(data$Y)
  )
  main_descriptive <- dplyr::bind_rows(lapply(factor_codes, function(code) {
    summarise_groups(data, code, outcome_label, category, code, factor_spec)
  }))
  interaction_descriptive <- dplyr::bind_rows(lapply(interaction_codes, function(effect_code) {
    summarise_groups(
      data,
      strsplit(effect_code, ":", fixed = TRUE)[[1]],
      outcome_label,
      category,
      effect_code,
      factor_spec
    )
  }))

  fitted_model <- NULL
  model_method_label <- NULL
  estimate_scale <- NULL
  omnibus_table <- NULL
  model_summary <- NULL
  art_model <- NULL
  sphericity_table <- tibble::tibble()

  if (selected_method == "ANOVA") {
    if (design$has_repeated) {
      anova_capture <- tryCatch(
        capture_warnings(
          fit_afex_anova(
            data,
            design,
            config$analysis$anova_type %||% 3L,
            config$analysis$sphericity_correction %||% "GG"
          )
        ),
        error = function(e) e
      )
      if (inherits(anova_capture, "error")) {
        warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
          DV = outcome_label, Category = category,
          Stage = "Repeated/mixed ANOVA model", Type = "Error",
          Message = conditionMessage(anova_capture)
        )
        return(list(
          assumptions = assumption_table, cell_shapiro = cell_shapiro,
          overall_descriptive = overall_descriptive, main_descriptive = main_descriptive,
          interaction_descriptive = interaction_descriptive,
          warnings_errors = dplyr::bind_rows(warnings_errors)
        ))
      }
      fitted_model <- anova_capture$value
      if (length(anova_capture$warnings) > 0L) {
        warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
          DV = outcome_label, Category = category,
          Stage = "Repeated/mixed ANOVA model", Type = "Warning",
          Message = paste(anova_capture$warnings, collapse = " | ")
        )
      }

      sphericity_capture <- tryCatch(
        capture_warnings(
          extract_sphericity_tests(
            fitted_model, outcome_label, category, factor_spec,
            config$analysis$sphericity_correction %||% "GG",
            config$analysis$alpha
          )
        ),
        error = function(e) e
      )
      if (inherits(sphericity_capture, "error")) {
        sphericity_table <- tibble::tibble(
          DV = outcome_label, Category = category,
          Effect_Code = NA_character_, Effect_Label = NA_character_,
          Mauchly_W = NA_real_, Mauchly_p = NA_real_,
          Sphericity_Decision = "Unavailable", Uncorrected_p = NA_real_,
          GG_Epsilon = NA_real_, GG_Corrected_p = NA_real_,
          HF_Epsilon = NA_real_, HF_Corrected_p = NA_real_,
          Applied_Correction = toupper(config$analysis$sphericity_correction %||% "GG"),
          Applied_p = NA_real_,
          Note = paste0("Sphericity diagnostics could not be extracted: ", conditionMessage(sphericity_capture))
        )
        warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
          DV = outcome_label, Category = category,
          Stage = "Sphericity diagnostics", Type = "Warning",
          Message = conditionMessage(sphericity_capture)
        )
      } else {
        sphericity_table <- sphericity_capture$value
        if (length(sphericity_capture$warnings) > 0L) {
          warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
            DV = outcome_label, Category = category,
            Stage = "Sphericity diagnostics", Type = "Warning",
            Message = paste(sphericity_capture$warnings, collapse = " | ")
          )
        }
      }

      omnibus_capture <- tryCatch(
        extract_afex_anova_table(
          fitted_model, outcome_label, category, factor_spec,
          config$analysis$anova_type %||% 3L,
          config$analysis$sphericity_correction %||% "GG",
          config$analysis$alpha
        ) |>
          dplyr::filter(.data$Effect_Code %in% effect_codes),
        error = function(e) e
      )
      formula_report <- paste0(
        formula_text,
        " + Error(ID/(",
        paste(design$within, collapse = " * "),
        "))"
      )
    } else {
      if (is.null(residual_model)) {
        warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
          DV = outcome_label, Category = category, Stage = "ANOVA model", Type = "Error",
          Message = "The between-subjects linear model was unavailable."
        )
        return(list(
          assumptions = assumption_table, cell_shapiro = cell_shapiro,
          overall_descriptive = overall_descriptive, main_descriptive = main_descriptive,
          interaction_descriptive = interaction_descriptive,
          warnings_errors = dplyr::bind_rows(warnings_errors)
        ))
      }
      fitted_model <- residual_model
      if (inherits(fitted_model, "lm") &&
          (fitted_model$rank < length(stats::coef(fitted_model)) ||
           stats::df.residual(fitted_model) <= 0L)) {
        warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
          DV = outcome_label, Category = category, Stage = "ANOVA model", Type = "Error",
          Message = "The fitted between-subjects model is rank deficient or has no residual degrees of freedom."
        )
        return(list(
          assumptions = assumption_table, cell_shapiro = cell_shapiro,
          overall_descriptive = overall_descriptive, main_descriptive = main_descriptive,
          interaction_descriptive = interaction_descriptive,
          warnings_errors = dplyr::bind_rows(warnings_errors)
        ))
      }
      omnibus_capture <- tryCatch(
        extract_anova_table(
          fitted_model, outcome_label, category, factor_spec,
          config$analysis$anova_type %||% 3L,
          config$analysis$alpha
        ) |>
          dplyr::filter(.data$Effect_Code %in% effect_codes),
        error = function(e) e
      )
      formula_report <- formula_text
    }

    if (inherits(omnibus_capture, "error")) {
      warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
        DV = outcome_label, Category = category, Stage = "ANOVA omnibus table", Type = "Error",
        Message = conditionMessage(omnibus_capture)
      )
      return(list(
        assumptions = assumption_table, cell_shapiro = cell_shapiro,
        overall_descriptive = overall_descriptive, main_descriptive = main_descriptive,
        interaction_descriptive = interaction_descriptive,
        warnings_errors = dplyr::bind_rows(warnings_errors)
      ))
    }

    omnibus_table <- omnibus_capture
    model_method_label <- unique(omnibus_table$Model_Method)[[1]]
    estimate_scale <- "raw outcome"
    model_summary <- tibble::tibble(
      DV = outcome_label,
      Category = category,
      Design_Type = design$type,
      Model_Method = model_method_label,
      Formula = formula_report,
      N = nrow(data),
      N_Subjects = n_subjects,
      Residual_df = if (!design$has_repeated && inherits(fitted_model, "lm")) {
        stats::df.residual(fitted_model)
      } else {
        NA_real_
      },
      R_squared = if (!design$has_repeated && inherits(fitted_model, "lm")) {
        summary(fitted_model)$r.squared
      } else {
        NA_real_
      },
      Adjusted_R_squared = if (!design$has_repeated && inherits(fitted_model, "lm")) {
        summary(fitted_model)$adj.r.squared
      } else {
        NA_real_
      },
      Sphericity_Correction = if (design$has_repeated) correction_value else "Not applicable",
      ART_Max_Absolute_Aligned_Sum = NA_real_,
      ART_Diagnostic_File = NA_character_
    )
  } else {
    art_formula_text <- if (design$has_repeated) {
      paste0(formula_text, " + (1|ID)")
    } else {
      formula_text
    }
    art_model_formula <- stats::as.formula(art_formula_text)

    art_capture <- tryCatch(
      capture_warnings(ARTool::art(art_model_formula, data = data)),
      error = function(e) e
    )
    if (inherits(art_capture, "error")) {
      warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
        DV = outcome_label, Category = category, Stage = "ART model", Type = "Error",
        Message = conditionMessage(art_capture)
      )
      return(list(
        assumptions = assumption_table, cell_shapiro = cell_shapiro,
        overall_descriptive = overall_descriptive, main_descriptive = main_descriptive,
        interaction_descriptive = interaction_descriptive,
        warnings_errors = dplyr::bind_rows(warnings_errors)
      ))
    }

    art_model <- art_capture$value
    fitted_model <- art_model
    if (design$has_repeated) {
      sphericity_table <- tibble::tibble(
        DV = outcome_label, Category = category,
        Effect_Code = NA_character_, Effect_Label = NA_character_,
        Mauchly_W = NA_real_, Mauchly_p = NA_real_,
        Sphericity_Decision = "Not applicable to ART-ANOVA",
        Uncorrected_p = NA_real_, GG_Epsilon = NA_real_, GG_Corrected_p = NA_real_,
        HF_Epsilon = NA_real_, HF_Corrected_p = NA_real_,
        Applied_Correction = "Not applicable to ART-ANOVA", Applied_p = NA_real_,
        Note = "Mauchly's sphericity test is a diagnostic for the univariate repeated-measures ANOVA path and is not applicable to the selected ART-ANOVA mixed-effects model."
      )
    }
    model_method_label <- paste0(
      "ART-ANOVA (Type ", config$analysis$anova_type %||% 3L,
      if (design$has_repeated) ", mixed-effects" else "",
      ")"
    )
    estimate_scale <- "aligned ranks"

    omnibus_capture <- tryCatch(
      extract_art_table(
        art_model, outcome_label, category, factor_spec,
        config$analysis$alpha,
        config$analysis$anova_type %||% 3L
      ) |>
        dplyr::filter(.data$Effect_Code %in% effect_codes) |>
        dplyr::mutate(Model_Method = model_method_label),
      error = function(e) e
    )
    if (inherits(omnibus_capture, "error")) {
      warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
        DV = outcome_label, Category = category, Stage = "ART omnibus table", Type = "Error",
        Message = conditionMessage(omnibus_capture)
      )
      return(list(
        assumptions = assumption_table, cell_shapiro = cell_shapiro,
        overall_descriptive = overall_descriptive, main_descriptive = main_descriptive,
        interaction_descriptive = interaction_descriptive,
        warnings_errors = dplyr::bind_rows(warnings_errors)
      ))
    }
    omnibus_table <- omnibus_capture

    if (length(art_capture$warnings) > 0L) {
      warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
        DV = outcome_label, Category = category, Stage = "ART model", Type = "Warning",
        Message = paste(art_capture$warnings, collapse = " | ")
      )
    }

    aligned_sums <- colSums(art_model$aligned, na.rm = TRUE)
    maximum_aligned_sum <- max(abs(aligned_sums), na.rm = TRUE)
    diagnostic_relative_path <- NA_character_

    if (isTRUE(config$output$save_art_diagnostics)) {
      diagnostic_file <- file.path(
        output_paths$art_diagnostics_dir,
        paste0(safe_path_component(outcome_label), "_ART_diagnostics.txt")
      )

      art_summary_text <- tryCatch(
        capture.output(print(summary(art_model))),
        error = function(e) paste0("Unavailable: ", conditionMessage(e))
      )

      diagnostic_lines <- c(
        paste0("Dependent variable: ", outcome_label),
        paste0("Design type: ", design$type),
        paste0("ART model: ", art_formula_text),
        "",
        "Column sums of aligned responses:",
        capture.output(print(aligned_sums)),
        "",
        paste0(
          "Maximum absolute aligned-column sum: ",
          format(maximum_aligned_sum, scientific = TRUE)
        ),
        "",
        "summary(art_model):",
        art_summary_text
      )

      # For a single fixed factor there are no non-target fixed effects, so the
      # extra aligned-response ANOVA diagnostic is empty and is simply omitted.
      if (length(effect_codes) > 1L) {
        aligned_anova_capture <- tryCatch(
          stats::anova(
            art_model,
            response = "aligned",
            type = as.integer(config$analysis$anova_type %||% 3L),
            test = "F"
          ),
          error = function(e) e
        )
        aligned_anova_text <- if (inherits(aligned_anova_capture, "error")) {
          paste0("Unavailable: ", conditionMessage(aligned_anova_capture))
        } else {
          tryCatch(
            capture.output(print(aligned_anova_capture)),
            error = function(e) paste0("Unavailable: ", conditionMessage(e))
          )
        }
        diagnostic_lines <- c(
          diagnostic_lines,
          "",
          "ANOVA on aligned responses:",
          aligned_anova_text
        )
      }

      diagnostic_write <- tryCatch({
        writeLines(diagnostic_lines, diagnostic_file, useBytes = TRUE)
        TRUE
      }, error = function(e) e)

      if (inherits(diagnostic_write, "error")) {
        warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
          DV = outcome_label, Category = category,
          Stage = "ART diagnostics", Type = "Warning",
          Message = paste0(
            "ART diagnostics could not be written, but the analysis continued: ",
            conditionMessage(diagnostic_write)
          )
        )
      } else {
        diagnostic_relative_path <- fs::path_rel(
          diagnostic_file,
          start = output_paths$root
        )
      }
    }

    model_summary <- tibble::tibble(
      DV = outcome_label,
      Category = category,
      Design_Type = design$type,
      Model_Method = model_method_label,
      Formula = art_formula_text,
      N = nrow(data),
      N_Subjects = n_subjects,
      Residual_df = if (nrow(omnibus_table) > 0L) unique(omnibus_table$df2)[[1]] else NA_real_,
      R_squared = NA_real_,
      Adjusted_R_squared = NA_real_,
      Sphericity_Correction = "Not applicable to ART-ANOVA",
      ART_Max_Absolute_Aligned_Sum = maximum_aligned_sum,
      ART_Diagnostic_File = diagnostic_relative_path
    )
  }

  main_posthoc <- list()
  interaction_cells <- list()
  interaction_contrasts <- list()
  main_posthoc_by_effect <- list()
  interaction_contrasts_by_effect <- list()

  for (factor_code in factor_codes) {
    result_capture <- tryCatch({
      if (selected_method == "ANOVA") {
        means <- emmeans::emmeans(fitted_model, specs = factor_code)
        capture_warnings(emmeans::contrast(means, method = "pairwise", adjust = posthoc_p_adjust_method))
      } else {
        capture_warnings(ARTool::art.con(art_model, factor_code, adjust = posthoc_p_adjust_method))
      }
    }, error = function(e) e)

    if (inherits(result_capture, "error")) {
      warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
        DV = outcome_label, Category = category, Stage = paste0("Main-effect post-hoc: ", factor_code),
        Type = "Error", Message = conditionMessage(result_capture)
      )
    } else {
      result_frame <- summary(result_capture$value, infer = c(TRUE, TRUE)) |>
        add_contrast_metadata(
          outcome_label, category, model_method_label, factor_code,
          "Main-effect pairwise comparison", estimate_scale,
          factor_spec, posthoc_p_adjust_method, config$analysis$alpha
        ) |>
        parse_pairwise_groups(levels(data[[factor_code]]))
      result_frame$Annotation_Eligible <-
        result_frame$Group1 %in% levels(data[[factor_code]]) &
        result_frame$Group2 %in% levels(data[[factor_code]])
      main_posthoc[[length(main_posthoc) + 1L]] <- result_frame
      main_posthoc_by_effect[[factor_code]] <- result_frame

      unmatched_significant <- result_frame |>
        dplyr::filter(
          !is.na(.data$p.value), .data$p.value < config$analysis$alpha,
          !(.data$Group1 %in% levels(data[[factor_code]]) & .data$Group2 %in% levels(data[[factor_code]]))
        )
      if (nrow(unmatched_significant) > 0L) {
        warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
          DV = outcome_label, Category = category,
          Stage = paste0("Main-effect plot annotation: ", factor_code),
          Type = "Warning",
          Message = paste0(
            nrow(unmatched_significant),
            " significant pairwise comparison(s) could not be mapped to configured factor levels."
          )
        )
      }

      if (length(result_capture$warnings) > 0L) {
        warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
          DV = outcome_label, Category = category, Stage = paste0("Main-effect post-hoc: ", factor_code),
          Type = "Warning", Message = paste(result_capture$warnings, collapse = " | ")
        )
      }
    }
  }

  for (effect_code in interaction_codes) {
    codes <- strsplit(effect_code, ":", fixed = TRUE)[[1]]
    specifications <- stats::as.formula(paste("~", paste(codes, collapse = " * ")))

    cell_capture <- tryCatch({
      if (selected_method == "ANOVA") {
        means <- emmeans::emmeans(fitted_model, specs = specifications)
        capture_warnings(emmeans::contrast(means, method = "pairwise", adjust = posthoc_p_adjust_method))
      } else {
        capture_warnings(ARTool::art.con(art_model, effect_code, adjust = posthoc_p_adjust_method))
      }
    }, error = function(e) e)

    if (inherits(cell_capture, "error")) {
      warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
        DV = outcome_label, Category = category, Stage = paste0("Interaction-cell post-hoc: ", effect_code),
        Type = "Error", Message = conditionMessage(cell_capture)
      )
    } else {
      interaction_cells[[length(interaction_cells) + 1L]] <- summary(cell_capture$value, infer = c(TRUE, TRUE)) |>
        add_contrast_metadata(
          outcome_label, category, model_method_label, effect_code,
          "Factor-combination pairwise comparison", estimate_scale,
          factor_spec, posthoc_p_adjust_method, config$analysis$alpha
        )
      if (length(cell_capture$warnings) > 0L) {
        warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
          DV = outcome_label, Category = category,
          Stage = paste0("Interaction-cell post-hoc: ", effect_code),
          Type = "Warning", Message = paste(cell_capture$warnings, collapse = " | ")
        )
      }
    }

    interaction_capture <- tryCatch({
      if (selected_method == "ANOVA") {
        means <- emmeans::emmeans(fitted_model, specs = specifications)
        capture_warnings(
          emmeans::contrast(
            means,
            interaction = rep("pairwise", length(codes)),
            adjust = posthoc_p_adjust_method
          )
        )
      } else {
        capture_warnings(
          ARTool::art.con(
            art_model, effect_code,
            interaction = TRUE,
            adjust = posthoc_p_adjust_method
          )
        )
      }
    }, error = function(e) e)

    if (inherits(interaction_capture, "error")) {
      warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
        DV = outcome_label, Category = category, Stage = paste0("Interaction contrast: ", effect_code),
        Type = "Error", Message = conditionMessage(interaction_capture)
      )
      interaction_contrasts_by_effect[[effect_code]] <- tibble::tibble()
    } else {
      contrast_frame <- summary(interaction_capture$value, infer = c(TRUE, TRUE)) |>
        add_contrast_metadata(
          outcome_label, category, model_method_label, effect_code,
          ifelse(length(codes) == 2L, "Difference-of-differences interaction contrast", "Higher-order interaction contrast"),
          estimate_scale, factor_spec, posthoc_p_adjust_method, config$analysis$alpha
        )
      interaction_contrasts[[length(interaction_contrasts) + 1L]] <- contrast_frame
      interaction_contrasts_by_effect[[effect_code]] <- contrast_frame
      if (length(interaction_capture$warnings) > 0L) {
        warnings_errors[[length(warnings_errors) + 1L]] <- tibble::tibble(
          DV = outcome_label, Category = category,
          Stage = paste0("Interaction contrast: ", effect_code),
          Type = "Warning", Message = paste(interaction_capture$warnings, collapse = " | ")
        )
      }
    }
  }

  main_plots <- lapply(factor_codes, function(code) {
    make_main_effect_plot(
      data, code, outcome_label, get_effect_row(omnibus_table, code),
      main_posthoc_by_effect[[code]] %||% tibble::tibble(),
      config, factor_spec, p_adjust_method = posthoc_p_adjust_method
    )
  })
  names(main_plots) <- factor_codes

  interaction_plots <- lapply(interaction_codes, function(effect_code) {
    effect_order <- length(strsplit(effect_code, ":", fixed = TRUE)[[1]])
    if (effect_order == 2L) {
      make_two_way_plot(
        data, effect_code, outcome_label, get_effect_row(omnibus_table, effect_code),
        interaction_contrasts_by_effect[[effect_code]] %||% tibble::tibble(),
        config, factor_spec, p_adjust_method = posthoc_p_adjust_method
      )
    } else {
      make_three_way_plot(
        data, effect_code, outcome_label, get_effect_row(omnibus_table, effect_code),
        interaction_contrasts_by_effect[[effect_code]] %||% tibble::tibble(),
        config, factor_spec, p_adjust_method = posthoc_p_adjust_method
      )
    }
  })
  names(interaction_plots) <- interaction_codes

  list(
    assumptions = assumption_table,
    sphericity_tests = sphericity_table,
    cell_shapiro = cell_shapiro,
    model_summary = model_summary,
    omnibus = omnibus_table,
    overall_descriptive = overall_descriptive,
    main_descriptive = main_descriptive,
    interaction_descriptive = interaction_descriptive,
    main_posthoc = dplyr::bind_rows(main_posthoc),
    interaction_cells = dplyr::bind_rows(interaction_cells),
    interaction_contrasts = dplyr::bind_rows(interaction_contrasts),
    warnings_errors = dplyr::bind_rows(warnings_errors),
    main_plots = main_plots,
    interaction_plots = interaction_plots,
    selected_method = selected_method,
    data = data
  )
}

create_figures_pdf <- function(
    results_by_outcome,
    outcome_spec,
    factor_spec,
    config,
    pdf_file,
    correlation_analysis = NULL) {
  if (!isTRUE(config$plots$create_pdf)) return(tibble::tibble())
  posthoc_p_adjust_info <- get_posthoc_p_adjust_info(config)
  has_factorial_plots <- any(vapply(
    results_by_outcome,
    function(result) {
      !is.null(result) &&
        ((!is.null(result$main_plots) && length(result$main_plots) > 0L) ||
         (!is.null(result$interaction_plots) && length(result$interaction_plots) > 0L))
    },
    logical(1)
  ))
  has_correlation_plot <- !is.null(correlation_analysis) &&
    !is.null(correlation_analysis$heatmap)
  if (!has_factorial_plots && !has_correlation_plot) return(tibble::tibble())

  grDevices::pdf(
    pdf_file,
    width = config$plots$pdf_width %||% 16,
    height = config$plots$pdf_height %||% 9,
    onefile = TRUE,
    useDingbats = FALSE
  )
  on.exit(grDevices::dev.off(), add = TRUE)

  category_order <- config$plots$category_order %||% unique(outcome_spec$category)
  category_order <- c(category_order, setdiff(unique(outcome_spec$category), category_order))
  page_number <- 0L
  plot_index <- list()

  for (category in category_order) {
    # Use .env$category for the loop variable. Without .env, dplyr data
    # masking resolves both occurrences of category to the data-frame column,
    # making the condition category == category and selecting every outcome.
    category_outcomes <- outcome_spec |>
      dplyr::filter(.data$category == .env$category)
    if (nrow(category_outcomes) > 0L) {
      has_plots <- vapply(
        category_outcomes$label,
        function(label) {
          result <- results_by_outcome[[label]]
          !is.null(result) && !is.null(result$main_plots) && length(result$main_plots) > 0L
        },
        logical(1)
      )
      category_outcomes <- category_outcomes[has_plots, , drop = FALSE]
    }
    if (nrow(category_outcomes) == 0L) next

    category_page <- ggplot2::ggplot() +
      ggplot2::annotate(
        "text",
        x = 0.5,
        y = 0.61,
        label = wrap_plot_title(category, config, page = TRUE),
        size = 12,
        fontface = "bold"
      ) +
      ggplot2::annotate(
        "text",
        x = 0.5,
        y = 0.48,
        label = "ANOVA / ART-ANOVA results",
        size = 6
      ) +
      ggplot2::annotate(
        "text",
        x = 0.5,
        y = 0.34,
        label = "Significance notation",
        size = 5,
        fontface = "bold"
      ) +
      ggplot2::annotate(
        "text",
        x = 0.5,
        y = 0.19,
        label = category_page_significance_note(),
        size = 4.5,
        lineheight = 1.25,
        hjust = 0.5,
        vjust = 0.5
      ) +
      ggplot2::xlim(0, 1) +
      ggplot2::ylim(0, 1) +
      ggplot2::theme_void()
    print(category_page)
    page_number <- page_number + 1L

    for (outcome_index in seq_len(nrow(category_outcomes))) {
      outcome_label <- category_outcomes$label[[outcome_index]]
      result <- results_by_outcome[[outcome_label]]
      if (is.null(result) || is.null(result$main_plots)) next

      main_page <- patchwork::wrap_plots(
        result$main_plots,
        ncol = length(result$main_plots)
      ) +
        patchwork::plot_annotation(
          title = wrap_plot_title(category, config, page = TRUE),
          subtitle = wrap_plot_title(
            paste0(
              outcome_label, " — Main Effects (", result$selected_method, ")",
              " | Post-hoc p adjustment: ", posthoc_p_adjust_info$display_label
            ),
            config, page = TRUE
          ),
          theme = ggplot2::theme(
            plot.title = ggplot2::element_text(size = 18, face = "bold"),
            plot.subtitle = ggplot2::element_text(size = 14, face = "bold"),
            plot.margin = ggplot2::margin(18, 18, 18, 18)
          )
        )
      print(main_page)
      page_number <- page_number + 1L
      plot_index[[length(plot_index) + 1L]] <- tibble::tibble(
        DV = outcome_label, Category = category, Plot_Type = "Main Effects",
        PDF_File = basename(pdf_file), PDF_Page = page_number
      )

      if (length(result$interaction_plots) > 0L) {
        interaction_page <- patchwork::wrap_plots(
          result$interaction_plots,
          ncol = min(config$plots$interaction_ncol %||% 4L, length(result$interaction_plots))
        ) +
          patchwork::plot_annotation(
            title = wrap_plot_title(category, config, page = TRUE),
            subtitle = wrap_plot_title(
              paste0(
                outcome_label, " — Interaction Effects (", result$selected_method, ")",
                " | Contrast p adjustment: ", posthoc_p_adjust_info$display_label
              ),
              config, page = TRUE
            ),
            theme = ggplot2::theme(
              plot.title = ggplot2::element_text(size = 18, face = "bold"),
              plot.subtitle = ggplot2::element_text(size = 14, face = "bold"),
              plot.margin = ggplot2::margin(18, 18, 18, 18)
            )
          )
        print(interaction_page)
        page_number <- page_number + 1L
        plot_index[[length(plot_index) + 1L]] <- tibble::tibble(
          DV = outcome_label, Category = category, Plot_Type = "Interaction Effects",
          PDF_File = basename(pdf_file), PDF_Page = page_number
        )
      }
    }
  }

  if (has_correlation_plot) {
    print(correlation_analysis$heatmap)
    page_number <- page_number + 1L
    plot_index[[length(plot_index) + 1L]] <- tibble::tibble(
      DV = "All selected outcomes",
      Category = "Correlation Analysis",
      Plot_Type = "Correlation Heatmap",
      PDF_File = basename(pdf_file),
      PDF_Page = page_number
    )
  }

  dplyr::bind_rows(plot_index)
}

run_analysis <- function(
    config_file, posthoc_p_adjust_method = NULL, correlation_p_adjust_method = NULL) {
  analysis_start_time <- Sys.time()
  config <- load_configuration(config_file)

  # Optional function arguments override the configuration for this run only.
  # When NULL, the values are read from CONFIG. This makes adjustment methods
  # available both to configuration-file users and programmatic callers.
  if (!is.null(posthoc_p_adjust_method)) {
    config$analysis$p_adjust_method <- posthoc_p_adjust_method
  }
  if (is.null(config$correlation)) config$correlation <- list()
  if (!is.null(correlation_p_adjust_method)) {
    config$correlation$p_adjust_method <- correlation_p_adjust_method
  }

  validate_configuration(config)
  config$analysis$p_adjust_method <- get_posthoc_p_adjust_method(config)
  config$correlation$p_adjust_method <- get_correlation_config(config)$p_adjust_method
  posthoc_p_adjust_info <- get_posthoc_p_adjust_info(config)
  correlation_p_adjust_info <- get_correlation_p_adjust_info(config)
  install_and_load_packages(config)

  # Preserve the caller's session state. The analysis still uses a reproducible
  # random seed and sum-to-zero contrasts internally, but restores the previous
  # RNG state and options when run_analysis() exits.
  previous_options <- options(c("contrasts", "stringsAsFactors", "scipen"))
  on.exit(options(previous_options), add = TRUE)

  had_random_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  previous_random_seed <- if (had_random_seed) get(".Random.seed", envir = .GlobalEnv) else NULL
  on.exit({
    if (had_random_seed) {
      assign(".Random.seed", previous_random_seed, envir = .GlobalEnv)
    } else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
      rm(".Random.seed", envir = .GlobalEnv)
    }
  }, add = TRUE)

  set.seed(config$analysis$random_seed %||% 20260731L)
  options(contrasts = c("contr.sum", "contr.poly"), stringsAsFactors = FALSE, scipen = 999)

  config_dir <- attr(config, "config_dir")
  input_file <- resolve_relative_path(config$input$file, config_dir)
  if (!file.exists(input_file)) stop("Input data file not found: ", input_file, call. = FALSE)

  input_stem <- safe_path_component(tools::file_path_sans_ext(basename(input_file)))
  output_root <- if (is.null(config$output$directory) || !nzchar(config$output$directory)) {
    file.path(dirname(input_file), paste0(input_stem, "_analysis_results"))
  } else {
    resolve_relative_path(config$output$directory, config_dir)
  }

  output_paths <- list(
    root = output_root,
    workbook = file.path(output_root, paste0(input_stem, "_statistical_results.xlsx")),
    figures = file.path(output_root, paste0(input_stem, "_figures.pdf")),
    logs_dir = file.path(output_root, "logs"),
    art_diagnostics_dir = file.path(output_root, "art_diagnostics")
  )
  fs::dir_create(output_paths$root)
  if (isTRUE(config$output$save_logs)) fs::dir_create(output_paths$logs_dir)
  if (isTRUE(config$output$save_art_diagnostics)) fs::dir_create(output_paths$art_diagnostics_dir)

  initial_sink_count <- sink.number(type = "output")
  sink_started <- FALSE
  sink_closed <- FALSE
  if (isTRUE(config$output$save_logs)) {
    console_log <- file.path(output_paths$logs_dir, "run_console_output.txt")
    sink(console_log, split = TRUE)
    sink_started <- TRUE
  }
  close_script_sink <- function() {
    if (isTRUE(sink_closed)) return(invisible(NULL))
    if (isTRUE(sink_started)) {
      while (sink.number(type = "output") > initial_sink_count) {
        before_level <- sink.number(type = "output")
        try(sink(type = "output"), silent = TRUE)
        if (sink.number(type = "output") >= before_level) break
      }
    }
    sink_closed <<- TRUE
    invisible(NULL)
  }
  on.exit(close_script_sink(), add = TRUE)

  cat("Analysis started:", format(analysis_start_time), "\n")
  cat("Configuration file:", attr(config, "config_path"), "\n")
  cat("Input file:", input_file, "\n")
  cat("Output directory:", output_root, "\n\n")

  raw_data <- tibble::as_tibble(read_input_file(input_file, config$input$sheet))
  prepared <- prepare_input_data(raw_data, config)
  analysis_data <- prepared$data
  factor_spec <- prepared$factor_spec
  outcome_spec <- prepared$outcome_spec
  factor_codes <- factor_spec$code
  design <- get_design_info(factor_spec)
  global_warnings_errors <- list()

  missing_id_count <- sum(is.na(analysis_data$ID) | !nzchar(trimws(as.character(analysis_data$ID))))
  if (missing_id_count > 0L) {
    stop(
      "The ID column contains ", missing_id_count,
      " missing or empty value(s). Every row must have an ID.",
      call. = FALSE
    )
  }

  structure_issues <- validate_subject_factor_structure(analysis_data, factor_spec)
  if (length(structure_issues) > 0L) {
    stop(
      "The prepared data do not match the configured ", design$type, " design:\n- ",
      paste(structure_issues, collapse = "\n- "),
      call. = FALSE
    )
  }

  conversion_problem_rows <- prepared$conversion_report |>
    dplyr::filter(
      .data$Non_Numeric_Values_Converted_to_NA > 0L |
        .data$Non_Finite_Numeric_Values > 0L
    )
  if (nrow(conversion_problem_rows) > 0L) {
    global_warnings_errors[[length(global_warnings_errors) + 1L]] <- conversion_problem_rows |>
      dplyr::transmute(
        DV = .data$DV,
        Category = .data$Category,
        Stage = "Numeric conversion",
        Type = "Warning",
        Message = paste0(
          .data$Non_Numeric_Values_Converted_to_NA,
          " non-numeric value(s) converted to NA; ",
          .data$Non_Finite_Numeric_Values,
          " non-finite numeric value(s) detected."
        )
      )
  }

  design_cell_counts <- analysis_data |>
    dplyr::group_by(dplyr::across(dplyr::all_of(factor_codes)), .drop = FALSE) |>
    dplyr::summarise(
      N = dplyr::n(),
      N_Subjects = dplyr::n_distinct(.data$ID),
      .groups = "drop"
    ) |>
    dplyr::mutate(Empty_Cell = .data$N == 0L)

  total_subjects <- dplyr::n_distinct(analysis_data$ID)
  missing_summary <- dplyr::bind_rows(lapply(seq_len(nrow(outcome_spec)), function(index) {
    source_column <- outcome_spec$column[[index]]
    finite_valid <- is.finite(analysis_data[[source_column]])
    valid_subjects <- dplyr::n_distinct(analysis_data$ID[finite_valid])
    tibble::tibble(
      DV = outcome_spec$label[[index]],
      Category = outcome_spec$category[[index]],
      N_Total = nrow(analysis_data),
      N_Subjects_Total = total_subjects,
      N_Valid = sum(finite_valid),
      N_Subjects_With_Valid_Data = valid_subjects,
      N_Missing = sum(!finite_valid),
      Missing_Percent = 100 * sum(!finite_valid) / nrow(analysis_data)
    )
  }))

  factor_level_table <- dplyr::bind_rows(lapply(seq_len(nrow(factor_spec)), function(index) {
    code <- factor_spec$code[[index]]
    tibble::tibble(
      Factor_Code = code,
      Factor_Role = factor_spec$role[[index]],
      Factor_Label = factor_spec$label[[index]],
      Factor_Short_Label = factor_spec$short_label[[index]],
      Source_Column = factor_spec$column[[index]],
      Level_Order = seq_along(config$factor_levels[[code]]),
      Level = config$factor_levels[[code]]
    )
  }))

  results_by_outcome <- list()
  for (index in seq_len(nrow(outcome_spec))) {
    outcome_label <- outcome_spec$label[[index]]
    cat(strrep("=", 80), "\n", sep = "")
    cat("Analyzing:", outcome_label, "\n")
    results_by_outcome[[outcome_label]] <- analyze_outcome(
      analysis_data,
      outcome_spec[index, , drop = FALSE],
      factor_spec,
      config,
      output_paths,
      p_adjust_method = config$analysis$p_adjust_method
    )
  }

  bind_result <- function(name) {
    frames <- lapply(results_by_outcome, function(result) result[[name]])
    frames <- frames[!vapply(frames, is.null, logical(1))]
    if (length(frames) == 0L) tibble::tibble() else dplyr::bind_rows(frames)
  }

  assumptions <- bind_result("assumptions")
  sphericity_tests <- bind_result("sphericity_tests")
  cell_shapiro <- bind_result("cell_shapiro")
  model_summary <- bind_result("model_summary")
  omnibus <- bind_result("omnibus")
  overall_descriptive <- bind_result("overall_descriptive")
  main_descriptive <- bind_result("main_descriptive")
  interaction_descriptive <- bind_result("interaction_descriptive")
  main_posthoc <- bind_result("main_posthoc")
  interaction_cells <- bind_result("interaction_cells")
  interaction_contrasts <- bind_result("interaction_contrasts")
  correlation_analysis <- analyze_correlations(
    analysis_data, outcome_spec, config, factor_spec,
    p_adjust_method = config$correlation$p_adjust_method
  )
  warnings_errors <- dplyr::bind_rows(
    dplyr::bind_rows(global_warnings_errors),
    bind_result("warnings_errors"),
    correlation_analysis$warnings_errors
  )

  significant_effects <- if (nrow(omnibus) > 0L) {
    # Filtering preserves the configured dependent-variable and factorial-effect
    # order already present in the omnibus table. Do not re-sort categories
    # alphabetically or effects by p value.
    omnibus |>
      dplyr::filter(.data$p_value < config$analysis$alpha)
  } else tibble::tibble()

  plot_index <- create_figures_pdf(
    results_by_outcome,
    outcome_spec,
    factor_spec,
    config,
    output_paths$figures,
    correlation_analysis = correlation_analysis
  )

  sphericity_summary <- if (design$has_repeated && nrow(sphericity_tests) > 0L) {
    sphericity_tests |>
      dplyr::group_by(.data$DV) |>
      dplyr::summarise(
        Sphericity_Tests = sum(is.finite(.data$Mauchly_p)),
        Sphericity_Violations = sum(is.finite(.data$Mauchly_p) & .data$Mauchly_p < config$analysis$alpha),
        Minimum_Mauchly_p = if (any(is.finite(.data$Mauchly_p))) min(.data$Mauchly_p[is.finite(.data$Mauchly_p)]) else NA_real_,
        .groups = "drop"
      )
  } else {
    tibble::tibble(
      DV = character(0), Sphericity_Tests = integer(0),
      Sphericity_Violations = integer(0), Minimum_Mauchly_p = numeric(0)
    )
  }

  analysis_summary <- if (nrow(assumptions) > 0L) {
    summary_frame <- assumptions |>
      dplyr::left_join(sphericity_summary, by = "DV") |>
      dplyr::left_join(
        omnibus |>
          dplyr::group_by(.data$DV) |>
          dplyr::summarise(
            N_Significant_Main_Effects = sum(.data$p_value < config$analysis$alpha & !grepl(":", .data$Effect_Code, fixed = TRUE), na.rm = TRUE),
            N_Significant_Interactions = sum(.data$p_value < config$analysis$alpha & grepl(":", .data$Effect_Code, fixed = TRUE), na.rm = TRUE),
            Minimum_Omnibus_p = if (all(is.na(.data$p_value))) NA_real_ else min(.data$p_value, na.rm = TRUE),
            .groups = "drop"
          ),
        by = "DV"
      )

    if (identical(design$type, "between-subjects")) {
      summary_frame |>
        dplyr::select(dplyr::all_of(c(
          "DV", "Category", "Design_Type", "N_Valid", "N_Subjects",
          "Shapiro_p", "Levene_p", "Selected_Method", "Selection_Reason",
          "N_Significant_Main_Effects", "N_Significant_Interactions", "Minimum_Omnibus_p"
        )))
    } else if (identical(design$type, "within-subjects")) {
      summary_frame |>
        dplyr::select(dplyr::all_of(c(
          "DV", "Category", "Design_Type", "N_Valid", "N_Subjects",
          "Shapiro_p", "Sphericity_Tests", "Sphericity_Violations",
          "Minimum_Mauchly_p", "Sphericity_Correction",
          "Selected_Method", "Selection_Reason",
          "N_Significant_Main_Effects", "N_Significant_Interactions", "Minimum_Omnibus_p"
        )))
    } else {
      summary_frame |>
        dplyr::select(dplyr::all_of(c(
          "DV", "Category", "Design_Type", "N_Valid", "N_Subjects",
          "Shapiro_p", "Levene_p", "Sphericity_Tests", "Sphericity_Violations",
          "Minimum_Mauchly_p", "Sphericity_Correction",
          "Selected_Method", "Selection_Reason",
          "N_Significant_Main_Effects", "N_Significant_Interactions", "Minimum_Omnibus_p"
        )))
    }
  } else tibble::tibble()

  assumptions_output <- if (nrow(assumptions) == 0L) {
    assumptions
  } else if (identical(design$type, "between-subjects")) {
    assumptions |>
      dplyr::select(dplyr::all_of(c(
        "DV", "Category", "Design_Type", "Between_Factors",
        "N_Valid", "N_Subjects",
        "Residual_Shapiro_W", "Shapiro_p", "Shapiro_Decision",
        "Levene_F", "Levene_df1", "Levene_df2", "Levene_p",
        "Levene_Decision", "Levene_Note",
        "Selected_Method", "Selection_Reason"
      )))
  } else if (identical(design$type, "within-subjects")) {
    assumptions |>
      dplyr::select(dplyr::all_of(c(
        "DV", "Category", "Design_Type", "Within_Factors",
        "N_Valid", "N_Subjects",
        "Residual_Shapiro_W", "Shapiro_p", "Shapiro_Decision",
        "Sphericity_Correction", "Selected_Method", "Selection_Reason"
      )))
  } else {
    assumptions |>
      dplyr::select(dplyr::all_of(c(
        "DV", "Category", "Design_Type",
        "Between_Factors", "Within_Factors",
        "N_Valid", "N_Subjects",
        "Residual_Shapiro_W", "Shapiro_p", "Shapiro_Decision",
        "Levene_F", "Levene_df1", "Levene_df2", "Levene_p",
        "Levene_Decision", "Levene_Note", "Sphericity_Correction",
        "Selected_Method", "Selection_Reason"
      )))
  }

  model_summary_output <- if (nrow(model_summary) == 0L || design$has_repeated) {
    model_summary
  } else {
    model_summary |>
      dplyr::select(-dplyr::any_of("Sphericity_Correction"))
  }

  outcome_spec_table <- outcome_spec |>
    dplyr::transmute(
      DV = .data$label,
      Category = .data$category,
      Source_Column = .data$column,
      Enabled = .data$enabled,
      Correlation_Enabled = .data$include_in_correlation
    )

  analysis_end_time <- Sys.time()
  run_info <- tibble::tibble(
    Item = c(
      "Analysis engine", "Configuration file", "Input file", "Input sheet",
      "Input data format", "Design type", "Between-subject factors",
      "Within-subject factors", "Number of participants",
      "Output directory", "Statistical workbook", "Figures PDF",
      "Enabled factors", "Dependent variables", "Alpha",
      "Post-hoc p-value adjustment", "Sphericity correction", "Method selection",
      "Parametric model", "ART model",
      "Correlation analysis enabled", "Correlation variables",
      "Correlation data unit", "Correlation method selection",
      "Correlation p-value adjustment", "R version", "Analysis started",
      "Analysis completed", "Elapsed seconds"
    ),
    Value = c(
      ENGINE_PATH, attr(config, "config_path"), input_file,
      as.character(config$input$sheet %||% "First sheet"),
      config$input$data_format %||% "wide",
      design$type,
      if (length(design$between) > 0L) paste(design$between, collapse = " × ") else "None",
      if (length(design$within) > 0L) paste(design$within, collapse = " × ") else "None",
      dplyr::n_distinct(analysis_data$ID),
      output_root, output_paths$workbook,
      if (file.exists(output_paths$figures)) output_paths$figures else NA_character_,
      paste0(factor_spec$label, " [", factor_spec$role, "]", collapse = " × "),
      nrow(outcome_spec), config$analysis$alpha, posthoc_p_adjust_info$display_label,
      if (design$has_repeated) toupper(config$analysis$sphericity_correction %||% "GG") else "Not applicable",
      config$analysis$method_selection,
      if (design$has_repeated) {
        paste0(
          "afex::aov_ez Type ", config$analysis$anova_type %||% 3L,
          ": Y ~ ", paste(factor_codes, collapse = " * "),
          "; ID = participant"
        )
      } else {
        paste0("lm/car::Anova Type ", config$analysis$anova_type %||% 3L, ": Y ~ ", paste(factor_codes, collapse = " * "))
      },
      paste0(
        "ARTool::art Type ", config$analysis$anova_type %||% 3L, ": Y ~ ",
        paste(factor_codes, collapse = " * "),
        if (design$has_repeated) " + (1|ID)" else ""
      ),
      get_correlation_config(config)$enabled,
      if (get_correlation_config(config)$enabled) sum(outcome_spec$include_in_correlation %in% TRUE) else 0L,
      if (design$has_repeated) "Participant-level means across repeated conditions" else "Rows / participants",
      if (get_correlation_config(config)$enabled && !is.na(correlation_analysis$selected_method)) {
        paste0(correlation_analysis$selected_method, ": ", correlation_analysis$method_selection_reason)
      } else if (get_correlation_config(config)$enabled) {
        "Enabled, but fewer than two eligible variables were available."
      } else {
        "Disabled"
      },
      correlation_p_adjust_info$display_label, R.version.string,
      format(analysis_start_time), format(analysis_end_time),
      round(as.numeric(difftime(analysis_end_time, analysis_start_time, units = "secs")), 3)
    )
  )

  # Keep run metadata design-specific as well: do not retain rows whose
  # concepts are structurally inapplicable to the configured design.
  if (identical(design$type, "between-subjects")) {
    run_info <- run_info |>
      dplyr::filter(!.data$Item %in% c("Within-subject factors", "Sphericity correction"))
  } else if (identical(design$type, "within-subjects")) {
    run_info <- run_info |>
      dplyr::filter(.data$Item != "Between-subject factors")
  }

  # Build worksheets by logical order first. Conditional worksheets are simply
  # omitted; numbering is assigned only after the final list is known, so the
  # workbook always uses contiguous 00, 01, 02, ... sheet prefixes.
  sheet_data <- list(
    Run_Info = run_info,
    Analysis_Summary = analysis_summary,
    Outcome_Spec = outcome_spec_table,
    Factor_Spec = factor_level_table,
    Design_Cell_Counts = design_cell_counts,
    Conversion_Report = prepared$conversion_report,
    Missing_Summary = missing_summary,
    Assumption_Tests = assumptions_output
  )
  if (design$has_repeated) {
    sheet_data$Sphericity_Tests <- sphericity_tests
  }
  sheet_data <- c(
    sheet_data,
    list(
      Cell_Shapiro = cell_shapiro,
      Model_Summary = model_summary_output,
      Overall_Desc = overall_descriptive,
      Main_Desc = main_descriptive,
      Interaction_Desc = interaction_descriptive,
      Omnibus_Effects = omnibus,
      Significant_Effects = significant_effects,
      Main_Posthoc = main_posthoc,
      Interaction_Cells = interaction_cells,
      Interaction_Contrasts = interaction_contrasts,
      Correlation_Normality = correlation_analysis$variable_normality,
      Correlation_Results = correlation_analysis$results,
      Correlation_Coeff = correlation_analysis$coefficient_matrix,
      Correlation_Adj_p = correlation_analysis$adjusted_p_matrix,
      Correlation_Methods = correlation_analysis$method_matrix,
      Plot_Index = plot_index,
      Warnings_Errors = warnings_errors
    )
  )
  sheet_data <- renumber_sheet_data(sheet_data)

  write_results_workbook(sheet_data, output_paths$workbook, config$analysis$alpha, factor_codes, config)

  if (isTRUE(config$output$save_logs)) {
    writeLines(capture.output(sessionInfo()), file.path(output_paths$logs_dir, "sessionInfo.txt"), useBytes = TRUE)
    file.copy(attr(config, "config_path"), file.path(output_paths$logs_dir, "configuration_used.R"), overwrite = TRUE)
    file.copy(ENGINE_PATH, file.path(output_paths$logs_dir, "analysis_engine_used.R"), overwrite = TRUE)
    writeLines(
      c(
        paste0("Post-hoc p-value adjustment actually used: ", posthoc_p_adjust_info$display_label, " [", config$analysis$p_adjust_method, "]"),
        paste0("Correlation p-value adjustment actually used: ", correlation_p_adjust_info$display_label, " [", config$correlation$p_adjust_method, "]"),
        paste0("Function override - posthoc_p_adjust_method: ", posthoc_p_adjust_method %||% "NULL (CONFIG/default)"),
        paste0("Function override - correlation_p_adjust_method: ", correlation_p_adjust_method %||% "NULL (CONFIG/default)")
      ),
      file.path(output_paths$logs_dir, "p_adjustment_methods_used.txt"),
      useBytes = TRUE
    )
  }

  close_script_sink()
  message("Analysis completed. Results: ", output_root)

  invisible(list(
    configuration = config,
    data = analysis_data,
    outcomes = outcome_spec,
    factors = factor_spec,
    results = results_by_outcome,
    correlations = correlation_analysis,
    workbook = output_paths$workbook,
    figures = output_paths$figures,
    output_directory = output_root
  ))
}

if (sys.nframe() == 0L) {
  trailing_arguments <- commandArgs(trailingOnly = TRUE)
  default_config <- file.path(ENGINE_DIR, "configs", "Config_Example_1_Default_TVCG.R")
  selected_config <- if (length(trailing_arguments) >= 1L) trailing_arguments[[1]] else default_config
  run_analysis(selected_config)
}
