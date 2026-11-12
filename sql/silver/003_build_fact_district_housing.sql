
BEGIN;

-- ============================================================
-- 1. SCHEMA UPDATE
-- Preserve all relevant housing indicators.
-- ============================================================

ALTER TABLE silver.fact_district_housing
    ADD COLUMN IF NOT EXISTS serviceable_pct NUMERIC(6,2);

ALTER TABLE silver.fact_district_housing
    ADD COLUMN IF NOT EXISTS unclassifiable_pct NUMERIC(6,2);


-- Rebuild percentage validation constraint.

ALTER TABLE silver.fact_district_housing
    DROP CONSTRAINT IF EXISTS ck_housing_percentages;

ALTER TABLE silver.fact_district_housing
    ADD CONSTRAINT ck_housing_percentages CHECK (

        (household_reference_base_pct BETWEEN 0 AND 100)

        AND (good_housing_pct BETWEEN 0 AND 100)

        AND (livable_housing_pct BETWEEN 0 AND 100)

        AND (dilapidated_housing_pct BETWEEN 0 AND 100)

        AND (residential_households_pct BETWEEN 0 AND 100)

        AND (residential_good_pct BETWEEN 0 AND 100)

        AND (residential_livable_pct BETWEEN 0 AND 100)

        AND (residential_dilapidated_pct BETWEEN 0 AND 100)

        AND (permanent_housing_pct BETWEEN 0 AND 100)

        AND (semi_permanent_housing_pct BETWEEN 0 AND 100)

        AND (temporary_housing_pct BETWEEN 0 AND 100)

        AND (non_serviceable_housing_pct BETWEEN 0 AND 100)

        AND (serviceable_pct BETWEEN 0 AND 100)

        AND (unclassifiable_pct BETWEEN 0 AND 100)

    );


-- ============================================================
-- 2. SOURCE VALIDATION
-- Expected: 24 unique Jharkhand district records.
-- ============================================================

DO $$
DECLARE

    source_rows BIGINT;
    unique_districts BIGINT;
    invalid_state_codes BIGINT;
    invalid_numeric_values BIGINT;
    invalid_percentage_values BIGINT;
    district_matching_failures BIGINT;
    housing_condition_failures BIGINT;
    residential_condition_failures BIGINT;

