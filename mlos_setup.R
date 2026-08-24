# mLOS - Setup: Read Settings and Define Periods
# =======================================================================

#' Read settings file (YAML)
#'
#' @param settings_file Path to the settings file
#' @return List containing parsed settings
read_settings <- function(settings_file) {
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("yaml package is required. Install with: install.packages('yaml')")
  }
  if (!file.exists(settings_file)) {
    stop("Settings file not found: ", settings_file)
  }

  settings <- yaml::read_yaml(settings_file)
  if (!is.list(settings)) {
    stop("Settings file must contain a YAML mapping (key-value pairs).")
  }

  settings
}


#' Define periods from period_dates setting
#'
#' Labels come from the optional period_labels setting (one per period);
#' when absent they default to Period_1, Period_2, ...
#'
#' @param settings List containing settings (must have period_dates)
#' @return Data frame with period definitions
define_periods <- function(settings) {

  period_dates <- settings[["period_dates"]]

  if (is.null(period_dates)) {
    stop("period_dates not found in settings file")
  }

  period_boundaries <- as.Date(period_dates)

  # Check for parsing errors
  if (any(is.na(period_boundaries))) {
    stop("Error parsing period_dates. Ensure dates are in YYYY-MM-DD format.")
  }

  # Check that we have at least 2 dates
  if (length(period_boundaries) < 2) {
    stop("period_dates must contain at least 2 dates to define 1 period")
  }

  # Out-of-order or duplicate boundaries would silently define negative- or
  # zero-length periods; the docs promise b1 < b2 < ... (math methods 2.4).
  if (any(diff(period_boundaries) <= 0)) {
    stop("period_dates must be strictly increasing (each date later than the previous one).")
  }

  # Create period definitions
  # Each period is [start_date, end_date) - left-closed, right-open
  n_periods <- length(period_boundaries) - 1

  periods <- data.frame(
    period_num = 1:n_periods,
    start_date = period_boundaries[1:n_periods],
    end_date = period_boundaries[2:(n_periods + 1)],
    stringsAsFactors = FALSE
  )

  # Add period labels: custom from the optional period_labels setting,
  # otherwise Period_1, Period_2, ...
  custom_labels <- settings[["period_labels"]]
  if (is.null(custom_labels)) {
    periods$period_label <- paste0("Period_", 1:n_periods)
  } else {
    labels <- .parse_raw_labels(custom_labels, "period_labels")
    if (length(labels) != n_periods) {
      stop("period_labels must contain exactly ", n_periods,
           " label(s), one per period (found: ", length(labels), ").")
    }
    if (anyDuplicated(labels) > 0) {
      stop("period_labels contains duplicate labels: ",
           paste(unique(labels[duplicated(labels)]), collapse = ", "))
    }
    # Commas and equals signs would corrupt the "colname=level, ..." stratum
    # names that survfit builds and .strip_stratum_prefix parses back apart.
    if (any(grepl("[,=]", labels))) {
      stop("period_labels must not contain commas or equals signs.")
    }
    periods$period_label <- labels
  }

  # Calculate period duration in days
  periods$duration_days <- as.numeric(periods$end_date - periods$start_date)

  return(periods)
}


# Validate a settings list of raw outcome labels and return it as a trimmed
# character vector. Rejects values YAML parsed as booleans (YAML 1.1 collapses
# bare yes/no/true/false/etc. to logical before R sees them) and empty strings.
.parse_raw_labels <- function(vals, key_name) {
  if (any(vapply(vals, is.logical, logical(1)))) {
    stop(key_name, " contains a value YAML parsed as boolean. ",
         "Put quotes around all raw labels to prevent this.")
  }
  char_vals <- trimws(vapply(vals, as.character, character(1)))
  if (any(char_vals == "")) {
    stop(key_name, " contains an empty value.")
  }
  char_vals
}


