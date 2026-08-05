# Shared predicted-probability computation (continuous curves and
# categorical points alike), used by plot_regression_probability_grid.R
# and plot_regression_probability_categorical.R to build each cell of a
# faceted grid.
#
# Sourced by those scripts, not run directly. Requires nnet and
# marginaleffects to already be loaded (for predict.multinom() method
# dispatch and datagrid() respectively).

# Varies one focal predictor across its observed range, holds every other
# predictor at a representative value (mean for numeric, mode for
# factors, via marginaleffects::datagrid()), and returns predicted P(profile)
# for all three profiles as a function of that predictor -- the
# multinomial generalisation of a sigmoid curve (softmax replaces sigmoid
# with 3+ unordered outcome categories, so all three probabilities are
# returned together; they sum to 1 at every point).
#
# Confidence bands come from a nonparametric bootstrap, not
# marginaleffects' delta-method intervals: marginaleffects can't extract a
# variance-covariance matrix from nnet::multinom (see
# plot_regression_probability_surface.R), so instead this resamples
# respondents with replacement, refits the model, and predicts on the same
# grid each time; the ci_level empirical percentile of the resulting
# curves at each point is the band. The reference profile (mean/mode of
# every non-focal predictor) is fixed from the original data across all
# replicates, so the band reflects sampling uncertainty in the fitted
# coefficients, not uncertainty in which reference point to hold other
# predictors at.
predicted_probability_curve <- function(model, model_data, focal_predictor, n_boot, ci_level, label = "",
                                         value_range = NULL) {
  ci_tail <- (1 - ci_level) / 2
  profile_levels <- c("Egalitarian", "Universalist", "Utilitarian")

  # value_range lets a caller estimate over a *shared* range across several
  # models (e.g. plot_regression_probability_grid.R aligning every row in
  # a column to the same x-axis) instead of each model's own observed
  # range -- this does mean extrapolating slightly beyond the observed
  # data for whichever sample(s) have a narrower distribution than the
  # widest one in the group.
  if (is.null(value_range)) value_range <- range(model_data[[focal_predictor]], na.rm = TRUE)
  grid_values <- seq(value_range[1], value_range[2], length.out = 100)

  datagrid_args <- list(model = model, newdata = model_data)
  datagrid_args[[focal_predictor]] <- grid_values
  grid <- do.call(marginaleffects::datagrid, datagrid_args)

  point_probs <- predict(model, newdata = grid, type = "probs")
  model_formula <- formula(model)

  boot_probs <- vector("list", n_boot)
  for (b in seq_len(n_boot)) {
    resampled <- model_data[sample(nrow(model_data), replace = TRUE), ]
    boot_model <- tryCatch(
      nnet::multinom(model_formula, data = resampled, trace = FALSE, MaxNWts = 2000),
      error = function(e) NULL
    )
    boot_probs[[b]] <- if (is.null(boot_model)) {
      NULL
    } else {
      tryCatch(predict(boot_model, newdata = grid, type = "probs"), error = function(e) NULL)
    }
  }
  n_failed <- sum(vapply(boot_probs, is.null, logical(1)))
  if (n_failed > 0) {
    message(sprintf(
      "[predicted_probability_curve/%s] %d of %d bootstrap refits failed and were skipped",
      label, n_failed, n_boot
    ))
  }
  boot_probs <- boot_probs[!vapply(boot_probs, is.null, logical(1))]

  dplyr::bind_rows(lapply(profile_levels, function(cls) {
    boot_matrix <- vapply(boot_probs, function(m) m[, cls], numeric(length(grid_values)))
    data.frame(
      value = grid_values,
      profile_class = cls,
      estimate = point_probs[, cls],
      conf.low = apply(boot_matrix, 1, quantile, probs = ci_tail),
      conf.high = apply(boot_matrix, 1, quantile, probs = 1 - ci_tail),
      n_boot_success = length(boot_probs)
    )
  })) |>
    dplyr::mutate(profile_class = factor(profile_class, levels = profile_levels))
}

# Categorical analogue of predicted_probability_curve(): instead of
# varying the focal predictor over a continuous sequence, predicts one
# point per *observed factor level* (e.g. each age band, each gender, each
# income bracket), with every other predictor held at a representative
# value as before. Same nonparametric-bootstrap rationale for the
# confidence interval as predicted_probability_curve() -- see that
# function's comment.
#
# Levels are taken from model_data[[focal_predictor]]'s own factor level
# order (set once, upstream, in regression_predictors.R -- e.g. ascending
# age bands, income brackets ordered by embedded bracket value rather than
# alphabetically) rather than re-derived here, so this plot and the
# model's own coefficient ordering/reference level always agree. A
# low-cardinality numeric predictor (e.g. wave 4's income, an already-
# discrete 1-10 decile code, once code 11's "prefer not to say" respondents
# are recoded to NA upstream in regression_predictors.R, rather than a
# labelled band) is treated the
# same way, one point per distinct observed value in ascending order --
# the model formula/type is untouched either way, this only changes how
# results are displayed.
predicted_probability_by_category <- function(model, model_data, focal_predictor, n_boot, ci_level, label = "") {
  ci_tail <- (1 - ci_level) / 2
  profile_levels <- c("Egalitarian", "Universalist", "Utilitarian")

  # category_values keeps the focal predictor's native type (factor level
  # names, or the actual numeric values for a discrete-numeric predictor
  # like wave 4's income) since that's what datagrid()/predict() need to
  # match the model's training data; category_labels is the display-only
  # character version used for the output data frame's x-axis factor.
  focal_values <- model_data[[focal_predictor]]
  category_values <- if (is.factor(focal_values)) {
    levels(droplevels(focal_values))
  } else {
    sort(unique(focal_values))
  }
  category_labels <- as.character(category_values)

  datagrid_args <- list(model = model, newdata = model_data)
  datagrid_args[[focal_predictor]] <- category_values
  grid <- do.call(marginaleffects::datagrid, datagrid_args)

  point_probs <- predict(model, newdata = grid, type = "probs")
  model_formula <- formula(model)

  boot_probs <- vector("list", n_boot)
  for (b in seq_len(n_boot)) {
    resampled <- model_data[sample(nrow(model_data), replace = TRUE), ]
    boot_model <- tryCatch(
      nnet::multinom(model_formula, data = resampled, trace = FALSE, MaxNWts = 2000),
      error = function(e) NULL
    )
    boot_probs[[b]] <- if (is.null(boot_model)) {
      NULL
    } else {
      tryCatch(predict(boot_model, newdata = grid, type = "probs"), error = function(e) NULL)
    }
  }
  n_failed <- sum(vapply(boot_probs, is.null, logical(1)))
  if (n_failed > 0) {
    message(sprintf(
      "[predicted_probability_by_category/%s] %d of %d bootstrap refits failed and were skipped",
      label, n_failed, n_boot
    ))
  }
  boot_probs <- boot_probs[!vapply(boot_probs, is.null, logical(1))]

  dplyr::bind_rows(lapply(profile_levels, function(cls) {
    boot_matrix <- vapply(boot_probs, function(m) m[, cls], numeric(length(category_values)))
    data.frame(
      category = category_labels,
      profile_class = cls,
      estimate = point_probs[, cls],
      conf.low = apply(boot_matrix, 1, quantile, probs = ci_tail),
      conf.high = apply(boot_matrix, 1, quantile, probs = 1 - ci_tail),
      n_boot_success = length(boot_probs)
    )
  })) |>
    dplyr::mutate(
      category = factor(category, levels = category_labels),
      profile_class = factor(profile_class, levels = profile_levels)
    )
}
