# Regress LPA class membership on a set of predictors.
#
# Run through Snakemake (see rules/analyse.smk), which injects the
# `snakemake@input`/`@output`/`@params` S4 slots.
#
# Uses multinomial logistic regression (nnet::multinom) since the outcome
# here is unordered class membership. If a regression's outcome is instead
# an ordinal Likert item rather than a latent class, use
# ordinal::clm()/clmm() (cumulative link model) instead -- do not use plain
# lm() on Likert data.

library(arrow)
library(broom)
library(dplyr)
library(nnet)
library(readr)

set.seed(snakemake@params[["random_seed"]])

data <- read_parquet(snakemake@input[["data"]])
classes <- read_csv(snakemake@input[["classes"]], show_col_types = FALSE)

# TODO: replace with the actual predictor set for this wave/topic (e.g.
# sociodemographics, political values) once decided. Column names differ
# across waves (Qualtrics vs SoSci exports), so as a placeholder this just
# grabs one mostly-complete, low-cardinality numeric column so the pipeline
# runs end to end (the cardinality cap excludes ID-like fields, e.g. wave 3's
# "m" -- see the longer note in src/analyse/lpa.R).
bookkeeping_columns <- c("wave", "country", "topic", "respondent_id")
max_missing_share <- 0.2
min_unique_values <- 2
max_unique_values <- 20
predictor_columns <- data |>
  select(-any_of(bookkeeping_columns)) |>
  select(where(is.numeric)) |>
  select(where(~ mean(is.na(.)) <= max_missing_share)) |>
  select(where(~ between(length(unique(na.omit(.))), min_unique_values, max_unique_values))) |>
  colnames() |>
  head(1)

if (length(predictor_columns) == 0) {
  stop(
    "No usable regression predictor columns found for this wave under the ",
    "placeholder heuristic -- see the TODO in this file."
  )
}

model_data <- classes |>
  inner_join(data, by = "respondent_id") |>
  mutate(profile_class = factor(profile_class)) |>
  select(profile_class, all_of(predictor_columns)) |>
  na.omit()

# Backtick-quote predictor names: reformulate() doesn't auto-quote column
# names containing hyphens/spaces (e.g. "household-size"), which R's formula
# parser would otherwise silently misparse as an arithmetic expression.
formula <- reformulate(paste0("`", predictor_columns, "`"), response = "profile_class")
model <- multinom(formula, data = model_data, trace = FALSE)

saveRDS(model, snakemake@output[["model"]])

coefficients <- tidy(model, conf.int = TRUE) |>
  mutate(odds_ratio = exp(estimate))

write_csv(coefficients, snakemake@output[["coefficients"]])
