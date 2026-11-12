
BEGIN;

-- ============================================================
-- 1. SOURCE VALIDATION
-- Expected: 24 Jharkhand demographic records.
-- ============================================================

DO $$
DECLARE
    source_rows BIGINT;
    unique_districts BIGINT;
    invalid_numeric_values BIGINT;
    invalid_demographics BIGINT;
    missing_districts BIGINT;
BEGIN

    SELECT
        COUNT(*),
        COUNT(DISTINCT NULLIF(
            TRIM(raw_record ->> 'District code'), ''
        )::INTEGER)
    INTO source_rows, unique_districts
    FROM bronze.census_demographics_raw
    WHERE UPPER(TRIM(raw_record ->> 'State name')) = 'JHARKHAND';

    IF source_rows <> 24 OR unique_districts <> 24 THEN
        RAISE EXCEPTION
            'Expected 24 unique demographic districts. Found rows: %, unique districts: %',
            source_rows, unique_districts;
    END IF;


    -- Check all required numeric fields.

    SELECT COUNT(*)
    INTO invalid_numeric_values
    FROM bronze.census_demographics_raw b
    CROSS JOIN LATERAL (
        VALUES
            (b.raw_record ->> 'District code'),
            (b.raw_record ->> 'Population'),
            (b.raw_record ->> 'Male'),
            (b.raw_record ->> 'Female'),
            (b.raw_record ->> 'Literate'),
            (b.raw_record ->> 'Workers'),
            (b.raw_record ->> 'SC'),
            (b.raw_record ->> 'ST'),
            (b.raw_record ->> 'Households'),
            (b.raw_record ->> 'Age_Group_0_29'),
            (b.raw_record ->> 'Age_Group_30_49'),
            (b.raw_record ->> 'Age_Group_50'),
            (b.raw_record ->> 'Age not stated')
    ) AS v(raw_value)
    WHERE UPPER(TRIM(b.raw_record ->> 'State name')) = 'JHARKHAND'
      AND (
          v.raw_value IS NULL
          OR TRIM(v.raw_value) = ''
          OR TRIM(v.raw_value) !~
             '^([0-9]+|[0-9]{1,3}(,[0-9]{3})+)$'
      );

    IF invalid_numeric_values > 0 THEN
        RAISE EXCEPTION
            'Invalid demographic numeric values found: %',
            invalid_numeric_values;
    END IF;


    -- Validate demographic business rules.

    SELECT COUNT(*)
    INTO invalid_demographics
    FROM bronze.census_demographics_raw b
    WHERE UPPER(TRIM(b.raw_record ->> 'State name')) = 'JHARKHAND'
      AND (
          REPLACE(b.raw_record ->> 'Population', ',', '')::BIGINT <= 0

          OR
          REPLACE(b.raw_record ->> 'Male', ',', '')::BIGINT
          +
          REPLACE(b.raw_record ->> 'Female', ',', '')::BIGINT
          <>
          REPLACE(b.raw_record ->> 'Population', ',', '')::BIGINT

          OR
          REPLACE(b.raw_record ->> 'Literate', ',', '')::BIGINT
          >
          REPLACE(b.raw_record ->> 'Population', ',', '')::BIGINT

          OR
          REPLACE(b.raw_record ->> 'Workers', ',', '')::BIGINT
          >
          REPLACE(b.raw_record ->> 'Population', ',', '')::BIGINT

          OR
          REPLACE(b.raw_record ->> 'Households', ',', '')::BIGINT <= 0

          OR
          REPLACE(b.raw_record ->> 'Households', ',', '')::BIGINT
          >
          REPLACE(b.raw_record ->> 'Population', ',', '')::BIGINT

          OR
          REPLACE(b.raw_record ->> 'SC', ',', '')::BIGINT
          >
          REPLACE(b.raw_record ->> 'Population', ',', '')::BIGINT

          OR
          REPLACE(b.raw_record ->> 'ST', ',', '')::BIGINT
          >
          REPLACE(b.raw_record ->> 'Population', ',', '')::BIGINT

          OR
          REPLACE(b.raw_record ->> 'Age_Group_0_29', ',', '')::BIGINT
          +
          REPLACE(b.raw_record ->> 'Age_Group_30_49', ',', '')::BIGINT
          +
          REPLACE(b.raw_record ->> 'Age_Group_50', ',', '')::BIGINT
          +
          REPLACE(b.raw_record ->> 'Age not stated', ',', '')::BIGINT
          <>
          REPLACE(b.raw_record ->> 'Population', ',', '')::BIGINT
      );

    IF invalid_demographics > 0 THEN
        RAISE EXCEPTION
            'Demographic business-rule violations detected: %',
            invalid_demographics;
    END IF;


    -- Verify district dimension matching.

    SELECT COUNT(*)
    INTO missing_districts
    FROM bronze.census_demographics_raw b
    LEFT JOIN silver.dim_district d
        ON d.district_code =
           (b.raw_record ->> 'District code')::SMALLINT
       AND d.district_name_normalized =
           REGEXP_REPLACE(
               LOWER(TRIM(b.raw_record ->> 'District name')),
               '[^a-z0-9]',
               '',
               'g'
           )
    WHERE UPPER(TRIM(b.raw_record ->> 'State name')) = 'JHARKHAND'
      AND d.district_code IS NULL;

    IF missing_districts > 0 THEN
        RAISE EXCEPTION
            'Unmatched demographic districts found: %',
            missing_districts;
    END IF;