BEGIN

    SELECT
        COUNT(*),
        COUNT(DISTINCT NULLIF(
            TRIM(raw_record ->> 'District Code'), ''
        )),
        COUNT(*) FILTER (
            WHERE TRIM(raw_record ->> 'State Code') <> '20'
        )

    INTO
        source_rows,
        unique_districts,
        invalid_state_codes

    FROM bronze.census_housing_raw

    WHERE UPPER(TRIM(raw_record ->> 'State Name')) = 'JHARKHAND'
      AND LOWER(TRIM(raw_record ->> 'Rural/Urban')) = 'total';


    IF source_rows <> 24 OR unique_districts <> 24 THEN

        RAISE EXCEPTION
            'Housing source reconciliation failed. Rows: %, Unique districts: %',
            source_rows, unique_districts;

    END IF;


    IF invalid_state_codes > 0 THEN

        RAISE EXCEPTION
            'Invalid Jharkhand state codes found: %',
            invalid_state_codes;

    END IF;


    -- Validate required percentage fields.

    SELECT COUNT(*)
    INTO invalid_numeric_values

    FROM bronze.census_housing_raw h

    CROSS JOIN LATERAL (

        VALUES
            (h.raw_record ->> 'Total Number of households'),
            (h.raw_record ->> 'Total Number of Good'),
            (h.raw_record ->> 'Total Number of Livable'),
            (h.raw_record ->> 'Total Number of Dilapidated'),
            (h.raw_record ->> 'Total Number of Residence households'),
            (h.raw_record ->> 'Total Number of Residence Good'),
            (h.raw_record ->> 'Total Number of Residence Livable'),
            (h.raw_record ->> 'Total Number of Residence Dilapidated'),
            (h.raw_record ->> 'Permanents'),
            (h.raw_record ->> 'Semi_Permanent'),
            (h.raw_record ->> 'Total_Temporary'),
            (h.raw_record ->> 'Non_Serviceable'),
            (h.raw_record ->> 'Serviceable'),
            (h.raw_record ->> 'Unclassifiable')

    ) AS v(raw_value)

    WHERE UPPER(TRIM(h.raw_record ->> 'State Name')) = 'JHARKHAND'
      AND LOWER(TRIM(h.raw_record ->> 'Rural/Urban')) = 'total'

      AND (
          v.raw_value IS NULL
          OR TRIM(v.raw_value) = ''
          OR TRIM(v.raw_value) !~
             '^([0-9]+|[0-9]{1,3}(,[0-9]{3})+)(\.[0-9]+)?$'
      );


    IF invalid_numeric_values > 0 THEN

        RAISE EXCEPTION
            'Invalid housing numeric values detected: %',
            invalid_numeric_values;

    END IF;


    -- Ensure percentages are between zero and one hundred.

    SELECT COUNT(*)
    INTO invalid_percentage_values

    FROM bronze.census_housing_raw h

    CROSS JOIN LATERAL (

        VALUES
            (h.raw_record ->> 'Total Number of households'),
            (h.raw_record ->> 'Total Number of Good'),
            (h.raw_record ->> 'Total Number of Livable'),
            (h.raw_record ->> 'Total Number of Dilapidated'),
            (h.raw_record ->> 'Total Number of Residence households'),
            (h.raw_record ->> 'Total Number of Residence Good'),
            (h.raw_record ->> 'Total Number of Residence Livable'),
            (h.raw_record ->> 'Total Number of Residence Dilapidated'),
            (h.raw_record ->> 'Permanents'),
            (h.raw_record ->> 'Semi_Permanent'),
            (h.raw_record ->> 'Total_Temporary'),
            (h.raw_record ->> 'Non_Serviceable'),
            (h.raw_record ->> 'Serviceable'),
            (h.raw_record ->> 'Unclassifiable')

    ) AS v(raw_value)

    WHERE UPPER(TRIM(h.raw_record ->> 'State Name')) = 'JHARKHAND'
      AND LOWER(TRIM(h.raw_record ->> 'Rural/Urban')) = 'total'

      AND (
          CASE
              WHEN TRIM(v.raw_value) ~
                  '^([0-9]+|[0-9]{1,3}(,[0-9]{3})+)(\.[0-9]+)?$'

              THEN
                  REPLACE(TRIM(v.raw_value), ',', '')::NUMERIC
                  NOT BETWEEN 0 AND 100

              ELSE TRUE
          END
      );


    IF invalid_percentage_values > 0 THEN

        RAISE EXCEPTION
            'Housing percentage values outside the valid range: %',
            invalid_percentage_values;

    END IF;


    -- Verify district code and normalized name matching.

    SELECT COUNT(*)

    INTO district_matching_failures

    FROM bronze.census_housing_raw h

    LEFT JOIN silver.dim_district d

        ON d.district_code =
           (h.raw_record ->> 'District Code')::SMALLINT

    WHERE UPPER(TRIM(h.raw_record ->> 'State Name')) = 'JHARKHAND'
      AND LOWER(TRIM(h.raw_record ->> 'Rural/Urban')) = 'total'

      AND (
          d.district_code IS NULL

          OR d.district_name_normalized IS DISTINCT FROM
             REGEXP_REPLACE(
                 LOWER(TRIM(h.raw_record ->> 'District Name')),
                 '[^a-z0-9]',
                 '',
                 'g'
             )
      );


    IF district_matching_failures > 0 THEN

        RAISE EXCEPTION
            'District matching failures detected: %',
            district_matching_failures;

    END IF;


    -- Validate general housing composition.

    SELECT COUNT(*)

    INTO housing_condition_failures

    FROM bronze.census_housing_raw h

    WHERE UPPER(TRIM(h.raw_record ->> 'State Name')) = 'JHARKHAND'
      AND LOWER(TRIM(h.raw_record ->> 'Rural/Urban')) = 'total'

      AND ABS(

          REPLACE(h.raw_record ->> 'Total Number of Good', ',', '')::NUMERIC

          +

          REPLACE(h.raw_record ->> 'Total Number of Livable', ',', '')::NUMERIC

          +

          REPLACE(h.raw_record ->> 'Total Number of Dilapidated', ',', '')::NUMERIC

          - 100

      ) > 0.2;


    IF housing_condition_failures > 0 THEN

        RAISE EXCEPTION
            'Housing condition reconciliation failures: %',
            housing_condition_failures;

    END IF;


    -- Validate residential housing composition.

    SELECT COUNT(*)

    INTO residential_condition_failures

    FROM bronze.census_housing_raw h

    WHERE UPPER(TRIM(h.raw_record ->> 'State Name')) = 'JHARKHAND'
      AND LOWER(TRIM(h.raw_record ->> 'Rural/Urban')) = 'total'

      AND ABS(

          REPLACE(
              h.raw_record ->> 'Total Number of Residence households',
              ',', ''
          )::NUMERIC

          -

          REPLACE(
              h.raw_record ->> 'Total Number of Residence Good',
              ',', ''
          )::NUMERIC

          -

          REPLACE(
              h.raw_record ->> 'Total Number of Residence Livable',
              ',', ''
          )::NUMERIC

          -

          REPLACE(
              h.raw_record ->> 'Total Number of Residence Dilapidated',
              ',', ''
          )::NUMERIC

      ) > 0.2;


    IF residential_condition_failures > 0 THEN

        RAISE EXCEPTION
            'Residential housing reconciliation failures: %',
            residential_condition_failures;

    END IF;

