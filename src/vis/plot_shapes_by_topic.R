# Supplementary shape figure: mean +/- SE profile per class (not individual
# spaghetti lines), one panel per topic/wave-family -- see
# config/default.yaml's lpa.shape_topics. Companion to
# src/vis/plot_composition.R: that chart carries the "Utilitarian is a
# minority" message; this one shows what each profile actually looks like.
#
# Run through Snakemake (see rules/vis.smk).

library(dplyr)
library(ggplot2)
library(readr)
library(tidyr)

source("src/vis/justice_palette.R")

principle_order <- c("Egalitarian", "Universalist", "Utilitarian")
principle_cols <- c(
  "justice_principle_egalitarian", "justice_principle_limitarian",
  "justice_principle_sufficientarian", "justice_principle_utilitarian"
)
principle_labels <- c("Egal", "Lim", "Suff", "Util")

classes_files <- snakemake@input[["classes"]]
wave_ids <- gsub("_spaghetti_classes\\.csv$", "", basename(classes_files))
classes_by_wave <- setNames(as.list(classes_files), wave_ids)
shape_topics <- snakemake@params[["shape_topics"]]
# Preserve config/default.yaml's lpa.shape_topics order (matches the wave
# sequence) rather than facet_wrap's default alphabetical ordering.
topic_order <- names(shape_topics)

topic_long <- bind_rows(lapply(names(shape_topics), function(topic) {
  topic_wave_ids <- unlist(shape_topics[[topic]])
  df <- bind_rows(lapply(topic_wave_ids, function(w) read_csv(classes_by_wave[[w]], show_col_types = FALSE)))
  # Standardise within its own wave/topic pool, same as the main spaghetti plot.
  df <- df |> mutate(across(all_of(principle_cols), ~ as.numeric(scale(.))))
  df |>
    mutate(
      topic = factor(topic, levels = topic_order),
      profile_class = factor(profile_class, levels = principle_order)
    ) |>
    pivot_longer(cols = all_of(principle_cols), names_to = "principle", values_to = "value") |>
    mutate(principle = factor(principle, levels = principle_cols, labels = principle_labels))
}))

summary_data <- topic_long |>
  summarise(
    mean = mean(value, na.rm = TRUE),
    se = sd(value, na.rm = TRUE) / sqrt(sum(!is.na(value))),
    .by = c(topic, profile_class, principle)
  ) |>
  mutate(ci_lower = mean - 1.96 * se, ci_upper = mean + 1.96 * se)

p <- ggplot(summary_data, aes(x = principle, y = mean, color = profile_class, group = profile_class)) +
  geom_ribbon(
    aes(ymin = ci_lower, ymax = ci_upper, fill = profile_class),
    alpha = 0.15, color = NA
  ) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 1.6) +
  facet_wrap(~topic, ncol = 2) +
  scale_color_manual(values = justice_palette) +
  scale_fill_manual(values = justice_palette) +
  labs(
    x = "Justice principle", y = "Standardised score (z), mean (95% CI)",
    color = "Profile", fill = "Profile"
  ) +
  theme_classic(base_size = 11) +
  theme(
    legend.position = "bottom",
    strip.background = element_rect(linewidth = 0),
    strip.text = element_text(face = "bold", size = 10)
  )

ggsave(snakemake@output[["figure"]], p, width = 8, height = 6, dpi = 200)
