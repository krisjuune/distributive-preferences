rule clean_wave:
    message: "Clean and tidy raw survey export for {wildcards.wave_id}."
    input:
        raw = lambda w: "raw-data/" + config["waves"][w.wave_id]["file"]
    params:
        wave_meta = lambda w: config["waves"][w.wave_id],
        pii_columns = config["pii_columns"],
        metadata_columns = config["metadata_columns"]
    output:
        data = "build/data/processed/{wave_id}.parquet"
    conda: "../environment.yml"
    script:
        "../src/preprocess/clean_survey.py"


rule clean_open_ended:
    message: "Clean open-ended justice-reasoning responses for {wildcards.wave_id}."
    input:
        data = "build/data/processed/{wave_id}.parquet"
    params:
        country = lambda w: config["waves"][w.wave_id]["country"]
    output:
        clean = "build/results/open_ended/{wave_id}_clean.csv"
    conda: "../environment.yml"
    script:
        "../src/preprocess/clean_open_ended.py"


rule build_validation_sample:
    message: "Build the stratified open-ended classification validation sample."
    input:
        open_ended = expand(
            "build/results/open_ended/{wave_id}_clean.csv", wave_id=config["open_ended"]["waves"]
        ),
        classes = expand(
            "build/results/lpa/{wave_id}_spaghetti_classes.csv", wave_id=config["open_ended"]["waves"]
        )
    params:
        waves = config["open_ended"]["waves"],
        n_per_cell = config["open_ended"]["validation"]["n_per_cell"],
        random_seed = config["open_ended"]["validation"]["random_seed"]
    output:
        full = "build/results/open_ended/validation_sample_full.csv",
        blind = "build/results/open_ended/validation_sample_blind.csv"
    conda: "../environment.yml"
    script:
        "../src/preprocess/build_open_ended_validation_sample.py"


rule translate_open_ended_validation_sample:
    message: "Add an English translation column to the open-ended validation sample."
    input:
        full = "build/results/open_ended/validation_sample_full.csv",
        blind = "build/results/open_ended/validation_sample_blind.csv"
    params:
        model = config["open_ended"]["validation"]["translation_model"]
    output:
        # Not in `rule all`: calls the Anthropic API (costs money, needs
        # ANTHROPIC_API_KEY set) -- invoke explicitly:
        #   snakemake --cores 1 build/results/open_ended/validation_sample_blind_translated.csv
        cache = "build/results/open_ended/validation_sample_translations_cache.csv",
        blind_translated = "build/results/open_ended/validation_sample_blind_translated.csv"
    conda: "../environment.yml"
    script:
        "../src/preprocess/translate_open_ended_validation_sample.py"
