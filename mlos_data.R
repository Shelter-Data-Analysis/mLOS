# mLOS - Data: Read CSV and Break Down by Period
# =======================================================================

# ---- The screening ledger ---------------------------------------------
#
# One record per screening stage, in execution order, shaped after the
# statistics table ShelterDataPrep writes (documented in that project's README
# under "The statistics table"). Matching its columns is the point: the two
# tables can be read by one reader and concatenated into a single flow from the
# raw extract to the rows the models ran on. mLOS's additions to the shared
# vocabulary are the `split` action, whose row count RISES, and the `pass` role
# for a keep-only filter; both are described in the User Guide.
#
# The register the attrition figures come from is derived from this ledger
# rather than recorded beside it, so the two cannot disagree.

# Distinct animal_id values in a frame, NA when the column is absent. Blanks are
# not counted: before the fill in read_and_prepare_data they are not yet an
# animal.
.distinct_animals <- function(df) {
  if (!("animal_id" %in% names(df))) return(NA_integer_)
  ids <- trimws(as.character(df$animal_id))
  length(unique(ids[!is.na(ids) & nzchar(ids)]))
}

# One by-value detail record per value a setting names, counted within the rows
# the step touched. `col_values` are the values the step matched on and
# `touched` the mask of rows it cut, kept, or rewrote.
#
# A value matching nothing keeps a record with a count of 0, and that zero is
# the point of the table. A settings file deliberately names labels that may be
# absent from a given extract, and a report of what did happen is exactly the
# report that cannot show a key which is misspelled, differently cased, or was
# flattened to TRUE/FALSE by YAML.
.value_breakdown <- function(role, column, values, col_values, touched, scope) {
  lapply(values, function(v) {
    list(role = role, column = column, value = v, scope = scope,
         mask = touched & !is.na(col_values) & col_values == v)
  })
}

# One stage row of the ledger. Takes counts rather than the frames they came
# from, because break_down_by_period records the period split, where "before"
# and "after" hold different things (stays, and animal-period rows).
.ledger_row <- function(step, name, action, column, detail,
                        rows_in, rows_affected, rows_out,
                        animal_id_in, animal_id_affected, animal_id_out) {
  data.frame(
    step               = as.integer(step),
    # mLOS's own name for the stage. Carried for the attrition projection and
    # for anyone reading results.json; deliberately NOT emitted to the
    # compatibility CSV, which identifies a stage the way ShelterDataPrep does,
    # by action, column and detail.
    name               = name,
    action             = action,
    column             = column,
    detail             = detail,
    rows_in            = as.integer(rows_in),
    rows_affected      = as.integer(rows_affected),
    rows_out           = as.integer(rows_out),
    animal_id_in       = as.integer(animal_id_in),
    animal_id_affected = as.integer(animal_id_affected),
    animal_id_out      = as.integer(animal_id_out),
    stringsAsFactors   = FALSE
  )
}

# The by-value table's shape when a run configured no setting that names values.
# Returned as a typed zero-row frame rather than NULL so the column names
# survive into results.json, exactly as .no_value_map_counts does.
.empty_ledger_detail <- function() {
  data.frame(step = integer(0), action = character(0), column = character(0),
             role = character(0), value = character(0), scope = character(0),
             rows_affected = integer(0), animal_id_affected = integer(0),
             stringsAsFactors = FALSE)
}

# Replace missing/blank entries in an optional stratification column with an
# explicit placeholder level, so the column never carries NA (coxph and
# survfit would otherwise silently drop those rows from the stratified
# analyses while the unified KM kept them). The label starts as "_UNKNOWN_"
# and grows an underscore on each side until it matches no value the user
# already has in that column. Reports the fill on the console.
.fill_missing_level <- function(values, col_name) {
  missing <- is.na(values) | trimws(values) == ""
  if (!any(missing)) return(values)
  label <- "_UNKNOWN_"
  while (label %in% values[!missing]) {
    label <- paste0("_", label, "_")
  }
  cat(col_name, ": filled ", sum(missing), " missing value(s) with \"",
      label, "\"\n", sep = "")
  values[missing] <- label
  values
}

# The counts a value map reports when there is nothing to report: no map
# configured, or no column for one to act on.
.no_value_map_counts <- function() {
  data.frame(from = character(0), to = character(0), rows_mapped = integer(0),
             stringsAsFactors = FALSE)
}

# Apply one optional value map (see parse_value_map) to a prepared column's
# values, returning the rewritten values and the per-pair hit counts.
#
# All replacements happen at once against the ORIGINAL values, so the pairs
# never chain: with XL -> LRG and LRG -> MED, an XL becomes LRG and stops
# there. That is what makes the result independent of the order the pairs are
# listed in, which a map written as a set of relabelings has every right to
# expect.
#
# A key matching nothing is not an error (the setting exists partly to name
# rare labels that may be absent from a given extract), so the report lists
# every pair with its count, including the zeros. That is the signal the
# user gets that a key is spelled wrong or was flattened to TRUE/FALSE by YAML,
# and checking it is their job (see parse_value_map).
#
# The counts come back as a data frame rather than a named vector because a
# vector's names do not survive JSON serialization (jsonlite writes it as a bare
# array), which would drop the very thing being counted; the same reason the
# attrition register is a frame. An unconfigured map returns the frame with zero
# rows, so the shape does not change with the setting.
#
# `hit` comes back beside the counts: it is the per-row index into the map's
# pairs, which is what lets the caller record each pair's rows as a by-value
# detail row of the ledger (and count the animals behind them) without matching
# a second time. NULL when no map was configured, the same way the counts frame
# is empty then.
.apply_value_map <- function(values, map, key_name) {
  if (is.null(map)) {
    return(list(values = values, counts = .no_value_map_counts(), hit = NULL))
  }

  hit     <- match(values, names(map))
  matched <- !is.na(hit)
  counts  <- data.frame(
    from        = names(map),
    to          = unname(map),
    rows_mapped = tabulate(hit[matched], nbins = length(map)),
    stringsAsFactors = FALSE,
    row.names   = NULL
  )
  values[matched] <- unname(map[hit[matched]])
  cat(key_name, ": transformed ", sum(matched), " value(s) [",
      paste0(counts$from, " -> ", counts$to, ": ", counts$rows_mapped,
             collapse = ", "),
      "]\n", sep = "")
  list(values = values, counts = counts, hit = hit)
}

# Apply one optional pass/cut value filter to `data` on `column`. `spec` is the
# list(mode, values) built by parse_filter_spec. Matching is on the trimmed
# column values (as.character, so factors compare by their labels). The caller
# applies these late in read_and_prepare_data, after the duplicate/overlap
# screens; by then intake_type and animal_group have been filled and factored,
# so a blank there matches as its "_UNKNOWN_" fill, while the "other" column is
# still raw and matches the CSV's labels directly. A configured filter whose
# column is absent is a hard error (the setting cannot be present without the
# column), and a filter that removes every row stops the run with a
# filter-specific message rather than letting the later empty-data check report
# a misleading period-window cause.
#
# Returns the filtered frame together with the keep mask and the values it
# matched on, so the caller can record what each named value cut or kept
# without re-deriving the comparison. An unconfigured filter never reaches
# here; the caller skips it, since a filter that did not run records no stage.
.apply_value_filter <- function(data, spec, column, label) {
  if (!(column %in% names(data))) {
    stop("The ", label, " filter is configured, but the column '", column,
         "' does not exist in the data. Remove the filter or add the column.")
  }
  col_vals <- trimws(as.character(data[[column]]))
  in_list  <- col_vals %in% spec$values
  keep     <- if (spec$mode == "pass") in_list else !in_list
  n_total  <- length(keep)
  n_keep   <- sum(keep)
  cat(label, " filter (", spec$mode, " ", paste(spec$values, collapse = ", "),
      "): dropped ", n_total - n_keep, ", kept ", n_keep, " of ", n_total,
      " row(s)\n", sep = "")
  if (!any(keep)) {
    stop("The ", label, " filter (", spec$mode, ") removed every row. ",
         "Check its values against the '", column, "' column of the data.")
  }
  list(data = data[keep, , drop = FALSE], keep = keep, col_vals = col_vals)
}

