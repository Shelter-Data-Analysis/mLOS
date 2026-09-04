# mLOS - Cox Regression Analysis
# =======================================================================

# Relevel a factor predictor column and report the reference level used.
# Only called when the predictor has >1 level (has_xxxxx is TRUE).
# Reference semantics:
#   - named and present -> used;
#   - named but absent  -> ERROR (typo protection: silently substituting a
#     different baseline would reparametrize the model behind the user's back);
#   - NULL (unnamed)    -> most frequent level, counted over animal-period
#     rows; a filled _UNKNOWN_ level is eligible like any other.
# setting_name is the settings-file key named in the error message.
.relevel_and_report <- function(data, col, reference, label, setting_name) {
  if (!is.null(reference)) {
    ref_str <- as.character(reference)
    if (!ref_str %in% levels(data[[col]])) {
      stop(label, " reference '", ref_str, "' not found in the data (available: ",
           paste(levels(data[[col]]), collapse = ", "),
           "). Check ", setting_name, " in the settings file.")
    }
    default <- ""
  } else {
    ref_str <- names(which.max(table(data[[col]])))
    default <- " (most frequent)"
  }
  data[[col]] <- relevel(data[[col]], ref = ref_str)
  cat(label, " reference: ", ref_str, default, "\n", sep = "")
  data
}

# One definitional reference row for a coefficient table: the effect
# estimate is exactly 1 (the reference is the denominator of every ratio,
# not an estimate), CI and p-value stay NA and export as blank cells.
.reference_row_for <- function(tbl, variable, value_col) {
  row <- tbl[NA_integer_, , drop = FALSE]
  row$variable <- variable
  row[[value_col]] <- 1
  row
}

# Insert each factor predictor's reference level into a coefficient table
# as a definitional row (see .reference_row_for), at the level's CANONICAL
# slot -- chronological for period, alphabetical for intake_type and
# animal_group -- so every predictor block lists all levels in the same
# order as the By_Period / By_Intake_Type / By_Animal_Group worksheet
# columns, whatever reference policy is in force (an OLDEST period
# reference lands first, a NEWEST one last, a mid-order group reference in
# the middle). xlevels comes from the fit with the reference first
# (relevel's doing), so xlevels[[term]][1] identifies it;
# canonical_levels carries the pre-relevel order captured in
# cox_regression_analysis. Only terms actually in the fit (present in
# xlevels) get a row, so a dropped period predictor or an absent optional
# column inserts nothing.
.insert_reference_rows <- function(tbl, xlevels, canonical_levels, value_col) {
  blocks <- list()
  used <- rep(FALSE, nrow(tbl))
  for (term in names(xlevels)) {
    canon <- canonical_levels[[term]]
    if (is.null(canon)) next
    ref_level <- xlevels[[term]][1]
    block <- list()
    for (lv in canon) {
      var_name <- paste0(term, lv)
      if (identical(lv, ref_level)) {
        block[[length(block) + 1]] <- .reference_row_for(tbl, var_name, value_col)
      } else {
        idx <- which(tbl$variable == var_name)
        if (length(idx) > 0) {
          used[idx] <- TRUE
          block[[length(block) + 1]] <- tbl[idx, , drop = FALSE]
        }
      }
    }
    blocks[[term]] <- do.call(rbind, block)
  }
  # Rows outside every canonical block (none today) are appended rather
  # than silently dropped.
  out <- do.call(rbind, c(blocks, list(tbl[!used, , drop = FALSE])))
  rownames(out) <- NULL
  out
}


