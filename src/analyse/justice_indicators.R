# Shared indicator-column selection for LPA, sourced by lpa.R and
# lpa_fixed_g.R so the two stay consistent.

library(dplyr)

select_justice_indicators <- function(data) {
  # The real LPA indicators are the 4 justice-principle scores
  # (utilitarian/egalitarian/sufficientarian/limitarian), each summed across
  # the general/tax/subsidy(/ban) policy domains -- not the raw 12-16 items --
  # computed in src/preprocess/harmonise.py::compute_justice_principle_scores
  # as `justice_principle_<principle>`, for every wave (1-4).
  #
  # Fall back to the raw justice_<subscale>_<item> columns, then to a generic
  # numeric/completeness/cardinality heuristic, only when the principle
  # scores aren't available, so the pipeline still runs end to end rather
  # than silently doing nothing.
  bookkeeping_columns <- c("wave", "country", "topic", "respondent_id")

  indicator_columns <- data |>
    select(starts_with("justice_principle_")) |>
    colnames()

  if (length(indicator_columns) == 0) {
    indicator_columns <- data |>
      select(starts_with("justice_")) |>
      select(where(is.numeric)) |>
      colnames()
  }

  if (length(indicator_columns) == 0) {
    max_missing_share <- 0.2
    min_unique_values <- 2
    max_unique_values <- 20
    indicator_columns <- data |>
      select(-any_of(bookkeeping_columns)) |>
      select(where(is.numeric)) |>
      select(where(~ mean(is.na(.)) <= max_missing_share)) |>
      select(where(~ between(length(unique(na.omit(.))), min_unique_values, max_unique_values))) |>
      colnames()
  }

  if (length(indicator_columns) == 0) {
    stop(
      "No usable LPA indicator columns found for this wave: no justice_* ",
      "battery and the generic fallback heuristic also found nothing. See ",
      "src/preprocess/harmonise.py::harmonise_justice_columns."
    )
  }

  indicator_columns
}
