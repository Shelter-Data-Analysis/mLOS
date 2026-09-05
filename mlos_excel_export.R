# mLOS - Export Consolidated Excel Workbook
# =======================================================================
# ---- Per-sheet helper functions (used by write_results_excel) ----

.excel_make_period_row <- function(measure, values, period_labels) {
  row_df <- data.frame(Measure = measure, stringsAsFactors = FALSE)
  for (j in seq_along(period_labels)) {
    row_df[[period_labels[j]]] <- values[j]
  }
  row_df
}

.excel_period_rows <- function(measures_list, period_labels) {
  lapply(names(measures_list), function(measure) {
    .excel_make_period_row(measure, measures_list[[measure]], period_labels)
  })
}

# Period-metadata typed rows (start/end dates and duration, one column per
# period). Shared by the By_Period sheet and the General cover sheet so
# the two stay identical. End dates are exclusive (see the section title).
.period_metadata_typed_rows <- function(periods) {
  .excel_period_rows(
    list(
      start_date    = as.character(periods$start_date),
      end_date      = as.character(periods$end_date),
      duration_days = as.numeric(periods$duration_days)
    ),
    as.character(periods$period_label)
  )
}

.excel_write_rowwise_table <- function(wb, sheet, row_dfs, start_row, start_col = 1) {
  if (length(row_dfs) == 0) {
    return(start_row)
  }
  # The header must be a one-row data.frame: a character vector would be
  # written as a column, leaving only "Measure" visible after the data rows
  # overwrite the rest (same gotcha as in .excel_write_kv_table).
  header <- data.frame(as.list(names(row_dfs[[1]])), stringsAsFactors = FALSE)
  openxlsx::writeData(
    wb, sheet, header,
    startRow = start_row, startCol = start_col, colNames = FALSE
  )
  data_start <- start_row + 1
  for (i in seq_along(row_dfs)) {
    openxlsx::writeData(
      wb, sheet, row_dfs[[i]],
      startRow = data_start + i - 1, startCol = start_col, colNames = FALSE
    )
  }
  data_start + length(row_dfs) - 1
}

.is_non_integer_numeric <- function(x, tol = 1e-9) {
  x <- suppressWarnings(as.numeric(x))
  x <- x[is.finite(x)]
  if (length(x) == 0) return(FALSE)
  any(abs(x - round(x)) > tol)
}

.excel_style_for_values <- function(values, num_style_int, num_style_float) {
  if (.is_non_integer_numeric(values)) num_style_float else num_style_int
}

.excel_apply_row_num_style <- function(wb, sheet, values, row, cols, num_style_int, num_style_float) {
  if (is.null(num_style_int) || is.null(num_style_float) || !is.numeric(values)) {
    return(invisible(NULL))
  }
  openxlsx::addStyle(
    wb, sheet,
    .excel_style_for_values(values, num_style_int, num_style_float),
    rows = row, cols = cols, gridExpand = TRUE, stack = TRUE
  )
  invisible(NULL)
}

.excel_apply_table_num_styles <- function(wb, sheet, df, start_row, value_cols,
                                          num_style_int, num_style_float) {
  if (is.null(df) || nrow(df) == 0) return(invisible(NULL))

  for (i in seq_len(nrow(df))) {
    row_vals <- unlist(df[i, value_cols, drop = FALSE], use.names = FALSE)
    .excel_apply_row_num_style(
      wb, sheet, row_vals, start_row + i - 1, value_cols,
      num_style_int, num_style_float
    )
  }
  invisible(NULL)
}

# A section heading: a short bold phrase in the first cell, and whatever
# clarifies it in the second, rather than the two run together in one cell with
# the clarification in parentheses. Splitting them lets the heading be read and
# matched on its own, and gives the explanation room to run along the row,
# which on a heading row is empty anyway. A parenthetical carrying only a
# symbol, "Weibull shape (k)", is part of the phrase and stays in the first
# cell. Returns the next free row.
.excel_write_section_title <- function(wb, sheet, row, title, note = NULL,
                                       title_style = NULL) {
  openxlsx::writeData(wb, sheet, title, startRow = row, startCol = 1, colNames = FALSE)
  if (!is.null(title_style)) {
    openxlsx::addStyle(wb, sheet, title_style, rows = row, cols = 1)
  }
  if (!is.null(note)) {
    openxlsx::writeData(wb, sheet, note, startRow = row, startCol = 2, colNames = FALSE)
  }
  row + 1
}

# One labeled estimate row: the label in column 1 and estimate, lower, upper
# as three numeric cells in columns 2:4, the same columns the ratio tables put
# their value / ci_95_lower / ci_95_upper in, so a scalar triplet lines up
# under the table it belongs with. Numbers as numbers, never a formatted
# "[lo, hi]" string. Callers advance their own row counter.
.excel_write_estimate_row <- function(wb, sheet, row, label, est, lo, hi,
                                      num_style_int = NULL, num_style_float = NULL) {
  openxlsx::writeData(wb, sheet,
                      data.frame(label, est, lo, hi, stringsAsFactors = FALSE),
                      startRow = row, startCol = 1, colNames = FALSE)
  .excel_apply_row_num_style(wb, sheet, c(est, lo, hi), row, 2:4,
                             num_style_int, num_style_float)
  invisible(NULL)
}

.excel_write_kv_table <- function(wb, sheet, metrics, values, start_row, start_col = 1,
                                  num_style_int = NULL, num_style_float = NULL) {
  # Header must be a one-row data.frame: a character vector would be written
  # as a column, putting "Value" under "Metric" where the first data row
  # then overwrites it.
  openxlsx::writeData(
    wb, sheet, data.frame("Metric", "Value", stringsAsFactors = FALSE),
    startRow = start_row, startCol = start_col, colNames = FALSE
  )
  for (i in seq_along(metrics)) {
    # A missing value arrives either as NA or, from a bundle read back out of
    # JSON, as NULL: JSON has one way to say "no value", so an NA scalar and an
    # absent field both come back empty. Both mean the same thing on a
    # worksheet, so both are written as a blank-looking NA cell.
    value <- if (length(values[[i]]) == 0) NA else values[[i]]
    row_df <- data.frame(Metric = metrics[i], Value = value, stringsAsFactors = FALSE)
    row_num <- start_row + i
    openxlsx::writeData(wb, sheet, row_df, startRow = row_num, startCol = start_col, colNames = FALSE)
    if (is.numeric(value)) {
      .excel_apply_row_num_style(
        wb, sheet, value, row_num, start_col + 1,
        num_style_int, num_style_float
      )
    }
  }
  start_row + length(metrics)
}

# Reference-level column shared by the Cox and Weibull sheets: a "Reference"
# header at (header_row, col 3) and, next to each predictor-group count, the
# level the fit used -- the first xlevels level, since relevel() in
# cox_regression_analysis puts the reference first. A term not in the model
# (dropped period term, absent column) leaves a blank cell. The period levels
# ARE the period labels, so no lookup is needed.
.excel_write_reference_column <- function(wb, sheet, xlev, overview_metrics, header_row) {
  predictor_refs <- c(
    "Predictor groups: period"       = if ("period" %in% names(xlev)) xlev[["period"]][1] else NA_character_,
    "Predictor groups: intake_type"  = if ("intake_type" %in% names(xlev)) xlev[["intake_type"]][1] else NA_character_,
    "Predictor groups: animal_group" = if ("animal_group" %in% names(xlev)) xlev[["animal_group"]][1] else NA_character_
  )
  openxlsx::writeData(wb, sheet, "Reference",
                      startRow = header_row, startCol = 3, colNames = FALSE)
  for (metric in names(predictor_refs)[!is.na(predictor_refs)]) {
    openxlsx::writeData(wb, sheet, predictor_refs[[metric]],
                        startRow = header_row + match(metric, overview_metrics),
                        startCol = 3, colNames = FALSE)
  }
  invisible(NULL)
}

write_cox_regression_sheet <- function(wb, cox, coverage, title_style, num_style_int, num_style_float) {
  openxlsx::addWorksheet(wb, "Cox_Regression")
  openxlsx::setColWidths(wb, "Cox_Regression", cols = 1, widths = 30)
  openxlsx::setColWidths(wb, "Cox_Regression", cols = 2:20, widths = 13)

  if (!isTRUE(cox$has_analysis)) {
    openxlsx::writeData(
      wb, "Cox_Regression",
      data.frame(Note = "Cox regression not available: no predictors (single period, no intake_type or animal_group columns)."),
      startRow = 1, startCol = 1
    )
    return(invisible(NULL))
  }

  next_row <- 1

  overview_metrics <- c(
    "Model formula", "N", "events", "Concordance", "concordance_se",
    "Uses clustered SE", "Predictor groups: period", "Predictor groups: intake_type",
    "Predictor groups: animal_group"
  )
  overview_values <- list(
    cox$formula,
    cox$n,
    cox$n_events,
    cox$concordance,
    cox$concordance_se,
    cox$uses_clustered_se,
    coverage$period$n,
    coverage$intake$n,
    coverage$group$n
  )

  tests <- cox$tests

  hr_export <- cox$hr_table[, c("variable", "hr", "ci_lower", "ci_upper", "p_value")]
  names(hr_export) <- c("variable", "hazard_ratio", "ci_95_lower", "ci_95_upper", "p_value")

  openxlsx::writeData(wb, "Cox_Regression", "Model overview", startRow = next_row,
                      startCol = 1, colNames = FALSE)
  openxlsx::addStyle(wb, "Cox_Regression", title_style, rows = next_row, cols = 1)
  overview_end <- .excel_write_kv_table(
    wb, "Cox_Regression", overview_metrics, overview_values,
    start_row = next_row + 1, num_style_int = num_style_int, num_style_float = num_style_float
  )

  .excel_write_reference_column(wb, "Cox_Regression", cox$xlevels,
                                overview_metrics, next_row + 1)

  next_row <- overview_end + 3

  openxlsx::writeData(wb, "Cox_Regression", "Model tests", startRow = next_row,
                      startCol = 1, colNames = FALSE)
  openxlsx::addStyle(wb, "Cox_Regression", title_style, rows = next_row, cols = 1)
  tests_start <- next_row + 1
  openxlsx::writeData(wb, "Cox_Regression", tests, startRow = next_row + 1, startCol = 1)
  .excel_apply_table_num_styles(
    wb, "Cox_Regression", tests,
    start_row = tests_start + 1, value_cols = 2:4,
    num_style_int, num_style_float
  )
  next_row <- next_row + nrow(tests) + 3

  openxlsx::writeData(wb, "Cox_Regression", "Hazard ratios", startRow = next_row,
                      startCol = 1, colNames = FALSE)
  openxlsx::addStyle(wb, "Cox_Regression", title_style, rows = next_row, cols = 1)
  hr_start <- next_row + 1
  openxlsx::writeData(wb, "Cox_Regression", hr_export, startRow = next_row + 1, startCol = 1)
  .excel_apply_table_num_styles(
    wb, "Cox_Regression", hr_export,
    start_row = hr_start + 1, value_cols = 2:5,
    num_style_int, num_style_float
  )
}

