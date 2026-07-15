# Confirmatory factor analysis of the justice-principle items -- testing
# whether the 4-principle structure used for LPA (utilitarian/egalitarian/
# sufficientarian/limitarian, H1-H4) fits better than a simpler 2-factor
# distribution-insensitive-vs-sensitive alternative (H5-H6). Follows the
# core of Rogers' (2024) CFA best-practices workflow: drop incomplete rows,
# sanity-check item variance/skew, fit with robust MLR, compare fit indices.
#
# A third model, bifactor, is fit alongside these two: a general "fairness
# endorsement" factor loading on every item plus the same 4 specific
# principle factors, all mutually orthogonal (orthogonal = TRUE). This is
# the standard follow-up when the 4-factor correlated-traits model shows
# near-unity inter-factor correlations -- it separates genuine
# principle-specific variance from a shared response tendency (e.g.
# acquiescence). If the specific factors' loadings/discriminant validity
# clean up once the general factor absorbs the shared variance, that
# favours a method-variance explanation over "people don't distinguish
# these principles."
#
# wave2 is included only as a comparison against wave1_3's Likert items --
# its constant-sum items are ipsative (forced to sum to a constant within
# each domain), which can make the sample covariance matrix singular and
# the model simply un-fittable. Models can also fail to fit for other
# subsets/reasons (e.g. non-convergence on a small or homogeneous sample),
# so every fit is wrapped in tryCatch and a failure is written out as a
# result (NA fit measures + a failure_reason column) rather than crashing
# the rule.
#
# Run through Snakemake (see rules/analyse.smk), which injects the
# `snakemake@input`/`@output`/`@params`/`@wildcards` S4 slots.

library(arrow)
library(dplyr)
library(lavaan)
library(readr)

set.seed(snakemake@params[["random_seed"]])

cfa_group <- snakemake@wildcards[["cfa_group"]]

