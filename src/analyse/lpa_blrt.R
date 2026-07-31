# Bootstrapped likelihood-ratio test (BLRT) for the LPA profile count
# (Nylund-Gibson, Grimm & Masyn 2019's recommended companion to information
# criteria): sequentially tests G vs G+1 via mclust::mclustBootstrapLRT(),
# which parametrically bootstraps the null (G-profile) model and refits both
# G and G+1 to each bootstrap sample to get a reference distribution for the
# observed likelihood-ratio statistic.
#
# This is deliberately not a resample of the whole G=1-8 elbow plot (see
# lpa.R) -- it targets only the specific decision boundaries the main text
# argues about (2 vs 3, 3 vs 4), which is both the standard use of this test
# and far cheaper than bootstrapping every information criterion at every G.
#
# Run through Snakemake (see rules/analyse.smk), which injects the
# `snakemake@input`/`@output`/`@params` S4 slots.

library(arrow)
library(dplyr)
library(mclust)
library(readr)

source("src/analyse/justice_indicators.R")

data <- read_parquet(snakemake@input[["data"]])
indicator_columns <- select_justice_indicators(data)

lpa_input <- data |>
  select(all_of(indicator_columns)) |>
  na.omit()

set.seed(snakemake@params[["random_seed"]])
result <- mclustBootstrapLRT(
  lpa_input,
  modelName = "EEI",
  nboot = snakemake@params[["nboot"]],
  maxG = snakemake@params[["max_g"]],
  verbose = FALSE
)

comparison_labels <- paste(result$G, result$G + 1, sep = " vs ")

tibble(
  comparison = comparison_labels,
  lrts = as.numeric(result$obs),
  p_value = as.numeric(result$p.value),
  nboot = snakemake@params[["nboot"]]
) |>
  write_csv(snakemake@output[["blrt"]])