# Weibull sheet (only when parametric_regression: WEIBULL): the same three
# blocks as the Cox sheet, cell-for-cell comparable -- overview rows without a
# Weibull counterpart hold NA, and the "Hazard ratios" block carries the HRs
# implied by the fit (hr = LOS_ratio^(-k)) so agreement with the Cox sheet can
# be read off directly -- plus a fourth, practitioner-facing "LOS ratios"
# block with the shape parameter and its plain-language reading, and a final
# "Crude Weibull" block: the same fit with the group terms dropped
# (intercept + period only), whose shape describes the pooled process.
# .fit_weibull's verdict on a fit, as a worksheet value. Always written, never
# conditional on there being something wrong: a row that appears only on the
# runs with a problem is a row nobody knows to look for, and its absence reads
# as "not checked" rather than as "checked and fine".
.excel_fit_stability <- function(unstable) {
  if (is.null(unstable) || is.na(unstable)) return("ok")
  paste0("approximate confidence intervals: ", unstable)
}

write_weibull_regression_sheet <- function(wb, wres, cox_has_analysis, coverage,
                                           title_style, num_style_int, num_style_float) {
  openxlsx::addWorksheet(wb, "Weibull_Regression")
  openxlsx::setColWidths(wb, "Weibull_Regression", cols = 1, widths = 30)
  openxlsx::setColWidths(wb, "Weibull_Regression", cols = 2:20, widths = 13)

  if (!isTRUE(wres$has_analysis)) {
    msg <- if (!isTRUE(cox_has_analysis)) {
      "Weibull regression not available: no predictors (single period, no intake_type or animal_group columns)."
    } else {
      paste0("Weibull regression not available: ", wres$message, ".")
    }
    openxlsx::writeData(wb, "Weibull_Regression", data.frame(Note = msg),
                        startRow = 1, startCol = 1)
    return(invisible(NULL))
  }

  next_row <- 1

  overview_metrics <- c(
    "Model formula", "N", "events", "Fit stability", "Concordance", "concordance_se",
    "Uses clustered SE", "Predictor groups: period", "Predictor groups: intake_type",
    "Predictor groups: animal_group"
  )
  overview_values <- list(
    paste0(wres$formula, "  (dist = weibull)"),
    wres$n,
    wres$n_events,
    .excel_fit_stability(wres$fit_unstable),
    NA_real_,   # no concordance counterpart; row kept so the sheets align
    NA_real_,
    FALSE,      # SEs are model-based (Hessian), not clustered -- see math doc 6.6
    coverage$period$n,
    coverage$intake$n,
    coverage$group$n
  )

  openxlsx::writeData(wb, "Weibull_Regression", "Model overview", startRow = next_row,
                      startCol = 1, colNames = FALSE)
  openxlsx::addStyle(wb, "Weibull_Regression", title_style, rows = next_row, cols = 1)
  overview_end <- .excel_write_kv_table(
    wb, "Weibull_Regression", overview_metrics, overview_values,
    start_row = next_row + 1, num_style_int = num_style_int, num_style_float = num_style_float
  )
  .excel_write_reference_column(wb, "Weibull_Regression", wres$xlevels,
                                overview_metrics, next_row + 1)
  next_row <- overview_end + 3

  # Model tests: identical table shape to the Cox sheet; only the
  # likelihood-ratio test has a Weibull counterpart (vs the null model).
  has_lr <- !is.null(wres$lr)
  tests <- data.frame(
    test      = c("Likelihood ratio", "Wald", "Score (logrank)", "Robust score"),
    statistic = c(if (has_lr) wres$lr$stat else NA_real_, NA_real_, NA_real_, NA_real_),
    df        = c(if (has_lr) wres$lr$df   else NA_real_, NA_real_, NA_real_, NA_real_),
    p_value   = c(if (has_lr) wres$lr$p    else NA_real_, NA_real_, NA_real_, NA_real_),
    stringsAsFactors = FALSE
  )
  openxlsx::writeData(wb, "Weibull_Regression", "Model tests", startRow = next_row,
                      startCol = 1, colNames = FALSE)
  openxlsx::addStyle(wb, "Weibull_Regression", title_style, rows = next_row, cols = 1)
  openxlsx::writeData(wb, "Weibull_Regression", tests, startRow = next_row + 1, startCol = 1)
  .excel_apply_table_num_styles(
    wb, "Weibull_Regression", tests,
    start_row = next_row + 2, value_cols = 2:4,
    num_style_int, num_style_float
  )
  next_row <- next_row + nrow(tests) + 3

  hr_export <- wres$hr_table[, c("variable", "hr", "ci_lower", "ci_upper", "p_value")]
  names(hr_export) <- c("variable", "hazard_ratio", "ci_95_lower", "ci_95_upper", "p_value")
  next_row <- .excel_write_section_title(
    wb, "Weibull_Regression", next_row, "Hazard ratios",
    "implied: hr = LOS_ratio^(-k); compare with the Cox sheet", title_style
  )
  openxlsx::writeData(wb, "Weibull_Regression", hr_export, startRow = next_row, startCol = 1)
  .excel_apply_table_num_styles(
    wb, "Weibull_Regression", hr_export,
    start_row = next_row + 1, value_cols = 2:5,
    num_style_int, num_style_float
  )
  next_row <- next_row + nrow(hr_export) + 3

  los_export <- wres$los_table[, c("variable", "los_ratio", "ci_lower", "ci_upper", "p_value")]
  names(los_export) <- c("variable", "los_ratio", "ci_95_lower", "ci_95_upper", "p_value")
  openxlsx::writeData(wb, "Weibull_Regression", "LOS ratios", startRow = next_row,
                      startCol = 1, colNames = FALSE)
  openxlsx::addStyle(wb, "Weibull_Regression", title_style, rows = next_row, cols = 1)
  openxlsx::writeData(wb, "Weibull_Regression", los_export, startRow = next_row + 1, startCol = 1)
  .excel_apply_table_num_styles(
    wb, "Weibull_Regression", los_export,
    start_row = next_row + 2, value_cols = 2:5,
    num_style_int, num_style_float
  )
  next_row <- next_row + nrow(los_export) + 2

  openxlsx::writeData(
    wb, "Weibull_Regression",
    "A LOS ratio of 1.30 means stays run about 30% longer than the reference level; 0.75 means about 25% shorter.",
    startRow = next_row, startCol = 1, colNames = FALSE
  )
  next_row <- next_row + 2

  # A section like any other rather than a bold data row: what follows a blank
  # row is a heading, so the value goes underneath, labeled with the bundle's
  # own name for it. Estimate, lower, upper in three cells of their own, under
  # the same columns the LOS-ratio table above uses for them. Not one cell
  # holding a formatted "0.822 [0.812, 0.831]": a bound written as text cannot
  # be charted, sorted, or read back by a script.
  next_row <- .excel_write_section_title(
    wb, "Weibull_Regression", next_row, "Weibull shape (k)",
    "estimate, lower, upper", title_style
  )
  .excel_write_estimate_row(wb, "Weibull_Regression", next_row, "shape",
                            wres$shape, wres$shape_lo, wres$shape_hi,
                            num_style_int, num_style_float)
  shape_legend <- c(
    "k < 1: discharge hazard falls with time in care, so there are more long residents and LOS differences between groups are larger than the hazard ratios suggest.",
    "k = 1: constant hazard; LOS ratio = 1/HR.",
    "k > 1: discharge hazard rises with time in care, so there are fewer long residents and LOS differences are smaller than the hazard ratios suggest.",
    "LOS ratios describe full stays under the fitted model; restricted means (which stop at the stay cap) differ slightly."
  )
  openxlsx::writeData(wb, "Weibull_Regression", shape_legend,
                      startRow = next_row + 1, startCol = 1, colNames = FALSE)
  # +1 past the last legend line: one blank row before the next heading, as
  # everywhere else on the sheet.
  next_row <- next_row + 1 + length(shape_legend) + 1

  # Unified companion: the same Weibull with the group terms dropped
  # (intercept + period only), so its shape describes the pooled
  # discharge process (see .weibull_regression_analysis in mlos_cox.R).
  next_row <- .excel_write_section_title(
    wb, "Weibull_Regression", next_row, "Crude Weibull", "intercept + period only", title_style
  )

  uni <- wres$crude
  if (!isTRUE(uni$has_analysis)) {
    openxlsx::writeData(wb, "Weibull_Regression",
                        paste0("Crude Weibull not available: ",
                               if (is.null(uni$message)) "not run" else uni$message, "."),
                        startRow = next_row, startCol = 1, colNames = FALSE)
    return(invisible(NULL))
  }
  if (isTRUE(uni$same_as_main)) {
    openxlsx::writeData(wb, "Weibull_Regression",
                        "The model above has no intake_type or animal_group terms, so it already is the crude fit.",
                        startRow = next_row, startCol = 1, colNames = FALSE)
    return(invisible(NULL))
  }

  openxlsx::writeData(wb, "Weibull_Regression",
                      data.frame(c("Model formula", "N", "events", "Fit stability"),
                                 c(paste0(uni$formula, "  (dist = weibull)"),
                                   uni$n, uni$n_events,
                                   .excel_fit_stability(uni$fit_unstable)),
                                 stringsAsFactors = FALSE),
                      startRow = next_row, startCol = 1, colNames = FALSE)
  next_row <- next_row + 4
  .excel_write_estimate_row(wb, "Weibull_Regression", next_row,
                            "Crude Weibull shape (k)",
                            uni$shape, uni$shape_lo, uni$shape_hi,
                            num_style_int, num_style_float)
  next_row <- next_row + 2

  if (nrow(uni$los_table) > 0) {
    uni_export <- uni$los_table[, c("variable", "los_ratio", "ci_lower", "ci_upper", "p_value")]
    names(uni_export) <- c("variable", "los_ratio", "ci_95_lower", "ci_95_upper", "p_value")
    next_row <- .excel_write_section_title(
      wb, "Weibull_Regression", next_row, "Crude period LOS ratios",
      "crude: no group adjustment", title_style
    )
    openxlsx::writeData(wb, "Weibull_Regression", uni_export, startRow = next_row, startCol = 1)
    .excel_apply_table_num_styles(
      wb, "Weibull_Regression", uni_export,
      start_row = next_row + 1, value_cols = 2:5,
      num_style_int, num_style_float
    )
    next_row <- next_row + nrow(uni_export) + 2
  }

  openxlsx::writeData(
    wb, "Weibull_Regression",
    "The pooled discharge process, with no group adjustment. A pooled k below 1 alongside an adjusted k near 1 signals a mix of fast and slow groups (the fast leavers drain out of the risk set first), not stays that stall with tenure.",
    startRow = next_row, startCol = 1, colNames = FALSE
  )
}