#' Perform Cox regression analysis with period, intake type, and animal group
#'
#' @param period_data Data frame from break_down_by_period
#' @param references List with reference values from extract_references
#' @return List containing Cox model fit and summary statistics
cox_regression_analysis <- function(period_data, references) {

  cat("\n=======================================================================\n")
  cat("COX REGRESSION ANALYSIS\n")
  cat("=======================================================================\n")

  # The period predictor qualifies only when at least two periods actually
  # contain data: a defined-but-empty period (warned about in
  # break_down_by_period) contributes no rows, and a single-level factor
  # would crash coxph.
  present_periods <- sort(unique(period_data$period_num))
  has_period_predictor <- length(present_periods) > 1

  # With no qualifying predictor (fewer than two periods with data, no
  # intake_type or animal_group column), the formula would be surv_obj ~ 1: a
  # null model with no coefficients to test, so the global tests
  # (logtest/waldtest/sctest) are undefined. Rather than fit a degenerate
  # model, skip Cox regression entirely.
  if (!has_period_predictor && !references$has_intake_type && !references$has_animal_group) {
    cat("\nNo predictors available (fewer than two periods with data, no intake_type\n")
    cat("or animal_group column) -- Cox regression requires at least one predictor. Skipping.\n")
    return(list(has_analysis = FALSE,
                message = "no predictors available (fewer than two periods with data, no intake_type/animal_group)"))
  }

  # Create Surv object for left-truncated, right-censored data
  surv_obj <- .make_surv_obj(period_data)

  # -------------------------------------------------------------------------
  # Prepare predictors with reference levels
  # -------------------------------------------------------------------------

  # Period predictor, built on period LABELS -- the same labels the KM strata
  # and the By_Period sheet use -- so coefficients read e.g. "periodQ2_2024".
  # Levels must be set explicitly in chronological period order: factor()
  # alone would sort labels alphabetically ("Q10" before "Q2"). Only periods
  # with data become levels (an empty period would be a zero-row level).
  n_periods <- references$n_periods
  periods_with_data <- references$periods[references$periods$period_num %in% present_periods, ]
  period_data$period <- factor(period_data$period_label,
                               levels = periods_with_data$period_label)
  cat("\nPeriods: ", n_periods, " period(s) defined, ",
      length(present_periods), " with data\n", sep = "")

  # Canonical level orders, captured BEFORE any releveling: chronological
  # for period (set explicitly above), alphabetical for intake_type and
  # animal_group (fixed once at read_and_prepare_data). Reference-row
  # insertion into the coefficient tables (.insert_reference_rows) restores
  # this order regardless of which level relevel() moves to the front.
  canonical_levels <- list(period = levels(period_data$period))
  if (references$has_intake_type)  canonical_levels$intake_type  <- levels(period_data$intake_type)
  if (references$has_animal_group) canonical_levels$animal_group <- levels(period_data$animal_group)

  if (has_period_predictor) {
    # OLDEST/NEWEST name a policy, not a level: resolve them against the
    # periods that contain data, so an empty boundary period cannot make the
    # requested reference unsatisfiable (the original pre-refactor semantics).
    ref_num <- if (references$period_reference == "NEWEST") {
      max(present_periods)
    } else {
      min(present_periods)
    }
    ref_label <- references$periods$period_label[match(ref_num, references$periods$period_num)]
    period_data <- .relevel_and_report(period_data, "period", ref_label, "Period",
                                       setting_name = "period_reference")
    cat("  (", tolower(references$period_reference), " period with data)\n", sep = "")
  } else if (references$has_period) {
    cat("Period: only one period contains data -- excluded from the model\n")
  }

  # Intake type and animal group — availability from references (detect_optional_columns)
  if (references$has_intake_type) {
    period_data <- .relevel_and_report(period_data, "intake_type",
                                       references$intake_type_reference, "Intake type",
                                       setting_name = "intake_type_reference")
  }
  if (references$has_animal_group) {
    period_data <- .relevel_and_report(period_data, "animal_group",
                                       references$animal_group_reference, "Animal group",
                                       setting_name = "animal_group_reference")
  }

  # animal_id is guaranteed present and fully populated by read_and_prepare_data
  # (auto-generated when the CSV omits it), so Cox always clusters the robust SE
  # on animal_id. This keeps the period-split rows of one animal in one cluster.
  cat("Clustered SE: Using animal_id for robust standard errors\n")

  # -------------------------------------------------------------------------
  # Build and fit Cox regression model
  # -------------------------------------------------------------------------

  # Build formula from available predictors; "1" is a valid null model and a
  # no-op when other predictors are present, so no special-casing needed.
  #
  # The terms are named one by one rather than looped over the stratifiers
  # registry, because each needs its own availability test and its own
  # reference-level handling above (period's reference resolves OLDEST/NEWEST
  # against the periods with data; the other two take a named level). That
  # makes this a place a new stratifier has to be wired by hand, so it is
  # also the place that has to notice when one has not been. See
  # .assert_stratifier_model_wiring in mlos_common.R for what goes wrong
  # silently otherwise.
  .assert_stratifier_model_wiring(c("period", "intake_type", "animal_group"))
  predictors <- c(
    "1",
    if (has_period_predictor)        "period",
    if (references$has_intake_type)  "intake_type",
    if (references$has_animal_group) "animal_group"
  )
  formula_parts <- paste("surv_obj ~", paste(predictors, collapse = " + "))

  cat("\n=== Cox Regression Model ===\n")
  cat("Model formula: ", formula_parts, "\n", sep = "")

  # Fit the model (always clustered on animal_id for robust SE).
  #
  # ties = "efron" is named rather than left to the default because it is a
  # modelling choice, not a numerical detail: event times are whole days, so
  # every day with more than one outcome is a tie, and the tie rule decides
  # what the reported hazard ratio estimates. Efron targets the within-day
  # rate ratio (math methods Section 6.2), which is the quantity the
  # sim_geometric_period_effect fixture pins against its generating truth.
  cox_model <- survival::coxph(
    as.formula(formula_parts),
    data = period_data,
    cluster = animal_id,
    robust = TRUE,
    ties = "efron"
  )

  cox_summary <- summary(cox_model)

  # Print essential model info
  cat("  n =", cox_model$n, ", number of events =", cox_model$nevent, "\n")
  # summary(coxph)$concordance is c(C, se(C)) -- the second element is
  # already the standard error, not a variance.
  cat("  Concordance =", round(cox_summary$concordance[1], 3),
      " (se =", round(cox_summary$concordance[2], 3), ")\n")

  # Print test statistics
  cat("  Likelihood ratio test =", round(cox_summary$logtest[1], 1),
      " on", cox_summary$logtest[2], "df,   p =",
      format.pval(cox_summary$logtest[3], digits = 2), "\n")
  cat("  Wald test            =", round(cox_summary$waldtest[1], 1),
      " on", cox_summary$waldtest[2], "df,   p =",
      format.pval(cox_summary$waldtest[3], digits = 2), "\n")
  cat("  Score (logrank) test =", round(cox_summary$sctest[1], 1),
      " on", cox_summary$sctest[2], "df,   p =",
      format.pval(cox_summary$sctest[3], digits = 2))

  # Add robust score test info if clustered. In some degenerate fits (e.g. a
  # single categorical predictor with a zero-event level) coxph's robust
  # variance does not yield a robscore, and summary() leaves it NULL.
  if (!is.null(cox_summary$robscore)) {
    cat(",   Robust =", round(cox_summary$robscore[1], 1),
        " p =", format.pval(cox_summary$robscore[3], digits = 2), "\n")
  } else {
    cat(",   Robust = not available\n")
  }
  cat("  (Note: the likelihood ratio and score tests assume independence of\n")
  cat("     observations within a cluster, the Wald and robust score tests do not).\n")

  # -------------------------------------------------------------------------
  # Extract hazard ratios
  # -------------------------------------------------------------------------

  coef_table <- cox_summary$coefficients
  conf_table <- cox_summary$conf.int

  hr_table <- data.frame(
    variable = rownames(coef_table),
    hr = exp(coef_table[, "coef"]),
    ci_lower = conf_table[, "lower .95"],
    ci_upper = conf_table[, "upper .95"],
    p_value = coef_table[, "Pr(>|z|)"],
    stringsAsFactors = FALSE
  )

  # Insert the reference levels as definitional hr = 1 rows: the table then
  # lists every level of every predictor in canonical order, matching the
  # By_Period / By_Intake_Type / By_Animal_Group worksheet columns.
  hr_table <- .insert_reference_rows(hr_table, cox_model$xlevels, canonical_levels, "hr")

  # The table itself, with its bounds and its HR > 1 / < 1 reading, is on the
  # Cox_Regression sheet and in the bundle; the console reports only its size.
  cat("Hazard ratios: ", nrow(hr_table), " rows (one per level of each predictor)\n", sep = "")

  # -------------------------------------------------------------------------
  # Per-predictor stratified variants (see .cox_stratified_variants)
  # -------------------------------------------------------------------------

  stratified_variants <- .cox_stratified_variants(period_data, surv_obj, predictors[-1],
                                                  cox_model$xlevels, canonical_levels)

  # -------------------------------------------------------------------------
  # Optional parametric companion fit (parametric_regression: WEIBULL)
  # -------------------------------------------------------------------------

  weibull_results <- NULL
  if (identical(references$parametric_regression, "WEIBULL")) {
    # The crude companion drops the group terms: intercept + period only
    # (just the intercept when fewer than two periods have data). Built with
    # the same c("1", ...) idiom as formula_parts above so the two strings
    # compare equal when the main model already has no group terms -- the
    # identical() check in .weibull_regression_analysis relies on that to
    # recognize the crude fit as the main fit instead of refitting it.
    #
    # The results.json key for this block is still weibull$unified, which is
    # the reserved word for a whole-sample output everywhere else. Rename it to
    # weibull$crude the next time the goldens churn for another reason: OC1 and
    # OC2 regenerate easily and no results are stored or distributed, so the
    # only cost is regenerating tests/golden for every Weibull fixture.
    #
    # Keeping period while dropping intake_type/animal_group is deliberate,
    # not an accident of ordering. The block exists to expose
    # composition-driven shape: a mixture of fast- and slow-leaving groups
    # produces a declining pooled hazard (a Weibull k < 1) even when every
    # group is memoryless, because the risk set drifts toward the slow group
    # as tenure grows. That sorting needs a PERSISTENT subject-level
    # attribute, which intake_type and animal_group are and period is not:
    # period_data splits a crossing stay into one row per period, so period
    # is a time-varying covariate of the row and no animal carries a period
    # membership for the risk set to sort on. Keeping it leaves the
    # diagnostic measuring composition rather than calendar-time drift in
    # LOS. If period ever became a stay-level attribute (period of intake,
    # say), this reasoning would no longer hold and the term should be
    # dropped with the others.
    unified_formula_parts <- paste("surv_obj ~",
                                   paste(c("1", if (has_period_predictor) "period"),
                                         collapse = " + "))
    weibull_results <- .weibull_regression_analysis(period_data, surv_obj, formula_parts,
                                                    cox_model$xlevels, canonical_levels,
                                                    unified_formula_parts, predictors[-1],
                                                    isTRUE(references$weibull_shape_crossing))
  }

  # -------------------------------------------------------------------------
  # Return results
  # -------------------------------------------------------------------------

  results <- list(
    has_analysis        = TRUE,
    cox_model           = cox_model,
    hr_table            = hr_table,
    stratified_variants = stratified_variants,
    weibull             = weibull_results
  )

  return(results)
}

