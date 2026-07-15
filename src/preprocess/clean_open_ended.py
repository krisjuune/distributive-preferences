"""Melt and clean wave 3's open-ended justice-reasoning responses into a
long-format, flagged table -- one row per respondent who was randomly
shown a context (general/tax/subsidy), ready to join against LPA profile
assignments on respondent_id.

Run through Snakemake (see rules/preprocess.smk). Transform logic lives in
open_ended.py so it's unit-testable without a Snakemake context.
"""

import pandas as pd
from open_ended import clean_open_ended

data = pd.read_parquet(snakemake.input["data"])
country = snakemake.params["country"]

clean = clean_open_ended(data, country)
clean.to_csv(snakemake.output["clean"], index=False)