write_general_sheet <- function(wb, bundle, title_style,
                                        num_style_int = NULL, num_style_float = NULL) {
  settings <- bundle$settings
  outcome_type_mapping <- settings$outcome_type_mapping
  openxlsx::addWorksheet(wb, "General")
  openxlsx::setColWidths(wb, "General", cols = 1, widths = 30)
  openxlsx::setColWidths(wb, "General", cols = 2:20, widths = 13)
  next_row <- 1

  write_section <- function(title, df, start_row, note = NULL) {
    data_row <- .excel_write_section_title(wb, "General", start_row, title, note, title_style)
    openxlsx::writeData(wb, "General", df, startRow = data_row, startCol = 1, rowNames = FALSE)
    data_row + nrow(df) + 2
  }

  # A field is absent from a bundle written before the tool recorded it, and
  # rendering such a bundle is the point of mlos_render.R, so every cell falls
  # back to "(not recorded)" rather than dropping out of the vector and
  # unbalancing the two columns.
  run_items <- c("mlos_version", "generated_at", MLOS_VERSION_FIELDS,
                 "data_file", "settings_file", "output_dir", "log_file")
  run_info <- data.frame(
    Item  = run_items,
    Value = vapply(run_items, function(item) {
      value <- bundle$run[[item]]
      if (is.null(value)) "(not recorded)" else as.character(value)
    }, character(1)),
    stringsAsFactors = FALSE, row.names = NULL
  )
  next_row <- write_section("Run metadata", run_info, next_row)

  # Period metadata: the same start/end/duration block that leads the By_Period
  # sheet, repeated here so this cover sheet records the analysis windows. End
  # dates are exclusive (see the section title).
  next_row <- .write_stratum_section(
    wb, "General", next_row, "Period metadata", note = "end dates excluded",
    typed_rows = .period_metadata_typed_rows(settings$periods), title_style = title_style,
    num_style_int = num_style_int, num_style_float = num_style_float
  )

  # Observation gaps: stretches of days with no animal at risk, detected in
  # the unified KM (km_results$gaps) and per stratum in the stratified KM
  # (stratified_results$gaps). Statistics are NOT adjusted for gaps -- this
  # section is the workbook's record that they exist. Placed high, right after
  # the period metadata, so a reader cannot miss it. Green when empty, red when
  # not; see 'Observation gaps' in the User Guide for remedies.
  gap_red_style   <- openxlsx::createStyle(fgFill = "#FFC7CE", fontColour = "#9C0006")
  gap_green_style <- openxlsx::createStyle(fgFill = "#C6EFCE", fontColour = "#006100")

  gaps_table <- bundle$unified$gaps

  next_row <- .excel_write_section_title(wb, "General", next_row, "Observation gaps",
                                         "days with no animal at risk", title_style)
  if (is.null(gaps_table) || nrow(gaps_table) == 0) {
    openxlsx::writeData(wb, "General",
                        data.frame(Status = "No observation gaps detected.", stringsAsFactors = FALSE),
                        startRow = next_row, startCol = 1, colNames = FALSE)
    openxlsx::addStyle(wb, "General", gap_green_style,
                       rows = next_row, cols = 1, stack = TRUE)
    next_row <- next_row + 3
  } else {
    openxlsx::writeData(wb, "General", gaps_table, startRow = next_row, startCol = 1)
    openxlsx::addStyle(wb, "General", gap_red_style,
                       rows = next_row:(next_row + nrow(gaps_table)),
                       cols = 1:ncol(gaps_table), gridExpand = TRUE, stack = TRUE)
    .excel_apply_table_num_styles(
      wb, "General", gaps_table,
      start_row = next_row + 1, value_cols = 3:4,
      num_style_int, num_style_float
    )
    next_row <- next_row + nrow(gaps_table) + 3
  }

  # analysis settings that affect the substantive computation or interpretation
  # of results. Deliberately excluded: plot-only cosmetics (plot_stay_cap, the
  # png_* factors, max_plot_strata, the CI-ribbon toggles) and the
  # output-emission flags. The raw-label -> L/T/N relabeling is substantive too
  # but keeps its own "Outcome type mapping" section below; the two outcome
  # settings that DROP rows or reclassify outcomes as censored are shown here.
  # restricted_stay_cap also appears in Unified KM detail below; it leads here
  # as the headline knob.
  fmt_ref <- function(x) if (is.null(x)) "(default)" else as.character(x)
  fmt_group_cols <- function(cols) if (is.null(cols)) "(default)" else paste(cols, collapse = ", ")
  fmt_parametric <- function(p) if (isFALSE(p)) "FALSE (Cox only)" else as.character(p)
  fmt_labels <- function(x) if (length(x) == 0) "(none)" else paste(x, collapse = ", ")
  fmt_filter <- function(f) {
    if (is.null(f)) return("(none)")
    col_tag <- if (!is.null(f$column)) paste0(" [", f$column, "]") else ""
    paste0(f$mode, col_tag, ": ", paste(f$values, collapse = ", "))
  }
  settings_metrics <- c(
    "Restricted stay cap (days)",
    "Period reference",
    "Intake type reference",
    "Animal group reference",
    "Animal group columns",
    "Parametric regression",
    "Discard bad rows",
    "Discard overlapping rows",
    "Intake filter",
    "Animal group filter",
    "Other filter",
    "Outcome types deleted",
    "Outcome types treated as in-care"
  )
  settings_values <- list(
    settings$restricted_stay_cap,
    settings$period_reference,
    fmt_ref(settings$intake_type_reference),
    fmt_ref(settings$animal_group_reference),
    fmt_group_cols(settings$animal_group_columns),
    fmt_parametric(settings$parametric_regression),
    as.character(settings$discard_bad_rows),
    as.character(settings$discard_overlapping_rows),
    fmt_filter(settings$intake_filter),
    fmt_filter(settings$animal_group_filter),
    fmt_filter(settings$other_filter),
    fmt_labels(settings$outcome_type_delete),
    fmt_labels(settings$outcome_type_in_care)
  )
  next_row <- .excel_write_section_title(
    wb, "General", next_row, "Analysis settings",
    "substantive; excludes plot and output-emission settings", title_style
  )
  settings_end <- .excel_write_kv_table(
    wb, "General", settings_metrics, settings_values,
    start_row = next_row, num_style_int = num_style_int, num_style_float = num_style_float
  )
  next_row <- settings_end + 3

  # The full unified analysis (counts, KM medians and restricted means, census
  # aggregates, outcome mix, incidence, and AJ competing risks) lives on the
  # By_All sheet, built with the stratum-sheet machinery so it is structurally
  # identical to By_Intake_Type / By_Animal_Group with a single pooled column.
  # A few unified facts do not fit that shared layout and stay here: the overall
  # study window, the restricted stay cap and the fraction of stays it bound, and
  # the unified median, 90th percentile, still-in-care-at-cap and restricted
  # mean -- the same four KM Length of Stay figures the By_All sheet carries per
  # column, repeated here as a quick headline. Confidence bounds are not shown
  # here; the stratum sheets (By_All included) carry them in their closing CI
  # section.
  #
  # "Fraction capped" and "Still in care at cap (fitted)" are the observed and
  # fitted readings of one event, kept apart in the list so neither is mistaken
  # for the other.
  km_detail_metrics <- c(
    "Study period start", "Study period end", "Restricted stay cap", "Fraction capped",
    "Median LOS", "P90 LOS", "Still in care at cap (fitted)", "Restricted mean LOS"
  )
  km_detail_values <- list(
    bundle$unified$study_start,
    bundle$unified$study_end,
    bundle$unified$restricted_stay_cap,
    bundle$unified$fraction_capped,
    bundle$unified$median_los,
    bundle$unified$percentile_90,
    bundle$unified$still_in_care_at_cap,
    bundle$unified$restricted_mean
  )
  # By_All always carries the fuller unified analysis, whatever the period
  # structure, so this pointer is fixed.
  next_row <- .excel_write_section_title(wb, "General", next_row, "Unified KM detail",
                                         "fuller unified analysis on By_All", title_style)
  km_detail_end <- .excel_write_kv_table(
    wb, "General", km_detail_metrics, km_detail_values,
    start_row = next_row, num_style_int = num_style_int, num_style_float = num_style_float
  )
  next_row <- km_detail_end + 3

  coverage <- settings$coverage
  strat_summary <- data.frame(
    dimension   = vapply(coverage, function(d) d$label, character(1), USE.NAMES = FALSE),
    included    = vapply(coverage, function(d) d$included, logical(1), USE.NAMES = FALSE),
    group_count = vapply(coverage, function(d) as.numeric(d$n), numeric(1), USE.NAMES = FALSE),
    stringsAsFactors = FALSE
  )
  next_row <- write_section("Stratified analysis coverage", strat_summary, next_row)

  if (!is.null(outcome_type_mapping)) {
    mapping_df <- data.frame(
      your_label     = names(outcome_type_mapping),
      canonical_code = unname(outcome_type_mapping),
      stringsAsFactors = FALSE
    )
    mapping_df <- mapping_df[order(mapping_df$canonical_code, mapping_df$your_label), ]
    next_row <- write_section("Outcome type mapping", mapping_df, next_row,
                              note = "your labels to L/T/N")
  }

}


