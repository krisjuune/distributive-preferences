"""Build the stratified validation sample for the open-ended LLM
classification step: joins each wave's cleaned open-ended responses to its
LPA profile_class, draws a profile-oversampled stratified sample, and
splits it into a full (internal) file and a blind (no profile_class, no
LPA info at all) file for independent human coding.

The blind file is the one to hand to coders -- duplicate it into two
separate copies (one per coder) before coding, so neither sees the
other's labels while coding. Label columns are left blank for manual
multi-label annotation (mark each principle that applies; dont_know and
uninterpretable are mutually exclusive with everything else, including
each other).

Run through Snakemake (see rules/preprocess.smk). Transform logic lives in
open_ended_validation_sample.py so it's unit-testable without a Snakemake
context.
"""

import pandas as pd
from open_ended_validation_sample import assign_item_ids, build_validation_sample, stratified_sample

LABEL_COLUMNS = [
    "utilitarian",
    "egalitarian",
    "sufficientarian",
    "limitarian",
    "other_justice",
    "other_justice_note",  # free text, filled in only alongside other_justice --
    # a couple of words on the actual theme (e.g. "polluter pays", "global
    # equity", "meta/relativist"). Not itself a label to score agreement on;
    # it's there so a later pass can group other_justice into real subthemes
    # (polluter-pays recurs often enough already to be a likely candidate)
    # without having to re-read every flagged response from scratch.
    "dont_know",  # explicit/implicit "I don't know" in non-standard wording --
    # interpretable, unlike uninterpretable, but not evidence for/against any
    # principle. Distinct from the exact-phrase non_answer_phrase filter in
    # open_ended.py, which only catches a fixed list of standard phrasings
    # at the preprocessing stage; this label is for everything else that
    # amounts to the same thing but wasn't caught there.
    "uninterpretable",
]

waves = snakemake.params["waves"]
open_ended_paths = snakemake.input["open_ended"]
classes_paths = snakemake.input["classes"]

frames = []
for wave_id, oe_path, cl_path in zip(waves, open_ended_paths, classes_paths):
    open_ended = pd.read_csv(oe_path)
    classes = pd.read_csv(cl_path)
    country = open_ended["country"].iloc[0]
    frames.append(build_validation_sample(open_ended, classes, wave_id, country))
data = pd.concat(frames, ignore_index=True)

sample = stratified_sample(
    data, n_per_cell=snakemake.params["n_per_cell"], random_seed=snakemake.params["random_seed"]
)
sample = assign_item_ids(sample, random_seed=snakemake.params["random_seed"])

full_columns = [
    "item_id",
    "wave_id",
    "country",
    "language",
    "context",
    "respondent_id",
    "profile_class",
    "response_clean",
]
sample[full_columns].to_csv(snakemake.output["full"], index=False)

blind = sample[["item_id", "country", "language", "context", "response_clean"]].copy()
for col in LABEL_COLUMNS:
    blind[col] = ""
blind.to_csv(snakemake.output["blind"], index=False)