# Per-predictor stratified Cox fits: one model per qualifying predictor X that
# carries X alone in the linear predictor while every OTHER qualifying predictor
# moves inside strata(), so each combination of the others gets its own
# unrestricted baseline hazard and X's hazard ratios become within-cell
# contrasts. With period, intake type and animal group all qualifying, the
# "period" variant is
#   surv_obj ~ period + strata(intake_type, animal_group)
# and symmetrically for the other two. A single strata() call crossing the other
# terms is what makes each COMBINATION a baseline rather than each dimension
# separately.
#
# This is the Cox counterpart of the per-predictor Weibull shape variants below
# (§6.7 of the methods doc), and it answers the same question: what happens to
# X's coefficient once the other predictors stop being forced to share one
# baseline. The pooled model above adjusts for them, but proportional hazards
# still ties every covariate pattern to the single baseline h0(t), so the pooled
# and stratified estimates of X agree when that assumption holds for the OTHER
# predictors and diverge when it does not. That comparison is the closest thing
# mLOS has to a proportional-hazards diagnostic (it has no Schoenfeld test),
# which is why the variants are fit unconditionally rather than behind a setting.
#
# Needs at least two qualifying predictors: with one there is no other predictor
# to stratify on and the variant would simply be the pooled model refit.
#
# Three things a variant does NOT give, all consequences of the free baseline
# rather than defects, and all restated in the bundle's consumers:
#   - the likelihood-ratio test (and Wald, score, robust score) compares the fit
#     against the STRATIFIED null on X's degrees of freedom alone, so the
#     statistic is not comparable with the pooled model's joint test;
#   - concordance is computed within strata, likewise not comparable;
#   - the stratified predictors get no coefficients at all, so a variant
#     stratified on period is silent about period by construction.
#
# surv_obj is passed rather than rebuilt because coxph resolves it from the
# formula's environment, which as.formula takes from here.
.cox_stratified_variants <- function(period_data, surv_obj, main_terms,
                                     xlevels, canonical_levels) {
  if (length(main_terms) < 2) return(list())

  cat("\n=== Stratified Cox variants (one per stratifier) ===\n")

  term_to_stratifier_id <- .stratifier_ids_by_model_term()
  variants <- list()

  for (term in main_terms) {
    other_terms <- setdiff(main_terms, term)
    variant_formula <- paste0("surv_obj ~ ", term, " + strata(",
                              paste(other_terms, collapse = ", "), ")")
    sid <- term_to_stratifier_id[[term]]

    fit <- tryCatch(
      survival::coxph(as.formula(variant_formula), data = period_data,
                      cluster = animal_id, robust = TRUE, ties = "efron"),
      error = function(e) e
    )
    if (inherits(fit, "error")) {
      cat("  ", variant_formula, " -- fit failed (", conditionMessage(fit),
          "), skipping\n", sep = "")
      variants[[sid]] <- list(has_analysis = FALSE,
                              message = paste0("fit failed: ", conditionMessage(fit)))
      next
    }

    # Baseline strata as the fit sees them: combinations actually present in the
    # rows (drop = TRUE), of which only those holding at least one event
    # contribute to the partial likelihood at all. Reporting both is what lets a
    # consumer judge whether the stratification was affordable on this dataset
    # -- the failure mode here is sparsity, not misspecification.
    strata_key <- interaction(period_data[other_terms], drop = TRUE, sep = ", ")
    events_per_stratum <- tapply(period_data$event, strata_key, sum)

    s <- summary(fit)
    robscore <- if (is.null(s$robscore)) c(NA_real_, NA_real_, NA_real_) else s$robscore

    hr_table <- data.frame(
      variable = rownames(s$coefficients),
      hr       = exp(s$coefficients[, "coef"]),
      ci_lower = s$conf.int[, "lower .95"],
      ci_upper = s$conf.int[, "upper .95"],
      p_value  = s$coefficients[, "Pr(>|z|)"],
      stringsAsFactors = FALSE
    )
    # Only the focal term's reference row: the stratified terms have no
    # coefficients, and coxph files their crossed factor in xlevels under the
    # full call string ("strata(intake_type, animal_group)"), so passing the
    # whole xlevels would offer .insert_reference_rows a term it has no
    # canonical order for. Restricting to the focal term says so explicitly.
    hr_table <- .insert_reference_rows(hr_table, xlevels[term], canonical_levels, "hr")

    cat("  ", variant_formula, "\n", sep = "")
    cat("    ", length(events_per_stratum), " baseline strata (",
        sum(events_per_stratum > 0), " with events); LR = ", round(s$logtest[1], 1),
        " on ", s$logtest[2], " df, p = ", format.pval(s$logtest[3], digits = 2), "\n", sep = "")

    variants[[sid]] <- list(
      has_analysis         = TRUE,
      formula              = variant_formula,
      n                    = fit$n,
      n_events             = fit$nevent,
      concordance          = unname(s$concordance[1]),
      concordance_se       = unname(s$concordance[2]),
      uses_clustered_se    = TRUE,
      effect_stratifier    = sid,
      strata_stratifiers   = unname(term_to_stratifier_id[other_terms]),
      n_strata             = length(events_per_stratum),
      n_strata_with_events = sum(events_per_stratum > 0),
      xlevels              = xlevels[term],
      tests = data.frame(
        test      = c("Likelihood ratio", "Wald", "Score (logrank)", "Robust score"),
        statistic = unname(c(s$logtest[1], s$waldtest[1], s$sctest[1], robscore[1])),
        df        = unname(c(s$logtest[2], s$waldtest[2], s$sctest[2], robscore[2])),
        p_value   = unname(c(s$logtest[3], s$waldtest[3], s$sctest[3], robscore[3])),
        stringsAsFactors = FALSE
      ),
      hr_table = hr_table
    )
  }

  variants
}