# Drop the columns of a ledger table that are empty for this run, so the sheet
# does not show a blank column as if it were a missing result. The one that
# actually goes is animal_id_*, on a run whose ids the tool generated.
.drop_empty_ledger_cols <- function(df) {
  keep <- vapply(df, function(v) any(!is.na(v) & trimws(as.character(v)) != ""),
                 logical(1))
  df[, keep, drop = FALSE]
}

# The screening ledger as a worksheet: how the rows of the CSV became the
# animal-period rows every other sheet counts.
#
# The same table goes to data_preparation_stats.csv, in the stacked
# ShelterDataPrep layout that lets the two projects' files be read together
# (see build_screening_ledger). Here it is split back into its two tables and
# the columns belonging to the other one are dropped, because in a spreadsheet a
# blank column reads as a bug rather than as a section marker. Both come from
# the one frame, so this is a projection and cannot state different numbers.
write_data_preparation_sheet <- function(wb, bundle, title_style,
                                         num_style_int = NULL, num_style_float = NULL) {
  # Widths serve both tables at once, so the columns line up down the sheet:
  # 1 step, 2 action, 3 column, then counts (and the detail table's short
  # role/value/scope), with the one prose column last so it can spill right
  # instead of pushing the counts off the screen.
  openxlsx::addWorksheet(wb, "Data_Preparation")
  openxlsx::setColWidths(wb, "Data_Preparation", cols = 1, widths = 8)
  openxlsx::setColWidths(wb, "Data_Preparation", cols = 2, widths = 12)
  openxlsx::setColWidths(wb, "Data_Preparation", cols = 3, widths = 40)
  openxlsx::setColWidths(wb, "Data_Preparation", cols = 4:9, widths = 18)
  openxlsx::setColWidths(wb, "Data_Preparation", cols = 10, widths = 90)

  ledger <- build_screening_ledger(bundle$data_preparation)
  if (is.null(ledger)) {
    openxlsx::writeData(
      wb, "Data_Preparation",
      data.frame(Note = "This run carries no data-preparation register.",
                 stringsAsFactors = FALSE),
      startRow = 1, startCol = 1, colNames = FALSE
    )
    return(invisible(NULL))
  }

  stages <- .drop_empty_ledger_cols(
    ledger[ledger$section == "stage",
           c("step", "action", "column", "rows_in", "rows_affected", "rows_out",
             "animal_id_in", "animal_id_affected", "animal_id_out", "detail")])
  next_row <- .excel_write_section_title(
    wb, "Data_Preparation", 1, "Row flow",
    "one row per screening stage, in the order it ran", title_style)
  openxlsx::writeData(wb, "Data_Preparation", stages, startRow = next_row, startCol = 1)
  .excel_apply_table_num_styles(wb, "Data_Preparation", stages, next_row + 1,
                                which(names(stages) != "step" &
                                      vapply(stages, is.numeric, logical(1))),
                                num_style_int, num_style_float)
  next_row <- next_row + nrow(stages) + 3

  # rows_in exceeds rows_out at the split, and saying so here saves a reader
  # deciding whether they have found a bug. Placed under the table it explains.
  openxlsx::writeData(
    wb, "Data_Preparation",
    paste("Counts chain from one stage to the next. A cut or dedup stage ends",
          "with fewer rows than it began with, a map stage rewrites rows without",
          "removing any, and the split turns each stay into one row per period it",
          "is observed in, which is the one stage whose count rises. Rows are",
          "stays until the split and animal-period rows after it."),
    startRow = next_row, startCol = 1, colNames = FALSE
  )
  next_row <- next_row + 2

  detail <- ledger[ledger$section == "detail", , drop = FALSE]
  if (nrow(detail) == 0) return(invisible(NULL))

  detail <- .drop_empty_ledger_cols(
    detail[, c("step", "action", "column", "role", "value", "scope",
               "rows_affected", "animal_id_affected")])
  next_row <- .excel_write_section_title(
    wb, "Data_Preparation", next_row, "By value",
    "one row per value your settings name, counted within the rows that stage touched",
    title_style)
  openxlsx::writeData(wb, "Data_Preparation", detail, startRow = next_row, startCol = 1)
  .excel_apply_table_num_styles(wb, "Data_Preparation", detail, next_row + 1,
                                which(names(detail) != "step" &
                                      vapply(detail, is.numeric, logical(1))),
                                num_style_int, num_style_float)
  next_row <- next_row + nrow(detail) + 2

  openxlsx::writeData(
    wb, "Data_Preparation",
    paste("A value showing 0 matched nothing in this file. That is worth",
          "checking: it is what a misspelled or differently cased setting looks",
          "like, and a value your data no longer carries looks the same."),
    startRow = next_row, startCol = 1, colNames = FALSE
  )
  invisible(NULL)
}


.write_stratum_section <- function(wb, sheet, start_row, title, df = NULL, title_style,
                                   num_style_int = NULL, num_style_float = NULL,
                                   typed_rows = NULL, shade_triplet_estimates = FALSE,
                                   note = NULL) {
  data_start <- .excel_write_section_title(wb, sheet, start_row, title, note, title_style)
  if (!is.null(typed_rows)) {
    data_end <- .excel_write_rowwise_table(wb, sheet, typed_rows, data_start)
    n_rows <- length(typed_rows) + 1
    if (!is.null(num_style_int) && !is.null(num_style_float)) {
      for (i in seq_along(typed_rows)) {
        vals <- unlist(typed_rows[[i]][, -1, drop = FALSE], use.names = FALSE)
        .excel_apply_row_num_style(
          wb, sheet, vals, data_start + i, 2:ncol(typed_rows[[1]]),
          num_style_int, num_style_float
        )
      }
    }
  } else {
    openxlsx::writeData(wb, sheet, df, startRow = data_start, startCol = 1, rowNames = FALSE)
    n_rows <- nrow(df) + 1
    if (!is.null(num_style_int) && !is.null(num_style_float)) {
      .excel_apply_table_num_styles(wb, sheet, df, data_start + 1, 2:ncol(df), num_style_int, num_style_float)
    }
    if (shade_triplet_estimates) {
      # Rows are estimate/lower/upper triplets in order (see the CI section
      # caller); shading just the estimate row of each triplet -- the first
      # of every three -- gives the eye a repeating anchor without touching
      # row counts or positions anything else depends on.
      estimate_rows <- data_start + seq(1, nrow(df), by = 3)
      shade_style <- openxlsx::createStyle(fgFill = "#F2F2F2")
      openxlsx::addStyle(wb, sheet, shade_style, rows = estimate_rows, cols = 1:ncol(df),
                         gridExpand = TRUE, stack = TRUE)
    }
  }
  start_row + n_rows + 2
}

# Write a single-line "not available" note to a stratum sheet when a
# section's data couldn't be computed, and advance the row by 3 (matching
# .write_stratum_section's blank-line spacing).
.write_stratum_note <- function(wb, sheet, row, message) {
  openxlsx::writeData(
    wb, sheet,
    data.frame(Note = message, stringsAsFactors = FALSE),
    startRow = row, startCol = 1
  )
  row + 3
}

# Convert a measures-by-strata matrix (rownames = measure names) into the
# Measure/label-columns data frame that .write_stratum_section expects.
.stratum_measure_df <- function(measure_matrix, labels) {
  df <- data.frame(
    Measure = rownames(measure_matrix),
    measure_matrix,
    check.names = FALSE,
    row.names = NULL,
    stringsAsFactors = FALSE
  )
  names(df)[-1] <- labels
  df
}


# Census-aggregates section note, shared by every sheet .write_stratum_measure_sections
# builds (By_Period, By_All, and the stratum sheets) so they all read identically.
# The heading itself is the bare "Census aggregates"; this is what sits beside it.
.census_section_note <- function() {
  paste("observed and expected census, elapsed/future animal-days,",
        "per-resident days, resident tenure quantiles within the cap")
}

# stratifier id -> the term-name prefix the shape variants' tables use for that
# predictor's rows. Read straight off the registry's model_term field, the same
# source .weibull_regression_analysis inverts for its own lookup, so the two
# cannot disagree and a new stratifier needs no entry here. Note that period's
# term is the temporary factor column cox_regression_analysis builds
# (period_data$period), NOT period_data's own period_label that the registry's
# col field names -- where this differs from a plain id/col lookup.
.STRATIFIER_ID_TO_TERM <- .stratifier_model_terms()

# id -> "Weibull_" + the stratifiers registry's own sheet_name, e.g.
# "Weibull_By_Animal_Group" -- the dedicated sheet write_weibull_by_stratifier_sheet
# below builds for that predictor's shape variant. Every stratifier is in here,
# period included: write_results_excel special-cases period only in the ORDER it
# writes the sheets (as it does for By_Period itself), not in how it names them,
# so this is the single place any of these sheet names is spelled out.
.STRATIFIER_ID_TO_WEIBULL_SHEET <- stats::setNames(
  paste0("Weibull_", vapply(stratifiers, function(s) s$sheet_name, character(1))),
  vapply(stratifiers, function(s) s$id, character(1))
)

