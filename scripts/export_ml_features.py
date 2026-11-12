import logging
import sys
from pathlib import Path

import pandas as pd
from sqlalchemy import text

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT / "src"))

from jharkhand_uddp.database.connection import (
    dispose_engine,
    get_engine,
)

OUTPUT_FILE = PROJECT_ROOT / "outputs" / "ml_district_features.csv"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
)
logger = logging.getLogger(__name__)

PENSION_COLUMNS = [
    "old_age_pension_beneficiary_count",
    "widow_pension_beneficiary_count",
    "old_age_beneficiaries_per_1000_population",
    "widow_beneficiaries_per_1000_population",
    "old_age_beneficiaries_per_1000_households",
    "widow_beneficiaries_per_1000_households",
    "total_pension_beneficiaries_per_1000_households",
]


def validate_dataset(df: pd.DataFrame) -> None:
    """Validate the ML feature dataset before exporting."""

    if len(df) != 24:
        raise ValueError(f"Expected 24 districts, found {len(df)}.")

    if df["district_code"].nunique() != 24:
        raise ValueError("District codes are missing or duplicated.")

    expected_distribution = {
        "High": 8,
        "Medium": 8,
        "Low": 8,
    }

    actual_distribution = df["target_priority_category"].value_counts().to_dict()

    if actual_distribution != expected_distribution:
        raise ValueError(f"Unexpected priority distribution: {actual_distribution}")

    expected_target = df["target_priority_category"].eq("High").astype(int)

    if not df["target_high_priority"].equals(expected_target):
        raise ValueError("Binary target does not match priority category.")

    if df["district_pension_data_available"].isna().any():
        raise ValueError("Pension availability flags contain NULL values.")

    if df["district_pension_data_available"].any():
        raise ValueError("Unexpected district-level pension availability.")

    for column in PENSION_COLUMNS:
        if df[column].notna().any():
            raise ValueError(f"Expected NULL pension values, found data in {column}.")


def main() -> None:
    engine = get_engine()

    try:
        query = text("""
            SELECT *
            FROM ml.ml_district_features
            ORDER BY target_priority_rank;
        """)

        with engine.connect() as connection:
            df = pd.read_sql_query(query, connection)

        validate_dataset(df)

        OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)

        temporary_file = OUTPUT_FILE.with_suffix(".csv.tmp")

        df.to_csv(
            temporary_file,
            index=False,
            encoding="utf-8",
            lineterminator="\n",
            na_rep="",
        )

        temporary_file.replace(OUTPUT_FILE)

        logger.info("Successfully exported %d district records.", len(df))

        print("\nML FEATURE EXPORT SUCCESSFUL")
        print("----------------------------")
        print(f"Output file : {OUTPUT_FILE}")
        print(f"File size   : {OUTPUT_FILE.stat().st_size:,} bytes")
        print(f"Total records: {len(df)}")
        print("\nPriority distribution:")

        for category in ["High", "Medium", "Low"]:
            count = (df["target_priority_category"] == category).sum()
            print(f"  {category:<7}: {count}")

        print("\nDistrict-level pension figures: NULL")

    finally:
        dispose_engine()


if __name__ == "__main__":
    main()