#' Read and prepare the MLOS CSV file
#'
#' @param csv_file Path to the CSV file (default: "MLOS.csv")
#' @param references References list from extract_references; uses
#'   references$periods and references$outcome_type_mapping.
#' @return Data frame with cleaned and typed data. Every cleaning and
#'   filtering step in this function removes rows without reordering them,
#'   so the returned rows keep their CSV file order (the overlapping-stay
#'   tie-break relies on it); the order is preserved downstream until
#'   break_down_by_period slices the data into periods.
read_and_prepare_data <- function(csv_file = "MLOS.csv", references) {
  periods <- references$periods
  outcome_type_mapping <- references$outcome_type_mapping

  # Read every column as character: read.csv's type inference would turn a
  # column whose values are all in {T, F, TRUE, FALSE} into a logical -- e.g.
  # a gender column of an all-female subset becomes FALSE -- the CSV-side
  # analog of the YAML boolean gotcha guarded in .parse_raw_labels. Dates
  # are parsed explicitly below, and no column is ever used as numeric.
  data <- read.csv(csv_file, stringsAsFactors = FALSE, colClasses = "character")
  rows_read <- nrow(data)

  # The screening ledger: how the rows of the CSV became the stays this analysis
  # runs on. Every count in it is already computed for the console messages
  # below; recording it here is what carries the flow into the results bundle
  # and so into results.json and the compatibility CSV, where a report can state
  # it without re-reading the source file and re-deriving the cleaning rules.
  #
  # A stage is recorded when it actually ran: one that had no occasion to run (a
  # filter that was not configured, a discard_bad_rows drop that found nothing)
  # is absent, while the always-run checks (blank records, duplicates, overlaps,
  # the study window) are recorded even when they removed nothing. The recodes
  # are recorded too, as stages whose row count is unchanged and whose
  # rows_affected says how many rows they rewrote.
  #
  # The one rule the call sites must follow: pass the FRAMES on either side of
  # the stage, never counts carried between stages. That is what makes a hole
  # detectable. A future row-removing step added without a record_step call
  # leaves the NEXT recorded stage starting somewhere other than where the
  # previous one finished, and the chain visibly stops joining up, which
  # tests/run_tests.R asserts against precisely for this reason. Counts carried
  # forward by hand would silently absorb those rows into the next stage
  # instead, and the suite would have nothing to catch.
  ledger        <- list()
  ledger_detail <- list()
  next_step     <- 0L

  # `affected` is the mask, over `before`'s rows, of what the stage removed or
  # rewrote; NULL for a stage that only observes, whose affected count is then
  # the rows it lost. `breakdown` is what .value_breakdown returned.
  record_step <- function(name, action, column, detail, before, after,
                          affected = NULL, breakdown = NULL) {
    step      <- next_step
    next_step <<- next_step + 1L
    ledger[[length(ledger) + 1L]] <<- .ledger_row(
      step, name, action, column, detail,
      rows_in            = nrow(before),
      rows_affected      = if (is.null(affected)) nrow(before) - nrow(after) else sum(affected),
      rows_out           = nrow(after),
      animal_id_in       = .distinct_animals(before),
      animal_id_affected = if (is.null(affected)) 0L
                           else .distinct_animals(before[affected, , drop = FALSE]),
      animal_id_out      = .distinct_animals(after)
    )
    for (b in breakdown) {
      ledger_detail[[length(ledger_detail) + 1L]] <<- data.frame(
        step               = as.integer(step),
        action             = action,
        column             = b$column,
        role               = b$role,
        value              = b$value,
        scope              = b$scope,
        rows_affected      = sum(b$mask),
        animal_id_affected = .distinct_animals(before[b$mask, , drop = FALSE]),
        stringsAsFactors   = FALSE
      )
    }
    invisible(NULL)
  }

  record_step("read", "read", basename(csv_file),
              paste0(ncol(data), " column(s)"), data, data)

  # Apply outcome_type_delete: drop rows whose raw outcome_type matches the list.
  # Done before any normalization so raw CSV labels are matched directly.
  if (!is.null(references$outcome_type_delete)) {
    raw_ot <- trimws(data$outcome_type)
    to_delete <- raw_ot %in% references$outcome_type_delete
    n_deleted <- sum(to_delete)
    cat("outcome_type_delete: removed", n_deleted, "animal(s) matching",
        paste(references$outcome_type_delete, collapse = ", "), "\n")
    kept <- data[!to_delete, ]
    record_step("outcome_type_delete", "cut", "outcome_type",
                paste0("drop where outcome_type in (",
                       paste(references$outcome_type_delete, collapse = ", "), ")"),
                data, kept, affected = to_delete,
                breakdown = .value_breakdown("cut", "outcome_type",
                                             references$outcome_type_delete,
                                             raw_ot, to_delete, "rows cut"))
    data <- kept
  }

  mandatory_cols <- c("intake_date", "outcome_date", "outcome_type")

  # Check for mandatory columns
  missing_cols <- setdiff(mandatory_cols, names(data))
  if (length(missing_cols) > 0) {
    stop("Missing mandatory columns: ", paste(missing_cols, collapse = ", "))
  }

  # Build animal_group from animal_group_columns if specified.
  ag_cols <- references$animal_group_columns
  if (!is.null(ag_cols)) {
    missing_ag <- setdiff(ag_cols, names(data))
    if (length(missing_ag) > 0) {
      stop("animal_group_columns: column(s) not found in CSV: ",
           paste(missing_ag, collapse = ", "))
    }
    # Fill each source column's blanks before concatenating: pasting a raw NA
    # would silently embed the text "NA" in the composite group name.
    parts <- lapply(ag_cols, function(col) {
      .fill_missing_level(as.character(data[[col]]), col)
    })
    data$animal_group <- do.call(paste, c(parts, list(sep = "_")))
    cat("animal_group_columns: built animal_group from",
        paste(ag_cols, collapse = ", "), "\n")
  }

  # The optional value filters run much later (after the duplicate-stay and
  # overlapping-stay screens, so those judge the complete file); carry the
  # "other" filter's named column through this pruning so it still exists when
  # that filter fires, then drop it there.
  optional_cols <- c("intake_type", "animal_group", "animal_id")
  other_filter_col <- if (!is.null(references$other_filter)) references$other_filter$column else character(0)
  cols_to_keep <- c(mandatory_cols, intersect(c(optional_cols, other_filter_col), names(data)))
  data <- data[, cols_to_keep, drop = FALSE]

  # Drop rows where all three key fields are missing (completely blank
  # records, e.g. a stray ",," line). Done on the raw strings BEFORE
  # validation: such a row carries no data worth stopping the run over,
  # whereas a row with a blank intake_date but a real outcome is a genuine
  # error that validation below must still catch.
  blank_field <- function(x) is.na(x) | trimws(as.character(x)) == ""
  all_missing <- blank_field(data$intake_date) &
                 blank_field(data$outcome_date) &
                 blank_field(data$outcome_type)
  n_all_missing <- sum(all_missing)
  if (n_all_missing > 0) {
    cat("Dropped", n_all_missing, "row(s) with no intake_date, outcome_date, or outcome_type.\n")
  }
  record_step("blank_records", "cut", "intake_date, outcome_date, outcome_type",
              "drop rows with none of intake_date, outcome_date, outcome_type",
              data, data[!all_missing, ], affected = all_missing)
  data <- data[!all_missing, ]

  # -----------------------------------------------------------------------
  # Row-level validation (discard_bad_rows controls drop vs. stop)
  # -----------------------------------------------------------------------
  discard_bad_rows <- isTRUE(references$discard_bad_rows)

  raw_intake_str <- data$intake_date   # still character at this point

  intake_parsed <- as.Date(raw_intake_str, format = "%Y-%m-%d")

  # Check 1: intake_date must be a valid date
  bad_intake <- is.na(intake_parsed)
  if (any(bad_intake)) {
    bad_vals <- unique(raw_intake_str[bad_intake])
    msg <- paste0(
      sum(bad_intake), " row(s) have an invalid or missing intake_date: ",
      paste(bad_vals, collapse = ", ")
    )
    if (discard_bad_rows) {
      cat("discard_bad_rows: dropping", sum(bad_intake),
          "row(s) with invalid intake_date.\n")
      record_step("invalid_intake_date", "cut", "intake_date",
                  "drop rows whose intake_date is missing or unparseable",
                  data, data[!bad_intake, ], affected = bad_intake)
      data          <- data[!bad_intake, ]
      intake_parsed <- intake_parsed[!bad_intake]
    } else {
      stop(msg, ". Fix the data or set discard_bad_rows: true to drop these rows.")
    }
  }

  # Check 2: outcome_date, when present, must be a valid date AND must not be
  #          earlier than intake_date (same-day intake and outcome is allowed)
  # Use data$outcome_date (re-aligned after possible intake drop in Check 1)
  outcome_str_cur    <- trimws(data$outcome_date)
  outcome_present    <- !is.na(outcome_str_cur) & outcome_str_cur != ""
  outcome_parsed_cur <- as.Date(data$outcome_date, format = "%Y-%m-%d")
  intake_parsed_cur  <- intake_parsed  # already aligned

  bad_outcome_parse <- outcome_present & is.na(outcome_parsed_cur)
  bad_outcome_order <- !is.na(outcome_parsed_cur) & outcome_parsed_cur < intake_parsed_cur
  bad_outcome       <- bad_outcome_parse | bad_outcome_order

  if (any(bad_outcome)) {
    bad_rows <- which(bad_outcome)
    details <- vapply(bad_rows, function(r) {
      if (bad_outcome_parse[r]) {
        paste0("row ", r, ": outcome_date='", data$outcome_date[r], "' cannot be parsed")
      } else {
        paste0("row ", r, ": outcome_date=", format(outcome_parsed_cur[r]),
               " < intake_date=", format(intake_parsed_cur[r]))
      }
    }, character(1))
    msg <- paste0(
      sum(bad_outcome), " row(s) have an invalid outcome_date:\n  ",
      paste(details, collapse = "\n  ")
    )
    if (discard_bad_rows) {
      cat("discard_bad_rows: dropping", sum(bad_outcome),
          "row(s) with invalid outcome_date.\n")
      record_step("invalid_outcome_date", "cut", "outcome_date",
                  "drop rows whose outcome_date is unparseable or precedes intake_date",
                  data, data[!bad_outcome, ], affected = bad_outcome)
      data               <- data[!bad_outcome, ]
      intake_parsed_cur  <- intake_parsed_cur[!bad_outcome]
      outcome_parsed_cur <- outcome_parsed_cur[!bad_outcome]
    } else {
      stop(msg, "\nFix the data or set discard_bad_rows: true to drop these rows.")
    }
  }

  # Check 3: outcome_type must be blank/NA, in outcome_type_delete, in outcome_type_in_care,
  #          or mappable to L/T/N.
  all_known_labels <- c(
    if (!is.null(references$outcome_type_mapping)) names(references$outcome_type_mapping),
    if (!is.null(references$outcome_type_delete))  references$outcome_type_delete,
    if (!is.null(references$outcome_type_in_care)) references$outcome_type_in_care,
    if (is.null(references$outcome_type_mapping))  c("L", "T", "N")
  )
  ot_cur        <- trimws(data$outcome_type)
  has_ot        <- !is.na(ot_cur) & ot_cur != ""
  unrecognized  <- has_ot & !(ot_cur %in% all_known_labels)

  if (any(unrecognized)) {
    bad_vals <- unique(ot_cur[unrecognized])
    msg <- paste0(
      sum(unrecognized), " row(s) have an unrecognized outcome_type: ",
      paste(bad_vals, collapse = ", "),
      ". Expected one of: ", paste(sort(unique(all_known_labels)), collapse = ", ")
    )
    if (discard_bad_rows) {
      cat("discard_bad_rows: dropping", sum(unrecognized),
          "row(s) with unrecognized outcome_type.\n")
      # No by-value breakdown: the detail table counts the values a SETTING
      # names, and what is unrecognized here is by definition named by none.
      record_step("unrecognized_outcome_type", "cut", "outcome_type",
                  "drop rows whose outcome_type no setting recognizes",
                  data, data[!unrecognized, ], affected = unrecognized)
      data <- data[!unrecognized, ]
    } else {
      stop(msg, "\nFix the data or set discard_bad_rows: true to drop these rows.")
    }
  }
  # -----------------------------------------------------------------------

  data$intake_date <- as.Date(data$intake_date, format = "%Y-%m-%d")
  data$outcome_date <- as.Date(data$outcome_date, format = "%Y-%m-%d")

  # Apply outcome_type_in_care: treat matching animals as still in care
  # (set outcome_type to NA; outcome_date is retained as the censoring date).
  # A recode, not a removal, so it is reported beside the attrition register
  # rather than as a step in it.
  n_recoded <- 0L
  if (!is.null(references$outcome_type_in_care)) {
    raw_ot <- trimws(data$outcome_type)
    to_recode <- !is.na(raw_ot) & raw_ot %in% references$outcome_type_in_care
    n_recoded <- sum(to_recode)
    cat("outcome_type_in_care: recoded", n_recoded, "animal(s) matching",
        paste(references$outcome_type_in_care, collapse = ", "),
        "to NA outcome_type (outcome_date retained for censoring)\n")
    record_step("outcome_type_in_care", "map", "outcome_type",
                paste0(paste(references$outcome_type_in_care, collapse = ", "),
                       " -> still in care (outcome_date kept as the censoring date)"),
                data, data, affected = to_recode,
                breakdown = .value_breakdown("map from", "outcome_type",
                                             references$outcome_type_in_care,
                                             raw_ot, to_recode, "rows mapped"))
    data$outcome_type[to_recode] <- NA
  }

  # Note: outcome_date will be NA for animals still in care - this is expected

  # Convert outcome_type to factor (categorical)
  # Valid values: L (community live), T (transfer), N (non-live)
  # Blank values for animals still in care will be NA
  data$outcome_type[trimws(data$outcome_type) == ""] <- NA

  # Check 4: an outcome_type with no outcome_date. It sits here rather than
  # beside the three checks above because it has to judge the outcome type
  # AFTER outcome_type_in_care has had its say: a code meaning "has not left
  # yet" is exactly the case where a blank outcome_date is correct, and that
  # setting is what declares which codes those are. What reaches this line is a
  # stay claiming to have ended without saying when, and nothing downstream can
  # tell it from an animal still in care: it is censored at the period end (or
  # the restricted cap), counts as an event nowhere, and holds the overlapping
  # stay screen open against every later stay of the same animal. Its length of
  # stay is then whatever the period boundary makes it, which is the quiet
  # inflation this check exists to prevent.
  no_outcome_date <- !is.na(data$outcome_type) & is.na(data$outcome_date)
  if (any(no_outcome_date)) {
    by_value <- table(data$outcome_type[no_outcome_date])
    msg <- paste0(
      sum(no_outcome_date), " row(s) have an outcome_type but no outcome_date: ",
      paste0(names(by_value), " (", as.integer(by_value), ")", collapse = ", "),
      ". Such a stay cannot be placed in time and would be analyzed as still in care"
    )
    if (discard_bad_rows) {
      cat("discard_bad_rows: dropping", sum(no_outcome_date),
          "row(s) with an outcome_type but no outcome_date.\n")
      # No by-value breakdown, as for the unrecognized outcome types above: the
      # detail table counts the values a SETTING names, and no setting names
      # these. They are reported by value in the message instead.
      record_step("outcome_type_without_date", "cut", "outcome_type, outcome_date",
                  "drop rows carrying an outcome_type with no outcome_date",
                  data, data[!no_outcome_date, ], affected = no_outcome_date)
      data <- data[!no_outcome_date, ]
    } else {
      stop(msg, ".\nFix the data, list the value under outcome_type_in_care if it ",
           "means the animal has not left, or set discard_bad_rows: true to drop ",
           "these rows.")
    }
  }

  if (!is.null(outcome_type_mapping)) {
    # Remap site-specific raw labels to canonical L/T/N codes.
    # outcome_type_mapping: names = raw CSV values, values = L/T/N codes.
    raw_values  <- trimws(data$outcome_type)
    non_missing <- !is.na(raw_values)
    mapped_mask <- non_missing & raw_values %in% names(outcome_type_mapping)
    record_step("outcome_type_mapping", "map", "outcome_type",
                paste(paste0(names(outcome_type_mapping), " -> ",
                             unname(outcome_type_mapping)), collapse = ", "),
                data, data, affected = mapped_mask,
                breakdown = .value_breakdown("map from", "outcome_type",
                                             names(outcome_type_mapping),
                                             raw_values, mapped_mask, "rows mapped"))
    data$outcome_type[non_missing] <- outcome_type_mapping[raw_values[non_missing]]
  } else {
    # No mapping supplied; CSV is expected to already use L/T/N directly.
    raw_values  <- trimws(data$outcome_type)
    non_missing <- !is.na(raw_values)
    data$outcome_type[non_missing] <- raw_values[non_missing]
  }

  data$outcome_type <- factor(data$outcome_type, levels = .OUTCOME_STATE_LEVELS)

  # Convert optional categorical columns to factors if they exist. Missing
  # values become an explicit "_UNKNOWN_" level (see .fill_missing_level)
  # rather than NA. For a constructed animal_group this is a no-op, since
  # its source columns were already filled before concatenation.
  # factor() with no levels argument sorts the levels alphabetically, and
  # that is deliberate: these categories have no natural order, so
  # alphabetical serves as a stable convention (see .stratum_levels_present
  # in mlos_common.R for the full ordering rationale, including why
  # frequency ordering was rejected).
  #
  # The optional intake_type_map / animal_group_map recodes are applied HERE,
  # between the fill and the factor conversion, which places them before
  # everything that reads these columns: the levels, every count and stratum
  # built from them, the value filters, and the period split. A mapped-away
  # value therefore leaves no empty level behind -- it is as if the data had
  # carried the mapped label all along. Two consequences of the position: a
  # blank matches as its "_UNKNOWN_" fill (so mapping "_UNKNOWN_" to a real
  # group works, exactly as the filters match it), and for a constructed
  # animal_group the keys are the composite values, since the concatenation has
  # already happened above.
  #
  # A map configured without its column is an error, as for the value filters:
  # the setting cannot do anything, and is far likelier to be a mistake than
  # deliberate.
  check_map_column <- function(map, column) {
    if (!is.null(map) && !(column %in% names(data))) {
      stop("The ", column, "_map setting is configured, but the column '", column,
           "' does not exist in the data. Remove the setting or add the column.")
    }
  }
  check_map_column(references$intake_type_map, "intake_type")
  check_map_column(references$animal_group_map, "animal_group")

  intake_type_mapped  <- .no_value_map_counts()
  animal_group_mapped <- .no_value_map_counts()

  # A map that was not configured rewrites nothing and records no stage; one
  # that was records every pair, including the pairs that matched nothing.
  map_step <- function(name, column, mapped) {
    if (is.null(mapped$hit)) return(invisible(NULL))
    counts <- mapped$counts
    record_step(name, "map", column,
                paste(paste0(counts$from, " -> ", counts$to), collapse = ", "),
                data, data, affected = !is.na(mapped$hit),
                breakdown = lapply(seq_len(nrow(counts)), function(j) {
                  list(role = "map from", column = column, value = counts$from[j],
                       scope = "rows mapped", mask = !is.na(mapped$hit) & mapped$hit == j)
                }))
  }

  if ("intake_type" %in% names(data)) {
    mapped <- .apply_value_map(
      .fill_missing_level(as.character(data$intake_type), "intake_type"),
      references$intake_type_map, "intake_type_map")
    intake_type_mapped <- mapped$counts
    map_step("intake_type_map", "intake_type", mapped)
    data$intake_type <- factor(mapped$values)
  }

  if ("animal_group" %in% names(data)) {
    mapped <- .apply_value_map(
      .fill_missing_level(as.character(data$animal_group), "animal_group"),
      references$animal_group_map, "animal_group_map")
    animal_group_mapped <- mapped$counts
    map_step("animal_group_map", "animal_group", mapped)
    data$animal_group <- factor(mapped$values)
  }

  # animal_id links an animal's period-split rows back together so Cox can
  # cluster its robust SE on the original animal. If the CSV supplies no
  # animal_id, generate one per row on the assumption that each row is a
  # distinct animal; blanks in a supplied column are filled the same way.
  # This guarantees animal_id is always present and fully populated.
  if ("animal_id" %in% names(data)) {
    data$animal_id <- as.character(data$animal_id)
    blank <- is.na(data$animal_id) | trimws(data$animal_id) == ""
    data$animal_id[blank] <- paste0("auto_", which(blank))
    ids_supplied <- TRUE
  } else {
    data$animal_id <- paste0("auto_", seq_len(nrow(data)))
    ids_supplied <- FALSE
  }

  # Duplicate-stay removal: rows sharing (animal_id, intake_date, outcome_date)
  # describe the same stay recorded more than once. Identical triples are
  # theoretically possible as two same-day round trips (only when intake_date
  # equals outcome_date), but far more likely reflect a re-classification or
  # an accidental duplicate, so only the LAST row of each set (the presumed
  # correction) is kept. NA outcome dates compare equal here, so two
  # still-in-care rows for one animal and intake date also collapse. With
  # auto-generated ids every row is its own animal and this is structurally a
  # no-op, so it can run unconditionally after the fill above; the count is
  # reported only when the CSV supplied real ids.
  dup <- duplicated(data[, c("animal_id", "intake_date", "outcome_date")],
                    fromLast = TRUE)
  if (ids_supplied) {
    cat("Duplicate stays removed (same animal_id, intake_date, outcome_date):",
        sum(dup), "\n")
  }
  record_step("duplicate_stays", "dedup", "animal_id, intake_date, outcome_date",
              "drop all but the last row of each repeated animal_id, intake_date, outcome_date",
              data, data[!dup, ], affected = dup)
  data <- data[!dup, ]

  # Overlapping-stay check (discard_overlapping_rows controls drop vs. stop):
  # two stays of the same animal_id overlap, a physical impossibility, when
  # each begins strictly before the other ends,
  #     intake_a < outcome_b  AND  intake_b < outcome_a,
  # with a blank outcome_date treated as unbounded (still in care), so two
  # still-in-care rows for one animal always conflict. Equivalently, stays do
  # NOT overlap exactly when one ends on or before the other begins: a stay
  # starting the day another ends (a same-day departure and return) is
  # legitimate and never flagged. Within each animal, rows are ranked longest
  # stay first (blank outcome ranks longest; equal lengths rank the later
  # file row first) and a row is dropped when it overlaps an already-kept
  # row, so the shorter stay of each overlapping pair loses, ties dropping
  # the earlier row in the file. Runs BEFORE the study-window trimming below
  # so overlaps are judged on the complete file, and removes rows by logical
  # mask so the survivors keep their file order. With auto-generated ids
  # every row is its own animal and the check finds nothing.
  intake_num    <- as.numeric(data$intake_date)
  outcome_bound <- ifelse(is.na(data$outcome_date), Inf,
                          as.numeric(data$outcome_date))
  stay_length   <- outcome_bound - intake_num
  overlap_drop  <- logical(nrow(data))
  overlap_notes <- character(0)
  stay_desc <- function(r) {
    paste0("row ", r, " (", format(data$intake_date[r]), " to ",
           if (is.na(data$outcome_date[r])) "still in care"
           else format(data$outcome_date[r]), ")")
  }
  for (idx in split(seq_len(nrow(data)), data$animal_id)) {
    if (length(idx) < 2) next
    ranked <- idx[order(stay_length[idx], idx, decreasing = TRUE)]
    kept <- integer(0)
    for (r in ranked) {
      hit <- kept[intake_num[r] < outcome_bound[kept] &
                  intake_num[kept] < outcome_bound[r]]
      if (length(hit) == 0) {
        kept <- c(kept, r)
      } else {
        overlap_drop[r] <- TRUE
        overlap_notes <- c(overlap_notes,
          paste0("animal_id ", data$animal_id[r], ": ", stay_desc(r),
                 " overlaps ", stay_desc(hit[1])))
      }
    }
  }
  if (any(overlap_drop) && !isTRUE(references$discard_overlapping_rows)) {
    stop(sum(overlap_drop),
         " row(s) overlap another stay of the same animal_id:\n  ",
         paste(overlap_notes, collapse = "\n  "),
         "\nFix the data or set discard_overlapping_rows: true to drop these rows.")
  }
  if (ids_supplied) {
    cat("Overlapping stays removed (shorter stay of each overlapping pair):",
        sum(overlap_drop), "\n")
  }
  record_step("overlapping_stays", "cut", "animal_id, intake_date, outcome_date",
              "drop the shorter stay of each pair of one animal's stays that overlap in time",
              data, data[!overlap_drop, ], affected = overlap_drop)
  data <- data[!overlap_drop, ]

  # -----------------------------------------------------------------------
  # Optional value filters (intake_type / animal_group / one named column).
  # Deliberately applied HERE -- after the duplicate-stay removal and the
  # overlapping-stay screen above -- so those integrity checks judge the
  # COMPLETE file, not a filtered subset. If a filter dropped one row of a
  # duplicate pair, or one leg of an overlapping pair, before those screens,
  # the conflict would go unseen (never dropped, and with
  # discard_overlapping_rows: false never raised). The filters do not interact
  # with the study-window trimming just below, so this is the latest point at
  # which they can run. Each keeps no statistics of its own; a filtered-out row
  # is simply absent. Matching is on the values as prepared above, so an
  # intake_type or animal_group blank reads as its "_UNKNOWN_" fill (see
  # .fill_missing_level); the "other" column is unmodified, matching raw labels.
  # -----------------------------------------------------------------------
  # A filter that is not configured is a no-op and records no stage. A cut
  # filter's named values are counted over the rows it removed, a pass filter's
  # over the rows it kept, since that is what each of them names.
  apply_filter <- function(name, spec, column, label) {
    if (is.null(spec)) return(invisible(NULL))
    res     <- .apply_value_filter(data, spec, column, label)
    passing <- identical(spec$mode, "pass")
    record_step(name, "cut", column,
                paste0(if (passing) "keep only where " else "drop where ", column,
                       " in (", paste(spec$values, collapse = ", "), ")"),
                data, res$data, affected = !res$keep,
                breakdown = .value_breakdown(
                  if (passing) "pass" else "cut", column, spec$values, res$col_vals,
                  if (passing) res$keep else !res$keep,
                  if (passing) "rows kept" else "rows cut"))
    data <<- res$data
    invisible(NULL)
  }

  apply_filter("intake_filter", references$intake_filter, "intake_type", "intake_type")
  apply_filter("animal_group_filter", references$animal_group_filter,
               "animal_group", "animal_group")

  if (!is.null(references$other_filter)) {
    ocol <- references$other_filter$column
    apply_filter("other_filter", references$other_filter, ocol, paste0("other (", ocol, ")"))
    # Retained through the earlier pruning only to be filtered on; it is not
    # used anywhere else, so drop it now unless it is a standard analysis column.
    if (!(ocol %in% c(mandatory_cols, optional_cols))) {
      data[[ocol]] <- NULL
    }
  }

  first_date <- min(periods$start_date)
  last_date <- max(periods$end_date)
  n_before <- nrow(data)

  # Discard observations that left before the study period began (outcome_date
  # prior to the first date) or entered on or after it ended. One mask rather
  # than two consecutive subsettings, since both are row-wise predicates and the
  # ledger records this as the single stage it is.
  in_window <- (is.na(data$outcome_date) | data$outcome_date >= first_date) &
               data$intake_date < last_date

  record_step("outside_study_window", "cut", "intake_date, outcome_date",
              paste0("drop where outcome_date < ", format(first_date),
                     " or intake_date >= ", format(last_date)),
              data, data[in_window, ], affected = !in_window)
  data <- data[in_window, ]

  n_after <- nrow(data)
  n_discarded <- n_before - n_after

  # Report filtering results
  cat("\n=== Data Filtering Results ===\n")
  cat("Records before filtering:", n_before, "\n")
  cat("Records after filtering: ", n_after, "\n")
  cat("Records discarded:       ", n_discarded, "\n")
  cat("Study period: ", format(first_date), " to ", format(last_date), "\n\n")

  # Without this, downstream code fails obscurely on the empty data frame
  # (e.g. "attempt to set an attribute on NULL" in break_down_by_period).
  if (n_after == 0) {
    stop("No records remain within the study window (", format(first_date),
         " to ", format(last_date), "). Every stay was filtered out or dropped -- ",
         "check period_dates and the data file.")
  }

  data$in_care          <- is.na(data$outcome_type) & is.na(data$outcome_date)
  data$censored_early   <- is.na(data$outcome_type) & !is.na(data$outcome_date)
  data$has_outcome      <- !is.na(data$outcome_type)

  # Carried on the returned frame rather than returned beside it, so no caller
  # has to change shape to pass it along; break_down_by_period forwards it onto
  # period_data the same way it forwards its own drop counts, and
  # build_results_bundle reads both off there. Everything here is a stay-level
  # figure: one row is one stay, before the period split multiplies a stay that
  # spans periods into one row per period. That is what makes these worth
  # carrying -- every count elsewhere in the bundle is at the period-row level,
  # and no other output states the size of the cohort itself.
  ledger_df <- do.call(rbind, ledger)

  # The attrition register is the row-removing part of the ledger, in the order
  # it ran: a projection rather than a second record, so the two cannot drift
  # apart. `read` is excluded because it removes nothing, and the recodes
  # because they rewrite rows without removing any; both are still in the
  # ledger, where rows_affected says what they touched.
  removing <- ledger_df$action %in% c("cut", "dedup")

  attr(data, "preparation") <- list(
    rows_read            = rows_read,
    rows_prepared        = nrow(data),
    attrition            = data.frame(
      step         = ledger_df$name[removing],
      rows_before  = ledger_df$rows_in[removing],
      rows_after   = ledger_df$rows_out[removing],
      rows_removed = ledger_df$rows_in[removing] - ledger_df$rows_out[removing],
      stringsAsFactors = FALSE
    ),
    # The full screening ledger and its by-value table (see the top of this
    # file). Every stage, including the recodes and the read itself, with the
    # animal counts on either side; break_down_by_period appends the period
    # split's own stages before the register reaches the results bundle.
    ledger               = ledger_df,
    ledger_detail        = if (length(ledger_detail) > 0) do.call(rbind, ledger_detail)
                           else .empty_ledger_detail(),
    recoded_in_care      = n_recoded,
    # Value-map hit counts, one row per configured pair (from, to,
    # rows_mapped). Recodes rather than removals, so they sit beside the
    # attrition register like recoded_in_care above. No rows means the map was
    # not configured: a configured one always lists every pair, a zero count
    # included, which is what distinguishes "no map" from "matched nothing".
    mapped_intake_type   = intake_type_mapped,
    mapped_animal_group  = animal_group_mapped,
    animal_ids_supplied  = ids_supplied,
    n_animals            = length(unique(data$animal_id)),
    stays_in_care        = sum(data$in_care),
    stays_censored_early = sum(data$censored_early),
    stays_with_outcome   = sum(data$has_outcome),
    study_window_start   = as.character(first_date),
    study_window_end     = as.character(last_date),
    intake_date_first    = as.character(min(data$intake_date)),
    intake_date_last     = as.character(max(data$intake_date)),
    # NA rather than an empty-range artefact when no stay has an outcome date
    # at all (every animal still in care), the same case display_data_summary
    # guards before printing the range.
    outcome_date_first   = if (any(!is.na(data$outcome_date)))
                             as.character(min(data$outcome_date, na.rm = TRUE)) else NA_character_,
    outcome_date_last    = if (any(!is.na(data$outcome_date)))
                             as.character(max(data$outcome_date, na.rm = TRUE)) else NA_character_
  )

  return(data)
}


