# Publication composition chart: sorted 100% stacked bar of latent profile
# class shares, one bar per country (one representative wave/country sample
# each -- see config/default.yaml's lpa.composition_waves), paired with a
# compact "what does each profile look like" reference panel (mean shape
# across the 4 justice principles, pooled across every composition country)
# so the chart is self-contained without cross-referencing
# src/vis/plot_shapes_by_topic.R separately. The message this is built to
# carry: the Utilitarian class is a minority everywhere.
#
# Run through Snakemake (see rules/vis.smk).

library(dplyr)
library(ggplot2)
library(patchwork)
library(readr)
library(scales)
library(tidyr)

source("src/vis/justice_palette.R")

principle_order <- c("Egalitarian", "Universalist", "Utilitarian")
principle_cols <- c(
  "justice_principle_egalitarian", "justice_principle_limitarian",
  "justice_principle_sufficientarian", "justice_principle_utilitarian"
)
principle_labels <- c("Egal", "Lim", "Suff", "Util")

classes_files <- snakemake@input[["classes"]]
wave_to_country <- unlist(snakemake@params[["wave_to_country"]])
wave_ids <- gsub("_spaghetti_classes\\.csv$", "", basename(classes_files))

# wave2_us is the only constant-sum (points-allocation) sample among the
# composition countries -- every other one uses the Likert scale. Flagged
# on the axis label with an asterisk (explained in the surrounding text,
# not on the plot itself).
constant_sum_wave_ids <- c("wave2_us")

classes_raw <- setNames(lapply(classes_files, read_csv, show_col_types = FALSE), wave_ids)

class_sizes <- bind_rows(lapply(wave_ids, function(wave_id) {
  country <- wave_to_country[[wave_id]]
  if (wave_id %in% constant_sum_wave_ids) country <- paste0(country, "*")
  classes_raw[[wave_id]] |> mutate(country = country)
})) |>
  mutate(profile_class = factor(profile_class, levels = principle_order)) |>
  count(country, profile_class, name = "n", .drop = FALSE) |>
  mutate(pct = 100 * n / sum(n), .by = country)

# Sort countries by descending Utilitarian share, so the "even the largest
# case is small" pattern reads clearly top to bottom.
country_order <- class_sizes |>
  filter(profile_class == "Utilitarian") |>
  arrange(desc(pct)) |>
  pull(country)

class_sizes <- class_sizes |> mutate(country = factor(country, levels = rev(country_order)))

# Faded fill (same alpha as the ribbons in
# src/vis/plot_regression_probability_grid.R) with a full-opacity border and
# percentage label in the same colour -- the label is the thing that has to
# read clearly, the fill just needs to distinguish segments.
faded_palette <- scales::alpha(justice_palette, 0.15)

p_bars <- ggplot(class_sizes, aes(x = country, y = pct, fill = profile_class, color = profile_class)) +
  geom_col(width = 0.7, linewidth = 0.4) +
  geom_text(
    aes(label = ifelse(pct >= 5, paste0(round(pct), "%"), "")),
    position = position_stack(vjust = 0.5), size = 3, fontface = "bold", show.legend = FALSE
  ) +
  coord_flip() +
  scale_fill_manual(
    values = faded_palette,
    guide = guide_legend(reverse = TRUE, override.aes = list(alpha = 1))
  ) +
  scale_color_manual(values = justice_palette, guide = "none") +
  scale_y_continuous(expand = c(0, 0)) +
  labs(x = NULL, y = "Share of respondents (%)", fill = "Profile") +
  theme_classic(base_size = 12) +
  theme(
    legend.position = "bottom",
    # Zero expansion on the (post-flip) x axis puts the "100" tick right at
    # the panel edge -- without extra right-hand margin its label gets
    # clipped by the saved image's bounding box.
    plot.margin = margin(t = 5.5, r = 12, b = 5.5, l = 5.5)
  )

# Pooled "what does each profile look like" reference: mean +/- 95% CI
# across the 4 justice principles, standardised within each wave first
# (same treatment as plot_lpa_spaghetti.R/plot_shapes_by_topic.R) then
# pooled across every composition country into one reference shape per
# profile -- not broken out by country, since the point here is just to
# show what the bar chart's profile labels mean, not to re-litigate
# cross-country shape differences (that's plot_shapes_by_topic.R's job).
shape_order <- c("Utilitarian", "Universalist", "Egalitarian")

shape_summary <- bind_rows(lapply(wave_ids, function(wave_id) {
  classes_raw[[wave_id]] |> mutate(across(all_of(principle_cols), ~ as.numeric(scale(.))))
})) |>
  mutate(profile_class = factor(profile_class, levels = shape_order)) |>
  pivot_longer(cols = all_of(principle_cols), names_to = "principle", values_to = "value") |>
  mutate(principle = factor(principle, levels = principle_cols, labels = principle_labels)) |>
  summarise(
    mean = mean(value, na.rm = TRUE),
    se = sd(value, na.rm = TRUE) / sqrt(sum(!is.na(value))),
    .by = c(profile_class, principle)
  ) |>
  mutate(ci_lower = mean - 1.96 * se, ci_upper = mean + 1.96 * se)

p_shapes <- ggplot(shape_summary, aes(x = principle, y = mean, color = profile_class, group = profile_class)) +
  geom_ribbon(aes(ymin = ci_lower, ymax = ci_upper, fill = profile_class), alpha = 0.15, color = NA) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 1.6) +
  facet_wrap(~profile_class, ncol = 3) +
  scale_color_manual(values = justice_palette, guide = "none") +
  scale_fill_manual(values = justice_palette, guide = "none") +
  labs(x = NULL, y = "Standardised\nscore (z)") +
  theme_classic(base_size = 10) +
  theme(
    strip.background = element_rect(linewidth = 0),
    strip.text = element_text(face = "bold", size = 9)
  )

p <- p_shapes / p_bars +
  plot_layout(heights = c(1, 2.4)) +
  plot_annotation(tag_levels = "A") &
  theme(plot.tag = element_text(face = "bold", size = 13))

ggsave(snakemake@output[["figure"]], p, width = 8, height = 8.5, dpi = 200)
