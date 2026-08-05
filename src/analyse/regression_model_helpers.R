# Shared model-data assembly and fitting logic for regression.R (the
# full per-wave/group multivariate model, used for the supplementary
# coefficients table) and regression_focal.R (one slimmer demographics +
# single-focal-predictor model per probability-grid column -- see that
# script's header for why grid columns are no longer fit from one shared
# "kitchen sink" model).
#
# Sourced by both scripts, not run directly. Requires regression_predictors.R
# to already be sourced (build_wave_predictors(), build_composite_index()).

# Assembles the full "wide" model data for one wave_id or pooled group of
# wave_ids (e.g. wave 4's 9-country "wave4_eu"): every demographic and
# attitude/value column build_wave_predictors() knows how to build for
# this topic, LPA profile_class joined in, `country` added as a control
# whenever more than one wave_id is pooled. Deliberately does NOT do
# listwise deletion or drop constant predictor levels -- which columns a
# given model actually uses (and therefore which rows/levels matter)
# differs between the full model and each focal-predictor model, so that
# happens downstream in fit_multinom_model(), once the caller has picked
# its column subset. This is also why a focal model can retain more rows
# than the full model: it isn't penalised by missingness in columns it
# never uses.
build_wide_model_data <- function(unit_id, wave_ids, topics, countries, data_paths, classes_paths) {
  per_wave <- lapply(seq_along(wave_ids), function(i) {
    wid <- wave_ids[i]
    data <- arrow::read_parquet(data_paths[i])
    classes <- readr::read_csv(classes_paths[i], show_col_types = FALSE) |>
      dplyr::select(respondent_id, profile_class)

    built <- build_wave_predictors(data, topics[[wid]], wid)

    simple <- built$simple
    simple$row_key <- paste(wid, simple$respondent_id, sep = "::")
    simple$country <- countries[[wid]]
    simple$respondent_id <- NULL

    classes_keyed <- classes |>
      dplyr::mutate(row_key = paste(wid, respondent_id, sep = "::")) |>
      dplyr::select(row_key, profile_class)
    simple <- simple |> dplyr::inner_join(classes_keyed, by = "row_key")

    composite_items <- lapply(built$composite_items, function(df) {
      df$row_key <- paste(wid, df$respondent_id, sep = "::")
      df$respondent_id <- NULL
      # Keep only rows that survived the classes join above (LPA can drop
      # a handful of rows with missing justice items).
      df |> dplyr::semi_join(simple, by = "row_key")
    })

    list(simple = simple, composite_items = composite_items)
  })

  model_data <- dplyr::bind_rows(lapply(per_wave, `[[`, "simple"))

  composite_names <- unique(unlist(lapply(per_wave, function(x) names(x$composite_items))))
  for (name in composite_names) {
    items_pooled <- dplyr::bind_rows(lapply(per_wave, function(x) x$composite_items[[name]]))
    items_pooled <- items_pooled[match(model_data$row_key, items_pooled$row_key), ]
    item_columns <- setdiff(colnames(items_pooled), "row_key")
    index <- build_composite_index(items_pooled[item_columns], label = sprintf("%s %s", unit_id, name))
    # See REVERSED_COMPOSITE_INDICES in regression_predictors.R for why.
    if (name %in% REVERSED_COMPOSITE_INDICES) index <- -index
    model_data[[name]] <- index
  }

  model_data$row_key <- NULL

  # `country` is only informative -- and only estimable -- when pooling
  # more than one wave_id; drop it otherwise rather than carry a constant
  # column (the same degenerate-predictor problem fit_multinom_model()
  # guards against below for any other column).
  if (length(unique(model_data$country)) < 2) {
    model_data$country <- NULL
  } else {
    message(sprintf(
      "[regression/%s] pooling %d wave_ids (%s) -- adding `country` as a control predictor",
      unit_id, length(wave_ids), paste(wave_ids, collapse = ", ")
    ))
    model_data$country <- factor(model_data$country)
  }

  model_data |> dplyr::mutate(profile_class = factor(profile_class))
}

# Selects predictor_columns from wide_model_data, listwise-deletes on
# just that subset (so a model excluding e.g. the cultural-worldview
# items isn't penalised by their missingness), drops empty/constant
# factor levels (a zero-variance dummy column left over after listwise
# deletion produces huge/infinite odds ratios -- first found fitting
# wave4's small per-country models), and fits the multinomial model.
# Returns list(model =, model_data =), ready to save directly.
fit_multinom_model <- function(wide_model_data, predictor_columns, decay, label) {
  model_data <- wide_model_data[, c("profile_class", predictor_columns), drop = FALSE]

  n_total <- nrow(model_data)
  model_data <- na.omit(model_data)
  message(sprintf(
    "[regression/%s] dropped %d of %d rows (%.1f%%) with missing predictors -- n = %d",
    label, n_total - nrow(model_data), n_total, 100 * (n_total - nrow(model_data)) / n_total, nrow(model_data)
  ))

  model_data <- droplevels(model_data)
  constant_predictors <- predictor_columns[vapply(
    predictor_columns, function(col) is.factor(model_data[[col]]) && nlevels(model_data[[col]]) < 2, logical(1)
  )]
  if (length(constant_predictors) > 0) {
    message(sprintf(
      "[regression/%s] dropped constant predictor(s) with no remaining variation after listwise deletion: %s",
      label, paste(constant_predictors, collapse = ", ")
    ))
    predictor_columns <- setdiff(predictor_columns, constant_predictors)
  }

  # Backtick-quote predictor names: reformulate() doesn't auto-quote
  # column names containing hyphens/spaces, which R's formula parser
  # would otherwise silently misparse as an arithmetic expression.
  formula <- reformulate(paste0("`", predictor_columns, "`"), response = "profile_class")
  model <- nnet::multinom(formula, data = model_data, trace = FALSE, MaxNWts = 2000, decay = decay)

  list(model = model, model_data = model_data)
}
