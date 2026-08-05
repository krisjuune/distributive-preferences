# Regress LPA profile membership on the FULL wave-specific set of socio-
# demographic and attitudinal/value predictors simultaneously, catalogued
# in manuscript/predictors_table.tex (built interactively; see that
# file's git history/conversation for how each item and composite index
# was verified against the raw data rather than assumed).
#
# This full multivariate model is used for the supplementary coefficients
# table. The probability-grid figures do NOT use this model any more --
# they use regression_focal.R's slimmer, one-predictor-at-a-time models
# instead, because several of this model's attitude/value predictors are
# highly collinear with each other (e.g. wave 4's economic-values index
# correlates 0.6-0.7 with two other indices in this same model), which
# was confirmed to flip the sign of at least one predictor's partial
# effect relative to its real (bivariate) relationship with profile
# membership. That collinearity is fine -- expected, even -- for a model
# whose purpose is reporting adjusted coefficients across every predictor
# jointly; it's specifically the "hold everything else constant and plot
# one curve" use case that collinearity makes misleading, hence the split.
#
# Outcome: the fixed-G=3 profile_class (Egalitarian/Universalist/
# Utilitarian), i.e. build/results/lpa/{wave_id}_spaghetti_classes.csv --
# not each wave's own BIC-optimal class assignment -- so profile labels
# mean the same thing across waves/countries, consistent with every other
# cross-wave figure in this pipeline.
#
# Handles both a single wave_id (e.g. "wave3_ch") and a pooled group of
# several wave_ids that share one topic (e.g. "wave4_eu" = all 9 wave4
# countries, see config regression.groups) -- pooling exists specifically
# to give small-sample countries (as few as ~100-250 respondents, ~10-40
# Utilitarian) more stable estimates than a per-country fit can support.
# `country` is added as a control predictor whenever more than one
# wave_id is combined, so index coefficients reflect within-country
# variation net of country-level baseline differences, not a conflation
# of the two. See regression_model_helpers.R's build_wide_model_data()
# for the pooling/join mechanics shared with regression_focal.R.
#
# Uses multinomial logistic regression (nnet::multinom) since the outcome
# is unordered class membership. If a regression's outcome is instead an
# ordinal Likert item rather than a latent class, use ordinal::clm()/
# clmm() (cumulative link model) instead -- do not use plain lm() on
# Likert data.
#
# Run through Snakemake (see rules/analyse.smk), which injects the
# `snakemake@input`/`@output`/`@params` S4 slots. Recoding/composite-index
# helpers live in regression_predictors.R, and the data-assembly/fitting
# logic shared with regression_focal.R lives in regression_model_helpers.R,
# so they're reusable and independently readable.

library(arrow)
library(broom)
library(dplyr)
library(nnet)
library(readr)

source("src/analyse/regression_predictors.R")
source("src/analyse/regression_model_helpers.R")

set.seed(snakemake@params[["random_seed"]])

unit_id <- snakemake@wildcards[["wave_id"]]
wave_ids <- snakemake@params[["wave_ids"]]
topics <- snakemake@params[["topics"]]
countries <- snakemake@params[["countries"]]

wide_model_data <- build_wide_model_data(
  unit_id, wave_ids, topics, countries,
  snakemake@input[["data"]], snakemake@input[["classes"]]
)
predictor_columns <- setdiff(colnames(wide_model_data), "profile_class")

fit <- fit_multinom_model(wide_model_data, predictor_columns, snakemake@params[["decay"]], unit_id)

saveRDS(fit$model, snakemake@output[["model"]])
# The exact post-NA-omit data the model was fit on -- saved so downstream
# scripts can build a correct reference row (factor levels, predictor
# ranges) without re-deriving the predictor set from scratch.
saveRDS(fit$model_data, snakemake@output[["model_data"]])

coefficients <- tidy(fit$model, conf.int = TRUE) |>
  mutate(odds_ratio = exp(estimate))

write_csv(coefficients, snakemake@output[["coefficients"]])
