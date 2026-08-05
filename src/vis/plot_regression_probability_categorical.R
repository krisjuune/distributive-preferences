# Composite predicted-probability grid for categorical predictors (age,
# gender, income): rows are samples (Europe/Switzerland/China, matching
# plot_regression_probability_grid.R's row structure), columns are
# predictors -- each cell is a point-range (predicted probability +
# bootstrap CI whisker) per observed category level, one point per
# profile, dodged so the three profiles don't overlap at a given
# category. This is the categorical analogue of that script's
# line+ribbon cells; see regression_probability_helpers.R for the shared
# bootstrap machinery both scripts use.
#
# Each cell is fit from its OWN model (all sociodemographics + that one
# focal predictor, see regression_focal.R), rather than one shared model
# per row reused across every column -- see
# plot_regression_probability_grid.R's header for why (confirmed
# collinearity distortion for at least one value-index column; age/
# gender/income aren't implicated in that specific finding, but the same
# per-cell model is used here too for consistency/symmetry with the
# other two grids).
#
# Europe (wave4_eu) currently has neither age nor gender in its model
# data (not yet supplied by the panel provider, see
# regression_predictors.R) -- regression_focal.R writes those two cells'
# model as NULL, and they're simply skipped when building the data here,
# and facet_grid() still draws them as empty panels since row/column are
# factors with the full label set. Once that data arrives, this script
# needs no changes -- the cells will populate automatically.
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

n_cols <- length(col_labels)
# Inputs are flat, one (model, model_data) pair per rows x columns cell,
# row-major: cell (i, j) sits at index (i-1)*n_cols + j -- see
# _focal_pairs() in the Snakefile, which enumerates rows x columns in
# this same order when building the rule's input list.
cell_index <- function(i, j) (i - 1) * n_cols + j

models <- lapply(snakemake@input[["models"]], readRDS)
model_datas <- lapply(snakemake@input[["model_data"]], readRDS)

# A predictor is treated as categorical/discrete for this plot if it's
# either an actual factor, or a numeric column with few enough distinct
# values to sensibly become one point per value (e.g. wave 4's income, an
# already-discrete 1-10 decile code) -- anything with more distinct
# numeric values than this belongs on plot_regression_probability_grid.R's
# continuous curve instead, not this one.
max_discrete_numeric_values <- 15
is_plottable_as_categorical <- function(x) {
  is.factor(x) || (is.numeric(x) && length(unique(stats::na.omit(x))) <= max_discrete_numeric_values)
}

points <- list()
for (i in seq_along(row_labels)) {
  for (j in seq_along(col_labels)) {
    predictor <- col_predictors[j]
    model <- models[[cell_index(i, j)]]
    model_data <- model_datas[[cell_index(i, j)]]
    if (is.null(model) || !predictor %in% colnames(model_data) || !is_plottable_as_categorical(model_data[[predictor]])) {
      message(sprintf(
        "[plot_regression_probability_categorical] %s has no categorical/discrete `%s` -- leaving that cell empty",
        row_wave_ids[i], predictor
      ))
      next
    }
    pts <- predicted_probability_by_category(
      model, model_data, predictor, n_boot, ci_level,
      label = sprintf("%s/%s", row_wave_ids[i], predictor)
    )
    pts$row_label <- row_labels[i]
    pts$col_label <- col_labels[j]
    points[[paste(i, j)]] <- pts
  }
}

pred <- bind_rows(points) |>
  mutate(
    row_label = factor(row_label, levels = row_labels),
    col_label = factor(col_label, levels = col_labels)
  )

p <- ggplot(pred, aes(x = category, y = estimate, color = profile_class)) +
  geom_pointrange(
    aes(ymin = conf.low, ymax = conf.high),
    position = position_dodge(width = 0.5), size = 0.35, linewidth = 0.7
  ) +
  facet_grid(rows = vars(row_label), cols = vars(col_label), scales = "free_x") +
  scale_color_manual(values = justice_palette) +
  scale_y_continuous(limits = c(0, 1), labels = scales::percent_format(accuracy = 1)) +
  labs(
    x = NULL,
    y = "Predicted probability of profile membership",
    color = "Profile"
  ) +
  theme_classic(base_size = 11) +
  theme(
    legend.position = "bottom",
    strip.background = element_blank(),
    strip.text = element_text(face = "bold"),
    axis.text.x = element_text(angle = 40, hjust = 1, size = 7)
  )

`%||%` <- function(x, default) if (is.null(x)) default else x
fig_width <- snakemake@params[["fig_width"]] %||% 12
fig_height <- snakemake@params[["fig_height"]] %||% 9
ggsave(snakemake@output[["figure"]], p, width = fig_width, height = fig_height, dpi = 200)
