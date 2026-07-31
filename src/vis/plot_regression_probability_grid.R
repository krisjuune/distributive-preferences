# Composite predicted-probability grid: rows are samples (e.g. Europe/
# Switzerland/China), columns are value/concern indices (e.g. economic,
# cultural, ecological, energy security) -- each cell is a predicted-
# probability curve (see regression_probability_helpers.R), faceted
# together with one shared legend and y-axis so samples and indices are
# directly comparable at a glance.
#
# Not every sample has every index (e.g. wave 3 has no energy security
# index -- that composite only exists for wave 4, see
# regression_predictors.R); those cells are simply skipped when building
# the data, and facet_grid() still draws them as empty panels since
# row/column are factors with the *full* label set, not just the labels
# that have data.
#
# Each column's x-axis range is standardised across every row that has
# it (the union of each sample's own observed range), rather than each
# cell estimating over just its own sample's range -- otherwise a sample
# with a narrower observed distribution renders a visibly shorter curve
# than its column-mates, which reads as if that panel were cut off even
# though nothing is actually missing. The tradeoff: a sample with a
# narrower range than its column-mates gets a curve that extrapolates
# slightly beyond its own observed data at the tails.
#
# Run through Snakemake (see rules/vis.smk).

library(nnet) # loaded for predict.multinom() method dispatch
library(marginaleffects) # datagrid() only -- see regression_probability_helpers.R
library(ggplot2)
library(dplyr)

source("src/vis/justice_palette.R")
source("src/vis/regression_probability_helpers.R")

row_labels <- unlist(snakemake@params[["row_labels"]])
row_wave_ids <- unlist(snakemake@params[["row_wave_ids"]])
col_labels <- unlist(snakemake@params[["col_labels"]])
col_predictors <- unlist(snakemake@params[["col_predictors"]])
n_boot <- snakemake@params[["n_boot"]]
ci_level <- snakemake@params[["ci_level"]]
set.seed(snakemake@params[["random_seed"]])

model_paths <- snakemake@input[["models"]]
model_data_paths <- snakemake@input[["model_data"]]

models <- lapply(model_paths, readRDS)
model_datas <- lapply(model_data_paths, readRDS)

column_ranges <- list()
for (predictor in unique(col_predictors)) {
  ranges <- lapply(model_datas, function(d) {
    if (predictor %in% colnames(d)) range(d[[predictor]], na.rm = TRUE) else NULL
  })
  ranges <- ranges[!vapply(ranges, is.null, logical(1))]
  if (length(ranges) > 0) column_ranges[[predictor]] <- range(unlist(ranges))
}

curves <- list()
for (i in seq_along(row_labels)) {
  model <- models[[i]]
  model_data <- model_datas[[i]]

  for (j in seq_along(col_labels)) {
    predictor <- col_predictors[j]
    if (!predictor %in% colnames(model_data)) {
      message(sprintf(
        "[plot_regression_probability_grid] %s has no `%s` -- leaving that cell empty",
        row_wave_ids[i], predictor
      ))
      next
    }
    curve <- predicted_probability_curve(
      model, model_data, predictor, n_boot, ci_level,
      label = sprintf("%s/%s", row_wave_ids[i], predictor),
      value_range = column_ranges[[predictor]]
    )
    curve$row_label <- row_labels[i]
    curve$col_label <- col_labels[j]
    curves[[paste(i, j)]] <- curve
  }
}

pred <- bind_rows(curves) |>
  mutate(
    row_label = factor(row_label, levels = row_labels),
    col_label = factor(col_label, levels = col_labels)
  )

p <- ggplot(pred, aes(x = value, y = estimate, color = profile_class, fill = profile_class)) +
  geom_ribbon(aes(ymin = conf.low, ymax = conf.high), alpha = 0.15, color = NA) +
  geom_line(linewidth = 1) +
  facet_grid(rows = vars(row_label), cols = vars(col_label), scales = "free_x") +
  scale_color_manual(values = justice_palette) +
  scale_fill_manual(values = justice_palette) +
  scale_y_continuous(limits = c(0, 1), labels = scales::percent_format(accuracy = 1)) +
  labs(
    x = "Predictor value (z-score, SD from sample mean)",
    y = "Predicted probability of profile membership",
    color = "Profile", fill = "Profile"
  ) +
  theme_classic(base_size = 11) +
  theme(
    legend.position = "bottom",
    strip.background = element_blank(),
    strip.text = element_text(face = "bold")
  )

# width/height are per-rule params (grids with fewer rows -- e.g. the
# single-row cultural-worldviews grid -- don't need the same height as a
# 3-row grid), falling back to the original 3-row size if a rule doesn't
# set them.
`%||%` <- function(x, default) if (is.null(x)) default else x
fig_width <- snakemake@params[["fig_width"]] %||% 12
fig_height <- snakemake@params[["fig_height"]] %||% 8
ggsave(snakemake@output[["figure"]], p, width = fig_width, height = fig_height, dpi = 200)