# This stratifier's own rows from any los_table/hr_table-shaped data frame
# (columns variable/<value_col>/ci_lower/ci_upper), matched by level name --
# stripping the term prefix from each row's "variable", not by position, so
# a canonical-order mismatch between the two computations cannot silently
# misalign the columns. Returns a vector of NAs (one per label) when `tbl`
# is NULL or empty, rather than erroring: the general Cox and Weibull fits
# this section compares the shape variant against can in principle succeed
# or fail independently of it (see .stratifier_weibull_comparison_matrix).
.stratifier_own_rows <- function(tbl, scale_stratifier, labels, value_col) {
  na_rows <- rep(NA_real_, length(labels))
  if (is.null(tbl) || nrow(tbl) == 0) {
    return(list(value = na_rows, ci_lower = na_rows, ci_upper = na_rows))
  }
  own_prefix <- .STRATIFIER_ID_TO_TERM[[scale_stratifier]]
  own        <- tbl[startsWith(tbl$variable, own_prefix), ]
  level      <- sub(paste0("^", own_prefix), "", own$variable)
  idx        <- match(labels, level)
  list(value = own[[value_col]][idx], ci_lower = own$ci_lower[idx], ci_upper = own$ci_upper[idx])
}

# This stratifier's KM restricted-mean ratio rows, read off its own KM matrix
# (.with_restricted_mean_ratios, mlos_results.R) and matched by level name for
# the same reason .stratifier_own_rows matches by name: a column-order drift
# between two computations must not silently misalign the sheet. The whole
# block is absent from the matrix, not merely empty, when no reference level
# could be resolved -- which is when the Cox fit declined, since the reference
# is taken from the model that used it -- so the rows are read as NA then.
.stratum_km_ratio_rows <- function(km_matrix, labels) {
  na_rows <- rep(NA_real_, length(labels))
  if (is.null(km_matrix) || !all(KM_RATIO_ROWS %in% rownames(km_matrix))) {
    return(list(value = na_rows, ci_lower = na_rows, ci_upper = na_rows))
  }
  idx <- match(labels, colnames(km_matrix))
  list(value    = unname(km_matrix[KM_RATIO_ROWS[1], idx]),
       ci_lower = unname(km_matrix[KM_RATIO_ROWS[2], idx]),
       ci_upper = unname(km_matrix[KM_RATIO_ROWS[3], idx]))
}

# The two ratio blocks that close a By_Period/By_Intake_Type/By_Animal_Group
# sheet, each a "Measure x Label" matrix in the same estimate/ci_lower/ci_upper
# triplet layout every other section on that sheet uses, columns = this
# stratifier's own levels (`labels`, in the sheet's own column order):
#
#   Hazard ratios  cox_pooled_hazard_ratio        pooled Cox (6.1)
#                  cox_stratified_hazard_ratio    per-predictor stratified Cox (6.8)
#                  weibull_pooled_hazard_ratio    pooled Weibull's implied HR (6.6)
#
#   LOS ratios     km_restricted_mean_ratio       stratified KM (5.4), unadjusted
#                  weibull_freed_shape_los_ratio  per-predictor shape variant (6.7)
#                  weibull_pooled_los_ratio       pooled Weibull (6.6)
#
# Two blocks and not one because within each of them the values are rigorously
# comparable with one another, and the fits that produce comparable values are
# not the same on the two sides. The shape variant has an implied hazard ratio
# too, and it is deliberately absent from the first block: its k is the
# reference shape cell's, so the number describes one covariate combination
# rather than the data.
#
# Naming. Every regression row says which fit it came from, because on this
# sheet the fits are the only thing that distinguishes them: "pooled" is the
# fully adjusted single-shape/single-baseline model of 6.1 and 6.6, "freed
# shape" is 6.7's Weibull variant, "stratified" is 6.8's Cox variant, and the
# words are the ones the math methods and the deck vocabulary
# (mlos_review/names.py) already use. In particular "pooled" is NOT "crude":
# the crude Weibull is a different fit again, with the group terms dropped, and
# it lives on the Weibull_Regression sheet. Nor is it "global", which in the
# Cox sections means the model-level tests of 6.4 and would collide here. The
# KM row keeps the bundle's own name for it rather than being renamed into the
# block's *_los_ratio pattern: the block heading already says these are LOS
# ratios, and the name is what a reader greps back to results.json with.
#
# The Weibull rows sit at the bottom of both blocks, which is what lets them be
# dropped entirely -- not written as NA -- when the parametric fit is off:
# nothing was asked for, so there is nothing to report missing, and each block
# says so in a footnote instead. With it ON, a fit that declined or failed
# leaves its rows present and empty, something WAS asked for and did not
# arrive, which is a different fact and shows as one (see .stratifier_own_rows).
.stratifier_hazard_ratio_matrix <- function(sid, labels, cox_bundle, weibull_bundle,
                                            cox_stratified, weibull_on) {
  own <- function(tbl) .stratifier_own_rows(tbl, sid, labels, "hr")

  cox_hr    <- own(if (isTRUE(cox_bundle$has_analysis))     cox_bundle$hr_table     else NULL)
  cox_strat <- own(if (isTRUE(cox_stratified$has_analysis)) cox_stratified$hr_table else NULL)

  m <- rbind(
    cox_pooled_hazard_ratio              = cox_hr$value,
    cox_pooled_hazard_ratio_ci_lower     = cox_hr$ci_lower,
    cox_pooled_hazard_ratio_ci_upper     = cox_hr$ci_upper,
    cox_stratified_hazard_ratio          = cox_strat$value,
    cox_stratified_hazard_ratio_ci_lower = cox_strat$ci_lower,
    cox_stratified_hazard_ratio_ci_upper = cox_strat$ci_upper
  )

  if (weibull_on) {
    weibull_hr <- own(if (isTRUE(weibull_bundle$has_analysis)) weibull_bundle$hr_table else NULL)
    m <- rbind(
      m,
      weibull_pooled_hazard_ratio          = weibull_hr$value,
      weibull_pooled_hazard_ratio_ci_lower = weibull_hr$ci_lower,
      weibull_pooled_hazard_ratio_ci_upper = weibull_hr$ci_upper
    )
  }

  colnames(m) <- labels
  m
}

.stratifier_los_ratio_matrix <- function(sid, labels, km_matrix, weibull_bundle,
                                         wres, weibull_on) {
  km <- .stratum_km_ratio_rows(km_matrix, labels)

  m <- rbind(
    km_restricted_mean_ratio          = km$value,
    km_restricted_mean_ratio_ci_lower = km$ci_lower,
    km_restricted_mean_ratio_ci_upper = km$ci_upper
  )

  if (weibull_on) {
    own <- function(tbl) .stratifier_own_rows(tbl, sid, labels, "los_ratio")
    variant_los <- own(if (isTRUE(wres$has_analysis))           wres$los_table           else NULL)
    weibull_los <- own(if (isTRUE(weibull_bundle$has_analysis)) weibull_bundle$los_table else NULL)
    m <- rbind(
      m,
      weibull_freed_shape_los_ratio          = variant_los$value,
      weibull_freed_shape_los_ratio_ci_lower = variant_los$ci_lower,
      weibull_freed_shape_los_ratio_ci_upper = variant_los$ci_upper,
      weibull_pooled_los_ratio               = weibull_los$value,
      weibull_pooled_los_ratio_ci_lower      = weibull_los$ci_lower,
      weibull_pooled_los_ratio_ci_upper      = weibull_los$ci_upper
    )
  }

  colnames(m) <- labels
  m
}

# Compact ratio comparison within a By_Period / By_Intake_Type /
# By_Animal_Group sheet itself: two sections in the same column-per-level
# layout as every other section on that sheet (Observations, KM, Census, ...),
# so they can be cut and pasted across sheets like the rest -- unlike the full
# shape-variant report on the dedicated Weibull_By_... sheet
# (write_weibull_by_stratifier_sheet), which is laid out row-wise with every
# scale predictor, p-values, and the shape-ratio table. Deliberate duplication
# between the two: these sections exist for scanning these numbers beside the
# rest of the by-stratifier sheet, the dedicated sheet for the full model
# report: no p-value here (kept off a sheet whose whole layout is estimate/CI
# triplets) and no shape-ratio table (those rows belong to the OTHER
# predictors, not this sheet's own columns).
#
# `stratifier_id` is NULL on By_All, which has no predictor for any of these
# ratios to be about, and gets a one-line "not applicable" note in each of the
# two slots instead. It is passed rather than read off `wres$scale_stratifier`
# because a declined variant carries no id, and the sections now outlive the
# variant.
#
# `cox_bundle`/`weibull_bundle` are the top-level bundle$cox/bundle$weibull
# (the pooled fits), `wres` is measures$weibull_shape, `cox_stratified` is
# measures$cox_stratified (this stratifier's own two variants), and `km_matrix`
# is measures$km, all read here only for this stratifier's own rows.
# `weibull_on` is the parametric_regression setting, and is what decides
# whether the Weibull rows exist at all: nothing else here can tell "not asked
# for" from "asked for and did not arrive", and the two are reported
# differently (a footnote against empty rows). Neither Cox nor KM has that
# distinction -- both are always attempted -- so their rows are always written,
# and always empty rather than absent when a fit declined.
#
# The footnote is repeated under both blocks rather than written once under the
# second. Each block loses rows when the parametric fit is off, and they are
# meant to be read, and cut, one at a time.
.write_stratifier_ratio_section <- function(wb, sheet, start_row, stratifier_id, labels,
                                            cox_bundle, weibull_bundle, wres, cox_stratified,
                                            km_matrix, weibull_on,
                                            title_style, num_style_int, num_style_float) {
  if (is.null(stratifier_id)) {
    next_row <- .write_stratum_note(
      wb, sheet, start_row,
      "Hazard ratios not applicable (By_All has no per-stratifier predictor)")
    return(.write_stratum_note(
      wb, sheet, next_row,
      "LOS ratios not applicable (By_All has no per-stratifier predictor)"))
  }

  target_sheet <- .STRATIFIER_ID_TO_WEIBULL_SHEET[[stratifier_id]]

  # Written directly under the values, so the absence is read with them rather
  # than looked up. -1 lands on the row after the table, inside the two-row gap
  # .write_stratum_section leaves; the row it returns is then one further on.
  write_block <- function(row, title, m, note) {
    next_row <- .write_stratum_section(
      wb, sheet, row, title, .stratum_measure_df(m, labels),
      title_style, num_style_int, num_style_float,
      shade_triplet_estimates = TRUE, note = note
    )
    if (!weibull_on) {
      openxlsx::writeData(
        wb, sheet,
        paste("Weibull regression is off (parametric_regression is not WEIBULL),",
              "so this run has no Weibull ratios."),
        startRow = next_row - 1, startCol = 1, colNames = FALSE
      )
      next_row <- next_row + 1
    }
    next_row
  }

  next_row <- write_block(
    start_row, "Hazard ratios",
    .stratifier_hazard_ratio_matrix(stratifier_id, labels, cox_bundle, weibull_bundle,
                                    cox_stratified, weibull_on),
    if (weibull_on) {
      paste0("comparable with one another; see the Cox_Regression and ",
             target_sheet, " sheets for the full regressions")
    } else {
      "comparable with one another; see the Cox_Regression sheet for the full regression"
    }
  )

  write_block(
    next_row, "LOS ratios",
    .stratifier_los_ratio_matrix(stratifier_id, labels, km_matrix, weibull_bundle,
                                 wres, weibull_on),
    paste("comparable with one another; the KM ratio adjusts for nothing and is",
          "restricted at the stay cap")
  )
}

