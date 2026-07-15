"""Pure dataframe-transform logic for clean_survey.py, kept separate so it's
testable without a Snakemake context (see tests/test_preprocess.py)."""

import re

import pandas as pd


def read_raw_survey(path: str, platform: str) -> pd.DataFrame:
    if platform == "qualtrics":
        # Row 2: question text, row 3: ImportId JSON metadata.
        return pd.read_csv(path, skiprows=[1, 2], encoding="utf-8")
    elif platform == "sosci":
        # Row 2: question text. UTF-8 with BOM.
        return pd.read_csv(path, skiprows=[1], encoding="utf-8-sig")
    else:
        raise ValueError(f"Unknown platform '{platform}'.")


def filter_to_country(df: pd.DataFrame, wave_meta: dict) -> pd.DataFrame:
    """Select one country's rows out of a raw file that bundles several
    (e.g. wave 4's single SoSci export covering 9 countries via LANGUAGE).
    A no-op for single-country raw files, i.e. when wave_meta has no
    `country_column`/`country_value`."""
    country_column = wave_meta.get("country_column")
    country_value = wave_meta.get("country_value")
    if country_column is None:
        return df
    return df[df[country_column] == country_value]


def fix_known_typos(df: pd.DataFrame, wave_meta: dict) -> pd.DataFrame:
    """One-off label/column-name fixes for specific known data-entry quirks
    per wave, rather than a general-purpose cleaning step."""
    df = df.copy()
    topic = wave_meta["topic"]
    country = wave_meta["country"]

    if topic == "heating-pv-choice":  # wave 1
        df = df.rename(columns={"languge": "language"})

    elif topic == "flying-wtc-wtp":  # wave 2
        if "recent_flights" in df.columns:
            df = df.rename(columns={"recent_flights": "flying_recent_number"})
        if country == "US" and "personal_income" in df.columns:
            # "15k_35k" overlaps with the existing "25k_35k" bracket -- a
            # mislabelled bracket that should read "15k_25k".
            df["personal_income"] = df["personal_income"].replace("15k_35k", "15k_25k")

    return df


def filter_invalid_responses(df: pd.DataFrame, wave_meta: dict) -> pd.DataFrame:
    """Drop preview/incomplete/quota-met/screened-out/pre-launch-test rows,
    per wave -- what counts as invalid differs by survey platform and
    fielding setup, so this is deliberately wave-specific rather than a
    single generic filter."""
    topic = wave_meta["topic"]
    country = wave_meta["country"]

    if topic == "heating-pv-choice":  # wave 1
        df = df[df["DistributionChannel"] != "preview"]
        df = df[df["Finished"] == True]  # noqa: E712
        df = df.dropna(subset=["canton"])  # quota-full respondents

    elif topic == "flying-wtc-wtp":  # wave 2
        df = df[df["DistributionChannel"] != "preview"]
        df = df[df["Finished"] != False]  # noqa: E712
        screened_out_values = ["true", "true_trap1", "true_trap2", "true_trap3"]
        if country == "CH":
            screened_out_values.append("true_region")
        df = df[~df["screened_out"].isin(screened_out_values)]
        df = df[~df["Q_TerminateFlag"].isin(["QuotaMet", "Screened"])]

    elif topic == "ccs-conjoint":  # wave 3
        df = df[df["DistributionChannel"] != "preview"]
        df = df[df["Finished"] != False]  # noqa: E712
        df = df[~df["Q_TerminateFlag"].isin(["QuotaMet", "Screened"])]
        # Survey officially launched 2025-02-13 10:00 -- earlier rows are
        # internal test responses, not real fielding.
        launch_cutoff = pd.Timestamp("2025-02-13 10:00:00")
        df = df[pd.to_datetime(df["StartDate"]) >= launch_cutoff]

    elif topic == "policy-instruments":  # wave 4 (SoSci)
        # STATUS is only set for sessions that reached the end of the flow
        # (FINISHED==1); "complete" excludes quality-fail and screenout
        # cases within that. Rows with STATUS NaN never finished at all.
        df = df[df["STATUS"] == "complete"]

    return df


