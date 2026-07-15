"""Add an English translation column to the open-ended validation sample,
for coders who aren't fluent in the source language (French/Chinese --
German and English responses are left untranslated, per the coders'
actual language coverage). Calls the Anthropic API once per response
needing translation and caches results to disk keyed by item_id, so a
rerun (after a crash, a rate limit, or adding more items to the sample
later) only translates rows that aren't cached yet.

Kept out of `rule all` -- this calls an external, paid API, so it's an
explicit target rather than part of the default pipeline run:

    snakemake --cores 1 build/results/open_ended/validation_sample_blind_translated.csv

Requires ANTHROPIC_API_KEY to be set in the environment.

Run through Snakemake (see rules/preprocess.smk). Transform logic lives in
open_ended_translation.py so it's unit-testable without a live API call.
"""

import os

import anthropic
import pandas as pd
from open_ended_translation import needs_translation, translate_response

if "ANTHROPIC_API_KEY" not in os.environ:
    raise RuntimeError(
        "ANTHROPIC_API_KEY is not set -- export it before running this rule "
        "(see src/preprocess/open_ended_translation.py)."
    )

model = snakemake.params["model"]
full = pd.read_csv(snakemake.input["full"])
blind = pd.read_csv(snakemake.input["blind"])

cache_path = snakemake.output["cache"]
if os.path.exists(cache_path):
    cache = pd.read_csv(cache_path).set_index("item_id")["response_translated_en"].to_dict()
else:
    cache = {}

to_translate = full[full["language"].map(needs_translation)]
client = anthropic.Anthropic()

for item_id, text in zip(to_translate["item_id"], to_translate["response_clean"]):
    if item_id in cache:
        continue
    try:
        cache[item_id] = translate_response(client, model, text)
    except Exception as e:  # noqa: BLE001 -- one failed call shouldn't kill the other 118
        print(f"[translate/{item_id}] FAILED: {e}")
        continue
    # Flush after every item (cheap at this volume) so a crash or rate
    # limit partway through doesn't lose already-translated rows.
    pd.DataFrame(
        {"item_id": list(cache.keys()), "response_translated_en": list(cache.values())}
    ).to_csv(cache_path, index=False)

n_missing = len(set(to_translate["item_id"]) - set(cache.keys()))
if n_missing > 0:
    print(f"[translate] {n_missing} of {len(to_translate)} responses still untranslated -- rerun to retry.")

blind["response_translated_en"] = blind["item_id"].map(cache).fillna("")
blind.to_csv(snakemake.output["blind_translated"], index=False)