#' Detect optional stratification columns and augment references
#'
#' Must be called after read_and_prepare_data. Adds has_intake_type,
#' n_intake_types, has_animal_group, and n_animal_groups to the references
#' list so every downstream step can use them without re-inspecting the data.
#'
#' @param data Data frame from read_and_prepare_data
#' @param references List from extract_references
#' @return Updated references list with the four new fields
detect_optional_columns <- function(data, references) {
  if ("intake_type" %in% names(data)) {
    clean <- data$intake_type[!is.na(data$intake_type)]
    references$n_intake_types <- length(unique(clean))
  } else {
    references$n_intake_types <- 0
  }
  references$has_intake_type <- references$n_intake_types > 1

  if ("animal_group" %in% names(data)) {
    clean <- data$animal_group[!is.na(data$animal_group)]
    references$n_animal_groups <- length(unique(clean))
  } else {
    references$n_animal_groups <- 0
  }
  references$has_animal_group <- references$n_animal_groups > 1

  references
}


#' Display summary statistics of the data
#'
#' @param data Data frame from read_and_prepare_data
display_data_summary <- function(data) {

  cat("\n=== Data Summary ===\n")
  cat("Total records:", nrow(data), "\n")
  cat("Animals still in care:", sum(data$in_care), "\n")
  cat("Animals censored (unclassified exit):", sum(data$censored_early), "\n")
  cat("Animals with outcomes:", sum(data$has_outcome), "\n\n")

  cat("Date ranges:\n")
  cat("  Intake dates:  ", format(min(data$intake_date)), " to ",
      format(max(data$intake_date)), "\n")
  if (any(data$has_outcome | data$censored_early)) {
    cat("  Outcome dates: ", format(min(data$outcome_date, na.rm = TRUE)), " to ",
        format(max(data$outcome_date, na.rm = TRUE)), "\n")
  }

  cat("\nOutcome types:\n")
  print(table(data$outcome_type, useNA = "ifany"))

  if ("intake_type" %in% names(data)) {
    cat("\nIntake types:\n")
    print(table(data$intake_type, useNA = "ifany"))
  }

  if ("animal_group" %in% names(data)) {
    cat("\nAnimal groups:\n")
    print(table(data$animal_group, useNA = "ifany"))
  }

  if ("animal_id" %in% names(data)) {
    cat("\nUnique animals:", length(unique(data$animal_id[!is.na(data$animal_id)])), "\n")
  }
}


