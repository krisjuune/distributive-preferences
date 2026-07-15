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


rule regression:
    message: "Fit regression model for {wildcards.wave_id}."
    input:
        data = "build/data/processed/{wave_id}.parquet",
        classes = "build/results/lpa/{wave_id}_classes.csv"
    params:
        random_seed = config["regression"]["random_seed"]
    output:
        model = "build/results/regression/{wave_id}_model.rds",
        coefficients = "build/results/regression/{wave_id}_coefficients.csv"
    conda: "../environment.yml"
    script:
        "../src/analyse/regression.R"