if (cfa_group %in% c("wave1_3", "wave2")) {
  # wave2 uses the same item names/structure as wave1_3 (justice_general/
  # tax/subsidy_1-4), just a constant-sum rather than Likert response
  # format -- see the caveat above.
  items <- c(
    paste0("justice_general_", 1:4), paste0("justice_tax_", 1:4), paste0("justice_subsidy_", 1:4)
  )
  model_4factor <- "
    util =~ justice_general_1 + justice_tax_1 + justice_subsidy_1
    egal =~ justice_general_2 + justice_tax_2 + justice_subsidy_2
    suff =~ justice_general_3 + justice_tax_3 + justice_subsidy_3
    lim  =~ justice_general_4 + justice_tax_4 + justice_subsidy_4
  "
  model_2factor <- "
    insensitive =~ justice_general_1 + justice_tax_1 + justice_subsidy_1
    sensitive   =~ justice_general_2 + justice_tax_2 + justice_subsidy_2 +
                    justice_general_3 + justice_tax_3 + justice_subsidy_3 +
                    justice_general_4 + justice_tax_4 + justice_subsidy_4
  "
  model_bifactor <- "
    general =~ justice_general_1 + justice_tax_1 + justice_subsidy_1 +
                justice_general_2 + justice_tax_2 + justice_subsidy_2 +
                justice_general_3 + justice_tax_3 + justice_subsidy_3 +
                justice_general_4 + justice_tax_4 + justice_subsidy_4
    util =~ justice_general_1 + justice_tax_1 + justice_subsidy_1
    egal =~ justice_general_2 + justice_tax_2 + justice_subsidy_2
    suff =~ justice_general_3 + justice_tax_3 + justice_subsidy_3
    lim  =~ justice_general_4 + justice_tax_4 + justice_subsidy_4
  "
} else if (cfa_group == "wave4") {
  items <- c(
    "justice_general_costmin", "justice_general_inequ", "justice_general_minim", "justice_general_many_benefits",
    "justice_tax_moderate", "justice_tax_basic", "justice_tax_all", "justice_tax_luxury",
    "justice_subsidy_everyone", "justice_subsidy_lower", "justice_subsidy_additional", "justice_subsidy_high",
    "justice_ban_reduction", "justice_ban_fleets", "justice_ban_alternatives", "justice_ban_all_income"
  )
  model_4factor <- "
    util =~ justice_general_costmin + justice_tax_moderate + justice_subsidy_everyone + justice_ban_reduction
    egal =~ justice_general_inequ + justice_tax_basic + justice_subsidy_lower + justice_ban_all_income
    suff =~ justice_general_minim + justice_tax_all + justice_subsidy_additional + justice_ban_alternatives
    lim  =~ justice_general_many_benefits + justice_tax_luxury + justice_subsidy_high + justice_ban_fleets
  "
  model_2factor <- "
    insensitive =~ justice_general_costmin + justice_tax_moderate + justice_subsidy_everyone + justice_ban_reduction
    sensitive   =~ justice_general_inequ + justice_tax_basic + justice_subsidy_lower + justice_ban_all_income +
                    justice_general_minim + justice_tax_all + justice_subsidy_additional + justice_ban_alternatives +
                    justice_general_many_benefits + justice_tax_luxury + justice_subsidy_high + justice_ban_fleets
  "
  model_bifactor <- "
    general =~ justice_general_costmin + justice_tax_moderate + justice_subsidy_everyone + justice_ban_reduction +
                justice_general_inequ + justice_tax_basic + justice_subsidy_lower + justice_ban_all_income +
                justice_general_minim + justice_tax_all + justice_subsidy_additional + justice_ban_alternatives +
                justice_general_many_benefits + justice_tax_luxury + justice_subsidy_high + justice_ban_fleets
    util =~ justice_general_costmin + justice_tax_moderate + justice_subsidy_everyone + justice_ban_reduction
    egal =~ justice_general_inequ + justice_tax_basic + justice_subsidy_lower + justice_ban_all_income
    suff =~ justice_general_minim + justice_tax_all + justice_subsidy_additional + justice_ban_alternatives
    lim  =~ justice_general_many_benefits + justice_tax_luxury + justice_subsidy_high + justice_ban_fleets
  "
} else {
  stop("Unknown cfa_group '", cfa_group, "'.")
}

# Select only the modelled items from each file before combining -- some
# waves carry unrelated columns under colliding names with mismatched types
# across raw exports (e.g. an embedded "m" column that's numeric in one
# wave's export and text in another's), which breaks a naive bind_rows().
data <- bind_rows(lapply(snakemake@input[["data"]], function(path) {
  read_parquet(path) |> select(all_of(items))
}))

# --- preprocessing: drop rows missing any justice item ---
n_total <- nrow(data)
cfa_data <- data |> filter(if_all(everything(), ~ !is.na(.)))
n_dropped <- n_total - nrow(cfa_data)
message(sprintf(
  "[cfa/%s] dropped %d of %d rows (%.1f%%) with missing justice items -- n = %d",
  cfa_group, n_dropped, n_total, 100 * n_dropped / n_total, nrow(cfa_data)
))

# --- sanity checks (report only, no row/item removal -- matches "main
# part" scope; a fuller pass would also screen multivariate outliers and
# straight-lining per Rogers 2024) ---
item_sd <- sapply(cfa_data, sd, na.rm = TRUE)
message(sprintf("[cfa/%s] item SD range: %.2f - %.2f", cfa_group, min(item_sd), max(item_sd)))
if (any(item_sd < 0.25)) {
  message(sprintf(
    "[cfa/%s] WARNING: %d item(s) have SD < 0.25 (low-variability responses; see Collier 2020).",
    cfa_group, sum(item_sd < 0.25)
  ))
}

