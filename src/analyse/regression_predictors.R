# Shared helpers for building the multinomial-logistic-regression predictor
# set (see regression.R): response-scale recoding vectors for the
# Qualtrics text-label items (waves 1-3 export Likert *labels*, not codes;
# wave 4's SoSci export is already numeric) and a composite-index builder
# for the multi-item attitude/value batteries catalogued in
# manuscript/predictors_table.tex.
#
# Sourced by regression.R, not run directly.

# --- response-scale recoding vectors -----------------------------------
# Named by (label -> numeric code); recode_scale() below looks up each
# response by name, so anything not listed (e.g. "prefer_not_to_say",
# "Prefer not to say") falls through to NA automatically -- no special-
# casing needed for refusals.

# wave 2's eu_clim_conc and wave 3's climate_worried share this exact
# 5-point label set.
SCALE_WORRY_5 <- c(
  not_at_all_worried = 1, not_very_worried = 2, somewhat_worried = 3,
  very_worried = 4, extremely_worried = 5,
  "Not at all worried" = 1, "Not very worried" = 2, "Somewhat worried" = 3,
  "Very worried" = 4, "Extremely worried" = 5
)

# wave 2's clim_concern_wtc/wtp.
SCALE_IMPORTANCE_6 <- c(
  very_unimportant = 1, unimportant = 2, somewhat_unimportant = 3,
  somewhat_important = 4, important = 5, very_important = 6
)

# wave 3's galtan_*, lreco_*, socio_ecological_* (7-point, explicit "Not
# sure" midpoint -- a substantive neutral response, not a refusal, so it's
# coded as the scale midpoint rather than NA).
SCALE_AGREE_7 <- c(
  "Completely disagree" = 1, "Disagree" = 2, "Somewhat disagree" = 3,
  "Not sure" = 4, "Somewhat agree" = 5, "Agree" = 6, "Completely agree" = 7
)

# wave 3's community_interest/global_interest (6-point, no neutral option
# -- a different scale from SCALE_AGREE_7, do not conflate the two).
SCALE_AGREE_6 <- c(
  "Strongly disagree" = 1, "Disagree" = 2, "Somewhat disagree" = 3,
  "Somewhat agree" = 4, "Agree" = 5, "Strongly agree" = 6
)

# wave 3's climate_heard.
SCALE_BELIEF_4 <- c(
  "Definitely not changing" = 1, "Probably not changing" = 2,
  "Probably changing" = 3, "Definitely changing" = 4
)

# wave 3's net_zero_question -- perceived sufficiency of the Swiss net-zero
# target, used as the "climate action" component of the socio-cultural
# values index.
SCALE_SUFFICIENCY_7 <- c(
  "Absolutely insufficient" = 1, "Insufficient" = 2, "Slightly insufficient" = 3,
  "Not sure" = 4, "Slightly sufficient" = 5, "Sufficient" = 6, "Absolutely sufficient" = 7
)

recode_scale <- function(x, scale) {
  unname(scale[x])
}

# Refusal-type responses ("Prefer not to say" etc.) are recoded to NA
# rather than kept as their own factor level -- a "declined to answer"
# coefficient is rarely meaningful and just adds noise.
na_if_refusal <- function(x) {
  refusals <- c("Prefer not to say", "prefer_not_to_say", "Other (please specify)")
  ifelse(x %in% refusals, NA, x)
}

# --- composite index builder --------------------------------------------
# Averages a set of already-numeric-recoded items into one z-scored index.
# Polarity is aligned empirically (whichever items correlate negatively
# with the first/reference item get reverse-scored) rather than assumed
# from question wording -- an a priori reverse-coding guess on
# socio_ecological_2 turned out backwards when checked against the real
# data (see manuscript/predictors_table.tex), so this project no longer
# assumes item direction without checking it.
cronbach_alpha <- function(mat) {
  mat <- na.omit(mat)
  k <- ncol(mat)
  item_var_sum <- sum(apply(mat, 2, var))
  total_var <- var(rowSums(mat))
  k / (k - 1) * (1 - item_var_sum / total_var)
}