# Weibull_By_Period / Weibull_By_Intake_Type / Weibull_By_Animal_Group: full
# detail for one predictor's Weibull shape variant
# (.weibull_regression_analysis, mlos_cox.R) -- identical scale
# formula to Weibull_Regression (so its LOS ratios agree with this sheet's),
# but with the OTHER predictors added as shape(...) terms. Laid out like
# Weibull_Regression itself (row-wise, one model report per sheet) rather
# than the column-per-level convention of By_Period/By_Intake_Type/
# By_Animal_Group, which only carry a compact LOS-ratio + CI companion
# section instead (.write_stratifier_ratio_section) -- the p-values,
# every scale predictor's row (not just this stratifier's own), and the
# shape-ratio table live here.
write_weibull_by_stratifier_sheet <- function(wb, sheet, wres,
                                              title_style, num_style_int, num_style_float) {
  openxlsx::addWorksheet(wb, sheet)
  openxlsx::setColWidths(wb, sheet, cols = 1, widths = 30)
  openxlsx::setColWidths(wb, sheet, cols = 2:20, widths = 13)

  if (!isTRUE(wres$has_analysis)) {
    openxlsx::writeData(
      wb, sheet,
      data.frame(Note = paste0("Weibull shape regression not available: ", wres$message, ".")),
      startRow = 1, startCol = 1
    )
    return(invisible(NULL))
  }

  id_to_label <- stats::setNames(vapply(stratifiers, function(s) s$label, character(1)),
                                 vapply(stratifiers, function(s) s$id, character(1)))
  shape_labels <- unname(id_to_label[wres$shape_stratifiers])

  # Shape additive in the other predictors, or crossed over their combinations
  # (.weibull_regression_analysis, mlos_cox.R). Which one the numbers below came
  # from is not cosmetic, so it is named in the subtitle, spelled in the "Shape
  # varies by" row, and given a row of its own that states the reason whatever
  # the reason is: asked for and used, not asked for, wanted and refused, or
  # nothing to cross. Written on every sheet, so a reader who wants to know
  # which model produced a number looks in one place and always finds an
  # answer.
  crossed <- isTRUE(wres$shape_crossing$crossed)
  next_row <- .excel_write_section_title(
    wb, sheet, 1, "Weibull shape regression",
    paste0("pooled-model scale; shape varies by ",
           if (crossed) "each combination of the other predictors"
           else "the other predictors"), title_style
  )

  fallback   <- wres$shape_crossing$fallback_reason
  refused    <- !is.null(fallback) && !is.na(fallback)
  applicable <- !identical(wres$shape_crossing$applicable, FALSE)
  crossing_state <- if (crossed) {
    "used: one shape per combination of the other predictors"
  } else if (refused) {
    paste0("wanted but not used (", fallback,
           "); shape is additive in the other predictors")
  } else if (!applicable) {
    "not applicable: one other predictor, so there is nothing to cross"
  } else {
    paste0("off (weibull_shape_crossing is false); shape is additive in the ",
           "other predictors")
  }

  overview_metrics <- c("Model formula", "N", "events", "Fit stability",
                        "Shape varies by", "Shape crossing")
  overview_values <- list(
    paste0(wres$formula, "  (dist = weibull)"),
    wres$n,
    wres$n_events,
    .excel_fit_stability(wres$fit_unstable),
    paste(shape_labels, collapse = if (crossed) " x " else ", "),
    crossing_state
  )
  next_row <- .excel_write_kv_table(
    wb, sheet, overview_metrics, overview_values,
    start_row = next_row, num_style_int = num_style_int, num_style_float = num_style_float
  )
  next_row <- next_row + 2

  # Headed like the Weibull_Regression sheet's own test block, and carrying the
  # same row label, so the two read as the same section. Only the likelihood
  # ratio has a Weibull counterpart, hence the single row there.
  #
  # A crossed fit adds a second row against a different reference: the additive
  # shape formula it replaced, which is nested inside it. That one answers
  # whether the extra shape parameters were earned, which the row above it,
  # against the intercept-only model on hundreds of degrees of freedom, does not.
  has_lr <- !is.null(wres$lr)
  lr_row <- data.frame(
    test      = "Likelihood ratio",
    reference = "intercept-only Weibull",
    statistic = if (has_lr) wres$lr$stat else NA_real_,
    df        = if (has_lr) wres$lr$df   else NA_real_,
    p_value   = if (has_lr) wres$lr$p    else NA_real_,
    stringsAsFactors = FALSE
  )
  clr <- wres$shape_crossing$lr
  if (!is.null(clr)) {
    lr_row <- rbind(lr_row, data.frame(
      test      = "Likelihood ratio",
      reference = "additive shape formula",
      statistic = clr$stat, df = clr$df, p_value = clr$p,
      stringsAsFactors = FALSE
    ))
  }
  next_row <- .excel_write_section_title(
    wb, sheet, next_row, "Model tests", "each against the nested model named beside it", title_style
  )
  openxlsx::writeData(wb, sheet, lr_row, startRow = next_row, startCol = 1)
  .excel_apply_table_num_styles(wb, sheet, lr_row, next_row + 1, 3:5, num_style_int, num_style_float)
  # +2, not +3: the title helper already advanced past the heading, so next_row
  # is the table's own header row and one blank separates the sections.
  next_row <- next_row + nrow(lr_row) + 2

  # Every scale predictor's row (not filtered to this stratifier's own),
  # since this dedicated sheet has room for the full model -- unlike the
  # compact companion section on the By_... sheet itself.
  los_export <- wres$los_table[, c("variable", "los_ratio", "ci_lower", "ci_upper", "p_value")]
  names(los_export) <- c("variable", "los_ratio", "ci_95_lower", "ci_95_upper", "p_value")
  next_row <- .excel_write_section_title(
    wb, sheet, next_row, "LOS ratios",
    "every scale predictor; same scale formula as the Weibull_Regression sheet", title_style
  )
  openxlsx::writeData(wb, sheet, los_export, startRow = next_row, startCol = 1)
  .excel_apply_table_num_styles(wb, sheet, los_export, next_row + 1, 2:5, num_style_int, num_style_float)
  next_row <- next_row + nrow(los_export) + 2

  # Its own section, one row, labeled with the bundle's own name for it. The
  # section sits directly above the ratios that multiply it, and its three
  # numeric cells fall in the same columns the table below puts shape_ratio /
  # ci_95_lower / ci_95_upper in, so a level's own shape is k times the ratio
  # straight down the column.
  ref <- wres$shape_reference
  next_row <- .excel_write_section_title(
    wb, sheet, next_row, "Baseline Weibull shape (k)",
    paste("estimate, lower, upper; every shape predictor at its reference level,",
          "so one combination and not an average over the data"),
    title_style
  )
  .excel_write_estimate_row(wb, sheet, next_row, "shape_reference",
                            ref$k, ref$k_lo, ref$k_hi,
                            num_style_int, num_style_float)
  next_row <- next_row + 2

  # The level's own shape sits beside its ratio rather than being left for the
  # reader to multiply out, and carries its own interval, which multiplying the
  # two published intervals would not give (see .weibull_shape_tables).
  shape_export <- wres$shape_table[, c("variable", "shape_ratio", "ci_lower", "ci_upper",
                                       "p_value", "shape_own", "shape_own_lower",
                                       "shape_own_upper")]
  names(shape_export) <- c("variable", "shape_ratio", "ci_95_lower", "ci_95_upper",
                           "p_value", "own_shape_k", "own_k_95_lower", "own_k_95_upper")
  next_row <- .excel_write_section_title(
    wb, sheet, next_row, "Shape ratios",
    paste0(paste(shape_labels, collapse = " x "),
           if (crossed) "; one level at a time, at the reference level of the other" else ""),
    title_style
  )
  openxlsx::writeData(wb, sheet, shape_export, startRow = next_row, startCol = 1)
  .excel_apply_table_num_styles(wb, sheet, shape_export, next_row + 1, 2:8, num_style_int, num_style_float)
  next_row <- next_row + nrow(shape_export) + 2

  # The rest of the fitted shape model, when there is any: one term per
  # combination of the other predictors. Written raw -- flexsurv's own row order,
  # no reference rows -- because a product term belongs to two predictors at once
  # and has no canonical slot to be sorted into. Present so that the worksheet
  # holds the whole fitted model rather than the part that happens to tabulate
  # neatly; nothing downstream reads it. Absent when the variant did not cross,
  # where the table is empty.
  interactions <- wres$shape_interaction_table
  if (!is.null(interactions) && nrow(interactions) > 0) {
    int_export <- interactions[, c("variable", "shape_ratio", "ci_lower", "ci_upper", "p_value")]
    names(int_export) <- c("variable", "shape_ratio", "ci_95_lower", "ci_95_upper", "p_value")
    next_row <- .excel_write_section_title(
      wb, sheet, next_row, "Shape interaction terms",
      "one per combination; a correction on the ratios above, not a shape",
      title_style
    )
    openxlsx::writeData(wb, sheet, int_export, startRow = next_row, startCol = 1)
    .excel_apply_table_num_styles(wb, sheet, int_export, next_row + 1, 2:5,
                                  num_style_int, num_style_float)
    next_row <- next_row + nrow(int_export) + 2
  }

  # Spelled out because the baseline invites exactly one misreading: it is the
  # shape of a single covariate combination, not an average over the data and
  # not a summary of the dataset's shape. A baseline near 1 sitting above a
  # column of ratios below 1 still means most of the population has a falling
  # discharge hazard.
  #
  # Under a crossed shape the "baseline times ratio" arithmetic needs a fourth
  # factor away from the reference row and column, and the interaction table
  # above supplies it. Spelled out because the plausible misreading -- that an
  # interaction term IS that combination's shape -- is the one a careful reader
  # arrives at unaided, and because the multiplication is the same one this
  # sheet has always asked of the main effects, just one factor longer.
  openxlsx::writeData(
    wb, sheet,
    paste0("A level's own Weibull shape is the baseline above times its shape ratio; ",
           "the baseline is one combination (every shape predictor at its reference level), ",
           "not an average over the data. A ratio below 1 means that level's discharge hazard ",
           "falls faster with time in care than the reference level's.",
           if (crossed) paste0(" Shape here varies by COMBINATION of the other predictors: a ",
                               "combination's own shape is the baseline times BOTH main-effect ",
                               "ratios times its interaction term above. An interaction term is ",
                               "that correction and not a shape on its own, and there is none ",
                               "where either predictor sits at its reference level.")
           else ""),
    startRow = next_row, startCol = 1, colNames = FALSE
  )

  invisible(NULL)
}