# One exponentiated-coefficient table: exp(beta) with a Wald 95% CI and the
# coefficient's own two-sided p-value, under whatever name the ratio goes by
# on that side of the model (los_ratio for a scale coefficient, shape_ratio
# for a shape one). The two tables below read different coefficients and call
# the result different things, but the arithmetic is the same, so it lives
# here once. Zero coefficients in gives zero rows out.
.wald_ratio_table <- function(vname, beta, se, value_col) {
  tbl <- data.frame(
    variable = vname,
    value    = exp(beta),
    ci_lower = exp(beta - 1.96 * se),
    ci_upper = exp(beta + 1.96 * se),
    p_value  = 2 * stats::pnorm(-abs(beta / se)),
    stringsAsFactors = FALSE
  )
  names(tbl)[names(tbl) == "value"] <- value_col
  tbl
}

# Likelihood ratio of one fitted flexsurvreg model against a NESTED one, so it
# lives here once: the main Weibull fit and every shape variant test against the
# intercept-only null, and a crossed shape variant additionally tests against the
# additive shape formula it replaced. NULL through when the smaller fit itself
# failed, and the caller's test row shows NA.
.lr_nested <- function(fit, sub_fit) {
  if (is.null(sub_fit)) return(NULL)
  stat <- 2 * (fit$loglik - sub_fit$loglik)
  df   <- fit$npars - sub_fit$npars
  list(stat = stat, df = df, p = stats::pchisq(stat, df, lower.tail = FALSE))
}

# Shape and coefficient tables of one fitted flexsurvreg Weibull model.
# Shape on the natural scale (fit$res); covariate effects on the log-time
# scale (fit$res.t rows fit$covpars[fit$mx$scale]), where exp(beta) is the
# LOS ratio. Restricting to fit$mx$scale (rather than every fit$covpars row)
# is what keeps this table to SCALE covariates only when a fit also carries
# shape(...) covariates (see the shape-variant block of
# .weibull_regression_analysis below, and .weibull_shape_table for those); for
# the two existing call sites here (the main Cox-companion Weibull fit and its
# crude companion), neither ever puts anything on shape, so
# mx$scale == seq_along(covpars) there and this is a no-op change.
# Handles a covariate-free fit (fit$covpars NULL, so fit$covpars[fit$mx$scale]
# is NULL too): the tables come back with zero rows.
.weibull_fit_tables <- function(fit) {
  k    <- unname(fit$res["shape", "est"])
  k_lo <- unname(fit$res["shape", "L95%"])
  k_hi <- unname(fit$res["shape", "U95%"])

  rows  <- fit$covpars[fit$mx$scale]
  vname <- rownames(fit$res.t)[rows]
  beta  <- unname(fit$res.t[rows, "est"])
  se    <- unname(fit$res.t[rows, "se"])

  los_table <- .wald_ratio_table(vname, beta, se, "los_ratio")
  p_cov     <- los_table$p_value

  # Implied hazard ratios: hr = LOS_ratio^(-k) = exp(-k*beta). Delta-method
  # CI on g = -k*beta over the estimation-scale parameters (log k is
  # parameter 1 in vcov): dg/dlog(k) = -k*beta, dg/dbeta = -k. hr = 1 iff
  # beta = 0, so the p-value is the coefficient's own.
  V <- vcov(fit)
  se_g <- vapply(seq_along(rows), function(j) {
    idx  <- c(1L, rows[j])
    grad <- c(-k * beta[j], -k)
    sqrt(drop(t(grad) %*% V[idx, idx] %*% grad))
  }, numeric(1))
  hr_table <- data.frame(
    variable  = vname,
    hr        = exp(-k * beta),
    ci_lower  = exp(-k * beta - 1.96 * se_g),
    ci_upper  = exp(-k * beta + 1.96 * se_g),
    p_value   = p_cov,
    stringsAsFactors = FALSE
  )

  list(k = k, k_lo = k_lo, k_hi = k_hi, los_table = los_table, hr_table = hr_table)
}

# Shape-covariate coefficient table of one fitted flexsurvreg model that used
# shape(...) formula terms (see the shape-variant block of
# .weibull_regression_analysis below): shape_ratio = exp(beta), the
# multiplicative effect on the Weibull shape parameter, with a plain Wald
# CI/p-value (.wald_ratio_table). Deliberately NOT the delta-method
# implied-HR of .weibull_fit_tables: that formula assumes beta is a
# location/scale coefficient combined with a single global shape k, which
# does not describe a shape covariate itself. fit$res.t rownames for a shape
# covariate look like "shape(x2Q)"; stripped back to "x2Q" here so the row
# naming matches the paste0(term, level) convention .insert_reference_rows
# expects (the same convention the scale table above already uses). Handles
# a fit with no shape covariates (fit$mx$shape empty): the table comes back
# with zero rows.
#
# Returned as TWO tables, split on whether the coefficient is an interaction.
# The crossed shape formula (see the shape-variant block below) estimates a
# coefficient per non-focal CELL, so its fitted rows include products like
# "shape(intake_typeOTH:animal_groupLARGE)" beside the main effects.
#
# `main` keeps the shape table the rest of the tool has always consumed: rows
# that .insert_reference_rows can place at a canonical (term, level) slot, and
# that mlos_review can decode, since it recovers a level as a SUFFIX
# (recommend.py _shape_level) and would read an interaction row ending in that
# level as the level's own ratio. Products must stay out of it for that reason.
#
# `interaction` is the rest, published as its own table and consumed by nothing:
# in the bundle and on the worksheet so that a reader who wants the whole fitted
# model can have it, in flexsurv's own row order and without reference rows,
# because a product term has no single (term, level) slot to be ordered by. It
# is a CORRECTION and not a shape: a combination's own k is the baseline times
# both main-effect ratios times this, which is the same "baseline times ratio"
# reading the sheet has always asked of the main effects, one factor longer.
.weibull_shape_tables <- function(fit) {
  rows  <- fit$covpars[fit$mx$shape]
  vname <- sub("^shape\\((.*)\\)$", "\\1", rownames(fit$res.t)[rows])
  is_interaction <- grepl(":", vname, fixed = TRUE)

  # Zero selected rows gives a zero-row table, which is the uncrossed variant's
  # interaction table and the covariate-free fit's main one.
  table_for <- function(sel) {
    .wald_ratio_table(vname[sel],
                      unname(fit$res.t[rows[sel], "est"]),
                      unname(fit$res.t[rows[sel], "se"]),
                      "shape_ratio")
  }

  # Each main-effect level's OWN shape, k = baseline * ratio, with an interval.
  # Published because the multiplication is the step a reader has to perform to
  # get the number the shape legend is actually about, and because the interval
  # is the part they cannot perform: own log k is log(k0) + gamma, a SUM of two
  # estimated parameters, so its variance carries both variances and twice their
  # covariance. Multiplying the baseline's interval by the ratio's would drop
  # that covariance term and is wrong in either direction.
  #
  # Same delta-method shape as the implied hazard ratios in .weibull_fit_tables,
  # and the same reliance on log k being estimation-scale parameter 1. Here the
  # gradient of log(k0) + gamma is (1, 1), so the quadratic form is just the sum
  # of the 2x2 covariance block.
  main <- table_for(!is_interaction)
  main_rows <- rows[!is_interaction]
  if (length(main_rows) > 0) {
    V     <- vcov(fit)
    log_k <- unname(fit$res.t["shape", "est"]) + unname(fit$res.t[main_rows, "est"])
    se    <- vapply(main_rows, function(row) {
      idx <- c(1L, row)
      sqrt(sum(V[idx, idx]))
    }, numeric(1))
    main$shape_own       <- exp(log_k)
    main$shape_own_lower <- exp(log_k - 1.96 * se)
    main$shape_own_upper <- exp(log_k + 1.96 * se)
  } else {
    main$shape_own <- main$shape_own_lower <- main$shape_own_upper <- numeric(0)
  }

  list(main = main, interaction = table_for(is_interaction))
}

