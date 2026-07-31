# 2D predicted-probability surface for one profile, over a grid of two
# focal predictors (e.g. socio_ecol_index x socio_econ_index), faceted by
# wave_id/country -- the bivariate extension of a single predicted-
# probability curve (see regression_probability_helpers.R), built to test
# whether a profile's probability responds to the two predictors
# additively (a straight-line boundary between the low- and
# high-probability regions) or interactively (a curved one).
#
# No confidence band: marginaleffects can't extract a variance-covariance
# matrix from nnet::multinom.
#
# Run through Snakemake (see rules/vis.smk).

library(nnet) # loaded for predict.multinom() method dispatch
library(marginaleffects)
library(ggplot2)
library(dplyr)

source("src/vis/justice_palette.R")

wave_ids <- snakemake@params[["wave_ids"]]
x_predictor <- snakemake@params[["x_predictor"]]
y_predictor <- snakemake@params[["y_predictor"]]
focal_profile <- snakemake@params[["focal_profile"]]
country_labels <- unlist(snakemake@params[["country_labels"]])

model_paths <- snakemake@input[["models"]]
model_data_paths <- snakemake@input[["model_data"]]

grid_resolution <- 60

surfaces <- bind_rows(lapply(seq_along(wave_ids), function(i) {
  wave_id <- wave_ids[i]
  model <- readRDS(model_paths[i])
  model_data <- readRDS(model_data_paths[i])

  x_range <- range(model_data[[x_predictor]], na.rm = TRUE)
  y_range <- range(model_data[[y_predictor]], na.rm = TRUE)

  datagrid_args <- list(model = model, newdata = model_data)
  datagrid_args[[x_predictor]] <- seq(x_range[1], x_range[2], length.out = grid_resolution)
  datagrid_args[[y_predictor]] <- seq(y_range[1], y_range[2], length.out = grid_resolution)
  grid <- do.call(datagrid, datagrid_args)

  # Precompute rather than looking up inside mutate(): once `wave_id`
  # exists as a column, a later reference to the bare name `wave_id` in
  # the same mutate() call resolves to that column (dplyr's data mask
  # shadows the outer scalar), not the loop variable.
  country_label <- country_labels[[wave_id]]
  # Each country's grid spans a different observed range, so the two
  # facets have different tile spacing -- geom_tile (with explicit
  # per-facet width/height) handles that correctly; geom_raster assumes
  # one global spacing and silently misplaces pixels when facets differ.
  x_step <- diff(x_range) / (grid_resolution - 1)
  y_step <- diff(y_range) / (grid_resolution - 1)
  pred <- predictions(model, newdata = grid, type = "probs") |>
    as.data.frame() |>
    filter(group == focal_profile) |>
    mutate(wave_id = wave_id, country = country_label, tile_width = x_step, tile_height = y_step) |>
    # predictions() carries every model predictor at its datagrid reference
    # value, not just the two focal ones -- e.g. `income` is a factor in
    # the wave3 models but numeric in wave4_eu's, which crashes bind_rows()
    # across wave_ids with a vctrs type-mismatch if left in. Only the
    # columns actually plotted need to survive the combine.
    select(all_of(c(x_predictor, y_predictor, "estimate", "wave_id", "country", "tile_width", "tile_height")))

  pred
})) |>
  # facet_wrap() defaults to alphabetical order otherwise -- use the order
  # wave_ids/country_labels were given in config instead.
  mutate(country = factor(country, levels = unname(country_labels[wave_ids])))

p <- ggplot(surfaces, aes(x = .data[[x_predictor]], y = .data[[y_predictor]])) +
  geom_tile(aes(fill = estimate, width = tile_width, height = tile_height)) +
  geom_contour(aes(z = estimate), breaks = c(0.1, 0.25, 0.5), color = "white", linewidth = 0.4) +
  facet_wrap(~country) +
  scale_fill_gradient(
    low = "white", high = unname(justice_palette[focal_profile]),
    limits = c(0, 1), labels = scales::percent_format(accuracy = 1)
  ) +
  labs(
    x = sprintf("%s (z-score, SD from sample mean)", x_predictor),
    y = sprintf("%s (z-score, SD from sample mean)", y_predictor),
    fill = sprintf("P(%s)", focal_profile),
    caption = "White contour lines mark 10%, 25%, and 50% predicted probability."
  ) +
  theme_classic(base_size = 12) +
  theme(
    legend.position = "right",
    strip.background = element_blank(),
    strip.text = element_text(face = "bold"),
    plot.caption = element_text(color = "grey40", size = 8, hjust = 0)
  )

ggsave(snakemake@output[["figure"]], p, width = 10, height = 5, dpi = 200)