# Shared core of the By_Period / By_All / By_Intake_Type / By_Animal_Group
# sheets: the measure sections common to every stratifying dimension, from
# "Observations" down to the confidence intervals. Every number here is read
# from `measures` (compute_stratum_measures in mlos_results.R); this function
# only chooses which rows to show, in what order, under what title, in what
# number format. Because the measure sets are deterministic functions of the
# full dataset, every sheet puts the same measure on the same worksheet line
# and columns can be cut and pasted across sheets.
.write_stratum_measure_sections <- function(wb, sheet, start_row, measures,
                                            cox_bundle, weibull_bundle,
                                            stratifier_id, weibull_on,
                                            title_style, num_style_int, num_style_float) {
  labels <- measures$labels
  next_row <- start_row
  write_matrix_section <- function(row, title, m, style_int = num_style_int,
                                   style_float = num_style_float, shade = FALSE,
                                   note = NULL) {
    .write_stratum_section(wb, sheet, row, title, .stratum_measure_df(m, labels),
                           title_style, style_int, style_float,
                           shade_triplet_estimates = shade, note = note)
  }

  # The rows to show, in sheet order. The measures matrix carries more than
  # this: mean_census_inventory and daily_mean_total_in_care_days appear in the
  # census-aggregates section instead (beside the expected census), and
  # censored and total_in_care_days_sum are components better read through the
  # rows below that summarize them. Naming the display rows explicitly keeps
  # the sheet layout fixed no matter what else the bundle grows.
  obs_display_rows <- c(
    "duration_days", "total_observations", "events", "left_truncated",
    "right_censored", "capped_at_restricted_stay_cap", "mean_days_at_risk",
    "total_animal_days", "total_intakes", "total_outcomes",
    "mean_daily_intakes", "mean_daily_outcomes"
  )
  next_row <- write_matrix_section(next_row, "Observations",
                                   measures$observations[obs_display_rows, , drop = FALSE])

  # completed_outcomes_total leads the outcome-events section, mirroring the
  # overall-then-breakdown shape of the incidence rates below.
  if (!is.null(measures$outcomes)) {
    next_row <- write_matrix_section(next_row, "Outcome events", measures$outcomes)
  } else {
    next_row <- .write_stratum_note(wb, sheet, next_row, "Outcome events not available")
  }

  if (!is.null(measures$mix)) {
    next_row <- write_matrix_section(next_row, "Outcome mix among completed outcomes",
                                     measures$mix)
    # Per-100 scale so the rate reads like a daily percentage of the population;
    # shown to exactly two decimals (the style is passed for BOTH the int and
    # float slots so a whole-number rate still displays as e.g. 5.00).
    num_style_rate <- openxlsx::createStyle(numFmt = "0.00")
    next_row <- write_matrix_section(next_row, "Incidence rates per 100 animal-days",
                                     measures$incidence, num_style_rate, num_style_rate)
  } else {
    next_row <- .write_stratum_note(wb, sheet, next_row,
                                    "Outcome mix and incidence rates not available")
  }

  # The KM matrix also carries the bounds (shown in the CI section) and the
  # per-intake day helpers behind the census aggregates; only the headline
  # estimates belong here. km_still_in_care_at_cap follows the 90th percentile
  # because it continues the same reading of the curve: the median and the P90
  # are the days by which half and nine tenths have left, and the terminal
  # value is the fraction that never does within the cap. Compare it with
  # fraction_capped in the observations section, which counts the same event
  # from the rows rather than from the fitted curve.
  next_row <- write_matrix_section(
    next_row, "KM Length of Stay",
    measures$km[c("km_median_los", "km_p90_los", "km_still_in_care_at_cap",
                  "km_restricted_mean"), , drop = FALSE]
  )

  # Census aggregates, observed beside expected. Observed: the mean census
  # (mean_census_inventory) and the mean nightly total accumulated in-care days
  # (daily_mean_total_in_care_days), both moved down from the observations
  # section above. Expected (math methods 5.7): the steady-state census (the
  # km_census_by_* CSV's expected_census, inventory convention via Little's law,
  # mean daily intakes x KM restricted mean; directly comparable to
  # mean_census_inventory, both capped at the restricted stay cap, so a gap
  # between them signals a population in transition, not the cap), the elapsed
  # animal-days the current census has already accrued, and the future
  # animal-days it still owes, both within the cap. The section closes with three
  # days-per-resident ratios ordered so the KM-inferred past sits between the two
  # measures it is naturally compared with: observed accumulated care-days per
  # resident (a direct data count), the same quantity as implied by the KM
  # census-by-tenure profile, and expected future care-days per resident.
  # Observed vs KM-inferred past is the backward-looking counterpart of the
  # census gap above; KM past and KM future differ by exactly one day (the
  # future - past = census identity divided through by the census).
  next_row <- write_matrix_section(next_row, "Census aggregates", measures$census,
                                   note = .census_section_note())

  if (!is.null(measures$aj_final_cif)) {
    next_row <- write_matrix_section(next_row, "AJ Final CIF", measures$aj_final_cif)
    next_row <- write_matrix_section(next_row, "AJ restricted mean",
                                     measures$aj_restricted_mean)
    next_row <- write_matrix_section(
      next_row, "AJ restricted mean days by state", measures$aj_rmtl,
      note = "in care = RMST, departed = RMTL"
    )
  } else {
    next_row <- .write_stratum_note(wb, sheet, next_row, "AJ analysis not available")
  }

  # 95% confidence intervals, gathered in one section at the bottom rather
  # than as extra columns beside the estimates (extra columns would multiply
  # the sheet width by three and make multi-level dimensions hard to read).
  # Rows are estimate/lower/upper triplets in the order the sections above
  # introduce them; each estimate is re-displayed above its bounds so a triplet
  # reads on its own. Which intervals exist, and on what assumptions, is
  # decided in compute_stratum_measures (math methods 8.2).
  next_row <- write_matrix_section(next_row, "95% confidence intervals", measures$ci,
                                   shade = TRUE, note = "estimate, lower, upper")

  # Hazard ratios and LOS ratios: placed last, after every section the "aligned
  # with By_All" test checks (check_excel_workbook, tests/run_tests.R),
  # because unlike every section above -- each an all-or-nothing function of
  # the FULL dataset, so its row count is identical whether or not it is
  # available on THIS sheet -- these two differ sheet by sheet even within one
  # run: By_All has neither (no per-stratifier predictor for a ratio to be
  # about), and a by-stratifier sheet's own variant can succeed or decline
  # independently of its neighbors'. Putting them last keeps that variability
  # from ever shifting a measure below them out of alignment; nothing here
  # needs to line up with anything else.
  .write_stratifier_ratio_section(
    wb, sheet, next_row, stratifier_id, labels,
    cox_bundle, weibull_bundle, measures$weibull_shape, measures$cox_stratified,
    measures$km, weibull_on,
    title_style, num_style_int, num_style_float
  )
  invisible(NULL)
}


write_by_period_sheet <- function(wb, periods, measures, cox_bundle, weibull_bundle,
                                  weibull_on,
                                  title_style, num_style_int, num_style_float) {
  openxlsx::addWorksheet(wb, "By_Period")
  openxlsx::setColWidths(wb, "By_Period", cols = 1, widths = 30)
  openxlsx::setColWidths(wb, "By_Period", cols = 2:20, widths = 13)

  period_meta_rows <- .period_metadata_typed_rows(periods)
  by_period_row <- .write_stratum_section(
    wb, "By_Period", 1, "Period metadata", note = "end dates excluded", title_style = title_style,
    num_style_int = num_style_int, num_style_float = num_style_float, typed_rows = period_meta_rows
  )

  .write_stratum_measure_sections(
    wb, "By_Period", by_period_row, measures, cox_bundle, weibull_bundle,
    stratifier_id = "period", weibull_on = weibull_on,
    title_style = title_style, num_style_int = num_style_int, num_style_float = num_style_float
  )
}