END $$;


-- ============================================================
-- 3. CREATE VALIDATED HOUSING STAGING TABLE
-- Grain: One record per Jharkhand district.
-- ============================================================

CREATE TEMP TABLE housing_stage
ON COMMIT DROP
AS

SELECT

    d.district_code,

    REPLACE(
        h.raw_record ->> 'Total Number of households',
        ',',
        ''
    )::NUMERIC(6,2) AS household_reference_base_pct,

    REPLACE(
        h.raw_record ->> 'Total Number of Good',
        ',',
        ''
    )::NUMERIC(6,2) AS good_housing_pct,

    REPLACE(
        h.raw_record ->> 'Total Number of Livable',
        ',',
        ''
    )::NUMERIC(6,2) AS livable_housing_pct,

    REPLACE(
        h.raw_record ->> 'Total Number of Dilapidated',
        ',',
        ''
    )::NUMERIC(6,2) AS dilapidated_housing_pct,

    REPLACE(
        h.raw_record ->> 'Total Number of Residence households',
        ',',
        ''
    )::NUMERIC(6,2) AS residential_households_pct,

    REPLACE(
        h.raw_record ->> 'Total Number of Residence Good',
        ',',
        ''
    )::NUMERIC(6,2) AS residential_good_pct,

    REPLACE(
        h.raw_record ->> 'Total Number of Residence Livable',
        ',',
        ''
    )::NUMERIC(6,2) AS residential_livable_pct,

    REPLACE(
        h.raw_record ->> 'Total Number of Residence Dilapidated',
        ',',
        ''
    )::NUMERIC(6,2) AS residential_dilapidated_pct,

    REPLACE(
        h.raw_record ->> 'Permanents',
        ',',
        ''
    )::NUMERIC(6,2) AS permanent_housing_pct,

    REPLACE(
        h.raw_record ->> 'Semi_Permanent',
        ',',
        ''
    )::NUMERIC(6,2) AS semi_permanent_housing_pct,

    REPLACE(
        h.raw_record ->> 'Total_Temporary',
        ',',
        ''
    )::NUMERIC(6,2) AS temporary_housing_pct,

    REPLACE(
        h.raw_record ->> 'Non_Serviceable',
        ',',
        ''
    )::NUMERIC(6,2) AS non_serviceable_housing_pct,

    REPLACE(
        h.raw_record ->> 'Serviceable',
        ',',
        ''
    )::NUMERIC(6,2) AS serviceable_pct,

    REPLACE(
        h.raw_record ->> 'Unclassifiable',
        ',',
        ''
    )::NUMERIC(6,2) AS unclassifiable_pct,

    h.source_file_name,

    h.source_sha256,

    h.source_row_number,

    h.ingestion_id

FROM bronze.census_housing_raw h

INNER JOIN silver.dim_district d

    ON d.district_code =
       (h.raw_record ->> 'District Code')::SMALLINT

   AND d.district_name_normalized =
       REGEXP_REPLACE(
           LOWER(TRIM(h.raw_record ->> 'District Name')),
           '[^a-z0-9]',
           '',
           'g'
       )

WHERE UPPER(TRIM(h.raw_record ->> 'State Name')) = 'JHARKHAND'
  AND LOWER(TRIM(h.raw_record ->> 'Rural/Urban')) = 'total';


-- ============================================================
-- 4. STAGING RECONCILIATION
-- ============================================================

DO $$
DECLARE

    staged_rows BIGINT;
    unique_districts BIGINT;

