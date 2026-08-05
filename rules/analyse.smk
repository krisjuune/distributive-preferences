rule lpa:
    message: "Fit latent profile models for {wildcards.wave_id}."
    input:
        data = "build/data/processed/{wave_id}.parquet"
    params:
        n_profiles_max = config["lpa"]["n_profiles_max"],
        random_seed = config["lpa"]["random_seed"]
    output:
        fit_stats = "build/results/lpa/{wave_id}_fit_stats.csv",
        classes = "build/results/lpa/{wave_id}_classes.csv"
    conda: "../environment.yml"
    script:
        "../src/analyse/lpa.R"


rule lpa_blrt:
    message: "Bootstrapped LRT for profile count ({wildcards.wave_id})."
    input:
        data = "build/data/processed/{wave_id}.parquet"
    params:
        nboot = config["lpa"]["blrt"]["nboot"],
        max_g = config["lpa"]["blrt"]["max_g"],
        random_seed = config["lpa"]["random_seed"]
    output:
        blrt = "build/results/lpa/{wave_id}_blrt.csv"
    conda: "../environment.yml"
    script:
        "../src/analyse/lpa_blrt.R"


rule lpa_fixed_g:
    message: "Fit a fixed-G latent profile model for {wildcards.wave_id} (cross-wave comparison)."
    input:
        data = "build/data/processed/{wave_id}.parquet"
    params:
        g = config["lpa"]["spaghetti_g"],
        random_seed = config["lpa"]["random_seed"]
    output:
        classes = "build/results/lpa/{wave_id}_spaghetti_classes.csv"
    conda: "../environment.yml"
    script:
        "../src/analyse/lpa_fixed_g.R"


rule cfa:
    message: "Fit confirmatory factor analysis models for {wildcards.cfa_group}."
    input:
        data = lambda w: expand(
            "build/data/processed/{wave_id}.parquet",
            wave_id=config["cfa"]["groups"][w.cfa_group]
        )
    params:
        random_seed = config["lpa"]["random_seed"]
    output:
        fit_measures = "build/results/cfa/{cfa_group}_fit_measures.csv",
        loadings = "build/results/cfa/{cfa_group}_loadings.csv"
    conda: "../environment.yml"
    script:
        "../src/analyse/cfa.R"


rule check_open_ended_selection_bias:
    message: "Check open-ended assignment/response balance against LPA profile for {wildcards.wave_id}."
    input:
        open_ended = "build/results/open_ended/{wave_id}_clean.csv",
        classes = "build/results/lpa/{wave_id}_spaghetti_classes.csv"
    output:
        tests = "build/results/open_ended/{wave_id}_selection_bias_tests.csv",
        rates = "build/results/open_ended/{wave_id}_selection_bias_rates.csv"
    conda: "../environment.yml"
    script:
        "../src/analyse/open_ended_selection_bias.R"


def _regression_units(config):
    """Map every requestable {wave_id} value -- individual waves and
    regression.groups' pooled unit names alike -- to the list of actual
    wave_ids it covers."""
    units = {wave_id: [wave_id] for wave_id in config["waves"]}
    units.update(config["regression"]["groups"])
    return units


def _regression_wave_ids(wildcards):
    return _regression_units(config)[wildcards.wave_id]


rule regression:
    message: "Fit regression model for {wildcards.wave_id}."
    input:
        data = lambda w: expand(
            "build/data/processed/{wid}.parquet", wid=_regression_wave_ids(w)
        ),
        # Fixed-G=3 classes, not each wave's own BIC-optimal classes --
        # profile_class needs to mean the same thing across waves/countries
        # for the coefficients to be comparable, consistent with every
        # other cross-wave figure in this pipeline.
        classes = lambda w: expand(
            "build/results/lpa/{wid}_spaghetti_classes.csv", wid=_regression_wave_ids(w)
        )
    params:
        random_seed = config["regression"]["random_seed"],
        decay = config["regression"]["decay"],
        wave_ids = _regression_wave_ids,
        topics = {wave_id: meta["topic"] for wave_id, meta in config["waves"].items()},
        countries = {wave_id: meta["country"] for wave_id, meta in config["waves"].items()}
    output:
        model = "build/results/regression/{wave_id}_model.rds",
        model_data = "build/results/regression/{wave_id}_model_data.rds",
        coefficients = "build/results/regression/{wave_id}_coefficients.csv"
    conda: "../environment.yml"
    script:
        "../src/analyse/regression.R"


def _regression_demographics(wildcards):
    """Look up the fixed demographic control set for a {wave_id}'s topic
    (regression.demographics, keyed by topic since a pooled group's
    wave_ids all share one topic by construction -- see regression.groups)."""
    wave_ids = _regression_wave_ids(wildcards)
    topics = {wid: meta["topic"] for wid, meta in config["waves"].items()}
    topic = topics[wave_ids[0]]
    return config["regression"]["demographics"][topic]


rule regression_focal:
    message: "Fit focal-predictor model for {wildcards.wave_id} / {wildcards.model_key}."
    input:
        data = lambda w: expand(
            "build/data/processed/{wid}.parquet", wid=_regression_wave_ids(w)
        ),
        classes = lambda w: expand(
            "build/results/lpa/{wid}_spaghetti_classes.csv", wid=_regression_wave_ids(w)
        )
    params:
        random_seed = config["regression"]["random_seed"],
        decay = config["regression"]["decay"],
        wave_ids = _regression_wave_ids,
        topics = {wave_id: meta["topic"] for wave_id, meta in config["waves"].items()},
        countries = {wave_id: meta["country"] for wave_id, meta in config["waves"].items()},
        demographics = _regression_demographics,
        # Usually one predictor (model_key == that predictor's own name),
        # but >1 when model_key names a `group` of columns meant to be
        # fit together -- see _model_key_predictors() in the Snakefile.
        focal_predictors = lambda w: _model_key_predictors(w.model_key)
    output:
        model = "build/results/regression/focal/{wave_id}__{model_key}_model.rds",
        model_data = "build/results/regression/focal/{wave_id}__{model_key}_model_data.rds"
    conda: "../environment.yml"
    script:
        "../src/analyse/regression_focal.R"
