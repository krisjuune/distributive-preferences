# Spaghetti plot of individual respondent profiles across the 4 justice
# principles, one row per wave/country sample, each row showing the G
# profile classes (fixed G, see rules/analyse.smk::lpa_fixed_g) side by side
# plus a bar chart of class sizes. Styled after
# climate-justice-orientation/lpa/lpa_compare_waves.R.
#
# Run through Snakemake (see rules/vis.smk). Shared between the G=3 main
# figure and the G=4 robustness check (rules/vis.smk::plot_lpa_spaghetti /
# plot_lpa_spaghetti_g4) -- `g` selects which.

library(dplyr)
library(ggplot2)
library(patchwork)
library(purrr)
library(readr)
library(tidyr)

source("src/vis/justice_palette.R")

set.seed(snakemake@params[["random_seed"]])
g <- snakemake@params[["g"]]
sample_n <- snakemake@params[["sample_n"]]
wave_titles <- unlist(snakemake@params[["wave_titles"]])
ncol <- snakemake@params[["ncol"]]

classes_files <- snakemake@input[["classes"]]

# Preserve the wave/country order the files were listed in (matches
# config/default.yaml's `waves:` order) for a sensibly ordered stack of rows.
wave_order <- gsub("_spaghetti_classes(_g4)?\\.csv$", "", basename(classes_files))

# G=3 uses the named-principle labels/colours shared with every other LPA
# figure (src/vis/justice_palette.R). Any other G (generic "Profile N"
# labels, see src/analyse/lpa_fixed_g.R) gets its own palette so it isn't
# visually mistaken for a correspondence to the G=3 classes.
if (g == 3) {
  principle_order <- c("Egalitarian", "Universalist", "Utilitarian")
  class_palette <- justice_palette
} else {
  principle_order <- paste("Profile", seq_len(g))
  generic_colors <- c("#6a3d9a", "#1f78b4", "#33a02c", "#ff7f00", "#e31a1c", "#b15928")
  class_palette <- setNames(generic_colors[seq_len(g)], principle_order)
}

all_classes <- bind_rows(lapply(classes_files, read_csv, show_col_types = FALSE)) |>
  mutate(
    wave_id = factor(wave_id, levels = wave_order),
    # profile_class is already a meaningful label (see lpa_fixed_g.R), fixed
    # to the same `g` levels -- and so the same colour -- across every wave.
    profile_class = factor(profile_class, levels = principle_order)
  )

# Raw sum scores aren't comparable across waves (wave 4 is a 7-point scale
# summed over 4 items per principle, vs. waves 1-3's 6-point/3-item scale),
# so standardise each principle within its own wave before plotting -- shape
# across principles/classes is what we want to compare, not absolute level.
all_classes <- all_classes |>
  group_by(wave_id) |>
  mutate(across(starts_with("justice_principle_"), ~ as.numeric(scale(.)))) |>
  ungroup()

class_sizes <- all_classes |>
  count(wave_id, profile_class, name = "n", .drop = FALSE) |>
  mutate(pct = 100 * n / sum(n), .by = wave_id)

sampled <- all_classes |>
  group_split(wave_id, profile_class) |>
  map_dfr(~ slice_sample(.x, n = min(sample_n, nrow(.x))))

principle_levels <- c(
  "justice_principle_egalitarian",
  "justice_principle_limitarian",
  "justice_principle_sufficientarian",
  "justice_principle_utilitarian"
)
principle_labels <- c("Egal", "Lim", "Suff", "Util")

plot_data <- sampled |>
  mutate(unique_id = paste(wave_id, respondent_id, sep = "_")) |>
  pivot_longer(
    cols = starts_with("justice_principle_"),
    names_to = "principle",
    values_to = "value"
  ) |>
  mutate(principle = factor(principle, levels = principle_levels, labels = principle_labels))

plot_profiles_for_wave <- function(wave) {
  ggplot(
    filter(plot_data, wave_id == wave),
    aes(x = principle, y = value, group = unique_id, color = profile_class)
  ) +
    geom_line(alpha = 0.4, linewidth = 0.5) +
    facet_wrap(~profile_class, ncol = g) +
    labs(title = wave_titles[[wave]], x = NULL, y = "Standardised score (z)", color = "Profile") +
    scale_color_manual(values = class_palette, drop = FALSE) +
    theme_classic() +
    theme(
      plot.title = element_text(size = 10, face = "bold"),
      text = element_text(size = 9),
      strip.background = element_rect(linewidth = 0),
      strip.text = element_text(size = 9)
    )
}

plot_sizes_for_wave <- function(wave) {
  ggplot(
    filter(class_sizes, wave_id == wave),
    aes(x = profile_class, y = pct, fill = profile_class)
  ) +
    geom_col(width = 0.5) +
    geom_text(aes(label = paste0(round(pct), "%")), hjust = -0.15, size = 2.5) +
    coord_flip(clip = "off") +
    labs(x = NULL, y = NULL) +
    # guide = "none" at the scale level, not theme(legend.position = "none")
    # -- the latter gets clobbered by the shared `& theme(legend.position =
    # "bottom")` applied to every subplot when collecting guides below.
    scale_fill_manual(values = class_palette, drop = FALSE, guide = "none") +
    scale_y_continuous(expand = expansion(mult = c(0, 0.35))) +
    theme_classic() +
    theme(
      axis.text.y = element_blank(),
      axis.ticks.y = element_blank(),
      text = element_text(size = 9)
    )
}

row_plots <- lapply(wave_order, function(wave) {
  # Bar-chart column stays 1 unit wide regardless of G; the profile-facet
  # column scales with it (2 units/facet, matching the G=3 6:1 ratio).
  plot_profiles_for_wave(wave) + plot_sizes_for_wave(wave) + plot_layout(widths = c(2 * g, 1))
})

# One shared legend (collected from the profile plots' colour scale) at the
# bottom instead of one per row.
p <- wrap_plots(row_plots, ncol = ncol) +
  plot_layout(guides = "collect") &
  theme(legend.position = "bottom")

n_grid_rows <- ceiling(length(wave_order) / ncol)
ggsave(
  snakemake@output[["figure"]], p,
  width = 8 * ncol, height = 2.1 * n_grid_rows, dpi = 150, limitsize = FALSE
)
