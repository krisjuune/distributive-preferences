# Publication composition chart: sorted 100% stacked bar of latent profile
# class shares, one bar per country (one representative wave/country sample
# each -- see config/default.yaml's lpa.composition_waves). The message this
# is built to carry: the Utilitarian class is a minority everywhere.
#
# Run through Snakemake (see rules/vis.smk).

library(dplyr)
library(ggplot2)
library(readr)

source("src/vis/justice_palette.R")

principle_order <- c("Egalitarian", "Universalist", "Utilitarian")

classes_files <- snakemake@input[["classes"]]
wave_to_country <- unlist(snakemake@params[["wave_to_country"]])
wave_ids <- gsub("_spaghetti_classes\\.csv$", "", basename(classes_files))

# wave2_us is the only constant-sum (points-allocation) sample among the
# composition countries -- every other one uses the Likert scale. Flagged
# on the axis label with an asterisk (explained in the surrounding text,
# not on the plot itself).
constant_sum_wave_ids <- c("wave2_us")

class_sizes <- bind_rows(lapply(seq_along(classes_files), function(i) {
  wave_id <- wave_ids[i]
  country <- wave_to_country[[wave_id]]
  if (wave_id %in% constant_sum_wave_ids) country <- paste0(country, "*")
  read_csv(classes_files[i], show_col_types = FALSE) |>
    mutate(country = country)
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

p <- ggplot(class_sizes, aes(x = country, y = pct, fill = profile_class)) +
  geom_col(width = 0.7, alpha = 0.75) +
  geom_text(
    aes(label = ifelse(pct >= 5, paste0(round(pct), "%"), "")),
    position = position_stack(vjust = 0.5), size = 3, color = "black"
  ) +
  coord_flip() +
  scale_fill_manual(values = justice_palette, guide = guide_legend(reverse = TRUE)) +
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

ggsave(snakemake@output[["figure"]], p, width = 8, height = 6, dpi = 200)
