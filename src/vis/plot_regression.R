# Coefficient plot (odds ratios with 95% CIs) for a multinomial regression,
# faceted by outcome class level.
#
# Run through Snakemake (see rules/vis.smk).

library(ggplot2)
library(readr)

source("src/vis/theme.R")

coefficients <- read_csv(snakemake@input[["coefficients"]], show_col_types = FALSE) |>
  dplyr::filter(term != "(Intercept)")

p <- ggplot(coefficients, aes(x = odds_ratio, y = term)) +
  geom_vline(xintercept = 1, linetype = "dashed", colour = "grey50") +
  geom_pointrange(aes(xmin = exp(conf.low), xmax = exp(conf.high))) +
  facet_wrap(~y.level) +
  labs(
    title = "Regression coefficients (odds ratios)",
    x = "Odds ratio (95% CI)",
    y = NULL
  ) +
  theme_dp()

ggsave(snakemake@output[["figure"]], p, width = 7, height = 4, dpi = 300)