END $$;


-- ============================================================
-- 2. CREATE VALIDATED STAGING DATA
-- Grain: One row per Jharkhand district.
-- ============================================================

CREATE TEMP TABLE demographic_stage
ON COMMIT DROP
AS

SELECT

    d.district_code,

    REPLACE(d.population, ',', '')::BIGINT
        AS total_population,

    REPLACE(d.male, ',', '')::BIGINT
        AS male_population,

    REPLACE(d.female, ',', '')::BIGINT
        AS female_population,

    REPLACE(d.literate, ',', '')::BIGINT
        AS literate_population,

    REPLACE(d.workers, ',', '')::BIGINT
        AS total_workers,

    REPLACE(d.sc, ',', '')::BIGINT
        AS sc_population,

    REPLACE(d.st, ',', '')::BIGINT
        AS st_population,

    REPLACE(d.households, ',', '')::BIGINT
        AS total_households,

    REPLACE(d.age_50, ',', '')::BIGINT
        AS age_50_plus_population,

    d.source_file_name,

    d.source_sha256,

    d.source_row_number,

    d.ingestion_id

FROM (

    SELECT
        (raw_record ->> 'District code')::SMALLINT
            AS district_code,

        raw_record ->> 'Population' AS population,
        raw_record ->> 'Male' AS male,
        raw_record ->> 'Female' AS female,
        raw_record ->> 'Literate' AS literate,
        raw_record ->> 'Workers' AS workers,
        raw_record ->> 'SC' AS sc,
        raw_record ->> 'ST' AS st,
        raw_record ->> 'Households' AS households,
        raw_record ->> 'Age_Group_50' AS age_50,

        source_file_name,
        source_sha256,
        source_row_number,
        ingestion_id

    FROM bronze.census_demographics_raw

    WHERE UPPER(TRIM(raw_record ->> 'State name')) = 'JHARKHAND'

) d;


-- ============================================================
-- 3. STAGING RECONCILIATION
-- ============================================================

DO $$
DECLARE
    staged_rows BIGINT;
    unique_districts BIGINT;
BEGIN

    SELECT
        COUNT(*),
        COUNT(DISTINCT district_code)
    INTO staged_rows, unique_districts
    FROM demographic_stage;

    IF staged_rows <> 24 OR unique_districts <> 24 THEN
        RAISE EXCEPTION
            'Staging reconciliation failed. Rows: %, unique districts: %',
            staged_rows, unique_districts;
    END IF;

END $$;


-- ============================================================
-- 4. INSERT INTO SILVER DEMOGRAPHICS FACT
-- Idempotent using district_code as the business key.
-- ============================================================

INSERT INTO silver.fact_district_demographics (

    district_code,
    total_population,
    male_population,
    female_population,
    literate_population,
    total_workers,
    sc_population,
    st_population,
    total_households,
    age_50_plus_population,
    source_file_name,
    source_sha256,
    source_row_number,
    ingestion_id

)

SELECT
    district_code,
    total_population,
    male_population,
    female_population,
    literate_population,
    total_workers,
    sc_population,
    st_population,
    total_households,
    age_50_plus_population,
    source_file_name,
    source_sha256,
    source_row_number,
    ingestion_id

FROM demographic_stage

ON CONFLICT (district_code)
DO UPDATE SET

    total_population = EXCLUDED.total_population,

    male_population = EXCLUDED.male_population,

    female_population = EXCLUDED.female_population,

    literate_population = EXCLUDED.literate_population,

    total_workers = EXCLUDED.total_workers,

    sc_population = EXCLUDED.sc_population,

    st_population = EXCLUDED.st_population,

    total_households = EXCLUDED.total_households,

    age_50_plus_population = EXCLUDED.age_50_plus_population,

    source_file_name = EXCLUDED.source_file_name,

    source_sha256 = EXCLUDED.source_sha256,

    source_row_number = EXCLUDED.source_row_number,

    ingestion_id = EXCLUDED.ingestion_id,

    loaded_at = CURRENT_TIMESTAMP;


-- ============================================================
-- 5. POST-LOAD VALIDATION
-- ============================================================

DO $$
DECLARE
    fact_rows BIGINT;
    unmatched_rows BIGINT;
BEGIN

    SELECT COUNT(*)
    INTO fact_rows
    FROM silver.fact_district_demographics;

    IF fact_rows <> 24 THEN
        RAISE EXCEPTION
            'Expected 24 demographic fact records. Found: %',
            fact_rows;
    END IF;

    SELECT COUNT(*)
    INTO unmatched_rows
    FROM silver.dim_district d
    LEFT JOIN silver.fact_district_demographics f
        ON d.district_code = f.district_code
    WHERE f.district_code IS NULL;

    IF unmatched_rows > 0 THEN
        RAISE EXCEPTION
            'Districts missing from demographic fact: %',
            unmatched_rows;
    END IF;

END $$;

COMMIT;

