# Shared predicted-probability-curve computation, used by
# plot_regression_probability_grid.R to build each cell of a faceted grid.
#
# Sourced by that script, not run directly. Requires nnet and
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
