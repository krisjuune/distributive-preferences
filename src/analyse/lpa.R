# Fit latent profile models (equal-variance, zero-covariance mixture of
# Gaussians, i.e. mclust model "EEI") over a range of profile counts and
# write out fit statistics plus the best-fitting classification.
#
# Run through Snakemake (see rules/analyse.smk), which injects the
# `snakemake@input`/`@output`/`@params` S4 slots.

library(arrow)
library(dplyr)
library(mclust)
library(readr)

source("src/analyse/justice_indicators.R")

data <- read_parquet(snakemake@input[["data"]])

m <- snakemake@params[["n_profiles_max"]]
set.seed(snakemake@params[["random_seed"]])

indicator_columns <- select_justice_indicators(data)

lpa_input <- data |>
  select(all_of(indicator_columns)) |>
  na.omit()

# Fit each profile count separately and compute fit indices directly from
# loglik/npar/n (the standard formulas tidyLPA itself uses, e.g. Nylund-Gibson
# & Choi 2018), rather than mclust's own $bic/$icl fields, which use the
# opposite ("higher is better") sign convention. This keeps every criterion
# on one consistent lower-is-better scale for the elbow plot.
#
# A given G can fail to converge to a proper fit (mclust then returns $z =
# NULL rather than raising an error) when the indicator set is degenerate,
# e.g. near-collinear placeholder columns -- skip that G (NA row) instead of
# crashing the whole rule.
fit_stats <- lapply(1:m, function(g) {
  fit_g <- Mclust(lpa_input, G = g, modelNames = "EEI")
  if (is.null(fit_g) || is.null(fit_g$z)) {
    return(tibble(
      G = g, loglik = NA_real_, npar = NA_integer_, AIC = NA_real_, BIC = NA_real_,
      CAIC = NA_real_, AWE = NA_real_, SABIC = NA_real_, ICL = NA_real_,
      entropy = NA_real_, min_class_proportion = NA_real_
    ))
  }
  z <- fit_g$z
  n <- nrow(z)
  npar <- fit_g$df
  loglik <- fit_g$loglik
  entropy <- 1 - sum(-z * log(z + 1e-12)) / (n * log(g))
  # ICL = BIC + entropy penalty (Biernacki, Celeux & Govaert 1998).
  classification_entropy <- -sum(z * log(z + 1e-12))
  tibble(
    G = g,
    loglik = loglik,
    npar = npar,
    AIC = -2 * loglik + 2 * npar,
    BIC = -2 * loglik + npar * log(n),
    CAIC = -2 * loglik + npar * (log(n) + 1),
    AWE = -2 * loglik + 2 * npar * (log(n) + 1.5),
    SABIC = -2 * loglik + npar * log((n + 2) / 24),
    ICL = -2 * loglik + npar * log(n) + 2 * classification_entropy,
    entropy = if (g == 1) NA_real_ else entropy,
    min_class_proportion = min(table(fit_g$classification)) / n
  )
}) |> bind_rows()

write_csv(fit_stats, snakemake@output[["fit_stats"]])

if (all(is.na(fit_stats$BIC))) {
  stop(
    "Every G from 1 to ", m, " failed to converge to a proper fit for this ",
    "wave's placeholder indicator set (see fit_stats output). The indicator ",
    "columns are likely degenerate (e.g. redundant experimental-design ",
    "columns) -- see the TODO in this file."
  )
}

best_g <- fit_stats$G[which.min(fit_stats$BIC)]
best_fit <- Mclust(lpa_input, G = best_g, modelNames = "EEI")

classes <- data |>
  filter(if_all(all_of(indicator_columns), ~ !is.na(.))) |>
  mutate(profile_class = best_fit$classification) |>
  select(respondent_id, profile_class)

write_csv(classes, snakemake@output[["classes"]])