# Starting points for the retry below: (shape, scale) pairs spanning a falling,
# flat and rising hazard at shelter-plausible scales, with every covariate
# coefficient started at zero. Deliberately a handful and not a search -- the
# point is to get off a bad starting value, not to explore the surface.
#
# Scale 5 is here because a shelter at capacity turns over fast by necessity,
# and a mean stay of a few days is a real operating regime rather than an edge
# case. Nothing sits above 40: populations that slow are less common, and a
# start at 40 reaches them. A start that suits no cell costs one failed
# optimization, so the grid errs toward covering the fast end.
.WEIBULL_RETRY_INITS <- list(
  c(0.6, 5),  c(1.0, 5),
  c(0.6, 10), c(1.2, 10),
  c(0.6, 20), c(0.8, 20), c(1.0, 20),
  c(0.8, 40), c(1.2, 40)
)

# How much better a start has to do before its fit replaces the default's, as a
# fraction of the log-likelihood's own magnitude. Two starts that reach the same
# optimum do not agree to the last bit: on a 30-row fixture the grid comes in
# ahead of the default by about 1e-11, which is the optimizer's own convergence
# tolerance talking and not a better answer. Swapping the fit on that would
# rewrite the last digits of every number mLOS reports, on every dataset, for
# nothing. Relative rather than absolute because the noise scales with the
# log-likelihood: 1e-6 puts the bar at 7e-5 on that fixture and at 0.05 on OC2,
# in both cases three or more orders of magnitude above the noise and the same
# distance below the 54-to-260 gaps that motivated searching at all.
.WEIBULL_START_TOL <- 1e-6

# Outcomes a combination of the non-focal predictors must hold before the shape
# variants will give it a shape of its own (see the shape-variant block of
# .weibull_regression_analysis). Outcomes, not stays: a Weibull shape is
# identified by observed exit times, so a censored row contributes only a
# survival term and a left-truncated one only conditions the risk set. Left
# truncation is therefore no obstacle at all here, and a heavily censored cell
# is.
#
# Five, and the number follows from who is asking. Crossing runs only when
# weibull_shape_crossing says so, which makes the precision of a cell's shape
# the caller's judgment rather than this floor's. What the floor still owes
# them is the case no judgment can rescue: a cell with almost no outcomes
# does not estimate a shape at all. The same OC2 data gives its one-outcome
# cell an implied k of 1.78 whose interval runs 0.35 to 8.94, against 0.49 to
# 0.54 for a well-populated cell such as RET x LARGE, and an empty cell
# reaches flexsurvreg as a singular matrix.
#
# A precision floor lands much higher. The standard error of an estimated
# Weibull shape falls as about 0.78/sqrt(n) on the log scale (the OC2 cells
# come in at 0.72/sqrt(n), close enough), while the real spread of shape
# BETWEEN well-populated cells there -- the 15 of 20 holding at least 100
# outcomes -- is about 19%, k running 0.61 to 1.22 with a standard deviation
# of 0.17. Where those meet, so that a cell's shape is known about as
# precisely as the variation the crossing exists to model, is n = 14 to 16.
# That is the number to raise this back to if the setting ever stops being an
# affirmative choice.
#
# On OC2 the two floors refuse the same variant: RET x _UNKNOWN_ holds one
# outcome, so the period variant falls back to the additive shape formula at
# either. The message names a different count.
.WEIBULL_CROSSING_MIN_EVENTS <- 5L

# Which combinations of `terms` hold too few outcomes for a shape of their own,
# as a reportable phrase, or NA when every combination clears the floor.
# Combinations absent from the data count as zero rather than being skipped
# (tapply gives NA for them), so an empty cell is refused here, with a message
# naming it, instead of reaching flexsurvreg and failing as a singular matrix.
#
# Refused here rather than left to the fit because flexsurvreg passes its design
# matrix to optim as built: an empty cell leaves an all-zero column, and the fit
# dies in Lapack ("system is exactly singular") rather than dropping the aliased
# column the way lm, glm, and coxph do through their QR pivoting. Pivoting would
# be the graceful answer, and it is not ours to add. It would also not cover the
# case this guard mostly exists for, since a cell holding a handful of outcomes
# is not rank deficient at all: flexsurvreg fits it and returns a shape nobody
# should report.
.thin_shape_cells <- function(data, terms, floor_n) {
  key    <- interaction(data[terms], drop = FALSE, sep = " x ")
  counts <- tapply(data$event, key, sum)
  counts[is.na(counts)] <- 0
  under <- counts[counts < floor_n]
  if (length(under) == 0) return(NA_character_)
  fewest <- names(under)[which.min(under)]
  paste0(length(under), " of ", length(counts), " ",
         paste(terms, collapse = " x "), " combinations hold fewer than ",
         floor_n, " outcomes (fewest: ", fewest, " at ", min(under), ")")
}