#' Break data down by period with left-truncation and right-censoring
#'
#' Each observation gets a separate entry for each period it participates in.
#' Left-truncation: If an animal was already in care when the period started,
#'                  we only observe from the period start (not from intake)
#' Right-censoring: If an animal is still in care when the period ends,
#'                  we censor at the period end
#'
#' @param data Data frame from read_and_prepare_data
#' @param references References list; uses references$periods and references$restricted_stay_cap.
#' @return Data frame with one row per animal per period, including survival variables
break_down_by_period <- function(data, references) {
  periods <- references$periods

  # One id per cleaned input row, i.e. per stay record, so the period-split
  # rows can be re-unified downstream (see calculate_unified_stay_counts).
  # animal_id alone cannot key a stay: an animal can return for a later stay,
  # even on the same day it left, so (animal_id, intake_date) is not unique
  # either (real data contains same-day out-and-back-in pairs).
  data$stay_id <- seq_len(nrow(data))

  period_data_list <- list()
  dropped_invalid_by_period <- integer(nrow(periods))

  # Ledger bookkeeping for the split (see the top of this file): how many
  # periods each stay is observed in, how many rows that produced before the
  # invalid-interval drop below, and which animals that drop took away.
  participation <- integer(nrow(data))
  rows_created  <- 0L
  invalid_ids   <- character(0)

  # Process each period
  for (i in 1:nrow(periods)) {
    period_start <- periods$start_date[i]
    period_end <- periods$end_date[i]
    period_num <- periods$period_num[i]
    period_label <- periods$period_label[i]

    # Find animals that participate in this period
    # An animal participates if:
    # - intake_date < period_end (entered before period ended)
    # - AND (outcome_date >= period_start OR still in care)

    participating <- data$intake_date < period_end &
                     (is.na(data$outcome_date) | data$outcome_date >= period_start)

    period_subset <- data[participating, ]
    participation <- participation + as.integer(participating)
    rows_created  <- rows_created + nrow(period_subset)

    if (nrow(period_subset) == 0) {
      # A defined-but-empty period is a data condition worth flagging: it is
      # skipped by every per-period analysis and can never serve as the Cox
      # period reference (see mlos_cox.R).
      cat("\n*** WARNING: ", period_label, " (", format(period_start), " to ",
          format(period_end), ") contains no observations ***\n", sep = "")
      next
    }

    # Create period-specific dataframe
    period_df <- period_subset

    # Add period identifier
    period_df$period_num <- period_num
    period_df$period_label <- period_label
    period_df$period_start <- period_start
    period_df$period_end <- period_end

    # Calculate left-truncation time
    # If animal was already in care at period start, we left-truncate
    # Time at risk starts from max(intake_date, period_start)
    period_df$time_start <- pmax(
      as.numeric(period_start - period_df$intake_date),
      0
    )

    # Calculate observation end time
    # Observation ends at min(outcome_date, period_end) or period_end if still in care
    # Add +1 because both arrival and departure day count in the stay
    # However, period_end is the first day NOT in the period, so the +1 is already contained in it
    # The +1 for outcomes ensures time_end > time_start (never equal), since time_start >= 0
    period_df$time_end <- ifelse(
      is.na(period_df$outcome_date),
      as.numeric(period_df$period_end - period_df$intake_date),
      pmin(
        as.numeric(period_df$outcome_date - period_df$intake_date) + 1,
        as.numeric(period_df$period_end - period_df$intake_date)
      )
    )

    # Determine censoring status for this period
    # Event (status=1) occurs if:
    # - Animal had an outcome AND
    # - Outcome occurred before period end
    # Otherwise censored (status=0)
    period_df$event <- ifelse(
      !is.na(period_df$outcome_type) & !is.na(period_df$outcome_date) & period_df$outcome_date < period_df$period_end,
      1,
      0
    )

    # Apply restricted stay cap for restricted mean calculation
    # If time_end exceeds the cap, truncate it and treat as censored
    period_df$capped_at_rmean <- period_df$time_end > references$restricted_stay_cap

    # For capped observations, set time_end to cap and event to 0 (censored)
    period_df$time_end <- pmin(period_df$time_end, references$restricted_stay_cap)
    period_df$event <- ifelse(period_df$capped_at_rmean, 0, period_df$event)

    # CRITICAL: Ensure time_end > time_start (survival package requirement)
    # If time_start >= time_end after capping, drop those rows from this period.
    # This preserves the interval math instead of modifying observed times.
    invalid_times <- period_df$time_start >= period_df$time_end
    if (any(invalid_times)) {
      dropped_invalid_by_period[i] <- sum(invalid_times, na.rm = TRUE)
      invalid_ids <- c(invalid_ids,
                       as.character(period_df$animal_id[which(invalid_times)]))
      period_df <- period_df[!invalid_times, ]
    }

    # Calculate days_at_risk after capping
    # We don't add +1, because the time_end and time_start are already
    #     computed to include the days of arrival and departure
    # In effect, for animals that arrived and left intraday, days_at_risk=1
    period_df$days_at_risk <- period_df$time_end - period_df$time_start

    period_df$left_truncated <- period_df$intake_date < period_start
    period_df$right_censored <- (is.na(period_df$outcome_type) |
                                  is.na(period_df$outcome_date) |
                                  period_df$outcome_date >= period_df$period_end |
                                  period_df$capped_at_rmean)
    period_data_list[[i]] <- period_df
  }

  period_data <- do.call(rbind, period_data_list)
  rownames(period_data) <- NULL

  # Make period_label a factor with chronological levels, the single canonical
  # order every model, plot, and worksheet reads back through
  # .stratum_levels_present -- exactly as intake_type/animal_group are made
  # factors in read_and_prepare_data. Without this, survfit coerces the raw
  # character column to an ALPHABETICAL factor ("Period_10" before "Period_2")
  # and the KM by-period output drifts out of chronological order. Levels are
  # periods$period_label (built chronologically in mlos_setup.R) restricted to
  # periods that actually contributed rows, mirroring how those other factors
  # carry only present levels and avoiding a zero-row survfit stratum.
  present_levels <- periods$period_label[
    periods$period_label %in% unique(as.character(period_data$period_label))]
  period_data$period_label <- factor(period_data$period_label, levels = present_levels)

  # Forward the preparation register (see read_and_prepare_data): subsetting
  # and rbind drop custom attributes, so it has to be re-attached here to reach
  # build_results_bundle, which sees period_data and not the frame it came from.
  #
  # Three counts are added here rather than there, since they need the split
  # this function performs. They answer why the animal-period row count exceeds
  # the stay count, and they are the figures keyed on animal_id
  # (calculate_unified_stay_counts keys on stay_id, so it cannot see a repeat
  # visitor as one animal).
  #
  # animals_with_multiple_rows deliberately does NOT mean "animals whose stay
  # was split across a period boundary". Two quite different things put an
  # animal on more than one row, and on real data the larger is the one that
  # has nothing to do with periods: an animal that came back for a genuinely
  # separate later stay, which can even sit inside a single period. The other
  # two rows separate the causes, so the first is interpretable rather than a
  # number two effects are hiding behind.
  prep <- attr(data, "preparation")
  rows_per_animal  <- table(period_data$animal_id)
  stays_per_animal <- tapply(period_data$stay_id, period_data$animal_id,
                             function(v) length(unique(v)))
  prep$animals_with_multiple_rows <- sum(rows_per_animal > 1)
  prep$animals_with_repeat_stays  <- sum(stays_per_animal > 1)
  prep$stays_split_across_periods <- sum(table(period_data$stay_id) > 1)

  # The split's own three stages, appended to the ledger read_and_prepare_data
  # built. They are what stops the analyzed row count from matching nothing
  # upstream: the register above ends at a count of STAYS, and every stratum
  # section downstream is denominated in animal-period ROWS.
  #
  # `split` is the one action verb whose rows_out exceeds its rows_in, and the
  # reason mLOS's ledger is not monotone the way an upstream preparation ledger
  # is. Its rows_affected is the number of stays that landed on more than one
  # row, the ones the rise is made of.
  #
  # A stay in no period at all is possible only when the period definitions
  # leave a gap, since the study-window cut already removed everything outside
  # their span. It is recorded even when it takes nothing, so the chain joins.
  next_step   <- max(prep$ledger$step) + 1L
  in_period   <- data[participation > 0, , drop = FALSE]
  n_no_period <- sum(participation == 0)
  prep$ledger <- rbind(prep$ledger, rbind(
    .ledger_row(next_step, "no_period", "cut", "intake_date, outcome_date",
                "drop stays that fall in a gap between periods",
                nrow(data), n_no_period, nrow(in_period),
                .distinct_animals(data),
                .distinct_animals(data[participation == 0, , drop = FALSE]),
                .distinct_animals(in_period)),
    .ledger_row(next_step + 1L, "period_split", "split", "period_label",
                "one row per period a stay is observed in, left-truncated and censored at the period bounds",
                nrow(in_period), sum(participation > 1), rows_created,
                .distinct_animals(in_period),
                .distinct_animals(data[participation > 1, , drop = FALSE]),
                .distinct_animals(in_period)),
    .ledger_row(next_step + 2L, "invalid_interval", "cut", "time_start, time_end",
                "drop rows the cap or the truncation left with no time at risk (time_start >= time_end)",
                rows_created, sum(dropped_invalid_by_period), nrow(period_data),
                .distinct_animals(in_period),
                length(unique(invalid_ids)),
                .distinct_animals(period_data))
  ))

  # Generated ids are one per row, so counting them would restate rows_* under
  # a name that promises animals. Blanked here, once, rather than at each stage:
  # whether the file supplied ids is not known until well into the screening.
  if (!isTRUE(prep$animal_ids_supplied)) {
    prep$ledger$animal_id_in       <- NA_integer_
    prep$ledger$animal_id_affected <- NA_integer_
    prep$ledger$animal_id_out      <- NA_integer_
    if (nrow(prep$ledger_detail) > 0) {
      prep$ledger_detail$animal_id_affected <- NA_integer_
    }
  }

  attr(period_data, "preparation") <- prep

  # Store dropped invalid-time counts as attributes for reporting
  attr(period_data, "dropped_invalid_by_period") <- data.frame(
    period_num = periods$period_num,
    period_label = periods$period_label,
    dropped_invalid_rows = dropped_invalid_by_period,
    stringsAsFactors = FALSE
  )
  attr(period_data, "dropped_invalid_total") <- sum(dropped_invalid_by_period)

  return(period_data)
}


