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

# mclust's own class numbering (1/2/3/...) is arbitrary per fit, so "class 1"
# in one wave has no relationship to "class 1" in another. Relabel by each
# class's mean level across the 4 justice principles (highest -> lowest) so
# the label -- and its colour in src/vis/plot_lpa_spaghetti.R -- means the
# same thing everywhere.
#
# At G=3 specifically, the 3 levels get named principles (Egalitarian/
# Universalist/Utilitarian) because that solution is the one reported
# throughout the rest of the analysis. Any other G (e.g. the G=4 robustness
# check) gets generic "Profile N" labels instead -- there's no substantive
# reason a 4th class should map onto one of those 3 names, and doing so
# would imply a correspondence to the G=3 solution that hasn't been checked.
if (g == 3) {
  principle_order <- c("Egalitarian", "Universalist", "Utilitarian")
} else {
  principle_order <- paste("Profile", seq_len(g))
}

utilitarian_column <- indicator_columns[grepl("utilitarian", indicator_columns, ignore.case = TRUE)]
distributive_columns <- setdiff(indicator_columns, utilitarian_column)

# Wave 2's items are constant-sum (points allocated within each domain
# always sum to the same total), so every respondent's plain mean across
# the 4 principles is the same constant regardless of class -- ranking by
# it is essentially arbitrary there. The egalitarian/sufficientarian/
# limitarian-vs-utilitarian contrast doesn't have that problem (the split
# between those two groups of items still varies under a fixed total), so
# it's used for wave 2 -- but only at G != 3: G=3's principle_order needs
# the per-country correspondence verified in label_overrides below, which
# was calibrated against the plain-mean ranking, so switching its ranking
# key would invalidate that calibration. Outside wave 2, the plain mean is
# used everywhere (matching G=3) because the contrast metric mis-ranks
# small, uniformly-low outlier classes -- a tiny "low on everything"
# cluster can have a higher distributive-vs-utilitarian contrast than a
# larger, more central class despite sitting well below it on every
# principle.
use_contrast <- g != 3 && startsWith(wave_id, "wave2")

class_levels <- lpa_input |>
  mutate(
    mclust_class = fit$classification,
    rank_score = if (use_contrast) {
      rowMeans(across(all_of(distributive_columns))) - .data[[utilitarian_column]]
    } else {
      rowMeans(across(all_of(indicator_columns)))
    }
  ) |>
  summarise(rank_score = mean(rank_score), .by = mclust_class) |>
  arrange(desc(rank_score)) |>
  mutate(profile_class = principle_order[row_number()])

label_by_mclust_class <- setNames(class_levels$profile_class, class_levels$mclust_class)
profile_class_label <- label_by_mclust_class[as.character(fit$classification)]

# At G=3, wave 2's plain-mean ranking is arbitrary (see above) and is
# manually corrected per country instead, verified against the actual
# profile shapes.
label_overrides <- list(
  wave2_ch = c(Egalitarian = "Universalist", Universalist = "Egalitarian", Utilitarian = "Utilitarian"),
  wave2_cn = c(Egalitarian = "Utilitarian", Universalist = "Universalist", Utilitarian = "Egalitarian"),
  wave2_us = c(Egalitarian = "Universalist", Universalist = "Utilitarian", Utilitarian = "Egalitarian")
)

if (g == 3 && wave_id %in% names(label_overrides)) {
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
