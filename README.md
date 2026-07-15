# Distributive preferences

Regression and latent profile analysis of survey waves on distributive
justice preferences (heating/PV choices, flying willingness-to-pay,
CCS conjoint, EU-wide distributive justice attitudes).

This repository contains the entire analysis: no intermediate results are
committed, everything under `build/` is regenerated from `raw-data/` and code.

## Getting ready

You need [conda](https://conda.org) to run the analysis:

    conda env create -f environment.yml
    conda activate distributive-preferences

Place raw survey exports in `raw-data/` (gitignored) and register them in
`config/default.yaml` under `waves:`.

## Run the analysis

    snakemake --cores 1

This preprocesses every registered wave, fits latent profile models,
regresses profile membership on predictors, and renders figures. Run
`snakemake --list` to see individual rules, or target one wave, e.g.:

    snakemake build/figures/wave1_ch_lpa_fit.png --cores 1

To see the rule DAG without running anything: `snakemake --dry-run`.

## Run the tests

    pytest tests/

## Repo structure

* `raw-data`: untouched survey exports (gitignored, never committed — several
  waves contain respondent PII stripped out during preprocessing)
* `config`: wave registry and analysis parameters (`default.yaml`)
* `rules`: Snakemake rule definitions (`preprocess`, `analyse`, `vis`)
* `src/preprocess`: Python — reads raw exports, drops PII/bookkeeping
  columns, tags rows with wave/country/topic
* `src/analyse`: R — latent profile analysis (`mclust`) and regression
  (`nnet::multinom`, or `ordinal::clmm` for ordinal outcomes)
* `src/vis`: R/ggplot2 — shared theme and figure scripts
* `tests`: pytest tests for the preprocessing logic
* `build`: all generated output (does not exist initially, gitignored)

## Status

The pipeline plumbing (preprocessing, LPA, regression, plotting) runs
end to end, but the indicator columns for the latent profile models and
the predictor sets/formulas for the regressions are still placeholders —
see the `TODO` comments in `src/analyse/lpa.R` and
`src/analyse/regression.R`. Fill these in once the codebook for each
wave/topic is finalised.

## License

TODO: pick a license (e.g. MIT) once the analysis is ready to share.
