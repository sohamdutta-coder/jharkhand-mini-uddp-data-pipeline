"""Identify and preserve invalid Bronze source records."""

import csv
import logging
from pathlib import Path
from uuid import UUID

from sqlalchemy import Engine, text

logger = logging.getLogger(__name__)


QUARANTINE_QUERIES = (
    # --------------------------------------------------------
    # DEMOGRAPHICS: MISSING DISTRICT IDENTIFIERS
    # --------------------------------------------------------
    (
        "DEMOGRAPHIC_MISSING_DISTRICT_KEY",
        """
        INSERT INTO dq.quarantined_records (
            run_id, source_name, source_file_name,
            source_sha256, source_row_number,
            target_table, reason_code,
            reason_description, raw_record
        )
        SELECT
            :run_id,
            'Census District Demographics',
            b.source_file_name,
            b.source_sha256,
            b.source_row_number,
            'silver.dim_district',
            'DEMOGRAPHIC_MISSING_DISTRICT_KEY',
            'Missing or invalid district code or district name.',
            b.raw_record
        FROM bronze.census_demographics_raw b
        WHERE UPPER(TRIM(b.raw_record ->> 'State name')) = 'JHARKHAND'
          AND (
              NULLIF(TRIM(b.raw_record ->> 'District code'), '') IS NULL
              OR TRIM(b.raw_record ->> 'District code') !~ '^[0-9]+$'
              OR NULLIF(TRIM(b.raw_record ->> 'District name'), '') IS NULL
          )
        ON CONFLICT (
            source_sha256, source_row_number, reason_code
        ) DO NOTHING
        """,
    ),
    # --------------------------------------------------------
    # DEMOGRAPHICS: DUPLICATE DISTRICT CODES
    # --------------------------------------------------------
    (
        "DEMOGRAPHIC_DUPLICATE_DISTRICT_CODE",
        """
        WITH duplicates AS (
            SELECT
                TRIM(raw_record ->> 'District code') AS district_code
            FROM bronze.census_demographics_raw
            WHERE UPPER(TRIM(raw_record ->> 'State name')) = 'JHARKHAND'
              AND TRIM(raw_record ->> 'District code') ~ '^[0-9]+$'
            GROUP BY 1
            HAVING COUNT(*) > 1
        )
        INSERT INTO dq.quarantined_records (
            run_id, source_name, source_file_name,
            source_sha256, source_row_number,
            target_table, reason_code,
            reason_description, raw_record
        )
        SELECT
            :run_id,
            'Census District Demographics',
            b.source_file_name,
            b.source_sha256,
            b.source_row_number,
            'silver.dim_district',
            'DEMOGRAPHIC_DUPLICATE_DISTRICT_CODE',
            'District code appears more than once in demographic source.',
            b.raw_record
        FROM bronze.census_demographics_raw b
        JOIN duplicates d
          ON d.district_code = TRIM(b.raw_record ->> 'District code')
        WHERE UPPER(TRIM(b.raw_record ->> 'State name')) = 'JHARKHAND'
        ON CONFLICT (
            source_sha256, source_row_number, reason_code
        ) DO NOTHING
        """,
    ),
    # --------------------------------------------------------
    # DEMOGRAPHICS: UNMATCHED OR MISMATCHED DISTRICTS
    # --------------------------------------------------------
    (
        "DEMOGRAPHIC_DISTRICT_UNMATCHED",
        """
        INSERT INTO dq.quarantined_records (
            run_id, source_name, source_file_name,
            source_sha256, source_row_number,
            target_table, reason_code,
            reason_description, raw_record
        )
        SELECT
            :run_id,
            'Census District Demographics',
            b.source_file_name,
            b.source_sha256,
            b.source_row_number,
            'silver.dim_district',
            'DEMOGRAPHIC_DISTRICT_UNMATCHED',
            'District code or normalized name does not match the canonical dimension.',
            b.raw_record
        FROM bronze.census_demographics_raw b
        WHERE UPPER(TRIM(b.raw_record ->> 'State name')) = 'JHARKHAND'
          AND TRIM(b.raw_record ->> 'District code') ~ '^[0-9]+$'
          AND NULLIF(TRIM(b.raw_record ->> 'District name'), '') IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM silver.dim_district d
              WHERE d.district_code::TEXT =
                    TRIM(b.raw_record ->> 'District code')
                AND d.district_name_normalized =
                    REGEXP_REPLACE(
                        LOWER(TRIM(b.raw_record ->> 'District name')),
                        '[^a-z0-9]', '', 'g'
                    )
          )
        ON CONFLICT (
            source_sha256, source_row_number, reason_code
        ) DO NOTHING
        """,
    ),
    # --------------------------------------------------------
    # HOUSING: MISSING DISTRICT IDENTIFIERS
    # --------------------------------------------------------
    (
        "HOUSING_MISSING_DISTRICT_KEY",
        """
        INSERT INTO dq.quarantined_records (
            run_id, source_name, source_file_name,
            source_sha256, source_row_number,
            target_table, reason_code,
            reason_description, raw_record
        )
        SELECT
            :run_id,
            'Census District Housing',
            b.source_file_name,
            b.source_sha256,
            b.source_row_number,
            'silver.fact_district_housing',
            'HOUSING_MISSING_DISTRICT_KEY',
            'Missing or invalid housing district code or name.',
            b.raw_record
        FROM bronze.census_housing_raw b
        WHERE UPPER(TRIM(b.raw_record ->> 'State Name')) = 'JHARKHAND'
          AND LOWER(TRIM(b.raw_record ->> 'Rural/Urban')) = 'total'
          AND (
              NULLIF(TRIM(b.raw_record ->> 'District Code'), '') IS NULL
              OR TRIM(b.raw_record ->> 'District Code') !~ '^[0-9]+$'
              OR NULLIF(TRIM(b.raw_record ->> 'District Name'), '') IS NULL
          )
        ON CONFLICT (
            source_sha256, source_row_number, reason_code
        ) DO NOTHING
        """,
    ),
    # --------------------------------------------------------
    # HOUSING: DUPLICATE DISTRICT CODES
    # --------------------------------------------------------
    (
        "HOUSING_DUPLICATE_DISTRICT_CODE",
        """
        WITH duplicates AS (
            SELECT
                TRIM(raw_record ->> 'District Code') AS district_code
            FROM bronze.census_housing_raw
            WHERE UPPER(TRIM(raw_record ->> 'State Name')) = 'JHARKHAND'
              AND LOWER(TRIM(raw_record ->> 'Rural/Urban')) = 'total'
              AND TRIM(raw_record ->> 'District Code') ~ '^[0-9]+$'
            GROUP BY 1
            HAVING COUNT(*) > 1
        )
        INSERT INTO dq.quarantined_records (
            run_id, source_name, source_file_name,
            source_sha256, source_row_number,
            target_table, reason_code,
            reason_description, raw_record
        )
        SELECT
            :run_id,
            'Census District Housing',
            b.source_file_name,
            b.source_sha256,
            b.source_row_number,
            'silver.fact_district_housing',
            'HOUSING_DUPLICATE_DISTRICT_CODE',
            'District code appears more than once in housing source.',
            b.raw_record
        FROM bronze.census_housing_raw b
        JOIN duplicates d
          ON d.district_code = TRIM(b.raw_record ->> 'District Code')
        WHERE UPPER(TRIM(b.raw_record ->> 'State Name')) = 'JHARKHAND'
          AND LOWER(TRIM(b.raw_record ->> 'Rural/Urban')) = 'total'
        ON CONFLICT (
            source_sha256, source_row_number, reason_code
        ) DO NOTHING
        """,
    ),
    # --------------------------------------------------------
    # HOUSING: UNMATCHED OR MISMATCHED DISTRICTS
    # --------------------------------------------------------
    (
        "HOUSING_DISTRICT_UNMATCHED",
        """
        INSERT INTO dq.quarantined_records (
            run_id, source_name, source_file_name,
            source_sha256, source_row_number,
            target_table, reason_code,
            reason_description, raw_record
        )
        SELECT
            :run_id,
            'Census District Housing',
            b.source_file_name,
            b.source_sha256,
            b.source_row_number,
            'silver.fact_district_housing',
            'HOUSING_DISTRICT_UNMATCHED',
            'Housing district code or normalized name does not match the dimension.',
            b.raw_record
        FROM bronze.census_housing_raw b
        WHERE UPPER(TRIM(b.raw_record ->> 'State Name')) = 'JHARKHAND'
          AND LOWER(TRIM(b.raw_record ->> 'Rural/Urban')) = 'total'
          AND TRIM(b.raw_record ->> 'District Code') ~ '^[0-9]+$'
          AND NULLIF(TRIM(b.raw_record ->> 'District Name'), '') IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM silver.dim_district d
              WHERE d.district_code::TEXT =
                    TRIM(b.raw_record ->> 'District Code')
                AND d.district_name_normalized =
                    REGEXP_REPLACE(
                        LOWER(TRIM(b.raw_record ->> 'District Name')),
                        '[^a-z0-9]', '', 'g'
                    )
          )
        ON CONFLICT (
            source_sha256, source_row_number, reason_code
        ) DO NOTHING
        """,
    ),
    # --------------------------------------------------------
    # NSAP: INVALID ADMINISTRATIVE UNIT OR CATEGORY
    # --------------------------------------------------------
    (
        "NSAP_INVALID_ADMINISTRATIVE_UNIT",
        """
        INSERT INTO dq.quarantined_records (
            run_id, source_name, source_file_name,
            source_sha256, source_row_number,
            target_table, reason_code,
            reason_description, raw_record
        )
        SELECT
            :run_id,
            'National Social Assistance Programme',
            b.source_file_name,
            b.source_sha256,
            b.source_row_number,
            'silver.fact_pension_beneficiaries',
            'NSAP_INVALID_ADMINISTRATIVE_UNIT',
            'Missing administrative unit or invalid category.',
            b.raw_record
        FROM bronze.nsap_pension_raw b
        WHERE LOWER(TRIM(b.raw_record ->> 'States/UTs')) <> 'grand total'
          AND (
              NULLIF(TRIM(b.raw_record ->> 'States/UTs'), '') IS NULL
              OR TRIM(b.raw_record ->> 'Category') NOT IN (
                  'State', 'NE States', 'Union Territories'
              )
          )
        ON CONFLICT (
            source_sha256, source_row_number, reason_code
        ) DO NOTHING
        """,
    ),
    # --------------------------------------------------------
    # NSAP: INVALID BENEFICIARY COUNTS
    # --------------------------------------------------------
    (
        "NSAP_INVALID_BENEFICIARY_COUNT",
        """
        INSERT INTO dq.quarantined_records (
            run_id, source_name, source_file_name,
            source_sha256, source_row_number,
            target_table, reason_code,
            reason_description, raw_record
        )
        SELECT
            :run_id,
            'National Social Assistance Programme',
            b.source_file_name,
            b.source_sha256,
            b.source_row_number,
            'silver.fact_pension_beneficiaries',
            'NSAP_INVALID_BENEFICIARY_COUNT',
            'One or more scheme beneficiary counts are missing, negative or non-numeric.',
            b.raw_record
        FROM bronze.nsap_pension_raw b
        WHERE LOWER(TRIM(b.raw_record ->> 'States/UTs')) <> 'grand total'
          AND (
              COALESCE(TRIM(b.raw_record ->> 'Old Age Pension Scheme'), '')
                  !~ '^([0-9]+|[0-9]{1,3}(,[0-9]{3})+)$'
              OR
              COALESCE(TRIM(b.raw_record ->> 'Widow Pension Scheme'), '')
                  !~ '^([0-9]+|[0-9]{1,3}(,[0-9]{3})+)$'
              OR
              COALESCE(TRIM(b.raw_record ->> 'Divyangjan /Disability Pension Scheme'), '')
                  !~ '^([0-9]+|[0-9]{1,3}(,[0-9]{3})+)$'
          )
        ON CONFLICT (
            source_sha256, source_row_number, reason_code
        ) DO NOTHING
        """,
    ),
)


