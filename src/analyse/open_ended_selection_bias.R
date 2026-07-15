# Checks whether wave 3's open-ended-question assignment/response behaviour
# is confounded with LPA profile membership -- a prerequisite before any
# open-ended content analysis (see src/preprocess/open_ended.py). Two
# checks:
#  1. Randomisation balance: is profile_class evenly distributed across the
#     three context arms (general/tax/subsidy)? This is a manipulation
#     check on the random assignment itself, not a substantive finding --
#     it should come out null.
#  2. Differential response: does actually leaving a substantive answer
#     (vs. skipping/junk) depend on profile_class, pooled and controlling
#     for context? If e.g. Utilitarians are systematically less likely to
#     write anything, that's a caveat that has to travel with any content
#     finding from the open-ended text, not be discovered after the fact.
#
# Run through Snakemake (see rules/analyse.smk), against the fixed-G=3
# profile_class labels (the ones used for cross-wave comparison, not each
# wave's own BIC-optimal G) so results read consistently with the other
# wave3_ch/wave3_cn figures.

library(dplyr)
library(readr)

wave_id <- snakemake@wildcards[["wave_id"]]

open_ended <- read_csv(snakemake@input[["open_ended"]], show_col_types = FALSE)
classes <- read_csv(snakemake@input[["classes"]], show_col_types = FALSE) |>
  select(respondent_id, profile_class)

data <- open_ended |>
  inner_join(classes, by = "respondent_id")

n_unmatched <- nrow(open_ended) - nrow(data)
if (n_unmatched > 0) {
  message(sprintf(
    "[selection_bias/%s] %d of %d open-ended rows had no matching LPA profile_class (dropped from these checks).",
    wave_id, n_unmatched, nrow(open_ended)
  ))
}

# --- check 1: randomisation balance (profile_class x assigned context) ---
balance_table <- table(data$profile_class, data$context)
balance_test <- chisq.test(balance_table)
message(sprintf(
  "[selection_bias/%s] balance check (profile_class x context): chi-sq = %.2f, df = %d, p = %.3f",
  wave_id, balance_test$statistic, balance_test$parameter, balance_test$p.value
))

# --- check 2: differential response (is_substantive x profile_class) ---
response_table <- table(data$profile_class, data$is_substantive)
response_test <- chisq.test(response_table)
message(sprintf(
  "[selection_bias/%s] response-rate check, pooled (is_substantive x profile_class): chi-sq = %.2f, df = %d, p = %.3f",
  wave_id, response_test$statistic, response_test$parameter, response_test$p.value
))

# A pooled test can mask an effect that only shows up once context is
# accounted for (some contexts may just be harder to answer than others),
# so also compare a model with profile_class against one without, via a
# likelihood-ratio test.
model_full <- glm(is_substantive ~ profile_class + context, data = data, family = binomial)
model_null <- glm(is_substantive ~ context, data = data, family = binomial)
lr_test <- anova(model_null, model_full, test = "Chisq")
lr_stat <- lr_test[["Deviance"]][2]
lr_df <- lr_test[["Df"]][2]
lr_p <- lr_test[["Pr(>Chi)"]][2]
message(sprintf(
  "[selection_bias/%s] response-rate check, controlling for context: LR chi-sq = %.2f, df = %d, p = %.3f",
  wave_id, lr_stat, lr_df, lr_p
))

test_results <- data.frame(
  wave_id = wave_id,
  check = c(
    "balance_profile_by_context",
    "response_rate_by_profile_pooled",
    "response_rate_by_profile_controlling_context"
  ),
  statistic = c(balance_test$statistic, response_test$statistic, lr_stat),
  df = c(balance_test$parameter, response_test$parameter, lr_df),
  p_value = c(balance_test$p.value, response_test$p.value, lr_p)
)
write_csv(test_results, snakemake@output[["tests"]])

rates <- data |>
  group_by(profile_class, context) |>
  summarise(
    n = n(),
    n_substantive = sum(is_substantive),
    substantive_rate = mean(is_substantive),
    .groups = "drop"
  )
write_csv(rates, snakemake@output[["rates"]])