# One Weibull fit, with two things flexsurvreg leaves to the caller.
#
# FIRST, its starting values are derived from the data, and they go wrong in two
# ways. On some datasets they put the initial log-likelihood at -Inf, so optim
# quits with "initial value in 'vmmin' is not finite" before it has begun;
# observed on an OC2 subset (large dogs cut, animal group dropped), where the
# default inits fail outright while twelve of sixteen explicit starts agree on
# k = 0.945. On others they converge early and report success from a point that
# is not the maximum, which is the worse failure because nothing signals it. So
# every fit is made from the default start AND from each of
# .WEIBULL_RETRY_INITS, and the best log-likelihood wins.
#
# From every start rather than only after an outright failure, because the quiet
# case is real and is not rare. On OC2 three of the eight fits a run makes stop
# short of what a grid start reaches, by 54, 75 and 260 log-likelihood units,
# and all three carry shape() terms. At 260 the crossed shape variant scored
# BELOW the additive model nested inside it, making its likelihood ratio
# negative, which is arithmetically impossible for a maximized pair and is what
# exposed this. The same measurement on the preceding OC2 extract shows gaps of
# 69, 208 and 224, so the shortfall predates any one dataset: the earlier
# extract's ratio came out positive only because both of its fits were short by
# amounts that happened to leave the difference the right way up.
#
# The cost is that a Weibull number can move on any dataset, an archived run
# included, whenever a better optimum exists to move to. That is the trade
# taken deliberately: a fit that is not at the maximum is wrong whether or not
# it errored, and reproducing a wrong number is not worth the fits it saves. A
# tie goes to the default start, so a dataset where the grid finds nothing
# better reproduces exactly.
#
# The parameter count the inits vector has to match is not knowable from the
# formula string alone once shape() terms are in it, so it is read off a
# fixedpars probe, which builds the model frame without optimizing anything.
#
# SECOND, flexsurvreg does not error on a non-positive-definite Hessian: it
# warns, substitutes the nearest positive definite covariance matrix and returns
# a fit whose standard errors are an approximation around a point that may not
# be the maximum. Since every number mLOS reports off these fits carries a
# confidence interval, that case is reported as `unstable`, which is what lets
# the shape-variant block below fall back to the additive shape formula.
# Checking fit$cov afterwards would not find it -- by then flexsurv has already
# replaced it with the positive definite approximation.
# A fit whose standard errors flexsurvreg could not compute from the Hessian
# it reached, or that the optimizer left short (.fit_weibull's `unstable`),
# reported wherever such a fit is the one whose numbers get published. Every
# Weibull number mLOS shows carries an interval, and an interval computed
# around a point the optimizer is unsure of is an approximation the reader has
# no other way to notice. The shape variants can answer this by falling back
# to a simpler shape formula; the pooled and crude fits have nothing to fall
# back to, so for them saying so IS the answer.
.report_unstable <- function(unstable, what) {
  if (is.null(unstable) || is.na(unstable)) return(invisible(NULL))
  cat(what, ": ", unstable, " -- its confidence intervals are approximations\n", sep = "")
  invisible(NULL)
}

