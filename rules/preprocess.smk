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