#' Calculate daily mean of total in-care days by period
#' On each night an animal is in care it contributes its days in care as of that
#' night, on the inclusive count, which is also the number of nights it has been
#' held since intake, including that night. Equivalently, this is the elapsed
#' count on the next morning.
#' Nights are credited to the period containing the following morning --
#' the same convention as the overnight census (mean_census minus mean daily
#' intakes) -- so the two metrics count exactly the same nights, and a stay
#' split across periods contributes LOS - 1 nights in total (period splitting
#' is neutral; see tests/cases/in_care_days_boundary_neutrality).
#' An animal that comes and goes intra-day has LoS=1, no overnight stay, and
#' contributes nothing.
#' For example, time_start=0, time_end=4 means:
#'     no truncation and the animal had 3 (not 4) overnight stays
#'     the in-care days were 1, 2, 3; that's three values, with mean 2.
#' A left-truncated row keeps the night straddling the period boundary:
#'     time_start=5, time_end=9 contributes 5, 6, 7, 8.
#'
#' For each animal-period row, the contributions are the integers
#' m, ..., time_end - 1 with m = max(time_start, 1), summing to
#'   (time_end - m) * (m + time_end - 1) / 2
#' (time_end - m) is non-negative because time_end adds +1 for outcomes,
#' so time_end > time_start and days_at_risk >= 1. Invalid intervals are dropped in break_down_by_period.
#' Then sums across animals within each period and divides by period length in days.
#'
#' @param period_data Data frame from break_down_by_period
#' @param col Column of period_data to group by (default "period_label";
#'   the Excel stratum sheets pass "intake_type" or "animal_group")
#' @param window_days Denominator override in days. Required when col is not
#'   "period_label": a stratum subset spans several periods, so no single
#'   period length exists, and the callers pass the total days across all
#'   periods instead. NULL (the default) keeps the per-period length.
#' @return Data frame with one row per group and the daily mean metric;
#'   period_label holds the group label and period_num is NA for
#'   non-period groupings
calculate_daily_mean_total_in_care_days <- function(period_data, col = "period_label",
                                                    window_days = NULL) {
  by_period <- identical(col, "period_label")
  rows <- .map_period_subsets(period_data, function(period_subset, lbl) {
    m <- pmax(period_subset$time_start, 1)
    per_animal_value <- (
      (period_subset$time_end - m) *
      (period_subset$time_end + m - 1) / 2
    )

    total_in_care_days_sum <- sum(per_animal_value, na.rm = TRUE)
    period_days <- if (!is.null(window_days)) {
      window_days
    } else {
      as.numeric(unique(period_subset$period_end) - unique(period_subset$period_start))
    }

    daily_mean_total_in_care_days <- if (!is.na(period_days) && period_days > 0) {
      total_in_care_days_sum / period_days
    } else {
      NA_real_
    }

    data.frame(
      period_num = if (by_period) unique(period_subset$period_num) else NA_integer_,
      period_label = lbl,
      period_days = period_days,
      total_in_care_days_sum = total_in_care_days_sum,
      daily_mean_total_in_care_days = daily_mean_total_in_care_days,
      stringsAsFactors = FALSE
    )
  }, col = col)

  result <- do.call(rbind, rows)
  rownames(result) <- NULL
  result[order(result$period_num), ]
}