# One By_Intake_Type / By_Animal_Group sheet, row-for-row aligned with
# By_Period so a user can cut and paste columns across the three sheets and
# see compatible distributions of the same data. Deliberately, every measure
# section keeps the By_Period row-level conventions rather than re-unifying
# stays across period boundaries: rows are animal-period segments, truncated
# and censored at period boundaries, so a long stay contributes one row per
# period it touches to its stratum's column (exactly as it contributes one
# row to each period's column on By_Period). The one exception is the top
# section, in the slot the period-metadata table occupies on By_Period: it
# holds the unified-across-periods stay counts (each stay once; see
# calculate_unified_stay_counts), the three numbers whose row-level versions
# below carry period-boundary effects. The caveat block sits beside it on
# the same rows, as a light pink panel, so the conventions cannot be
# overlooked; either way every later section stays on the same worksheet
# lines. The days denominator for census and daily rates is the total days
# across all periods.
write_by_stratum_sheet <- function(wb, sheet, measures, window_days, n_periods_present,
                                   cox_bundle, weibull_bundle, stratifier_id, weibull_on,
                                   title_style, num_style_int, num_style_float) {
  labels <- measures$labels

  openxlsx::addWorksheet(wb, sheet)
  openxlsx::setColWidths(wb, sheet, cols = 1, widths = 30)
  openxlsx::setColWidths(wb, sheet, cols = 2:20, widths = 13)

  unified <- measures$unified_stay_counts
  unified_rows <- .excel_period_rows(
    list(
      unified_total_stays    = as.numeric(unified$total_stays),
      unified_left_truncated = as.numeric(unified$left_truncated_stays),
      unified_right_censored = as.numeric(unified$right_censored_stays)
    ),
    labels
  )
  next_row <- .write_stratum_section(
    wb, sheet, 1, "Counts unified across periods", note = "each stay counted once", title_style = title_style,
    num_style_int = num_style_int, num_style_float = num_style_float, typed_rows = unified_rows
  )

  # Caveat panel beside the unified counts: title on row 1, one note per
  # row below, over a colored field wide enough that overflowing note text
  # stays on the fill. Pink (multi-period contract) when more than one period
  # actually has data; a defined-but-empty period contributes no rows to
  # period_data, so this counts periods with data, not periods defined. With
  # only one period present, the multi-period caveat would be false -- there
  # is no period boundary for a stay to span -- so a green note pointing out
  # the resulting identity replaces it instead.
  caveat_col <- length(labels) + 3
  if (n_periods_present > 1) {
    caveat_notes <- c(
      "The unified rows at left (top section) count each stay once, even when it overlaps with multiple periods.",
      paste0("The remaining sections follow the By_Period row conventions: every animal-period row counts once, ",
             "so a stay spanning several periods may contribute several times in some counts."),
      paste0("The left_truncated counts include all instances of the animal already in care when a period starts, ",
             "and the right_censored counts include censoring at period boundaries."),
      paste0("Census and daily-rate denominators are the total days across all periods (",
             format(window_days), " days). NA or blank means not computable for that column.")
    )
    caveat_style <- openxlsx::createStyle(fgFill = "#FFEBEE")
  } else {
    caveat_notes <- c(
      paste0("This run has a single period, so the unified counts in the top section and the row-level ",
             "counts in the remaining sections below are identical column for column."),
      paste0("With no intermediate period boundary to split a stay, each column's left_truncated and ",
             "right_censored here already match the unified (each-stay-once) definitions exactly."),
      paste0("This identity would not hold with multiple periods, where a stay spanning periods instead ",
             "contributes one row per period.")
    )
    caveat_style <- openxlsx::createStyle(fgFill = "#C6EFCE", fontColour = "#006100")
  }
  # Keeps its parenthetical rather than splitting into a second cell like the
  # sheet's sections do: this is a side panel sitting on a colored field, not a
  # section following a blank row, and its title is wider than one column, so
  # it needs the cell to its right free to overflow into.
  openxlsx::writeData(wb, sheet, "How to read this sheet (see also User Guide)",
                      startRow = 1, startCol = caveat_col, colNames = FALSE)
  openxlsx::addStyle(wb, sheet, title_style, rows = 1, cols = caveat_col, stack = TRUE)
  for (i in seq_along(caveat_notes)) {
    openxlsx::writeData(wb, sheet, caveat_notes[i], startRow = 1 + i, startCol = caveat_col, colNames = FALSE)
  }
  caveat_last_row <- 1 + length(caveat_notes)
  openxlsx::addStyle(wb, sheet, caveat_style, rows = 1:caveat_last_row, cols = caveat_col:(caveat_col + 14),
                     gridExpand = TRUE, stack = TRUE)

  .write_stratum_measure_sections(
    wb, sheet, next_row, measures, cox_bundle, weibull_bundle,
    stratifier_id = stratifier_id, weibull_on = weibull_on,
    title_style = title_style, num_style_int = num_style_int, num_style_float = num_style_float
  )
}

# ---- Main entry point ----

write_results_excel <- function(excel_file, bundle) {
  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    cat("\n*** WARNING: openxlsx package not installed - skipping Excel export ***\n")
    cat("Install with: install.packages('openxlsx')\n")
    return(FALSE)
  }

  wb <- openxlsx::createWorkbook()
  title_style <- openxlsx::createStyle(textDecoration = "bold")
  num_style_int <- openxlsx::createStyle(numFmt = "0")
  num_style_float <- openxlsx::createStyle(numFmt = "0.00000")
  settings <- bundle$settings

  # Whether the parametric fit was asked for at all, which several sheets gate
  # on and which the by-stratifier ratio section needs in order to tell "not
  # asked for" from "asked for and declined".
  weibull_on <- identical(settings$parametric_regression, "WEIBULL")

  # General leads the workbook as its cover sheet (run metadata, period
  # windows, substantive settings, then the unified summary). It depends on no
  # other sheet, so adding it first just sets the tab order.
  write_general_sheet(wb, bundle, title_style, num_style_int, num_style_float)

  # Straight after the cover sheet, because it answers what a reader asks before
  # any result means anything: how many of my rows did this analysis use, and
  # what became of the rest.
  write_data_preparation_sheet(wb, bundle, title_style, num_style_int, num_style_float)

  write_cox_regression_sheet(wb, bundle$cox, settings$coverage,
                             title_style, num_style_int, num_style_float)

  if (weibull_on) {
    write_weibull_regression_sheet(wb, bundle$weibull, bundle$cox$has_analysis,
                                   settings$coverage,
                                   title_style, num_style_int, num_style_float)
  }

  # By_All: the whole dataset as a single pooled column, structurally identical
  # to the stratum sheets. Always present -- it is the whole-sample view, and
  # every run has one.
  write_by_stratum_sheet(wb, "By_All", bundle$strata$all, settings$window_days,
                         settings$n_periods_present, bundle$cox, bundle$weibull,
                         stratifier_id = NULL, weibull_on = weibull_on,
                         title_style, num_style_int, num_style_float)

  # By_Period is an ordinary stratifier sheet, subject to the same rule as the
  # others: shown when there are at least two levels to compare. With a single
  # period it would only restate By_All in a column headed by the period label,
  # and the period's dates and duration are on General either way.
  if (isTRUE(settings$coverage$period$included)) {
    write_by_period_sheet(wb, settings$periods, bundle$strata$period, bundle$cox, bundle$weibull,
                          weibull_on,
                          title_style, num_style_int, num_style_float)
  }

  # One stratum sheet per stratifier the bundle carries, each row-aligned with
  # By_Period; see write_by_stratum_sheet for the layout contract and the
  # period-boundary counting caveats.
  for (stratifier in stratifiers) {
    if (identical(stratifier$id, "period")) next
    measures <- bundle$strata[[stratifier$id]]
    if (is.null(measures)) next
    write_by_stratum_sheet(wb, stratifier$sheet_name, measures, settings$window_days,
                           settings$n_periods_present, bundle$cox, bundle$weibull,
                           stratifier_id = stratifier$id, weibull_on = weibull_on,
                           title_style, num_style_int, num_style_float)
  }

  # Dedicated Weibull shape-variant sheets, one per stratifier, placed AFTER
  # every by-stratifier sheet above rather than interleaved with them (e.g.
  # By_Period, By_Intake_Type, By_Animal_Group, THEN Weibull_By_Period,
  # Weibull_By_Intake_Type, Weibull_By_Animal_Group) -- the same "grouped by
  # kind" ordering the rest of the workbook already follows (Cox_Regression
  # then Weibull_Regression, not interleaved row by row). Gated the same way
  # Weibull_Regression itself is (parametric_regression: WEIBULL), not on
  # each variant's own has_analysis, so one that merely declined (e.g. fewer
  # than two qualifying predictors) still gets its sheet, with a note,
  # rather than the sheet vanishing outright.
  if (weibull_on) {
    if (isTRUE(settings$coverage$period$included)) {
      write_weibull_by_stratifier_sheet(wb, .STRATIFIER_ID_TO_WEIBULL_SHEET[["period"]],
                                        bundle$strata$period$weibull_shape,
                                        title_style, num_style_int, num_style_float)
    }
    for (stratifier in stratifiers) {
      if (identical(stratifier$id, "period")) next
      measures <- bundle$strata[[stratifier$id]]
      if (is.null(measures)) next
      write_weibull_by_stratifier_sheet(wb, .STRATIFIER_ID_TO_WEIBULL_SHEET[[stratifier$id]],
                                        measures$weibull_shape,
                                        title_style, num_style_int, num_style_float)
    }
  }

  openxlsx::saveWorkbook(wb, excel_file, overwrite = TRUE)
  cat("\nExcel results exported to:", excel_file, "\n")
  return(TRUE)
}
