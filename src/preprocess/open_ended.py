"""Cleaning of wave 3's open-ended justice-reasoning responses ("why did
you answer this way"). Kept separate from harmonise.py since it operates
on long-format melted text rather than the wide per-respondent survey row.

Each wave 3 respondent was randomly shown exactly one of three context
questions -- general/tax/subsidy -- never more than one (confirmed via
the show_open_Q1-3 flags), so melting collapses those three column pairs
into a single (respondent_id, context, response_raw) row per respondent
who was assigned a context. Flagging is deliberately conservative: it
marks likely-junk responses via cheap heuristics rather than silently
dropping them, so a human can spot-check the flagged/excluded set before
those rows are excluded from analysis (see clean_open_ended.py)."""

import re
import unicodedata

import pandas as pd

# Raw column pairs -> context label. Labels match the subscale names used
# in src/analyse/cfa.R (general/tax/subsidy).
_CONTEXT_COLUMNS = [
    ("show_open_Q1", "justice_open1_gen", "general"),
    ("show_open_Q2", "justice_open2_tax", "tax"),
    ("show_open_Q3", "justice_open3_sub", "subsidy"),
]

# CH's `language` field holds the full language name; wave 3 CN has no
# language column at all (single-language fielding, Chinese).
_LANGUAGE_CODES = {"Deutsch": "de", "Français": "fr", "English": "en"}


def melt_open_ended(df: pd.DataFrame, country: str) -> pd.DataFrame:
    """One row per respondent who was shown a context (each respondent
    contributes at most one row, by design -- see module docstring)."""
    columns = ["respondent_id", "country", "language", "context", "response_raw"]
    blocks = []
    for show_col, text_col, context in _CONTEXT_COLUMNS:
        if show_col not in df.columns or text_col not in df.columns:
            continue
        shown = df[df[show_col] == 1]
        if "language" in shown.columns:
            language = shown["language"].map(_LANGUAGE_CODES).fillna(shown["language"])
        else:
            language = "zh"
        blocks.append(
            pd.DataFrame(
                {
                    "respondent_id": shown["respondent_id"],
                    "country": country,
                    "language": language,
                    "context": context,
                    "response_raw": shown[text_col],
                }
            )
        )
    if not blocks:
        return pd.DataFrame(columns=columns)
    return pd.concat(blocks, ignore_index=True)[columns]


def normalize_text(text) -> str | None:
    """Strip/collapse whitespace and Unicode-normalize (NFC -- mainly
    matters for the Chinese responses, where composed/decomposed encoding
    can otherwise vary). Returns None for missing or empty-after-stripping
    text."""
    if pd.isna(text):
        return None
    text = unicodedata.normalize("NFC", str(text)).strip()
    text = re.sub(r"\s+", " ", text)
    return text if text else None


MIN_SUBSTANTIVE_LENGTH = 2
# Above this length, a single space-delimited token with no whitespace at
# all is more likely a piping/export artifact than a real one-word answer
# (real single-word answers are almost always well under this). Only
# meaningful for space-delimited languages -- Chinese doesn't use spaces
# between words at all, so a long unspaced CJK response is normal, not
# suspicious.
ARTIFACT_TOKEN_LENGTH = 60
_SPACE_DELIMITED_LANGUAGES = {"de", "fr", "en"}

_NUMERIC_OR_PUNCTUATION_ONLY = re.compile(r"^[\d.,;:!?/\\_\-–—]+$")

# Non-exhaustive "no substantive answer" phrase lists, matched case-
# insensitively against the whole (normalized) response. Not meant to catch
# everything -- see the module docstring on flagging vs. dropping.
_NON_ANSWER_PHRASES = {
    "de": {"weiss nicht", "weiß nicht", "keine ahnung", "k.a.", "nn", "na", "keine", "nichts", "keine angabe"},
    "fr": {"ne sais pas", "aucune idée", "rien", "aucun", "aucune", "je ne sais pas"},
    "en": {"idk", "i don't know", "n/a", "none", "nothing", "test", "dont know"},
    "zh": {"不知道", "没有", "无", "没有意见", "不清楚"},
}


def classify_exclusion(text: str | None, language: str) -> str | None:
    """Reason a normalized response looks non-substantive, or None if it
    should be treated as substantive. Checked in order; the first match
    wins."""
    # pandas' Series.map() can round-trip a returned None back into a float
    # NaN rather than preserving it as None, depending on the source
    # column's dtype -- check both.
    if text is None or pd.isna(text):
        return "missing"
    if _NUMERIC_OR_PUNCTUATION_ONLY.match(text):
        return "numeric_or_punctuation_only"
    if len(text) < MIN_SUBSTANTIVE_LENGTH:
        return "too_short"
    if text.lower() in _NON_ANSWER_PHRASES.get(language, set()):
        return "non_answer_phrase"
    if (
        language in _SPACE_DELIMITED_LANGUAGES
        and " " not in text
        and len(text) > ARTIFACT_TOKEN_LENGTH
    ):
        return "suspected_artifact"
    return None


def flag_non_substantive(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    df["response_clean"] = df["response_raw"].map(normalize_text)
    df["exclusion_reason"] = [
        classify_exclusion(text, language)
        for text, language in zip(df["response_clean"], df["language"])
    ]
    df["is_substantive"] = df["exclusion_reason"].isna()
    return df


def clean_open_ended(df: pd.DataFrame, country: str) -> pd.DataFrame:
    return flag_non_substantive(melt_open_ended(df, country))
