# Fits ONE slimmer model per probability-grid model_key: a fixed per-topic
# sociodemographic control set (see config regression.demographics) plus
# one or more focal attitude/value (or demographic) predictors -- rather
# than reusing one "kitchen sink" model (every attitude/value index
# simultaneously, see regression.R) for every column of a grid.
#
# Why one model per model_key rather than per column: several attitude/
# value predictors in the full model are highly collinear with each
# other (e.g. wave 4's economic-values index correlated 0.6-0.7 with two
# other indices in that same model). This was confirmed to flip the sign
# of at least one column's partial-effect curve relative to its actual
# (bivariate) relationship with profile membership -- refitting with
# just demographics + that one index brought it back in line with the
# bivariate direction. A small-multiples grid visually reads as "how
# does this one construct relate to profile membership", so each panel
# should come from a model built for exactly that question, not from a
# shared multivariate model whose collinearity among unrelated indices
# distorts individual partial effects.
#
# A model_key usually maps to exactly one predictor (one column, its own
# model). It maps to *more than one* predictor when several grid columns
# share a `group` in config -- e.g. the worldviews grid's individualism-
# communitarianism and hierarchy-egalitarianism columns are the two
# dimensions of one underlying construct (Kahan's cultural theory
# grid-group typology), not independent attitudes, so they're
# deliberately fit together: each one's curve then holds the OTHER
# worldview dimension constant (via predicted_probability_curve()'s
# usual "everything else at its reference value" behaviour), rather than
# ignoring it as if it were just another unrelated collinear predictor.
#
# Every grid config lists a full rows x columns cross product, and not
# every predictor exists for every row (e.g. wave4_eu currently has
# neither age nor gender). When NONE of a model_key's focal predictors
# are present for this wave/topic, this script writes NULL placeholder
# outputs rather than erroring, and the plotting scripts skip that cell
# -- same graceful-skip behaviour previously handled inline by checking
# column presence in a shared per-row model, just relocated here since
# each cell now has its own model file.
#
# Run through Snakemake (see rules/analyse.smk), which injects the
# `snakemake@input`/`@output`/`@params`/`@wildcards` S4 slots.

library(arrow)
library(dplyr)
library(nnet)
library(readr)

source("src/analyse/regression_predictors.R")
source("src/analyse/regression_model_helpers.R")

set.seed(snakemake@params[["random_seed"]])

unit_id <- snakemake@wildcards[["wave_id"]]
model_key <- snakemake@wildcards[["model_key"]]
focal_predictors <- unlist(snakemake@params[["focal_predictors"]])
wave_ids <- snakemake@params[["wave_ids"]]
topics <- snakemake@params[["topics"]]
countries <- snakemake@params[["countries"]]
demographics <- snakemake@params[["demographics"]]

wide_model_data <- build_wide_model_data(
  unit_id, wave_ids, topics, countries,
  snakemake@input[["data"]], snakemake@input[["classes"]]
)

available_focal <- intersect(focal_predictors, colnames(wide_model_data))
if (length(available_focal) == 0) {
  message(sprintf(
    "[regression_focal/%s/%s] none of (%s) available for this wave/topic -- writing empty placeholder outputs",
    unit_id, model_key, paste(focal_predictors, collapse = ", ")
  ))
  saveRDS(NULL, snakemake@output[["model"]])
  saveRDS(NULL, snakemake@output[["model_data"]])
  quit(save = "no", status = 0)
}

# demographics is a fixed per-topic list that may name columns this
# particular wave_id doesn't have (e.g. wave 3 CN has no left_right,
# wave 3 CN/CH's `language_region` is CH-only) -- keep only what's
# actually present rather than erroring. Deduplicated because a focal
# predictor is sometimes itself one of the demographics (e.g. the
# categorical grid's age/gender/income columns), in which case every
# column in that row ends up fit against the same "all demographics"
# set, which is correct: demographics were never the source of the
# collinearity problem this split exists to fix.
predictor_columns <- intersect(unique(c(demographics, available_focal)), colnames(wide_model_data))

fit <- fit_multinom_model(
  wide_model_data, predictor_columns, snakemake@params[["decay"]],
  label = sprintf("%s/%s", unit_id, model_key)
)

saveRDS(fit$model, snakemake@output[["model"]])
saveRDS(fit$model_data, snakemake@output[["model_data"]])
