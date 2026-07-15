# Combined elbow plot of LPA fit statistics across profile counts, one panel
# per wave/country sample (3 columns), single shared legend. Companion to
# the per-wave version in plot_lpa_fit.R.
#
# Run through Snakemake (see rules/vis.smk).

library(dplyr)
library(ggplot2)
library(readr)
library(tidyr)

fit_stats_files <- snakemake@input[["fit_stats"]]
wave_titles <- unlist(snakemake@params[["wave_titles"]])
ncol <- snakemake@params[["ncol"]]

wave_ids <- gsub("_fit_stats\\.csv$", "", basename(fit_stats_files))
# Preserve config/default.yaml's lpa.spaghetti_titles order (matches the
# wave sequence) rather than facet_wrap's default alphabetical ordering.
wave_order <- wave_titles[wave_ids]

all_fit_stats <- bind_rows(lapply(seq_along(fit_stats_files), function(i) {
  read_csv(fit_stats_files[i], show_col_types = FALSE) |>
    mutate(wave_title = wave_titles[[wave_ids[i]]])
}))

plot_data <- all_fit_stats |>
  mutate(wave_title = factor(wave_title, levels = wave_order)) |>
  select(wave_title, G, AIC, AWE, BIC, SABIC, ICL) |>
  pivot_longer(cols = c(AIC, AWE, BIC, SABIC, ICL), names_to = "statistic", values_to = "value") |>
  mutate(statistic = factor(statistic, levels = c("ICL", "AWE", "BIC", "SABIC", "AIC")))

p <- ggplot(plot_data, aes(x = G, y = value, colour = statistic, shape = statistic, fill = statistic)) +
  geom_line(linewidth = 0.8, alpha = 0.7) +
  geom_point(size = 2, stroke = 1.2) +
  facet_wrap(~wave_title, ncol = ncol, scales = "free_y") +
  scale_x_continuous(breaks = sort(unique(plot_data$G))) +
  labs(x = "Number of profiles", y = "Fit statistic value") +
  theme_classic() +
  theme(
    legend.position = "bottom",
    legend.title = element_blank(),
    text = element_text(size = 10),
    strip.background = element_rect(linewidth = 0),
    strip.text = element_text(face = "bold", size = 9)
  ) +
  scale_color_grey(end = 0.85) +
  scale_shape_manual(values = 21:25) +
  scale_fill_grey(end = 0.85)

n_grid_rows <- ceiling(length(wave_order) / ncol)
ggsave(
  snakemake@output[["figure"]], p,
  width = 5 * ncol, height = 3.2 * n_grid_rows, dpi = 200, limitsize = FALSE
)
