# Fit a latent profile model at a fixed number of profiles (rather than the
# BIC-optimal G used in lpa.R/build/results/lpa/*_classes.csv) so every
# wave/country sample can be compared side by side at the same G -- see
# src/vis/plot_lpa_spaghetti.R.
#
# Run through Snakemake (see rules/analyse.smk), which injects the
# `snakemake@input`/`@output`/`@params` S4 slots.

library(arrow)
library(dplyr)
library(mclust)
library(readr)

source("src/analyse/justice_indicators.R")

data <- read_parquet(snakemake@input[["data"]])

g <- snakemake@params[["g"]]
set.seed(snakemake@params[["random_seed"]])

indicator_columns <- select_justice_indicators(data)

lpa_input <- data |>
  select(all_of(indicator_columns)) |>
  na.omit()

fit <- Mclust(lpa_input, G = g, modelNames = "EEI")
if (is.null(fit) || is.null(fit$z)) {
  stop("Fixed-G fit (G = ", g, ") failed to converge for this wave.")
}

wave_id <- snakemake@wildcards[["wave_id"]]

# mclust's own class numbering (1/2/3) is arbitrary per fit, so "class 1"
# in one wave has no relationship to "class 1" in another. Relabel by each
# class's mean level across the 4 justice principles (highest -> Egalitarian,
# middle -> Universalist, lowest -> Utilitarian) so the label -- and its
# colour in src/vis/plot_lpa_spaghetti.R -- means the same thing everywhere.
principle_order <- c("Egalitarian", "Universalist", "Utilitarian")
class_levels <- lpa_input |>
  mutate(
    mclust_class = fit$classification,
    overall_level = rowMeans(across(all_of(indicator_columns)))
  ) |>
  summarise(overall_level = mean(overall_level), .by = mclust_class) |>
  arrange(desc(overall_level)) |>
  mutate(profile_class = principle_order[row_number()])

label_by_mclust_class <- setNames(class_levels$profile_class, class_levels$mclust_class)

# The overall-mean-level heuristic above is meaningless for wave 2: its
# items are constant-sum (points allocated within each domain always sum to
# the same total), so every respondent's mean across the 4 principles is
# the same constant regardless of class -- the ranking it produces there is
# essentially arbitrary. Manually corrected per country, verified against
# the actual profile shapes.
label_overrides <- list(
  wave2_ch = c(Egalitarian = "Universalist", Universalist = "Egalitarian", Utilitarian = "Utilitarian"),
  wave2_cn = c(Egalitarian = "Utilitarian", Universalist = "Universalist", Utilitarian = "Egalitarian"),
  wave2_us = c(Egalitarian = "Universalist", Universalist = "Utilitarian", Utilitarian = "Egalitarian")
)

profile_class_label <- label_by_mclust_class[as.character(fit$classification)]
if (wave_id %in% names(label_overrides)) {
  profile_class_label <- label_overrides[[wave_id]][profile_class_label]
}

classes <- data |>
  filter(if_all(all_of(indicator_columns), ~ !is.na(.))) |>
  mutate(
    profile_class = factor(profile_class_label, levels = principle_order),
    wave_id = wave_id
  ) |>
  select(wave_id, respondent_id, all_of(indicator_columns), profile_class)

write_csv(classes, snakemake@output[["classes"]])