build_composite_index <- function(item_matrix, label) {
  mat <- as.data.frame(lapply(item_matrix, as.numeric))
  colnames(mat) <- colnames(item_matrix)

  reference <- mat[[1]]
  flipped <- character(0)
  for (col in colnames(mat)[-1]) {
    r <- suppressWarnings(stats::cor(reference, mat[[col]], use = "pairwise.complete.obs"))
    if (!is.na(r) && r < 0) {
      item_range <- range(mat[[col]], na.rm = TRUE)
      mat[[col]] <- (item_range[1] + item_range[2]) - mat[[col]]
      flipped <- c(flipped, col)
    }
  }
  if (length(flipped) > 0) {
    message(sprintf(
      "[regression_predictors] %s: reversed %s to align polarity with %s",
      label, paste(flipped, collapse = ", "), colnames(mat)[1]
    ))
  }

  alpha <- cronbach_alpha(mat)
  message(sprintf(
    "[regression_predictors] %s: Cronbach's alpha = %.2f (%d items, n = %d complete cases)",
    label, alpha, ncol(mat), sum(stats::complete.cases(mat))
  ))

  z <- as.data.frame(lapply(mat, function(x) as.numeric(scale(x))))
  rowMeans(z, na.rm = FALSE)
}

# --- per-wave/topic predictor set ---------------------------------------
# Builds one wave_id's predictor columns, split into two parts:
#   simple          -- data.frame(respondent_id, <directly usable columns>)
#   composite_items -- named list of data.frame(respondent_id, <raw
#                       recoded sub-items>), one entry per composite index,
#                       deliberately NOT yet averaged into an index.
#
# Composite items are kept raw (unaveraged) here so a pooled multi-wave_id
# regression (see regression.R, used for e.g. wave4's 9-country "Europe"
# pool) can combine raw sub-items across countries first and build each
# composite index ONCE on the pooled distribution -- so "2 SD above the
# mean" means 2 SD above the pooled mean, not country-relative. A
# single-wave_id regression just calls build_composite_index() on one
# country's items, which is behaviourally identical to building the index
# inline.
build_wave_predictors <- function(data, topic, wave_id) {
  respondent_id <- data$respondent_id
  simple <- data.frame(respondent_id = respondent_id)
  composite_items <- list()

  if (topic == "heating-pv-choice") { # wave 1 (CH)
    simple$gender <- factor(data$gender)
    simple$age <- factor(data$age) # age band, e.g. "25-34" -- not continuous in any wave
    simple$region <- factor(data$region)
    simple$education <- factor(na_if_refusal(data$education))
    simple$income <- factor(na_if_refusal(data$income))
    simple$party <- factor(na_if_refusal(data$party))

  } else if (topic == "flying-wtc-wtp") { # wave 2 (CH/CN/US)
    simple$age <- factor(data$age) # age band, e.g. "25-34" -- not continuous in any wave
    simple$gender <- factor(data$gender)
    simple$education <- factor(na_if_refusal(data$education))
    # personal_income used over the near-duplicate income_group column --
    # see manuscript/predictors_table.tex.
    simple$income <- factor(na_if_refusal(data$personal_income))
    # CN's questionnaire omits a left-right self-placement item entirely
    # (same omission as wave 3's political_position_1) -- CH/US-only predictor.
    if ("politics" %in% colnames(data)) simple$left_right <- factor(na_if_refusal(data$politics))
    composite_items$climate_concern_index <- data.frame(
      respondent_id = respondent_id,
      worry = recode_scale(data$eu_clim_conc, SCALE_WORRY_5),
      wtc_importance = recode_scale(data$clim_concern_wtc, SCALE_IMPORTANCE_6),
      wtp_importance = recode_scale(data$clim_concern_wtp, SCALE_IMPORTANCE_6)
    )

  } else if (topic == "ccs-conjoint") { # wave 3 (CH/CN)
    simple$age <- factor(data$age) # age band, e.g. "25-34" -- not continuous in any wave
    simple$gender <- factor(data$gender)
    if ("language_region" %in% colnames(data)) simple$language_region <- factor(data$language_region)
    # CH uses "education_degree", CN uses "education" -- no shared column
    # name, unlike everything else in this wave.
    education_column <- if ("education_degree" %in% colnames(data)) "education_degree" else "education"
    simple$education <- factor(na_if_refusal(data[[education_column]]))
    simple$income <- factor(na_if_refusal(data$income))
    # CN's questionnaire omits a left-right self-placement item entirely
    # (plausibly a political-sensitivity omission) -- CH-only predictor.
    if ("political_position_1" %in% colnames(data)) simple$left_right <- as.numeric(data$political_position_1)
    simple$climate_belief <- recode_scale(data$climate_heard, SCALE_BELIEF_4)
    composite_items$ccs_index <- data.frame(
      respondent_id = respondent_id,
      community_interest = recode_scale(data$community_interest, SCALE_AGREE_6),
      global_interest = recode_scale(data$global_interest, SCALE_AGREE_6)
    )
    composite_items$socio_econ_index <- data.frame(
      respondent_id = respondent_id,
      lreco_1 = recode_scale(data$lreco_1, SCALE_AGREE_7),
      lreco_2 = recode_scale(data$lreco_2, SCALE_AGREE_7),
      lreco_3 = recode_scale(data$lreco_3, SCALE_AGREE_7)
    )
    composite_items$socio_cult_index <- data.frame(
      respondent_id = respondent_id,
      galtan_1 = recode_scale(data$galtan_1, SCALE_AGREE_7),
      galtan_2 = recode_scale(data$galtan_2, SCALE_AGREE_7),
      net_zero = recode_scale(data$net_zero_question, SCALE_SUFFICIENCY_7)
    )
    composite_items$socio_ecol_index <- data.frame(
      respondent_id = respondent_id,
      socio_ecological_1 = recode_scale(data$socio_ecological_1, SCALE_AGREE_7),
      socio_ecological_2 = recode_scale(data$socio_ecological_2, SCALE_AGREE_7),
      climate_worried = recode_scale(data$climate_worried, SCALE_WORRY_5)
    )

  } else if (topic == "policy-instruments") { # wave 4 (9 EU countries)
    # age/gender not yet available in this dataset -- to be supplied by
    # the panel provider; deliberately omitted rather than substituted
    # with anything, see manuscript/predictors_table.tex.
    simple$education_years <- as.numeric(data$SD23_01)
    simple$income <- as.numeric(data$Income)
    simple$type_of_area <- factor(data$type_of_area)
    simple$party <- factor(data$Party)
    # party_preference (up to 13 country-specific levels) deliberately
    # excluded: it alone accounted for 32-43% of every wave4 country
    # model's parameters, the dominant driver of the quasi-complete
    # separation (huge/infinite odds ratios, NaN standard errors) found
    # when first fitting these models against such a small Utilitarian
    # class (as few as 8-22 respondents per country). `party` (binary)
    # captures similar information far more parsimoniously.
    simple$household_size <- as.numeric(data$Household)
    simple$left_right <- as.numeric(data$left_right)
    composite_items$cultural_worldview_ic_index <- data.frame(
      respondent_id = respondent_id,
      interfere = data$ic_government_interfere, hurt = data$ic_government_hurt,
      protect = data$ic_government_protect, stop_telling = data$ic_government_stop_telling,
      society_goals = data$ic_government_society_goals, limits_choices = data$ic_government_limits_choices
    )
    composite_items$cultural_worldview_he_index <- data.frame(
      respondent_id = respondent_id,
      far_equal_goals = data$he_far_equal_goals, distrib_wealth = data$he_distrib_wealth,
      reduce_inequal = data$he_reduce_inequal, discrim_problem = data$he_discrim_problem,
      groups_special = data$he_groups_special, society_soft = data$he_society_soft
    )
    # Both raw items are labelled "Energy Security:" in the questionnaire,
    # but only these two are actually about energy security (fossil-fuel
    # dependency, grid reliability) -- climate_risks/extreme_weather below
    # are about climate risk, not energy security, despite sharing the
    # same question-block header.
    composite_items$energy_security_index <- data.frame(
      respondent_id = respondent_id,
      energy_depend = data$energy_depend, energy_reliable = data$energy_reliable
    )
    # wave 4's analog to wave 3's socio_ecol_index -- wave 4 has no
    # equivalent to wave 3's more philosophical items (willingness to
    # sacrifice income for the environment, views on humans dominating
    # nature), so this is built from the closest available cluster:
    # personal climate responsibility, general climate risk, and the two
    # "Energy Security:"-labelled items that are actually about climate
    # risk by content (see note above).
    composite_items$socio_ecol_index <- data.frame(
      respondent_id = respondent_id,
      climate_responsibility = as.numeric(data$cc_personal_responsibilty),
      climate_risk = as.numeric(data$climate_change),
      climate_risks = data$climate_risks, extreme_weather = data$extreme_weather
    )
    composite_items$socio_econ_index <- data.frame(
      respondent_id = respondent_id,
      left_right = data$left_right, unemp_lazy = data$unemp_lazy, benefits_strain = data$benefits_strain
    )
    composite_items$socio_cult_index <- data.frame(
      respondent_id = respondent_id,
      immig_econ = data$immig_econ, child_obedience = data$child_obedience, immig_cult = data$immig_cult
    )

  } else {
    stop("Unknown topic '", topic, "' -- no predictor set defined in build_wave_predictors().")
  }

  list(simple = simple, composite_items = composite_items)
}