BEGIN

    SELECT
        COUNT(*),
        COUNT(DISTINCT district_code)

    INTO
        staged_rows,
        unique_districts

    FROM housing_stage;


    IF staged_rows <> 24 OR unique_districts <> 24 THEN

        RAISE EXCEPTION
            'Housing staging reconciliation failed. Rows: %, Unique districts: %',
            staged_rows, unique_districts;

    END IF;

END $$;


-- ============================================================
-- 5. INSERT INTO SILVER HOUSING FACT
-- Idempotent using district_code as the business key.
-- ============================================================

INSERT INTO silver.fact_district_housing (

    district_code,

    household_reference_base_pct,

    good_housing_pct,

    livable_housing_pct,

    dilapidated_housing_pct,

    residential_households_pct,

    residential_good_pct,

    residential_livable_pct,

    residential_dilapidated_pct,

    permanent_housing_pct,

    semi_permanent_housing_pct,

    temporary_housing_pct,

    non_serviceable_housing_pct,

    serviceable_pct,

    unclassifiable_pct,

    source_file_name,

    source_sha256,

    source_row_number,

    ingestion_id

)

SELECT

    district_code,

    household_reference_base_pct,

    good_housing_pct,

    livable_housing_pct,

    dilapidated_housing_pct,

    residential_households_pct,

    residential_good_pct,

    residential_livable_pct,

    residential_dilapidated_pct,

    permanent_housing_pct,

    semi_permanent_housing_pct,

    temporary_housing_pct,

    non_serviceable_housing_pct,

    serviceable_pct,

    unclassifiable_pct,

    source_file_name,

    source_sha256,

    source_row_number,

    ingestion_id

FROM housing_stage

ON CONFLICT (district_code)

DO UPDATE SET

    household_reference_base_pct =
        EXCLUDED.household_reference_base_pct,

    good_housing_pct =
        EXCLUDED.good_housing_pct,

    livable_housing_pct =
        EXCLUDED.livable_housing_pct,

    dilapidated_housing_pct =
        EXCLUDED.dilapidated_housing_pct,

    residential_households_pct =
        EXCLUDED.residential_households_pct,

    residential_good_pct =
        EXCLUDED.residential_good_pct,

    residential_livable_pct =
        EXCLUDED.residential_livable_pct,

    residential_dilapidated_pct =
        EXCLUDED.residential_dilapidated_pct,

    permanent_housing_pct =
        EXCLUDED.permanent_housing_pct,

    semi_permanent_housing_pct =
        EXCLUDED.semi_permanent_housing_pct,

    temporary_housing_pct =
        EXCLUDED.temporary_housing_pct,

    non_serviceable_housing_pct =
        EXCLUDED.non_serviceable_housing_pct,

    serviceable_pct =
        EXCLUDED.serviceable_pct,

    unclassifiable_pct =
        EXCLUDED.unclassifiable_pct,

    source_file_name =
        EXCLUDED.source_file_name,

    source_sha256 =
        EXCLUDED.source_sha256,

    source_row_number =
        EXCLUDED.source_row_number,

    ingestion_id =
        EXCLUDED.ingestion_id,

    loaded_at = CURRENT_TIMESTAMP;


-- ============================================================
-- 6. POST-LOAD VALIDATION
-- ============================================================

DO $$
DECLARE

    fact_rows BIGINT;
    missing_districts BIGINT;

BEGIN

    SELECT COUNT(*)
    INTO fact_rows

    FROM silver.fact_district_housing;


    IF fact_rows <> 24 THEN

        RAISE EXCEPTION
            'Expected 24 housing fact records. Found: %',
            fact_rows;

    END IF;


    SELECT COUNT(*)

    INTO missing_districts

    FROM silver.dim_district d

    LEFT JOIN silver.fact_district_housing h

        ON d.district_code = h.district_code

    WHERE h.district_code IS NULL;


    IF missing_districts > 0 THEN

        RAISE EXCEPTION
            'Districts missing from housing fact: %',
            missing_districts;

    END IF;

END $$;


-- ============================================================
-- 7. DOCUMENTATION
-- ============================================================

COMMENT ON COLUMN silver.fact_district_housing.serviceable_pct IS
'Percentage of households classified as serviceable in the source housing dataset.';

COMMENT ON COLUMN silver.fact_district_housing.unclassifiable_pct IS
'Percentage of households with unclassifiable housing status in the source dataset.';


COMMIT;

