# Regress LPA profile membership on a wave-specific set of socio-
# demographic and attitudinal/value predictors, catalogued in
# manuscript/predictors_table.tex (built interactively; see that file's
# git history/conversation for how each item and composite index was
# verified against the raw data rather than assumed).
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
# When pooling, composite indices (see regression_predictors.R) are built
# ONCE on the combined raw sub-items across every country, not per-country
# then re-combined -- so "2 SD above the mean" means 2 SD above the
# pooled European mean, not country-relative. `country` is added as a
# control predictor whenever more than one wave_id is combined, so index
# coefficients reflect within-country variation net of country-level
# baseline differences, not a conflation of the two.
#
# Uses multinomial logistic regression (nnet::multinom) since the outcome
# is unordered class membership. If a regression's outcome is instead an
# ordinal Likert item rather than a latent class, use ordinal::clm()/
# clmm() (cumulative link model) instead -- do not use plain lm() on
# Likert data.
#
# Run through Snakemake (see rules/analyse.smk), which injects the
# `snakemake@input`/`@output`/`@params` S4 slots. Recoding/composite-index
# helpers live in regression_predictors.R so they're reusable and
# independently readable.

library(arrow)
library(broom)
library(dplyr)
library(nnet)
library(readr)

source("src/analyse/regression_predictors.R")

set.seed(snakemake@params[["random_seed"]])

unit_id <- snakemake@wildcards[["wave_id"]]
wave_ids <- snakemake@params[["wave_ids"]]
topics <- snakemake@params[["topics"]]
countries <- snakemake@params[["countries"]]

data_paths <- snakemake@input[["data"]]
classes_paths <- snakemake@input[["classes"]]

# Build each wave_id's predictors independently, join each to *its own*
# classes on respondent_id (which is only unique within a wave_id, not
# globally), and tag every row with a wave_id-qualified key before
# pooling -- avoids any risk of respondent_id collisions once combined.
per_wave <- lapply(seq_along(wave_ids), function(i) {
  wid <- wave_ids[i]
  data <- read_parquet(data_paths[i])
  classes <- read_csv(classes_paths[i], show_col_types = FALSE) |> select(respondent_id, profile_class)

  built <- build_wave_predictors(data, topics[[wid]], wid)

  simple <- built$simple
  simple$row_key <- paste(wid, simple$respondent_id, sep = "::")
  simple$country <- countries[[wid]]
  simple$respondent_id <- NULL

  classes_keyed <- classes |>
    mutate(row_key = paste(wid, respondent_id, sep = "::")) |>
    select(row_key, profile_class)
  simple <- simple |> inner_join(classes_keyed, by = "row_key")

  composite_items <- lapply(built$composite_items, function(df) {
    df$row_key <- paste(wid, df$respondent_id, sep = "::")
    df$respondent_id <- NULL
    # Keep only rows that survived the classes join above (LPA can drop a
    # handful of rows with missing justice items).
    df |> semi_join(simple, by = "row_key")
  })

  list(simple = simple, composite_items = composite_items)
})

model_data <- bind_rows(lapply(per_wave, `[[`, "simple"))

composite_names <- unique(unlist(lapply(per_wave, function(x) names(x$composite_items))))
for (name in composite_names) {
  items_pooled <- bind_rows(lapply(per_wave, function(x) x$composite_items[[name]]))
  items_pooled <- items_pooled[match(model_data$row_key, items_pooled$row_key), ]
  item_columns <- setdiff(colnames(items_pooled), "row_key")
  model_data[[name]] <- build_composite_index(items_pooled[item_columns], label = sprintf("%s %s", unit_id, name))
}

model_data$row_key <- NULL

# `country` is only informative -- and only estimable -- when pooling more
# than one wave_id; drop it otherwise rather than fit a constant column
# (the same degenerate-predictor problem as a zero-variance factor level,
# see below).
if (length(unique(model_data$country)) < 2) {
  model_data$country <- NULL
} else {
  message(sprintf(
    "[regression/%s] pooling %d wave_ids (%s) -- adding `country` as a control predictor",
    unit_id, length(wave_ids), paste(wave_ids, collapse = ", ")
  ))
  model_data$country <- factor(model_data$country)
}

model_data <- model_data |> mutate(profile_class = factor(profile_class))
predictor_columns <- setdiff(colnames(model_data), "profile_class")

n_total <- nrow(model_data)
model_data <- na.omit(model_data)
message(sprintf(
  "[regression/%s] dropped %d of %d rows (%.1f%%) with missing predictors -- n = %d",
  unit_id, n_total - nrow(model_data), n_total, 100 * (n_total - nrow(model_data)) / n_total, nrow(model_data)
))

# Factor levels are set when each predictor column is first built, from
# the *full* wave dataset -- if listwise deletion above happens to leave a
# level with zero remaining rows in a small country sample, that level's
# dummy column is a constant zero across every retained row: a degenerate
# predictor that produces exactly the kind of numerical explosion
# (huge/infinite odds ratios, NaN standard errors) first found when
# fitting wave4's country models. droplevels() removes empty levels; a
# factor occasionally has *no* remaining variation at all once emptied
# (e.g. wave4_fi's `party`, where every retained respondent turned out to
# share one level), so those are dropped from the model entirely too.
model_data <- droplevels(model_data)
constant_predictors <- predictor_columns[vapply(
  predictor_columns, function(col) is.factor(model_data[[col]]) && nlevels(model_data[[col]]) < 2, logical(1)
)]
if (length(constant_predictors) > 0) {
  message(sprintf(
    "[regression/%s] dropped constant predictor(s) with no remaining variation after listwise deletion: %s",
    unit_id, paste(constant_predictors, collapse = ", ")
  ))
  predictor_columns <- setdiff(predictor_columns, constant_predictors)
}

# Backtick-quote predictor names: reformulate() doesn't auto-quote column
# names containing hyphens/spaces, which R's formula parser would
# otherwise silently misparse as an arithmetic expression.
formula <- reformulate(paste0("`", predictor_columns, "`"), response = "profile_class")
# A small ridge-type penalty (nnet::multinom's built-in `decay`, standard
# weight-decay regularisation -- no extra package needed) tempers the
# residual separation that even careful predictor selection can't fully
# rule out: with a rare outcome category (e.g. wave4's ~10-20 Utilitarian
# respondents per country) crossed against any moderately-leveled
# categorical predictor, some cell is very likely to end up empty or
# near-empty by chance alone. Verified against wave4_fi (the worst case
# found): decay = 0.1 brings the max odds ratio from 216 down to ~30 and
# the min from 2e-6 up to ~0.3, without visibly changing the already
# well-behaved wave 1-3 estimates.
model <- multinom(
  formula, data = model_data, trace = FALSE, MaxNWts = 2000,
  decay = snakemake@params[["decay"]]
)

saveRDS(model, snakemake@output[["model"]])
# The exact post-NA-omit data the model was fit on -- saved so downstream
# scripts (e.g. predicted-probability plots) can build a correct reference
# row (factor levels, predictor ranges) without re-deriving the predictor
# set from scratch and risking drift from what's actually in `model`.
saveRDS(model_data, snakemake@output[["model_data"]])

coefficients <- tidy(model, conf.int = TRUE) |>
  mutate(odds_ratio = exp(estimate))

write_csv(coefficients, snakemake@output[["coefficients"]])