#' Parse outcome_type_L/T/N settings into a raw-label-to-code lookup
#'
#' The settings file supplies three keyed lists, one per canonical code.
#' Each list contains one or more raw CSV values that map to that code:
#'
#'   outcome_type_L:
#'     - "Adopted"
#'     - "RTO"
#'   outcome_type_T:
#'     - "Transferred"
#'   outcome_type_N:
#'     - "Died"
#'     - "Euthanized"
#'
#' If none of the three keys are present, the CSV is assumed to already
#' use L/T/N directly and NULL is returned.
#' Quote all values to avoid YAML parsing words like Yes/No as booleans.
#'
#' @param settings List containing settings
#' @return Named character vector (names = raw CSV values, values = "L"/"T"/"N")
#'   or NULL if no outcome_type_X keys are present
parse_outcome_type_mapping <- function(settings) {
  keys <- c(L = "outcome_type_L", T = "outcome_type_T", N = "outcome_type_N")

  raw_by_code <- lapply(keys, function(k) settings[[k]])

  if (all(vapply(raw_by_code, is.null, logical(1)))) {
    return(NULL)
  }

  result <- character(0)
  for (code in names(keys)) {
    vals <- raw_by_code[[code]]
    if (is.null(vals) || length(vals) == 0) {
      stop(keys[[code]], " is missing or empty. ",
           "All three (outcome_type_L, outcome_type_T, outcome_type_N) must be provided.")
    }
    char_vals <- .parse_raw_labels(vals, keys[[code]])
    # Duplicates must be caught BEFORE the assignment: result[label] <- code
    # overwrites an existing entry rather than appending, so a label already
    # assigned under an earlier code (or repeated within this list) would
    # otherwise be resolved silently to the last code seen.
    dupes <- unique(char_vals[char_vals %in% names(result) | duplicated(char_vals)])
    if (length(dupes) > 0) {
      stop("Raw outcome labels appear under more than one code: ",
           paste(dupes, collapse = ", "))
    }
    result[char_vals] <- code
  }

  result
}


#' Parse outcome_type_delete or outcome_type_in_care from settings
#'
#' @param settings List containing settings
#' @param key Either "outcome_type_delete" or "outcome_type_in_care"
#' @return Character vector of raw labels, or NULL if key is absent
parse_outcome_type_filter <- function(settings, key) {
  vals <- settings[[key]]
  if (is.null(vals)) return(NULL)
  if (length(vals) == 0) {
    stop(key, " is present but empty. Either provide at least one value or remove the key.")
  }
  .parse_raw_labels(vals, key)
}


#' Parse an optional value map (intake_type_map / animal_group_map)
#'
#' The setting is a list of one-key pairs, each naming a value as it appears in
#' the data and the value it becomes:
#'
#'   animal_group_map:
#'     - "XL": "LRG"
#'     - "TOY": "SMALL"
#'
#' Keys must be unique, but need not occur in the data: a map is the place to
#' put rare labels that may or may not turn up in a given extract, so a key that
#' matches nothing is not an error. The counts reported at map time (see
#' .apply_value_map in mlos_data.R) are what let the user check that.
#'
#' Quote both sides. A bare y/n/yes/no/true/false is resolved by YAML before R
#' sees it: an unquoted value is caught by .parse_raw_labels, but an unquoted
#' KEY arrives already flattened to "TRUE"/"FALSE" and is indistinguishable
#' from a quoted one, so it cannot be caught here -- it simply matches nothing,
#' and its zero count in the console report is the tell.
#'
#' @param settings List containing settings
#' @param key Either "intake_type_map" or "animal_group_map"
#' @return Named character vector (names = values to replace, values = their
#'   replacements) or NULL when the key is absent
parse_value_map <- function(settings, key) {
  pairs <- settings[[key]]
  if (is.null(pairs)) return(NULL)
  if (!is.list(pairs) || length(pairs) == 0) {
    stop(key, " must be a non-empty list of \"from: to\" pairs, one per list item.")
  }

  from <- character(length(pairs))
  to   <- character(length(pairs))
  for (i in seq_along(pairs)) {
    pair <- pairs[[i]]
    pair_name <- names(pair)
    # One pair per list item: a two-key item (a missing "- ") or a bare string
    # (a missing ": ") are the two ways the list form goes wrong.
    if (length(pair) != 1 || is.null(pair_name) || is.na(pair_name) ||
        trimws(pair_name) == "") {
      stop(key, " entry ", i, " must be a single \"from: to\" pair ",
           "(one pair per list item, e.g. - \"XL\": \"LRG\").")
    }
    if (length(pair[[1]]) != 1) {
      stop(key, " entry ", i, " (", trimws(pair_name),
           ") must map to exactly one value.")
    }
    from[i] <- trimws(pair_name)
    to[i]   <- .parse_raw_labels(pair[1], paste0(key, " entry ", i, " (", from[i], ")"))
  }

  # Uniqueness is enforced rather than resolved: setNames would keep both
  # entries, and the match() in .apply_value_map would silently honor the first,
  # so a value listed twice with different targets would map by list order.
  dupes <- unique(from[duplicated(from)])
  if (length(dupes) > 0) {
    stop(key, " has duplicate keys: ", paste(dupes, collapse = ", "),
         ". Each value may be mapped only once.")
  }

  setNames(to, from)
}


