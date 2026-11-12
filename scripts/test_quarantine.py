"""Controlled integration test for Bronze record quarantine."""

import json
import logging
import sys
from pathlib import Path
from uuid import uuid4

from sqlalchemy import text

PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = PROJECT_ROOT / "src"

sys.path.insert(0, str(SOURCE_DIR))


from jharkhand_uddp.database.connection import (
    dispose_engine,
    get_engine,
)
from jharkhand_uddp.quality.quarantine import (
    export_unmatched_districts,
    quarantine_source_records,
)


def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
    )

    engine = get_engine()

    run_id = uuid4()
    test_checksum = "f" * 64
    test_row_number = 9000001

    synthetic_record = {
        "State name": "JHARKHAND",
        "District code": "9999",
        "District name": "Synthetic Test District",
    }

    try:
        # Insert a temporary DQ run and synthetic Bronze record.

        with engine.begin() as connection:
            ingestion_id = connection.execute(
                text(
                    """
                    SELECT ingestion_id
                    FROM bronze.ingestion_metadata
                    WHERE source_name = 'Census District Demographics'
                      AND status = 'SUCCEEDED'
                    LIMIT 1
                    """
                )
            ).scalar_one()

            connection.execute(
                text(
                    """
                    INSERT INTO dq.data_quality_runs (
                        run_id,
                        status
                    )
                    VALUES (:run_id, 'RUNNING')
                    """
                ),
                {"run_id": run_id},
            )

            connection.execute(
                text(
                    """
                    INSERT INTO bronze.census_demographics_raw (
                        ingestion_id,
                        source_file_name,
                        source_sha256,
                        source_row_number,
                        raw_record
                    )
                    VALUES (
                        :ingestion_id,
                        'synthetic_quarantine_test.csv',
                        :checksum,
                        :row_number,
                        CAST(:raw_record AS JSONB)
                    )
                    """
                ),
                {
                    "ingestion_id": ingestion_id,
                    "checksum": test_checksum,
                    "row_number": test_row_number,
                    "raw_record": json.dumps(synthetic_record),
                },
            )

        print("\nSynthetic invalid district inserted.")

        # Execute the actual quarantine implementation.

        quarantined_count = quarantine_source_records(
            engine=engine,
            run_id=run_id,
            project_root=PROJECT_ROOT,
        )

        with engine.connect() as connection:
            quarantined_record = (
                connection.execute(
                    text(
                        """
                    SELECT
                        reason_code,
                        reason_description,
                        source_row_number,
                        raw_record ->> 'District name' AS district_name
                    FROM dq.quarantined_records
                    WHERE run_id = :run_id
                    """
                    ),
                    {"run_id": run_id},
                )
                .mappings()
                .one_or_none()
            )

        if quarantined_count != 1 or quarantined_record is None:
            raise AssertionError("Expected exactly one quarantined record.")

        if quarantined_record["reason_code"] != ("DEMOGRAPHIC_DISTRICT_UNMATCHED"):
            raise AssertionError("Unexpected quarantine reason.")

        if quarantined_record["district_name"] != ("Synthetic Test District"):
            raise AssertionError("Original record was not preserved.")

        print("\nQUARANTINE TEST PASSED")
        print("----------------------")
        print(f"Reason: {quarantined_record['reason_code']}")
        print(f"District: {quarantined_record['district_name']}")
        print(f"Source row: {quarantined_record['source_row_number']}")
        print("Original JSONB record successfully preserved.")

    finally:
        # Remove all synthetic test data.

        with engine.begin() as connection:
            connection.execute(
                text(
                    """
                    DELETE FROM dq.quarantined_records
                    WHERE run_id = :run_id
                    """
                ),
                {"run_id": run_id},
            )

            connection.execute(
                text(
                    """
                    DELETE FROM bronze.census_demographics_raw
                    WHERE source_sha256 = :checksum
                      AND source_row_number = :row_number
                    """
                ),
                {
                    "checksum": test_checksum,
                    "row_number": test_row_number,
                },
            )

            connection.execute(
                text(
                    """
                    DELETE FROM dq.data_quality_runs
                    WHERE run_id = :run_id
                    """
                ),
                {"run_id": run_id},
            )

        # Regenerate the report after removing the test record.

        export_unmatched_districts(engine, PROJECT_ROOT)

        print("\nSynthetic test data successfully cleaned up.")

        dispose_engine()


if __name__ == "__main__":
    main()
