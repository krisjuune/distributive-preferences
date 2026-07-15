"""Clean a single raw survey export into a tidy, PII-free parquet file.

Run through Snakemake (see rules/preprocess.smk) which injects the
`snakemake` object with `.input`, `.output`, and `.params`. The actual
transform logic lives in harmonise.py so it can be unit tested without
a Snakemake context.

This only handles what's common to every wave: reading past the
Qualtrics/SoSci metadata rows, dropping PII/bookkeeping columns, and
tagging rows with wave/country/topic. Likert-label recoding and any
other topic-specific harmonisation belongs in per-topic functions
(or new modules under src/preprocess/) once the codebook for that
wave/topic is finalised -- keep it there rather than inline here.
"""

from harmonise import clean_dataframe, read_raw_survey

wave_meta = snakemake.params["wave_meta"]

df = read_raw_survey(snakemake.input["raw"], wave_meta["platform"])
df = clean_dataframe(
    df,
    wave_meta=wave_meta,
    pii_columns=snakemake.params["pii_columns"],
    metadata_columns=snakemake.params["metadata_columns"],
)

# TODO: topic-specific recoding (e.g. Likert-label -> numeric, reverse-scoring,
# construct scale scoring) goes here or in a dedicated function once the
# codebook for `wave_meta["topic"]` is finalised.

df.to_parquet(snakemake.output["data"], index=False)