def export_unmatched_districts(
    engine: Engine,
    project_root: Path,
) -> Path:
    """Export unresolved district-related quarantine records."""

    report_path = project_root / "reports" / "unmatched_districts.csv"
    report_path.parent.mkdir(parents=True, exist_ok=True)

    query = text(
        """
        SELECT
            source_name,
            source_file_name,
            source_sha256,
            source_row_number,
            target_table,
            reason_code,
            reason_description,
            raw_record::TEXT AS raw_record
        FROM dq.quarantined_records
        WHERE resolved_at IS NULL
          AND reason_code IN (
              'DEMOGRAPHIC_MISSING_DISTRICT_KEY',
              'DEMOGRAPHIC_DUPLICATE_DISTRICT_CODE',
              'DEMOGRAPHIC_DISTRICT_UNMATCHED',
              'HOUSING_MISSING_DISTRICT_KEY',
              'HOUSING_DUPLICATE_DISTRICT_CODE',
              'HOUSING_DISTRICT_UNMATCHED'
          )
        ORDER BY source_name, source_row_number
        """
    )

    with engine.connect() as connection:
        records = connection.execute(query).mappings().all()

    fieldnames = [
        "source_name",
        "source_file_name",
        "source_sha256",
        "source_row_number",
        "target_table",
        "reason_code",
        "reason_description",
        "raw_record",
    ]

    with report_path.open(
        "w",
        encoding="utf-8",
        newline="",
    ) as report_file:
        writer = csv.DictWriter(
            report_file,
            fieldnames=fieldnames,
            lineterminator="\n",
        )

        writer.writeheader()
        writer.writerows([dict(record) for record in records])

    logger.info(
        "Generated unmatched district report with %s records.",
        len(records),
    )

    return report_path


def quarantine_source_records(
    engine: Engine,
    run_id: UUID,
    project_root: Path,
) -> int:
    """Find and persist invalid source records."""

    inserted_records = 0

    with engine.begin() as connection:
        for reason_code, query in QUARANTINE_QUERIES:
            result = connection.execute(
                text(query),
                {"run_id": run_id},
            )

            inserted_records += max(result.rowcount, 0)

            logger.info(
                "Quarantine check %s: %s new records.",
                reason_code,
                max(result.rowcount, 0),
            )

    export_unmatched_districts(engine, project_root)

    logger.info(
        "Total newly quarantined records: %s",
        inserted_records,
    )

    return inserted_records