#' Calculate intake/outcome flow metrics by period
#'
#' For each period:
#' - total_intakes: intake_date within [period_start, period_end)
#' - total_outcomes: outcome_date within [period_start, period_end)
#' - mean_daily_*: totals divided by period length in days
#'
#' @param period_data Data frame from break_down_by_period
#' @param col Column of period_data to group by (default "period_label";
#'   the Excel stratum sheets pass "intake_type" or "animal_group")
#' @param window_days Denominator override in days; required for non-period
#'   cols, same as in calculate_daily_mean_total_in_care_days
#' @return Data frame with one row per group and flow metrics; period_label
#'   holds the group label and period_num is NA for non-period groupings
calculate_period_flow_metrics <- function(period_data, col = "period_label",
                                          window_days = NULL) {
  by_period <- identical(col, "period_label")
  rows <- .map_period_subsets(period_data, function(period_subset, lbl) {
    period_days <- if (!is.null(window_days)) {
      window_days
    } else {
      as.numeric(unique(period_subset$period_end) - unique(period_subset$period_start))
    }

    # Each row is checked against its own row's period window. For a period
    # subset every row shares that period's bounds, so this is the original
    # per-period count; for a stratum subset spanning several periods, each
    # stay's intake/outcome date falls inside exactly one of its rows'
    # windows, so it is counted once, in the period that contains it.
    total_intakes <- sum(
      !is.na(period_subset$intake_date) &
      period_subset$intake_date >= period_subset$period_start &
      period_subset$intake_date < period_subset$period_end,
      na.rm = TRUE
    )
    total_outcomes <- sum(
      !is.na(period_subset$outcome_type) &
      !is.na(period_subset$outcome_date) &
      period_subset$outcome_date >= period_subset$period_start &
      period_subset$outcome_date < period_subset$period_end,
      na.rm = TRUE
    )

    mean_daily_intakes <- if (!is.na(period_days) && period_days > 0) {
      total_intakes / period_days
    } else {
      NA_real_
    }
    mean_daily_outcomes <- if (!is.na(period_days) && period_days > 0) {
      total_outcomes / period_days
    } else {
      NA_real_
    }

    data.frame(
      period_num = if (by_period) unique(period_subset$period_num) else NA_integer_,
      period_label = lbl,
      period_days = period_days,
      total_intakes = total_intakes,
      total_outcomes = total_outcomes,
      mean_daily_intakes = mean_daily_intakes,
      mean_daily_outcomes = mean_daily_outcomes,
      stringsAsFactors = FALSE
    )
  }, col = col)

  result <- do.call(rbind, rows)
  rownames(result) <- NULL
  result[order(result$period_num), ]
}


