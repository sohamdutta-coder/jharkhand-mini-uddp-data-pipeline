"""Centralized SQL-based data quality checks."""

from dataclasses import dataclass


@dataclass(frozen=True)
class DQCheck:
    code: str
    layer: str
    table_name: str
    description: str
    sql: str
    severity: str = "ERROR"
    expected_value: str = "0 violations"


DQ_CHECKS = (
    # --------------------------------------------------------
    # DISTRICT DIMENSION
    # --------------------------------------------------------
    DQCheck(
        "DQ-001",
        "SILVER",
        "silver.dim_district",
        "Duplicate district codes",
        """
        SELECT COUNT(*)
        FROM (
            SELECT district_code
            FROM silver.dim_district
            GROUP BY district_code
            HAVING COUNT(*) > 1
        ) duplicates
        """,
    ),
    DQCheck(
        "DQ-002",
        "SILVER",
        "silver.dim_district",
        "Missing district names or codes",
        """
        SELECT COUNT(*)
        FROM silver.dim_district
        WHERE district_code IS NULL
           OR NULLIF(TRIM(district_name), '') IS NULL
           OR NULLIF(TRIM(district_name_normalized), '') IS NULL
        """,
    ),
    # --------------------------------------------------------
    # DEMOGRAPHIC SOURCE VALIDATION
    # --------------------------------------------------------
    DQCheck(
        "DQ-003",
        "BRONZE",
        "bronze.census_demographics_raw",
        "Duplicate Jharkhand demographic district codes",
        """
        SELECT COUNT(*)
        FROM (
            SELECT TRIM(raw_record ->> 'District code') AS district_code
            FROM bronze.census_demographics_raw
            WHERE UPPER(TRIM(raw_record ->> 'State name')) = 'JHARKHAND'
            GROUP BY 1
            HAVING COUNT(*) > 1
        ) duplicates
        """,
    ),
    DQCheck(
        "DQ-004",
        "BRONZE",
        "bronze.census_demographics_raw",
        "Missing demographic district names or codes",
        """
        SELECT COUNT(*)
        FROM bronze.census_demographics_raw
        WHERE UPPER(TRIM(raw_record ->> 'State name')) = 'JHARKHAND'
          AND (
              NULLIF(TRIM(raw_record ->> 'District code'), '') IS NULL
              OR NULLIF(TRIM(raw_record ->> 'District name'), '') IS NULL
          )
        """,
    ),
    DQCheck(
        "DQ-005",
        "BRONZE",
        "bronze.census_housing_raw",
        "Duplicate Jharkhand housing district codes",
        """
        SELECT COUNT(*)
        FROM (
            SELECT TRIM(raw_record ->> 'District Code') AS district_code
            FROM bronze.census_housing_raw
            WHERE UPPER(TRIM(raw_record ->> 'State Name')) = 'JHARKHAND'
              AND LOWER(TRIM(raw_record ->> 'Rural/Urban')) = 'total'
            GROUP BY 1
            HAVING COUNT(*) > 1
        ) duplicates
        """,
    ),
    DQCheck(
        "DQ-006",
        "BRONZE",
        "bronze.census_housing_raw",
        "Missing housing district names or codes",
        """
        SELECT COUNT(*)
        FROM bronze.census_housing_raw
        WHERE UPPER(TRIM(raw_record ->> 'State Name')) = 'JHARKHAND'
          AND LOWER(TRIM(raw_record ->> 'Rural/Urban')) = 'total'
          AND (
              NULLIF(TRIM(raw_record ->> 'District Code'), '') IS NULL
              OR NULLIF(TRIM(raw_record ->> 'District Name'), '') IS NULL
          )
        """,
    ),
    # --------------------------------------------------------
    # DISTRICT MATCHING
    # --------------------------------------------------------
    DQCheck(
        "DQ-007",
        "SILVER",
        "silver.dim_district",
        "Demographic records unmatched with district dimension",
        """
        SELECT COUNT(*)
        FROM bronze.census_demographics_raw b
        WHERE UPPER(TRIM(b.raw_record ->> 'State name')) = 'JHARKHAND'
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
        """,
    ),
    DQCheck(
        "DQ-008",
        "SILVER",
        "silver.dim_district",
        "Housing records unmatched with district dimension",
        """
        SELECT COUNT(*)
        FROM bronze.census_housing_raw b
        WHERE UPPER(TRIM(b.raw_record ->> 'State Name')) = 'JHARKHAND'
          AND LOWER(TRIM(b.raw_record ->> 'Rural/Urban')) = 'total'
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
        """,
    ),
    DQCheck(
        "DQ-009",
        "SILVER",
        "silver.fact_district_demographics",
        "Districts missing demographic fact records",
        """
        SELECT COUNT(*)
        FROM silver.dim_district d
        LEFT JOIN silver.fact_district_demographics f
            ON d.district_code = f.district_code
        WHERE f.district_code IS NULL
        """,
    ),
    DQCheck(
        "DQ-010",
        "SILVER",
        "silver.fact_district_housing",
        "Districts missing housing fact records",
        """
        SELECT COUNT(*)
        FROM silver.dim_district d
        LEFT JOIN silver.fact_district_housing f
            ON d.district_code = f.district_code
        WHERE f.district_code IS NULL
        """,
    ),
    # --------------------------------------------------------
    # DEMOGRAPHIC NUMERIC VALIDATION
    # --------------------------------------------------------
    DQCheck(
        "DQ-011",
        "BRONZE",
        "bronze.census_demographics_raw",
        "Missing required demographic columns",
        """
        SELECT COUNT(*)
        FROM bronze.census_demographics_raw
        WHERE UPPER(TRIM(raw_record ->> 'State name')) = 'JHARKHAND'
          AND NOT (
              raw_record ?& ARRAY[
                  'District code', 'District name', 'Population',
                  'Male', 'Female', 'Literate', 'Workers',
                  'SC', 'ST', 'Households',
                  'Age_Group_0_29', 'Age_Group_30_49',
                  'Age_Group_50', 'Age not stated'
              ]
          )
        """,
    ),
    DQCheck(
        "DQ-012",
        "BRONZE",
        "bronze.census_demographics_raw",
        "Invalid or missing demographic numeric values",
        """
        SELECT COUNT(*)
        FROM bronze.census_demographics_raw b
        CROSS JOIN LATERAL jsonb_each_text(b.raw_record) v
        WHERE UPPER(TRIM(b.raw_record ->> 'State name')) = 'JHARKHAND'
          AND v.key = ANY(ARRAY[
              'District code', 'Population', 'Male', 'Female',
              'Literate', 'Workers', 'SC', 'ST', 'Households',
              'Age_Group_0_29', 'Age_Group_30_49',
              'Age_Group_50', 'Age not stated'
          ])
          AND (
              v.value IS NULL
              OR TRIM(v.value) !~
                  '^([0-9]+|[0-9]{1,3}(,[0-9]{3})+)$'
          )
        """,
    ),
    DQCheck(
        "DQ-013",
        "SILVER",
        "silver.fact_district_demographics",
        "Population less than or equal to zero",
        """
        SELECT COUNT(*)
        FROM silver.fact_district_demographics
        WHERE total_population <= 0
        """,
    ),
    DQCheck(
        "DQ-014",
        "SILVER",
        "silver.fact_district_demographics",
        "Households greater than population",
        """
        SELECT COUNT(*)
        FROM silver.fact_district_demographics
        WHERE total_households > total_population
        """,
    ),
    DQCheck(
        "DQ-015",
        "SILVER",
        "silver.fact_district_demographics",
        "Male and female population reconciliation",
        """
        SELECT COUNT(*)
        FROM silver.fact_district_demographics
        WHERE male_population + female_population
              <> total_population
        """,
    ),
    DQCheck(
        "DQ-016",
        "SILVER",
        "silver.fact_district_demographics",
        "Age-group population reconciliation",
        """
        SELECT COUNT(*)
        FROM bronze.census_demographics_raw
        WHERE UPPER(TRIM(raw_record ->> 'State name')) = 'JHARKHAND'
          AND (
              REPLACE(raw_record ->> 'Age_Group_0_29', ',', '')::BIGINT
              +
              REPLACE(raw_record ->> 'Age_Group_30_49', ',', '')::BIGINT
              +
              REPLACE(raw_record ->> 'Age_Group_50', ',', '')::BIGINT
              +
              REPLACE(raw_record ->> 'Age not stated', ',', '')::BIGINT
          )
          <>
          REPLACE(raw_record ->> 'Population', ',', '')::BIGINT
        """,
    ),
    DQCheck(
        "DQ-017",
        "SILVER",
        "silver.fact_district_demographics",
        "Literacy, worker, SC or ST population exceeds total population",
        """
        SELECT COUNT(*)
        FROM silver.fact_district_demographics
        WHERE literate_population > total_population
           OR total_workers > total_population
           OR sc_population > total_population
           OR st_population > total_population
        """,
    ),
    # --------------------------------------------------------
    # HOUSING VALIDATION
    # --------------------------------------------------------
    DQCheck(
        "DQ-018",
        "SILVER",
        "silver.fact_district_housing",
        "Missing or invalid housing percentages",
        """
        SELECT COUNT(*)
        FROM silver.fact_district_housing h
        CROSS JOIN LATERAL (
            VALUES
                (h.household_reference_base_pct),
                (h.good_housing_pct),
                (h.livable_housing_pct),
                (h.dilapidated_housing_pct),
                (h.residential_households_pct),
                (h.residential_good_pct),
                (h.residential_livable_pct),
                (h.residential_dilapidated_pct),
                (h.permanent_housing_pct),
                (h.semi_permanent_housing_pct),
                (h.temporary_housing_pct),
                (h.non_serviceable_housing_pct),
                (h.serviceable_pct),
                (h.unclassifiable_pct)
        ) AS v(value)
        WHERE v.value IS NULL
           OR v.value NOT BETWEEN 0 AND 100
        """,
    ),
    DQCheck(
        "DQ-019",
        "SILVER",
        "silver.fact_district_housing",
        "Housing condition percentage reconciliation",
        """
        SELECT COUNT(*)
        FROM silver.fact_district_housing
        WHERE ABS(
            good_housing_pct
            + livable_housing_pct
            + dilapidated_housing_pct
            - 100
        ) > 0.2
        """,
    ),
    DQCheck(
        "DQ-020",
        "SILVER",
        "silver.fact_district_housing",
        "Residential housing percentage reconciliation",
        """
        SELECT COUNT(*)
        FROM silver.fact_district_housing
        WHERE ABS(
            residential_households_pct
            - residential_good_pct
            - residential_livable_pct
            - residential_dilapidated_pct
        ) > 0.2
        """,
    ),
    # --------------------------------------------------------
    # PENSION VALIDATION
    # --------------------------------------------------------
    DQCheck(
        "DQ-021",
        "SILVER",
        "silver.fact_pension_beneficiaries",
        "Negative pension beneficiary counts",
        """
        SELECT COUNT(*)
        FROM silver.fact_pension_beneficiaries
        WHERE beneficiary_count < 0
        """,
    ),
    DQCheck(
        "DQ-022",
        "SILVER",
        "silver.fact_pension_beneficiaries",
        "Pension fact administrative-unit and scheme reconciliation",
        """
        SELECT
            CASE
                WHEN COUNT(*) = 108
                 AND COUNT(DISTINCT administrative_unit_normalized) = 36
                 AND COUNT(DISTINCT pension_scheme) = 3
                THEN 0
                ELSE 1
            END
        FROM silver.fact_pension_beneficiaries
        """,
    ),
    # --------------------------------------------------------
    # BRONZE TO SILVER RECONCILIATION
    # --------------------------------------------------------
    DQCheck(
        "DQ-023",
        "SILVER",
        "silver.fact_district_demographics",
        "Demographic Bronze-to-Silver row reconciliation",
        """
        SELECT
            CASE
                WHEN (
                    SELECT COUNT(*)
                    FROM bronze.census_demographics_raw
                    WHERE UPPER(TRIM(raw_record ->> 'State name')) = 'JHARKHAND'
                ) = (
                    SELECT COUNT(*)
                    FROM silver.fact_district_demographics
                )
                THEN 0
                ELSE 1
            END
        """,
    ),
    DQCheck(
        "DQ-024",
        "SILVER",
        "silver.fact_district_housing",
        "Housing Bronze-to-Silver row reconciliation",
        """
        SELECT
            CASE
                WHEN (
                    SELECT COUNT(*)
                    FROM bronze.census_housing_raw
                    WHERE UPPER(TRIM(raw_record ->> 'State Name')) = 'JHARKHAND'
                      AND LOWER(TRIM(raw_record ->> 'Rural/Urban')) = 'total'
                ) = (
                    SELECT COUNT(*)
                    FROM silver.fact_district_housing
                )
                THEN 0
                ELSE 1
            END
        """,
    ),
    DQCheck(
        "DQ-025",
        "BRONZE",
        "bronze.ingestion_metadata",
        "Bronze ingestion metadata row-count reconciliation",
        """
        WITH raw_counts AS (
            SELECT ingestion_id, COUNT(*) AS actual_rows
            FROM bronze.census_demographics_raw
            GROUP BY ingestion_id

            UNION ALL

            SELECT ingestion_id, COUNT(*)
            FROM bronze.census_housing_raw
            GROUP BY ingestion_id

            UNION ALL

            SELECT ingestion_id, COUNT(*)
            FROM bronze.nsap_pension_raw
            GROUP BY ingestion_id
        ),
        combined AS (
            SELECT
                ingestion_id,
                SUM(actual_rows) AS actual_rows
            FROM raw_counts
            GROUP BY ingestion_id
        )
        SELECT COUNT(*)
        FROM bronze.ingestion_metadata m
        LEFT JOIN combined r USING (ingestion_id)
        WHERE m.status = 'SUCCEEDED'
          AND (
              m.source_row_count <> COALESCE(r.actual_rows, 0)
              OR m.loaded_row_count <> COALESCE(r.actual_rows, 0)
          )
        """,
    ),
    DQCheck(
        "DQ-026",
        "BRONZE",
        "bronze.ingestion_metadata",
        "Required source ingestion freshness",
        """
        WITH required_sources(source_name) AS (
            VALUES
                ('Census District Demographics'),
                ('Census District Housing'),
                ('National Social Assistance Programme')
        )
        SELECT COUNT(*)
        FROM required_sources s
        WHERE NOT EXISTS (
            SELECT 1
            FROM bronze.ingestion_metadata m
            WHERE m.source_name = s.source_name
              AND m.status = 'SUCCEEDED'
              AND m.completed_at >=
                    CURRENT_TIMESTAMP - INTERVAL '30 days'
        )
        """,
        severity="WARNING",
        expected_value="All 3 source ingestions completed within 30 days",
    ),
)