def fix_wave3_ch_conjoint_numbering(df: pd.DataFrame, wave_meta: dict) -> pd.DataFrame:
    """Wave 3's CH conjoint tasks are numbered 6-11 in the raw export (CN's
    equivalent tasks are numbered 1-6) -- renumber CH down by 5 so both
    countries' conjoint task columns line up."""
    if not (wave_meta["topic"] == "ccs-conjoint" and wave_meta["country"] == "CH"):
        return df

    rename = {}
    for col in df.columns:
        match = re.match(r"^(\d+)(_conjoint_.*)", col)
        if match:
            old_task_num, rest = match.groups()
            new_task_num = int(old_task_num) - 5
            if new_task_num > 0:
                rename[col] = f"{new_task_num}{rest}"
    return df.rename(columns=rename)


# The distributive-justice battery (general/tax/subsidy fairness items, plus
# wave 4's extra "ban" subscale) appears in every wave under a different raw
# naming convention and, for waves 1 and 3, as Likert text labels rather than
# numbers. Harmonising all of them to `justice_<subscale>_<item>` lets
# src/analyse/lpa.R select `starts_with("justice_")` uniformly across waves
# instead of guessing at indicator columns. Within each subscale, item 1-4
# is a justice *principle* (utilitarian/egalitarian/sufficientarian/
# limitarian), not just a sequential item number -- see
# compute_justice_principle_scores().
_LIKERT_DE = {
    "Stimme überhaupt nicht zu": 0,
    "Stimme nicht zu": 1,
    "Stimme eher nicht zu": 2,
    "Stimme eher zu": 3,
    "Stimme zu": 4,
    "Stimme voll und ganz zu": 5,
}
_LIKERT_EN = {
    "Strongly disagree": 0,
    "Disagree": 1,
    "Somewhat disagree": 2,
    "Somewhat agree": 3,
    "Agree": 4,
    "Strongly agree": 5,
}

# wave 1-3 item position -> justice principle.
_PRINCIPLE_BY_ITEM = {
    1: "utilitarian",
    2: "egalitarian",
    3: "sufficientarian",
    4: "limitarian",
}

# wave 4 item suffix -> justice principle, per subscale. Named rather than
# positional (unlike waves 1-3's _1/_2/_3/_4) since wave 4's raw item names
# describe the policy mechanism rather than a numbered sequence.
_WAVE4_PRINCIPLE_BY_SUBSCALE_ITEM = {
    "general": {
        "costmin": "utilitarian",
        "inequ": "egalitarian",
        "minim": "sufficientarian",
        "many_benefits": "limitarian",
    },
    "tax": {
        "moderate": "utilitarian",
        "basic": "egalitarian",
        "all": "sufficientarian",
        "luxury": "limitarian",
    },
    "subsidy": {
        "everyone": "utilitarian",
        "lower": "egalitarian",
        "additional": "sufficientarian",
        "high": "limitarian",
    },
    "ban": {
        "reduction": "utilitarian",
        "fleets": "limitarian",
        "alternatives": "sufficientarian",
        "all_income": "egalitarian",
    },
}