.fit_weibull <- function(formula_text, data, env) {
  fml <- as.formula(formula_text, env = env)

  # Warnings are collected per attempt rather than across all of them, because
  # `unstable` below judges the fit that WON. A Hessian warning raised by a
  # start that lost says nothing about the point finally reported, and pooling
  # the two would condemn a sound fit for the company it kept.
  attempt <- function(inits) {
    warns <- character(0)
    fit <- withCallingHandlers(
      tryCatch(
        if (is.null(inits)) {
          flexsurv::flexsurvreg(fml, data = data, dist = "weibull")
        } else {
          flexsurv::flexsurvreg(fml, data = data, dist = "weibull", inits = inits)
        },
        error = function(e) e
      ),
      warning = function(w) {
        warns <<- c(warns, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    )
    list(fit = fit, warnings = warns)
  }

  best    <- attempt(NULL)
  retried <- FALSE
  npars <- tryCatch(
    nrow(flexsurv::flexsurvreg(fml, data = data, dist = "weibull",
                               fixedpars = TRUE)$res),
    error = function(e) NULL
  )
  if (!is.null(npars) && npars >= 2) {
    for (start in .WEIBULL_RETRY_INITS) {
      candidate <- attempt(c(start, rep(0, npars - 2)))
      if (inherits(candidate$fit, "error")) next
      # Materially better, so a tie (or a last-bit difference) leaves the
      # default start's fit in place. See .WEIBULL_START_TOL.
      better <- inherits(best$fit, "error") ||
        candidate$fit$loglik > best$fit$loglik +
          .WEIBULL_START_TOL * max(1, abs(best$fit$loglik))
      if (better) {
        best    <- candidate
        retried <- TRUE
      }
    }
  }
  fit   <- best$fit
  warns <- best$warnings

  unstable <- if (inherits(fit, "error")) NA_character_ else {
    reasons <- c(
      if (any(grepl("Hessian not positive definite", warns, fixed = TRUE)))
        "Hessian not positive definite",
      if (!is.null(fit$opt$convergence) && !identical(as.integer(fit$opt$convergence), 0L))
        paste0("optimizer did not converge (code ", fit$opt$convergence, ")")
    )
    if (length(reasons)) paste(reasons, collapse = "; ") else NA_character_
  }
  list(fit = fit, warnings = warns, unstable = unstable, retried = retried)
}

# Weibull AFT companion fit (parametric_regression: WEIBULL). Runs on the
# same releveled period_data, Surv object, and formula already built for Cox,
# so both models see identical predictors, reference levels, and rows.
#
# flexsurvreg rather than survreg because the counting-process rows carry
# left truncation, which survreg does not accept. Standard errors are
# model-based (Hessian): contiguous period-split segments of one stay
# multiply to exactly the full-stay likelihood contribution
# (S(t1)/S(t0) * f(T)/S(t1) = f(T)/S(t0)), so splitting cannot affect them.
# That invariance holds ONLY for likelihood-based SEs -- any future
# sandwich or bootstrap variance must cluster split rows by stay.
# Correlation among repeat stays of one animal (real animal_ids) is not
# corrected: unlike coxph there is no ready clustered option here, so this
# is a documented choice; a by-animal cluster bootstrap is the upgrade path.
.weibull_regression_analysis <- function(period_data, surv_obj, formula_parts,
                                         xlevels, canonical_levels,
                                         unified_formula_parts, main_terms,
                                         crossing_enabled) {

  cat("\n=======================================================================\n")
  cat("WEIBULL REGRESSION ANALYSIS (parametric companion to Cox)\n")
  cat("=======================================================================\n")

  if (!requireNamespace("flexsurv", quietly = TRUE)) {
    cat("\nPackage 'flexsurv' is required for parametric_regression: WEIBULL but\n")
    cat("is not installed -- skipping. Install with: install.packages(\"flexsurv\")\n")
    return(list(has_analysis = FALSE, message = "package 'flexsurv' not installed"))
  }

  main <- .fit_weibull(formula_parts, period_data, environment())
  fit  <- main$fit
  if (inherits(fit, "error")) {
    cat("\nWeibull fit failed (", conditionMessage(fit), ") -- skipping.\n", sep = "")
    return(list(has_analysis = FALSE,
                message = paste0("fit failed: ", conditionMessage(fit))))
  }

  cat("\nModel formula: ", formula_parts, "  (dist = weibull)\n", sep = "")
  cat("  n =", fit$N, ", number of events =", fit$events, "\n")
  .report_unstable(main$unstable, "  Pooled Weibull fit")

  # Covariate-free Weibull: the reference model of the likelihood-ratio
  # test, and reused as the crude companion when no period qualifies.
  null_res <- .fit_weibull("surv_obj ~ 1", period_data, environment())
  null_fit <- null_res$fit
  if (inherits(null_fit, "error")) null_fit <- NULL

  # Global test: likelihood ratio against the covariate-free Weibull -- the
  # parametric analogue of Cox's global tests (the others have no counterpart).
  lr <- .lr_nested(fit, null_fit)
  if (!is.null(lr)) {
    cat("  Likelihood ratio test =", round(lr$stat, 1), " on", lr$df, "df,   p =",
        format.pval(lr$p, digits = 2), "\n")
  }

  tables <- .weibull_fit_tables(fit)
  k    <- tables$k
  k_lo <- tables$k_lo
  k_hi <- tables$k_hi
  # Reference levels inserted as definitional rows (LOS ratio and implied
  # HR exactly 1), mirroring the Cox hr_table so the sheets stay
  # cell-for-cell comparable.
  los_table        <- .insert_reference_rows(tables$los_table, xlevels, canonical_levels, "los_ratio")
  weibull_hr_table <- .insert_reference_rows(tables$hr_table, xlevels, canonical_levels, "hr")

  # The tables themselves (implied HRs beside the Cox ones, LOS ratios with
  # their bounds) are on the Weibull_Regression sheet and in the bundle, with
  # the shape legend beside them; the console reports only that the fit ran and
  # what shape it found.
  cat("Weibull shape k = ", round(k, 3), " [", round(k_lo, 3), ", ",
      round(k_hi, 3), "]\n", sep = "")

  # Unified companion: the same Weibull with the group terms dropped
  # (intercept + period only), so its shape describes the POOLED
  # discharge process. A pooled k below 1 alongside an adjusted k near 1
  # signals a mix of fast and slow groups (the fast leavers drain out of
  # the risk set first), not stays that stall with tenure -- see the
  # sim_size_mixture fixture for a worked example.
  crude <- if (identical(unified_formula_parts, formula_parts)) {
    cat("Crude Weibull: the model above has no group terms, so it already is the crude fit\n")
    list(has_analysis = TRUE, same_as_main = TRUE, formula = formula_parts,
         n = fit$N, n_events = fit$events,
         shape = k, shape_lo = k_lo, shape_hi = k_hi,
         fit_unstable = main$unstable,
         los_table = los_table, hr_table = weibull_hr_table)
  } else {
    unified_res <- if (identical(unified_formula_parts, "surv_obj ~ 1")) {
      null_res
    } else {
      .fit_weibull(unified_formula_parts, period_data, environment())
    }
    unified_fit <- if (inherits(unified_res$fit, "error")) NULL else unified_res$fit
    if (is.null(unified_fit)) {
      cat("Crude Weibull fit failed -- skipping.\n")
      list(has_analysis = FALSE, message = "crude fit failed")
    } else {
      ut <- .weibull_fit_tables(unified_fit)
      # The crude model carries only the period term (if any), so only
      # the period reference row is inserted; a "~ 1" crude fit has no
      # terms and its tables stay empty.
      uni_xlevels <- if (grepl("period", unified_formula_parts, fixed = TRUE)) {
        xlevels["period"]
      } else {
        list()
      }
      uni_los <- .insert_reference_rows(ut$los_table, uni_xlevels, canonical_levels, "los_ratio")
      uni_hr  <- .insert_reference_rows(ut$hr_table,  uni_xlevels, canonical_levels, "hr")
      cat("Crude Weibull (", unified_formula_parts, "): shape k = ", round(ut$k, 3),
          " [", round(ut$k_lo, 3), ", ", round(ut$k_hi, 3), "]\n", sep = "")
      .report_unstable(unified_res$unstable, "  Crude Weibull fit")
      list(has_analysis = TRUE, same_as_main = FALSE, formula = unified_formula_parts,
           n = unified_fit$N, n_events = unified_fit$events,
           shape = ut$k, shape_lo = ut$k_lo, shape_hi = ut$k_hi,
           fit_unstable = unified_res$unstable,
           los_table = uni_los, hr_table = uni_hr)
    }
  }

  # -------------------------------------------------------------------------
  # Per-predictor shape variants: same scale formula (so LOS ratios stay
  # comparable to los_table/weibull_hr_table above), but with the OTHER
  # predictors moved onto shape as a single CROSSED term, excluding the one the
  # variant is named for -- e.g. with period + intake_type + animal_group all
  # present, the "period" variant is
  #   surv_obj ~ period + intake_type + animal_group + shape(intake_type * animal_group)
  # so period's coefficient is read under the SAME adjustment as the main fit
  # above, while every intake_type x animal_group COMBINATION carries its own
  # discharge-hazard shape instead of sharing k with everything else.
  #
  # Additive by default (shape(intake_type) + shape(animal_group)), crossed
  # only where weibull_shape_crossing asks for it. The crossed form is the
  # parametric counterpart of the stratified Cox variants of
  # .cox_stratified_variants above, whose single crossed strata() makes each
  # combination a baseline rather than each dimension separately, and where it
  # runs the data can prefer it decisively: an additive shape formula
  # constrains the cells to a grid they need not lie on, and on OC2 that
  # constraint is rejected in both variants that can afford to test it (see
  # shape_crossing$lr below). What it costs is a shape parameter per cell,
  # which a thin cell cannot pay for, and a run that hits one reports a
  # different model on one sheet than on another. That trade is the caller's to
  # make, so it is a setting and its absent case is the additive fit. Leaving
  # the SCALE formula additive either way is what keeps the choice confined to
  # the shape side: every LOS-ratio and hazard-ratio row downstream is named
  # and placed exactly as before.
  #
  # Fallback, when crossing IS asked for: two guards, in that order, both
  # falling back to the additive shape formula (fitted here in any case, as the
  # denominator of the crossing test) rather than to nothing, recording why in
  # shape_crossing.
  #
  # FIRST, the outcome count in every cell, against
  # .WEIBULL_CROSSING_MIN_EVENTS. Checked before fitting because a count is
  # predictable and explicable where a failed optimization is neither: the
  # worksheet can say "this combination holds four outcomes" and a reader knows
  # what to do about it.
  #
  # SECOND, the fit itself: .fit_weibull reports a non-positive-definite Hessian
  # or a non-zero convergence code, which catches what a count cannot -- cells
  # that are individually adequate but jointly awkward.
  #
  # Needs at least two predictor terms: with only one, there is no "other" term
  # to put on shape and the variant would be identical to the main fit. With
  # exactly two predictors there is a single other term, so the crossed and
  # additive formulas coincide and only one fit is made -- a case the setting
  # cannot affect, and shape_crossing$applicable is what distinguishes it from
  # a crossing that was declined.
  # xlevels/canonical_levels are already exactly right for every variant (same
  # predictors, same releveling as the main fit above), so no reconstruction is
  # needed.
  term_to_stratifier_id <- .stratifier_ids_by_model_term()
  shape_variants <- list()
  if (length(main_terms) >= 2) {
    for (term in main_terms) {
      other_terms <- setdiff(main_terms, term)
      sid <- term_to_stratifier_id[[term]]

      additive_formula <- paste(c(formula_parts, paste0("shape(", other_terms, ")")),
                                collapse = " + ")
      crossed_formula  <- paste(c(formula_parts,
                                  paste0("shape(", paste(other_terms, collapse = " * "), ")")),
                                collapse = " + ")
      crossing_applies <- !identical(crossed_formula, additive_formula)

      # Counted before anything is fitted, so a refusal costs nothing and can
      # say which combination was too thin. Not counted when crossing is off:
      # there is no crossed fit for a count to refuse, and a cell that would
      # have been short is not a fact about the additive fit that runs instead.
      thin_cells <- if (crossing_applies && crossing_enabled) {
        .thin_shape_cells(period_data, other_terms, .WEIBULL_CROSSING_MIN_EVENTS)
      } else {
        NA_character_
      }
      attempt_crossing <- crossing_applies && crossing_enabled && is.na(thin_cells)

      additive <- .fit_weibull(additive_formula, period_data, environment())
      crossed  <- if (attempt_crossing) {
        .fit_weibull(crossed_formula, period_data, environment())
      } else {
        additive
      }

      # Prefer the crossed fit, when one was attempted at all; fall back on too
      # thin a cell, a failure, or an untrustworthy fit. A reason is a fact
      # about a crossing that was wanted and could not be had, so crossing
      # turned off leaves it empty -- nothing was refused.
      fallback_reason <- if (!attempt_crossing) {
        thin_cells
      } else if (inherits(crossed$fit, "error")) {
        paste0("fit failed: ", conditionMessage(crossed$fit))
      } else {
        crossed$unstable
      }
      used_crossed <- attempt_crossing && is.na(fallback_reason)
      chosen <- if (used_crossed) crossed else additive

      if (inherits(chosen$fit, "error")) {
        msg <- paste0("fit failed: ", conditionMessage(chosen$fit))
        if (!is.na(fallback_reason)) {
          msg <- paste0("crossed shape formula unusable (", fallback_reason,
                        ") and additive fallback ", msg)
        }
        cat("\nShape variant (scale = ", term, ") fit failed (", msg, ") -- skipping.\n", sep = "")
        shape_variants[[sid]] <- list(has_analysis = FALSE, message = msg)
        next
      }
      variant_fit     <- chosen$fit
      variant_formula <- if (used_crossed) crossed_formula else additive_formula

      # Same recipe as the main model's own likelihood ratio test above:
      # against the intercept-only null, not against the main fit.
      v_lr <- .lr_nested(variant_fit, null_fit)

      # And, when the crossed formula was the one used, against the additive
      # shape formula it replaced: the one number that says whether letting the
      # cells off the additive grid was worth the parameters. Nested by
      # construction (shape a + b sits inside shape a * b, identical scale).
      crossing_lr <- if (used_crossed && !inherits(additive$fit, "error")) {
        .lr_nested(variant_fit, additive$fit)
      } else {
        NULL
      }

      vt         <- .weibull_fit_tables(variant_fit)
      shape_tbls <- .weibull_shape_tables(variant_fit)
      shape_ids  <- unname(term_to_stratifier_id[other_terms])

      shape_main <- .insert_reference_rows(shape_tbls$main, xlevels[other_terms],
                                           canonical_levels, "shape_ratio")
      # A reference level's own shape IS the baseline, so the definitional row
      # carries it rather than a gap in a column that is complete everywhere
      # else. .reference_row_for leaves every column but the ratio NA, which is
      # what identifies those rows here.
      ref_rows <- is.na(shape_main$ci_lower) & !is.na(shape_main$shape_ratio)
      shape_main$shape_own[ref_rows]       <- vt$k
      shape_main$shape_own_lower[ref_rows] <- vt$k_lo
      shape_main$shape_own_upper[ref_rows] <- vt$k_hi

      cat("\nShape variant (scale = ", term, ", shape = ",
          paste(other_terms, collapse = if (used_crossed) " x " else ", "),
          "): shape k (reference combination) = ", round(vt$k, 3), " [", round(vt$k_lo, 3), ", ",
          round(vt$k_hi, 3), "]\n", sep = "")
      if (!is.na(fallback_reason)) {
        cat("  crossed shape formula unusable (", fallback_reason,
            ") -- fell back to the additive shape formula\n", sep = "")
      } else if (crossing_applies && !crossing_enabled) {
        cat("  shape crossing off (weibull_shape_crossing) -- additive shape formula\n",
            sep = "")
      } else if (!is.null(crossing_lr)) {
        cat("  crossed vs additive shape: LR = ", round(crossing_lr$stat, 1), " on ",
            crossing_lr$df, " df, p = ", format.pval(crossing_lr$p, digits = 2), "\n", sep = "")
      }
      .report_unstable(chosen$unstable, "  This variant's fit")

      shape_variants[[sid]] <- list(
        has_analysis      = TRUE,
        formula           = variant_formula,
        n                 = variant_fit$N,
        n_events          = variant_fit$events,
        lr                = v_lr,
        scale_stratifier  = sid,
        shape_stratifiers = shape_ids,
        # Which shape parameterization the reported numbers came from, and the
        # test that justifies it. Four states, and a consumer that treats any
        # two of them alike is answering a different question than it thinks:
        # crossed, meaning a shape per cell and an LR saying it was earned;
        # applicable but not enabled, the ordinary default, where the additive
        # fit is the one asked for; applicable and enabled with a reason, a
        # crossing wanted and refused; and not applicable, the two-predictor
        # case, where crossing has nothing to cross and the setting is beside
        # the point.
        shape_crossing    = list(crossed         = used_crossed,
                                 applicable      = crossing_applies,
                                 enabled         = crossing_enabled,
                                 fallback_reason = fallback_reason,
                                 lr              = crossing_lr),
        # .fit_weibull's verdict on the fit these numbers come from, NA when it
        # had nothing to say. A crossed fit that earned this was replaced by the
        # additive one above, so a value here belongs to whichever fit won.
        fit_unstable      = chosen$unstable,
        shape_reference   = list(k = vt$k, k_lo = vt$k_lo, k_hi = vt$k_hi),
        los_table         = .insert_reference_rows(vt$los_table, xlevels, canonical_levels, "los_ratio"),
        hr_table          = .insert_reference_rows(vt$hr_table,  xlevels, canonical_levels, "hr"),
        shape_table       = shape_main,
        # No reference rows and no canonical ordering: a product term belongs to
        # two predictors at once, so there is no slot to place it in and none is
        # invented. Empty whenever the variant did not cross.
        shape_interaction_table = shape_tbls$interaction
      )
    }
  }

  list(
    has_analysis   = TRUE,
    fit            = fit,
    formula        = formula_parts,
    n              = fit$N,
    n_events       = fit$events,
    fit_unstable   = main$unstable,
    shape          = k,
    shape_lo       = k_lo,
    shape_hi       = k_hi,
    lr             = lr,
    los_table      = los_table,
    hr_table       = weibull_hr_table,
    crude          = crude,
    shape_variants = shape_variants,
    xlevels        = xlevels
  )
}