skewness <- function(x) {
  x <- x[!is.na(x)]
  n <- length(x)
  m <- mean(x)
  (sum((x - m)^3) / n) / (sum((x - m)^2) / n)^1.5
}
item_skew <- sapply(cfa_data, skewness)
message(sprintf("[cfa/%s] item skewness range: %.2f - %.2f", cfa_group, min(item_skew), max(item_skew)))
if (any(abs(item_skew) > 1)) {
  message(sprintf(
    "[cfa/%s] WARNING: %d item(s) have |skewness| > 1 -- treating as continuous may not be appropriate.",
    cfa_group, sum(abs(item_skew) > 1)
  ))
}

# --- fit all three models with robust MLR, tolerating outright fitting
# failures. The bifactor model additionally needs orthogonal = TRUE, which
# fixes covariances among ALL exogenous latents (general and every
# specific factor) to zero -- the standard bifactor specification. ---
fit_safely <- function(model_syntax, model_name, orthogonal = FALSE) {
  tryCatch(
    {
      fit <- cfa(model_syntax, data = cfa_data, estimator = "MLR", orthogonal = orthogonal)
      # cfa() can return an object without raising an error even when the
      # optimizer failed to converge (it just warns) -- fitMeasures() then
      # errors out downstream, so check convergence here and treat it as a
      # fitting failure, same as an outright error. Bifactor models with few
      # indicators per specific factor are especially prone to this.
      if (!lavInspect(fit, "converged")) {
        message(sprintf("[cfa/%s] %s did not converge", cfa_group, model_name))
        return(list(fit = NULL, error = "model did not converge"))
      }
      list(fit = fit, error = NA_character_)
    },
    error = function(e) {
      message(sprintf("[cfa/%s] %s FAILED TO FIT: %s", cfa_group, model_name, conditionMessage(e)))
      list(fit = NULL, error = conditionMessage(e))
    }
  )
}

result_4factor <- fit_safely(model_4factor, "four_factor")
result_2factor <- fit_safely(model_2factor, "two_factor")
result_bifactor <- fit_safely(model_bifactor, "bifactor", orthogonal = TRUE)

fit_measure_names <- c(
  "chisq.scaled", "df.scaled", "pvalue.scaled",
  "cfi.robust", "tli.robust", "rmsea.robust",
  "rmsea.ci.lower.robust", "rmsea.ci.upper.robust",
  "srmr", "aic", "bic"
)

# fitMeasures() returns a "lavaan.vector"-classed numeric vector; strip that
# class via as.numeric() before building rows, otherwise bind_rows() can't
# reconcile the custom class across the two models' data frames.
extract_fit_measures <- function(result, model_name) {
  if (is.null(result$fit)) {
    na_row <- as.data.frame(as.list(rep(NA_real_, length(fit_measure_names)))) |>
      setNames(fit_measure_names)
    return(na_row |> mutate(model = model_name, failure_reason = result$error))
  }
  fm <- fitMeasures(result$fit, fit_measure_names)
  as.data.frame(as.list(as.numeric(fm))) |>
    setNames(names(fm)) |>
    mutate(model = model_name, failure_reason = NA_character_)
}

fit_measures <- bind_rows(
  extract_fit_measures(result_4factor, "four_factor"),
  extract_fit_measures(result_2factor, "two_factor"),
  extract_fit_measures(result_bifactor, "bifactor")
) |> relocate(model)

write_csv(fit_measures, snakemake@output[["fit_measures"]])

extract_parameters <- function(result, model_name) {
  if (is.null(result$fit)) {
    return(NULL)
  }
  standardizedSolution(result$fit) |> mutate(model = model_name)
}

parameters <- bind_rows(
  extract_parameters(result_4factor, "four_factor"),
  extract_parameters(result_2factor, "two_factor"),
  extract_parameters(result_bifactor, "bifactor")
)

if (nrow(parameters) > 0) {
  parameters <- parameters |>
    relocate(model) |>
    rename(lhs_var = lhs, rhs_var = rhs, std_estimate = est.std)
}

write_csv(parameters, snakemake@output[["loadings"]])
