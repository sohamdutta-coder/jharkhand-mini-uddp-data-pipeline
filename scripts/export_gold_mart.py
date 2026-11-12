"""Export the Gold district pension outreach mart to CSV."""

import logging
import sys
from pathlib import Path

import pandas as pd
from sqlalchemy import text

PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = PROJECT_ROOT / "src"

sys.path.insert(0, str(SOURCE_DIR))

from jharkhand_uddp.database.connection import (
    dispose_engine,
    get_engine,
)

logger = logging.getLogger(__name__)


def export_gold_mart() -> Path:
    """Export and validate the district outreach mart."""

    output_directory = PROJECT_ROOT / "outputs"
    output_directory.mkdir(parents=True, exist_ok=True)

    output_path = output_directory / "mart_district_pension_outreach.csv"

    temporary_path = output_path.with_suffix(".csv.tmp")

    query = text(
        """
        SELECT *
        FROM gold.mart_district_pension_outreach
        ORDER BY priority_rank
        """
    )

    engine = get_engine()

    try:
        with engine.connect() as connection:
            dataframe = pd.read_sql_query(query, connection)

        # ----------------------------------------------------
        # VALIDATE EXPORT DATA
        # ----------------------------------------------------

        if len(dataframe) != 24:
            raise RuntimeError(f"Expected 24 districts, found {len(dataframe)}.")

        if dataframe["district_code"].nunique() != 24:
            raise RuntimeError("Duplicate district codes detected.")

        expected_categories = {
            "High": 8,
            "Medium": 8,
            "Low": 8,
        }

        actual_categories = dataframe["priority_category"].value_counts().to_dict()

        if actual_categories != expected_categories:
            raise RuntimeError(f"Priority distribution mismatch: {actual_categories}")

        if dataframe["district_pension_data_available"].any():
            raise RuntimeError("Unexpected district-level pension availability.")

        if (
            dataframe[
                [
                    "old_age_pension_beneficiary_count",
                    "widow_pension_beneficiary_count",
                    "old_age_beneficiaries_per_1000_population",
                    "widow_beneficiaries_per_1000_population",
                    "old_age_beneficiaries_per_1000_households",
                    "widow_beneficiaries_per_1000_households",
                ]
            ]
            .notna()
            .any()
            .any()
        ):
            raise RuntimeError(
                "Unavailable district pension indicators must remain NULL."
            )

        # ----------------------------------------------------
        # EXPORT CSV
        # ----------------------------------------------------

        dataframe.to_csv(
            temporary_path,
            index=False,
            encoding="utf-8",
            lineterminator="\n",
        )

        # Replace final output only after successful export.
        temporary_path.replace(output_path)

        logger.info(
            "Successfully exported %s district records.",
            len(dataframe),
        )

        return output_path

    finally:
        if temporary_path.exists():
            temporary_path.unlink()

        dispose_engine()


def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
    )

    output_path = export_gold_mart()

    print("\nGOLD MART EXPORT SUCCESSFUL")
    print("---------------------------")
    print(f"Output file : {output_path}")
    print(f"File size   : {output_path.stat().st_size:,} bytes")

    print("\nExported districts: 24")
    print("Priority distribution:")
    print("  High   : 8")
    print("  Medium : 8")
    print("  Low    : 8")

    print("\nPension beneficiary figures: NULL (not available at district level)")


if __name__ == "__main__":
    main()