#' Calculate per-period observation statistics
#'
#' Single source for the per-period counts and census metrics reported both by
#' the console period-breakdown summary (display_period_breakdown_summary) and
#' by every stratified report, through the results bundle (mlos_results.R). The
#' non-period stratifiers reuse it with `col` so their counts keep
#' the exact By_Period row semantics, deliberately: rows are animal-period
#' segments truncated and censored at period boundaries, so a long stay
#' contributes one row per period it touches to its stratum's column.
#'
#' @param period_data Data frame from break_down_by_period
#' @param period_labels Labels to compute rows for; defaults to the labels
#'   present in period_data (a label with no rows yields zero counts)
#' @param period_days_lookup Optional named lookup of days per label; when
#'   absent, the length is derived from the subset's period_start/period_end.
#'   Required for non-period cols (a stratum subset spans several periods, so
#'   no single length can be derived); the Excel stratum sheets pass the total
#'   days across all periods for every label.
#' @param col Column of period_data to group by (default "period_label";
#'   the Excel stratum sheets pass "intake_type" or "animal_group"). All
#'   counts stay row-level animal-period counts whatever the grouping.
#' @return Data frame with one row per label; the label column is named
#'   period_label for every grouping
calculate_period_observation_stats <- function(period_data, period_labels = NULL,
                                               period_days_lookup = NULL,
                                               col = "period_label") {
  values <- as.character(period_data[[col]])
  if (is.null(period_labels)) {
    period_labels <- unique(values)
    period_labels <- period_labels[!is.na(period_labels)]
  }

  rows <- lapply(period_labels, function(lbl) {
    period_subset <- period_data[!is.na(values) & values == lbl, , drop = FALSE]
    period_days <- if (!is.null(period_days_lookup)) {
      period_days_lookup[lbl][[1L]]
    } else {
      as.numeric(unique(period_subset$period_end) - unique(period_subset$period_start))
    }
    if (length(period_days) == 0) period_days <- NA_real_

    total_animal_days <- sum(period_subset$days_at_risk, na.rm = TRUE)
    mean_census <- if (!is.na(period_days) && period_days > 0) {
      total_animal_days / period_days
    } else {
      NA_real_
    }

    data.frame(
      period_label       = lbl,
      period_days        = period_days,
      total_observations = nrow(period_subset),
      events             = sum(period_subset$event, na.rm = TRUE),
      censored           = sum(!period_subset$event, na.rm = TRUE),
      left_truncated     = sum(period_subset$left_truncated, na.rm = TRUE),
      right_censored     = sum(period_subset$right_censored, na.rm = TRUE),
      capped_at_rmean    = sum(period_subset$capped_at_rmean, na.rm = TRUE),
      mean_days_at_risk  = mean(period_subset$days_at_risk, na.rm = TRUE),
      total_animal_days  = total_animal_days,
      mean_census        = mean_census,
      stringsAsFactors = FALSE
    )
  })

  result <- do.call(rbind, rows)
  rownames(result) <- NULL
  result
}