#' Extract reference values from settings
#'
#' @param settings List containing settings
#' @param periods Data frame of period definitions from define_periods
#' @return List with reference values
extract_references <- function(settings, periods) {
  # Typo protection: an unrecognized key would otherwise be silently ignored,
  # making the tool behave as if the (misspelled) setting were never given.
  known_keys <- c(
    "period_dates", "period_labels",
    "restricted_stay_cap", "plot_stay_cap",
    "outcome_type_L", "outcome_type_T", "outcome_type_N",
    "outcome_type_delete", "outcome_type_in_care",
    "animal_group_columns", "animal_group_reference", "intake_type_reference",
    "period_reference", "discard_bad_rows", "discard_overlapping_rows",
    "show_km_ci_ribbons", "show_aj_cif_ci_ribbons",
    "png_pointsize_factor", "png_line_width_factor",
    "max_plot_strata",
    "parametric_regression", "weibull_shape_crossing",
    "km_survival_by_stratifier", "km_remaining_los_by_stratifier",
    "km_census_by_tenure_by_stratifier", "km_in_care_tenure_by_stratifier",
    "aj_cif_by_stratifier", "aj_conditional_by_stratifier",
    "intake_type_map", "animal_group_map",
    "intake_filter_pass", "intake_filter_cut",
    "animal_group_filter_pass", "animal_group_filter_cut",
    "other_filter_column_name", "other_filter_pass", "other_filter_cut"
  )
  unknown_keys <- setdiff(names(settings), known_keys)
  if (length(unknown_keys) > 0) {
    stop("Unrecognized setting(s) in the settings file: ",
         paste(unknown_keys, collapse = ", "),
         ". Check the spelling (settings are case-sensitive).")
  }

  parse_positive_integer_cap <- function(raw_value, key_name) {
    cap <- suppressWarnings(as.numeric(raw_value))
    if (length(cap) != 1 || is.na(cap) || !is.finite(cap)) {
      stop(key_name, " must be a single positive integer in the settings file.")
    }
    if (cap <= 0 || cap != floor(cap)) {
      stop(key_name, " must be a positive integer (found: ", raw_value, ").")
    }
    as.integer(cap)
  }

  parse_positive_numeric <- function(raw_value, key_name) {
    value <- suppressWarnings(as.numeric(raw_value))
    if (length(value) != 1 || is.na(value) || !is.finite(value) || value <= 0) {
      stop(key_name, " must be a single positive number in the settings file.")
    }
    value
  }

  # Reference levels must be single values; a YAML list here would otherwise
  # surface as an obscure R condition error deep inside the Cox step.
  parse_scalar_reference <- function(key) {
    val <- settings[[key]]
    if (is.null(val)) return(NULL)
    if (length(val) != 1) {
      stop(key, " must be a single value (found ", length(val), ").")
    }
    as.character(val)
  }

  parse_positive_numeric_default <- function(key, default) {
    if (is.null(settings[[key]])) return(default)
    parse_positive_numeric(settings[[key]], key)
  }

  parse_logical_flag <- function(key, default = FALSE) {
    raw <- settings[[key]]
    if (is.null(raw)) return(default)
    if (is.logical(raw) && length(raw) == 1 && !is.na(raw)) return(raw)
    stop(key, " must be true or false in the settings file.")
  }

  # Per-stratified-output emission flag. Accepts TRUE/FALSE (both files or
  # neither), PNG (plot only), or CSV (data only), and returns a named logical
  # c(png=, csv=). Absent -> both, so a settings file that predates these keys
  # produces exactly the plot/CSV pairs it did before. TRUE/FALSE arrive as
  # YAML logicals; PNG/CSV (and any quoted TRUE/FALSE) arrive as strings.
  # Case-sensitive uppercase, like every other setting value.
  parse_output_flag <- function(key) {
    raw <- settings[[key]]
    if (is.null(raw)) return(c(png = TRUE, csv = TRUE))
    if (is.logical(raw) && length(raw) == 1 && !is.na(raw)) {
      return(c(png = raw, csv = raw))
    }
    if (length(raw) != 1) {
      stop(key, " must be a single value: TRUE, FALSE, PNG, or CSV.")
    }
    val <- trimws(as.character(raw))
    switch(val,
      "TRUE"  = c(png = TRUE,  csv = TRUE),
      "FALSE" = c(png = FALSE, csv = FALSE),
      "PNG"   = c(png = TRUE,  csv = FALSE),
      "CSV"   = c(png = FALSE, csv = TRUE),
      stop(key, " must be one of TRUE, FALSE, PNG, or CSV (found: ", val, ").")
    )
  }

  restricted_stay_cap <- parse_positive_integer_cap(
    settings[["restricted_stay_cap"]],
    "restricted_stay_cap"
  )

  if (!is.null(settings[["plot_stay_cap"]])) {
    plot_stay_cap <- parse_positive_integer_cap(settings[["plot_stay_cap"]], "plot_stay_cap")
  } else {
    plot_stay_cap <- restricted_stay_cap
  }
  if (plot_stay_cap > restricted_stay_cap) {
    stop("plot_stay_cap must be less than or equal to restricted_stay_cap.")
  }

  png_pointsize_factor  <- parse_positive_numeric_default("png_pointsize_factor", 1)
  png_line_width_factor <- parse_positive_numeric_default("png_line_width_factor", 1)

  # Plot-only legibility limit (see .MAX_PLOT_STRATA in mlos_common.R for the
  # default). 1 disables stratified plots entirely: a stratifier reaches the
  # plot code only through a has_field gate requiring two or more levels, so
  # its stratum count is always at least 2.
  if (!is.null(settings[["max_plot_strata"]])) {
    max_plot_strata <- parse_positive_integer_cap(settings[["max_plot_strata"]], "max_plot_strata")
    if (max_plot_strata > .MAX_PLOT_STRATA_LIMIT) {
      stop("max_plot_strata cannot exceed ", .MAX_PLOT_STRATA_LIMIT,
           " (the number of distinct stratum plot colors); found: ",
           max_plot_strata, ".")
    }
  } else {
    max_plot_strata <- .MAX_PLOT_STRATA
  }

  n_periods <- nrow(periods)

  # period_reference is a POLICY, not a period number: it is resolved against
  # the periods that actually contain data at Cox time (mlos_cox.R), so a
  # defined-but-empty boundary period is never chosen as the reference.
  # Case-sensitive (uppercase), like every other setting value.
  raw_period_ref <- settings[["period_reference"]]
  if (is.null(raw_period_ref)) {
    period_reference <- "OLDEST"
  } else {
    period_reference <- trimws(as.character(raw_period_ref))
    if (length(period_reference) != 1 || !period_reference %in% c("OLDEST", "NEWEST")) {
      stop("period_reference must be 'OLDEST' or 'NEWEST' (found: ",
           paste(raw_period_ref, collapse = ", "), ").")
    }
  }

  outcome_type_mapping  <- parse_outcome_type_mapping(settings)
  outcome_type_delete   <- parse_outcome_type_filter(settings, "outcome_type_delete")
  outcome_type_in_care  <- parse_outcome_type_filter(settings, "outcome_type_in_care")

  # Cross-setting duplicate check: a raw label must appear in at most one outcome_type_* setting.
  outcome_type_lists <- list(
    outcome_type_L       = if (!is.null(outcome_type_mapping)) names(outcome_type_mapping)[outcome_type_mapping == "L"] else NULL,
    outcome_type_T       = if (!is.null(outcome_type_mapping)) names(outcome_type_mapping)[outcome_type_mapping == "T"] else NULL,
    outcome_type_N       = if (!is.null(outcome_type_mapping)) names(outcome_type_mapping)[outcome_type_mapping == "N"] else NULL,
    outcome_type_delete  = outcome_type_delete,
    outcome_type_in_care = outcome_type_in_care
  )
  outcome_type_lists <- Filter(Negate(is.null), outcome_type_lists)
  if (length(outcome_type_lists) >= 2) {
    all_labels   <- unlist(outcome_type_lists)
    setting_names <- rep(names(outcome_type_lists), lengths(outcome_type_lists))
    dupes <- unique(all_labels[duplicated(all_labels)])
    if (length(dupes) > 0) {
      dupe_info <- vapply(dupes, function(d) {
        which_settings <- unique(setting_names[all_labels == d])
        paste0('"', d, '" in ', paste(which_settings, collapse = " and "))
      }, character(1))
      stop("Raw outcome labels appear in more than one outcome_type_* setting:\n  ",
           paste(dupe_info, collapse = "\n  "))
    }
  }

  discard_bad_rows       <- parse_logical_flag("discard_bad_rows")
  discard_overlapping_rows <- parse_logical_flag("discard_overlapping_rows")
  show_aj_cif_ci_ribbons <- parse_logical_flag("show_aj_cif_ci_ribbons")
  show_km_ci_ribbons     <- parse_logical_flag("show_km_ci_ribbons")

  # Optional value filter for one column: at most one of a pass-list (keep only
  # these values) or a cut-list (drop these values). Returns list(mode, values)
  # or NULL when neither key is present. The values are validated as raw labels
  # (quoted strings, no YAML booleans, no blanks) exactly like the outcome_type
  # lists; a present-but-empty list is rejected so an accidental "pass: []"
  # cannot silently delete every row. Column existence is checked later, in
  # read_and_prepare_data, where the data is available.
  parse_filter_spec <- function(pass_key, cut_key) {
    pass_val <- settings[[pass_key]]
    cut_val  <- settings[[cut_key]]
    if (!is.null(pass_val) && !is.null(cut_val)) {
      stop("At most one of ", pass_key, " and ", cut_key,
           " may be present, not both.")
    }
    for (kv in list(list(pass_key, pass_val, "pass"), list(cut_key, cut_val, "cut"))) {
      key <- kv[[1]]; val <- kv[[2]]; mode <- kv[[3]]
      if (is.null(val)) next
      values <- .parse_raw_labels(val, key)
      if (length(values) == 0) {
        stop(key, " is present but empty. Provide at least one value or remove the key.")
      }
      return(list(mode = mode, values = values))
    }
    NULL
  }

  intake_filter       <- parse_filter_spec("intake_filter_pass", "intake_filter_cut")
  animal_group_filter <- parse_filter_spec("animal_group_filter_pass", "animal_group_filter_cut")

  # The "other" filter names its column explicitly; the name and a pass/cut list
  # are all-or-none together (a column with no list, or a list with no column,
  # is a half-configured filter and almost certainly a mistake).
  other_filter_column <- parse_scalar_reference("other_filter_column_name")
  other_filter        <- parse_filter_spec("other_filter_pass", "other_filter_cut")
  if (is.null(other_filter_column) != is.null(other_filter)) {
    stop("other_filter_column_name and one of other_filter_pass / other_filter_cut ",
         "must be provided together (found only one of the two).")
  }
  if (!is.null(other_filter)) {
    other_filter$column <- other_filter_column
  }

  # parametric_regression: FALSE (default) or WEIBULL -- a parametric fit run
  # in ADDITION to Cox, never instead. The distribution must be named
  # explicitly (a bare true is rejected), so future distributions can be added
  # without changing the setting's meaning. Case-sensitive (uppercase), like
  # every other setting value. Validated here (typo protection), not at fit
  # time.
  raw_pr <- settings[["parametric_regression"]]
  if (is.null(raw_pr) || identical(raw_pr, FALSE)) {
    parametric_regression <- FALSE
  } else {
    parametric_regression <- trimws(as.character(raw_pr))
    if (length(parametric_regression) != 1 ||
        !parametric_regression %in% c("FALSE", "WEIBULL")) {
      stop("parametric_regression must be false or WEIBULL (found: ",
           paste(raw_pr, collapse = ", "), ").")
    }
    if (parametric_regression == "FALSE") parametric_regression <- FALSE
  }

  # weibull_shape_crossing: whether the per-predictor shape variants may give
  # every COMBINATION of the other predictors a Weibull shape of its own. FALSE
  # by default, so a variant fits an additive shape formula, one shape term per
  # dimension. Crossing is the advanced reading: where it runs, the data can
  # prefer it decisively (on OC2 it does, in both variants that can afford it),
  # but it spends a shape parameter per cell, a thin cell cannot pay for one,
  # and the fallback that follows leaves one sheet's model different from
  # another's in the same run.
  #
  # The one setting whose absent case is not the behavior that preceded it.
  # That rule exists so an archived settings file keeps reproducing its run,
  # and for Weibull the guarantee is already gone: .fit_weibull searches
  # starting values and takes the better optimum wherever one exists, so these
  # numbers move whenever a better fit is found. Inverting the default costs a
  # reproducibility the fit itself does not offer.
  weibull_shape_crossing <- parse_logical_flag("weibull_shape_crossing")

  animal_group_columns <- settings[["animal_group_columns"]]
  if (!is.null(animal_group_columns)) {
    if (!is.character(animal_group_columns) || length(animal_group_columns) == 0) {
      stop("animal_group_columns must be a non-empty list of column name strings.")
    }
    animal_group_columns <- trimws(animal_group_columns)
  }

  references <- list(
    periods                = periods,
    animal_group_columns   = animal_group_columns,
    animal_group_reference = parse_scalar_reference("animal_group_reference"),
    intake_type_reference  = parse_scalar_reference("intake_type_reference"),
    period_reference       = period_reference,
    n_periods              = n_periods,
    has_period             = n_periods > 1,
    restricted_stay_cap    = restricted_stay_cap,
    plot_stay_cap          = plot_stay_cap,
    png_pointsize_factor   = png_pointsize_factor,
    png_line_width_factor  = png_line_width_factor,
    max_plot_strata        = max_plot_strata,
    # names = raw CSV values, values = L/T/N codes; NULL if CSV uses L/T/N directly.
    outcome_type_mapping   = outcome_type_mapping,
    outcome_type_delete    = outcome_type_delete,
    outcome_type_in_care   = outcome_type_in_care,
    discard_bad_rows       = discard_bad_rows,
    discard_overlapping_rows = discard_overlapping_rows,
    # Optional value maps (named character vectors, names = the values to
    # replace) applied in read_and_prepare_data before anything counts, filters,
    # or strata by these columns; NULL when unconfigured.
    intake_type_map        = parse_value_map(settings, "intake_type_map"),
    animal_group_map       = parse_value_map(settings, "animal_group_map"),
    # Optional early-stage row filters (list(mode, values[, column]) or NULL).
    # Applied in read_and_prepare_data as soon as the relevant column exists.
    intake_filter          = intake_filter,
    animal_group_filter    = animal_group_filter,
    other_filter           = other_filter,
    show_aj_cif_ci_ribbons = show_aj_cif_ci_ribbons,
    show_km_ci_ribbons     = show_km_ci_ribbons,
    parametric_regression  = parametric_regression,
    weibull_shape_crossing = weibull_shape_crossing,
    # Per-stratified-output emission flags, keyed by setting name; each is a
    # named logical c(png=, csv=). Read via .output_flag(). Only the stratified
    # plots honor these; the unified plots/CSVs are always produced.
    output_flags = list(
      km_survival_by_stratifier         = parse_output_flag("km_survival_by_stratifier"),
      km_remaining_los_by_stratifier    = parse_output_flag("km_remaining_los_by_stratifier"),
      km_census_by_tenure_by_stratifier = parse_output_flag("km_census_by_tenure_by_stratifier"),
      km_in_care_tenure_by_stratifier   = parse_output_flag("km_in_care_tenure_by_stratifier"),
      aj_cif_by_stratifier              = parse_output_flag("aj_cif_by_stratifier"),
      aj_conditional_by_stratifier      = parse_output_flag("aj_conditional_by_stratifier")
    )
  )

  return(references)
}