def harmonise_justice_columns(df: pd.DataFrame, wave_meta: dict) -> pd.DataFrame:
    df = df.copy()
    topic = wave_meta["topic"]

    if topic == "heating-pv-choice":  # wave 1: hyphenated names, German Likert text
        rename = {
            f"justice-{sub}_{i}": f"justice_{sub}_{i}"
            for sub in ("general", "tax", "subsidy")
            for i in range(1, 5)
        }
        present = [target for source, target in rename.items() if source in df.columns]
        df = df.rename(columns=rename)
        for col in present:
            df[col] = df[col].map(_LIKERT_DE)

    elif topic == "ccs-conjoint":  # wave 3: abbreviated names, English Likert text
        rename = {
            f"justice_{raw}_{i}": f"justice_{canon}_{i}"
            for raw, canon in (("gen", "general"), ("tax", "tax"), ("sub", "subsidy"))
            for i in range(1, 5)
        }
        present = [target for source, target in rename.items() if source in df.columns]
        df = df.rename(columns=rename)
        for col in present:
            df[col] = df[col].map(_LIKERT_EN)

    elif topic == "policy-instruments":  # wave 4: differently-named, already numeric
        prefix_to_subscale = {
            "Trans_fair_": "general",
            "Tax_fair_": "tax",
            "Subsidy_fair_": "subsidy",
            "ban_fair_": "ban",
        }
        rename = {
            col: f"justice_{subscale}_{col[len(prefix):]}"
            for prefix, subscale in prefix_to_subscale.items()
            for col in df.columns
            if col.startswith(prefix)
        }
        df = df.rename(columns=rename)

    # topic == "flying-wtc-wtp" (wave 2): already justice_general/tax/subsidy_N
    # and already numeric -- nothing to do.

    return df


def compute_justice_principle_scores(df: pd.DataFrame, wave_meta: dict) -> pd.DataFrame:
    """Sum each justice principle's items across the general/tax/subsidy(/ban)
    policy domains into 4 scores (utilitarian/egalitarian/sufficientarian/
    limitarian) -- these, not the raw items, are the actual LPA indicators
    (see src/analyse/lpa.R and the justice_columns dict in the original
    wave 1 analysis script)."""
    topic = wave_meta["topic"]
    df = df.copy()

    if topic in ("heating-pv-choice", "flying-wtc-wtp", "ccs-conjoint"):
        for item, principle in _PRINCIPLE_BY_ITEM.items():
            cols = [
                f"justice_{sub}_{item}"
                for sub in ("general", "tax", "subsidy")
                if f"justice_{sub}_{item}" in df.columns
            ]
            if cols:
                df[f"justice_principle_{principle}"] = df[cols].sum(axis=1, skipna=False)

    elif topic == "policy-instruments":
        for principle in ("utilitarian", "egalitarian", "sufficientarian", "limitarian"):
            cols = [
                f"justice_{sub}_{item}"
                for sub, item_to_principle in _WAVE4_PRINCIPLE_BY_SUBSCALE_ITEM.items()
                for item, p in item_to_principle.items()
                if p == principle and f"justice_{sub}_{item}" in df.columns
            ]
            if cols:
                df[f"justice_principle_{principle}"] = df[cols].sum(axis=1, skipna=False)

    return df


def coerce_mixed_type_columns(df: pd.DataFrame) -> pd.DataFrame:
    """Cast columns pandas left as `object` dtype (usually free-text fields
    with a handful of stray numeric values, e.g. survey platform quirks) to
    a proper nullable string dtype. Parquet/Arrow requires a single type per
    column, so an unconverted mix of str and float raises on write."""
    df = df.copy()
    object_columns = df.select_dtypes(include="object").columns
    df[object_columns] = df[object_columns].astype("string")
    return df


def clean_dataframe(
    df: pd.DataFrame,
    wave_meta: dict,
    pii_columns: list[str],
    metadata_columns: list[str],
) -> pd.DataFrame:
    df = filter_to_country(df, wave_meta)
    df = fix_known_typos(df, wave_meta)
    df = filter_invalid_responses(df, wave_meta)
    df = fix_wave3_ch_conjoint_numbering(df, wave_meta)
    df = harmonise_justice_columns(df, wave_meta)
    df = compute_justice_principle_scores(df, wave_meta)

    df = df.drop(columns=pii_columns, errors="ignore")
    df = df.drop(columns=metadata_columns, errors="ignore")
    df = coerce_mixed_type_columns(df)

    df = df.copy()
    df.insert(0, "wave", wave_meta["wave"])
    df.insert(1, "country", wave_meta["country"])
    df.insert(2, "topic", wave_meta["topic"])
    df.insert(3, "respondent_id", range(len(df)))

    return df