#' Unified-across-periods stay counts by stratum
#'
#' The stay-level counterpart of the three row-level counts in
#' calculate_period_observation_stats whose meaning depends on period
#' splitting (total_observations, left_truncated, right_censored). Here each
#' stay counts exactly once, re-unified across period boundaries:
#'
#' - total_stays: distinct stays, keyed by the stay_id that
#'   break_down_by_period assigns per cleaned input row (animal_id cannot key
#'   a stay because an animal can return, even on the day it left)
#' - left_truncated_stays: stays whose intake precedes the start of the first
#'   period in which they are observed (in care before observation begins,
#'   or entering during a gap between periods), read from the left_truncated
#'   flag of the stay's earliest row
#' - right_censored_stays: stays with no observed outcome event in any of
#'   their rows (still in care at the end of observation, lost in a gap, or
#'   capped at the restricted stay cap)
#'
#' Feeds the top section of the Excel By_Intake_Type / By_Animal_Group
#' sheets, whose remaining sections keep the row-level By_Period conventions.
#'
#' @param period_data Data frame from break_down_by_period
#' @param labels stratum labels to compute rows for (a label with no rows
#'   yields zero counts)
#' @param col Column of period_data to group by
#' @return Data frame with one row per label; the label column is named
#'   period_label, matching the other shared metric functions
calculate_unified_stay_counts <- function(period_data, labels, col) {
  values <- as.character(period_data[[col]])
  rows <- lapply(labels, function(lbl) {
    subset_df <- period_data[!is.na(values) & values == lbl, , drop = FALSE]
    if (nrow(subset_df) == 0) {
      return(data.frame(period_label = lbl, total_stays = 0L,
                        left_truncated_stays = 0L, right_censored_stays = 0L,
                        stringsAsFactors = FALSE))
    }
    stay_key <- subset_df$stay_id
    # A stay's rows have strictly increasing time_start (counting process),
    # so ordering by time_start and keeping each key's first occurrence
    # selects every stay's earliest observed row.
    row_order <- order(subset_df$time_start)
    first_rows <- row_order[!duplicated(stay_key[row_order])]
    stay_has_event <- tapply(subset_df$event, stay_key, function(v) any(v == 1))
    data.frame(
      period_label         = lbl,
      total_stays          = length(first_rows),
      left_truncated_stays = sum(subset_df$left_truncated[first_rows], na.rm = TRUE),
      right_censored_stays = sum(!unlist(stay_has_event)),
      stringsAsFactors = FALSE
    )
  })
  result <- do.call(rbind, rows)
  rownames(result) <- NULL
  result
}


#' Outcome counts, mix, and incidence rates per stratum
#'
#' The three outcome blocks of every stratified report, computed together
#' because they share a row set and a denominator. Returns NULL when the data
#' carries no classified event rows at all, which is what the reports test to
#' decide between showing the blocks and showing a "not available" note.
#'
#' The outcome rows come from the FULL data's event rows, not from what one
#' stratum happened to observe, so every stratified report of the same dataset
#' carries the same rows in the same order and a stratum that never saw an
#' outcome type gets a zero rather than a missing row.
#'
#' @param period_data Data frame from break_down_by_period
#' @param labels stratum labels, in display order
#' @param col Column of period_data to group by
#' @param total_animal_days Days at risk per label, the incidence denominator
#' @param events_overall All events per label, the numerator of the overall
#'   incidence row. An event row always carries a classified outcome_type
#'   (break_down_by_period requires it for event = 1), so this equals the
#'   summed per-outcome counts; it is taken from the caller's observation
#'   stats rather than recounted here, so the overall row and the events row
#'   of the observations block cannot drift apart.
#' @return List with outcome_levels, counts (one row per outcome, counts),
#'   totals (completed outcomes per label), mix (share within completed
#'   outcomes) and incidence (events per 100 animal-days, overall row first);
#'   or NULL when no classified events exist
.stratum_outcome_matrices <- function(period_data, labels, col, total_animal_days,
                                      events_overall) {
  event_rows <- period_data[period_data$event == 1 & !is.na(period_data$outcome_type), ]
  if (nrow(event_rows) == 0) return(NULL)

  outcome_levels <- intersect(.OUTCOME_STATE_LEVELS, as.character(event_rows$outcome_type))
  if (length(outcome_levels) == 0) return(NULL)

  event_col_values <- as.character(event_rows[[col]])
  counts <- matrix(
    sapply(labels, function(lbl) {
      tbl <- table(factor(event_rows$outcome_type[event_col_values == lbl], levels = outcome_levels))
      as.numeric(tbl)
    }),
    nrow = length(outcome_levels), ncol = length(labels)
  )
  rownames(counts) <- paste0("outcome_", outcome_levels, "_events")
  colnames(counts) <- labels

  totals <- colSums(counts, na.rm = TRUE)

  mix_rows <- lapply(seq_along(outcome_levels), function(i) {
    ifelse(totals > 0, counts[i, ] / totals, NA_real_)
  })
  mix <- do.call(rbind, mix_rows)
  rownames(mix) <- paste0("outcome_mix_", outcome_levels)
  colnames(mix) <- labels

  rate_rows <- c(
    list(ifelse(total_animal_days > 0, events_overall / total_animal_days * 100, NA_real_)),
    lapply(seq_along(outcome_levels), function(i) {
      ifelse(total_animal_days > 0, counts[i, ] / total_animal_days * 100, NA_real_)
    })
  )
  incidence <- do.call(rbind, rate_rows)
  rownames(incidence) <- c("incidence_overall_per_100_animal_days",
                           paste0("incidence_", outcome_levels, "_per_100_animal_days"))
  colnames(incidence) <- labels

  list(outcome_levels = outcome_levels, counts = counts, totals = totals,
       mix = mix, incidence = incidence)
}


#' Report the period breakdown to the console
#'
#' Progress reporting, not a results outlet. Every number here is in the results
#' bundle (`strata$period`) and on the By_Period sheet, so this prints the per
#' period counts as one dump of the very data frame the bundle is built from
#' rather than re-deriving them and hand-formatting a second copy of that sheet.
#'
#' @param period_data Data frame from break_down_by_period
display_period_breakdown_summary <- function(period_data) {

  cat("\n=== Period Breakdown Summary ===\n")
  cat("Total observations (animal-periods):", nrow(period_data), "\n\n")
  print(calculate_period_observation_stats(period_data), row.names = FALSE)

  # A diagnostic rather than a result: rows the period split could not keep,
  # reported only when there are some. The per-period breakdown behind this
  # total is in the bundle's data_preparation node.
  dropped_invalid_total <- attr(period_data, "dropped_invalid_total")
  if (!is.null(dropped_invalid_total) && dropped_invalid_total > 0) {
    cat("\nRows dropped for an invalid interval (time_start >= time_end):",
        dropped_invalid_total, "\n")
  }

  if (sum(period_data$event) > 0) {
    cat("\nOutcome types (events only):\n")
    event_data <- period_data[period_data$event == 1, ]
    print(table(event_data$outcome_type, event_data$period_label))
  }
}
