#!/usr/bin/env python3
"""Builds OnTrack/Sources/Resources/foods.json from USDA FoodData Central's public-domain
generic-food datasets (FNDDS survey foods, Foundation Foods, SR Legacy).

Deliberately USDA-only: this file ships inside the app bundle, and Open Food Facts data is
ODbL-licensed (attribution + share-alike). Baking OFF data into a shipped derived database
would attach share-alike to the app's own release — OFF stays a live-only lookup, never here.

Usage:
    python3 tools/build_food_db.py

Re-run only when USDA publishes a new release (Foundation/Branded ~twice a year, FNDDS
roughly every two years, SR Legacy frozen since 2018) — this is not a service.
"""
import json
import os
import sys
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE_DIR = Path(os.environ.get("USDA_CACHE_DIR", ROOT / "tools" / ".cache"))
OUT_PATH = ROOT / "OnTrack" / "Sources" / "Resources" / "foods.json"

BASE = "https://fdc.nal.usda.gov/fdc-datasets/"
DATASETS = [
    # (cache filename, download filename, top-level JSON key, source tag)
    ("survey.zip", "FoodData_Central_survey_food_json_2024-10-31.zip", "SurveyFoods", "fndds"),
    ("foundation.zip", "FoodData_Central_foundation_food_json_2026-04-30.zip", "FoundationFoods", "foundation"),
    ("srlegacy.zip", "FoodData_Central_sr_legacy_food_json_2018-04.zip", "SRLegacyFoods", "srlegacy"),
]

# USDA nutrient IDs -> short output keys. Values are per 100g in the source data.
NUTRIENTS = {
    1008: "kcal", 1003: "protein", 1005: "carb", 1004: "fat",
    1258: "satFat", 1257: "transFat", 1253: "chol", 1093: "sodium",
    1079: "fiber", 2000: "sugar", 1106: "vitA", 1162: "vitC",
    1087: "calcium", 1089: "iron", 1092: "potassium",
}
# Atwater general-factor energy, used only if 1008 (direct kcal) is absent.
ENERGY_FALLBACK_IDS = {2047, 2048}


def fetch(cache_name: str, remote_name: str) -> Path:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    zip_path = CACHE_DIR / cache_name
    if not zip_path.exists():
        url = BASE + remote_name
        print(f"downloading {url}")
        urllib.request.urlretrieve(url, zip_path)
    extract_dir = CACHE_DIR / cache_name.replace(".zip", "")
    if not extract_dir.exists():
        with zipfile.ZipFile(zip_path) as zf:
            zf.extractall(extract_dir)
    json_files = list(extract_dir.glob("*.json"))
    assert len(json_files) == 1, f"expected exactly one json in {extract_dir}, found {json_files}"
    return json_files[0]


def portion_label(p: dict) -> str:
    desc = p.get("portionDescription")
    if desc and desc != "Quantity not specified":
        return desc
    modifier = (p.get("modifier") or "").strip()
    unit_name = (p.get("measureUnit") or {}).get("name", "")
    if modifier and not modifier.isdigit():
        label_unit = modifier
    elif unit_name and unit_name != "undetermined":
        label_unit = unit_name
    else:
        label_unit = "serving"
    amount = p.get("amount") or p.get("value")
    if amount:
        amount_str = f"{amount:g}"
        return f"{amount_str} {label_unit}"
    return label_unit


def extract_portions(food: dict) -> list:
    out = []
    seen = set()
    for p in food.get("foodPortions") or []:
        grams = p.get("gramWeight")
        if not grams or grams <= 0:
            continue
        label = portion_label(p)
        key = (label, round(grams, 1))
        if key in seen:
            continue
        seen.add(key)
        out.append([label, round(grams, 1)])
    out.append(["100 g", 100])
    return out


def extract_nutrients(food: dict) -> dict:
    values = {}
    energy_fallback = None
    for fn in food.get("foodNutrients") or []:
        nutrient = fn.get("nutrient") or {}
        nid = nutrient.get("id")
        amount = fn.get("amount")
        if amount is None:
            continue
        if nid in NUTRIENTS:
            values[NUTRIENTS[nid]] = round(amount, 2)
        elif nid in ENERGY_FALLBACK_IDS and energy_fallback is None:
            energy_fallback = round(amount, 2)
    if "kcal" not in values and energy_fallback is not None:
        values["kcal"] = energy_fallback
    return values


def build_records(foods: list, source: str) -> list:
    records = []
    for food in foods:
        if not food:
            continue  # USDA dumps keep null placeholder slots for retired foods
        name = food.get("description")
        fdc_id = food.get("fdcId")
        if not name or fdc_id is None:
            continue
        nutrients = extract_nutrients(food)
        if not nutrients.get("kcal"):
            continue  # unusable without an energy value (e.g. "Milk, human" placeholder row)
        record = {
            "id": str(fdc_id),
            "n": name,
            "s": source,
            "p": extract_portions(food),
        }
        record.update(nutrients)
        records.append(record)
    return records


def main():
    all_records = []
    for cache_name, remote_name, top_key, source in DATASETS:
        json_path = fetch(cache_name, remote_name)
        print(f"parsing {json_path.name} ({top_key})")
        data = json.load(open(json_path))
        foods = data[top_key]
        records = build_records(foods, source)
        print(f"  {len(foods)} raw -> {len(records)} usable ({source})")
        all_records.extend(records)

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT_PATH, "w") as f:
        json.dump(all_records, f, separators=(",", ":"), ensure_ascii=False)

    size = OUT_PATH.stat().st_size
    print(f"wrote {len(all_records)} records, {size / 1e6:.2f} MB -> {OUT_PATH}")

    # Self-check — the smallest thing that fails if this script silently breaks.
    assert 12_000 < len(all_records) < 16_000, f"record count out of expected range: {len(all_records)}"
    assert size < 8_000_000, f"bundle too large: {size} bytes"
    names = {r["n"] for r in all_records}
    for probe in ["Bread, chappatti or roti", "Biryani with chicken", "Samosa"]:
        assert probe in names, f"expected probe food missing: {probe!r}"
    print("self-check OK")


if __name__ == "__main__":
    sys.exit(main())
