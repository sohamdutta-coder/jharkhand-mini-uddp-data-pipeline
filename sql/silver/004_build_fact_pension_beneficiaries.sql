
BEGIN;

-- ============================================================
-- 1. SOURCE VALIDATION
-- ============================================================

DO $$
DECLARE
    total_rows BIGINT;
    administrative_units BIGINT;
    grand_total_rows BIGINT;
    invalid_categories BIGINT;
    invalid_numeric_values BIGINT;
BEGIN

    SELECT COUNT(*)
    INTO total_rows
    FROM bronze.nsap_pension_raw;

    IF total_rows <> 37 THEN
        RAISE EXCEPTION
            'Expected 37 NSAP source rows. Found: %',
            total_rows;
    END IF;


    SELECT
        COUNT(*),
        COUNT(DISTINCT
            REGEXP_REPLACE(
                LOWER(TRIM(raw_record ->> 'States/UTs')),
                '[^a-z0-9]',
                '',
                'g'
            )
        )
    INTO administrative_units, grand_total_rows
    FROM bronze.nsap_pension_raw
    WHERE LOWER(TRIM(raw_record ->> 'States/UTs')) <> 'grand total';


    IF administrative_units <> 36
       OR grand_total_rows <> 36 THEN
        RAISE EXCEPTION
            'Expected 36 unique administrative units. Found: %, unique: %',
            administrative_units, grand_total_rows;
    END IF;


    SELECT COUNT(*)
    INTO grand_total_rows
    FROM bronze.nsap_pension_raw
    WHERE LOWER(TRIM(raw_record ->> 'States/UTs')) = 'grand total';

    IF grand_total_rows <> 1 THEN
        RAISE EXCEPTION
            'Expected exactly one Grand Total row. Found: %',
            grand_total_rows;
    END IF;


    SELECT COUNT(*)
    INTO invalid_categories
    FROM bronze.nsap_pension_raw
    WHERE LOWER(TRIM(raw_record ->> 'States/UTs')) <> 'grand total'
      AND TRIM(raw_record ->> 'Category') NOT IN (
          'State',
          'NE States',
          'Union Territories'
      );

    IF invalid_categories > 0 THEN
        RAISE EXCEPTION
            'Invalid NSAP administrative categories: %',
            invalid_categories;
    END IF;


    -- Validate all three pension beneficiary fields.

    SELECT COUNT(*)
    INTO invalid_numeric_values

    FROM bronze.nsap_pension_raw b

    CROSS JOIN LATERAL (
        VALUES
            (b.raw_record ->> 'Old Age Pension Scheme'),
            (b.raw_record ->> 'Widow Pension Scheme'),
            (b.raw_record ->> 'Divyangjan /Disability Pension Scheme')
    ) AS v(raw_value)

    WHERE v.raw_value IS NULL
       OR TRIM(v.raw_value) = ''
       OR TRIM(v.raw_value) !~
          '^([0-9]+|[0-9]{1,3}(,[0-9]{3})+)$';


    IF invalid_numeric_values > 0 THEN
        RAISE EXCEPTION
            'Invalid NSAP beneficiary counts found: %',
            invalid_numeric_values;
    END IF;


    -- Validate source Grand Total against administrative totals.

    IF EXISTS (

        WITH calculated AS (
            SELECT
                SUM(REPLACE(raw_record ->> 'Old Age Pension Scheme',
                    ',', '')::BIGINT) AS old_age,

                SUM(REPLACE(raw_record ->> 'Widow Pension Scheme',
                    ',', '')::BIGINT) AS widow,

                SUM(REPLACE(raw_record ->> 'Divyangjan /Disability Pension Scheme',
                    ',', '')::BIGINT) AS disability

            FROM bronze.nsap_pension_raw

            WHERE LOWER(TRIM(raw_record ->> 'States/UTs'))
                <> 'grand total'
        ),

        reported AS (
            SELECT
                REPLACE(raw_record ->> 'Old Age Pension Scheme',
                    ',', '')::BIGINT AS old_age,

                REPLACE(raw_record ->> 'Widow Pension Scheme',
                    ',', '')::BIGINT AS widow,

                REPLACE(raw_record ->> 'Divyangjan /Disability Pension Scheme',
                    ',', '')::BIGINT AS disability

            FROM bronze.nsap_pension_raw

            WHERE LOWER(TRIM(raw_record ->> 'States/UTs'))
                = 'grand total'
        )

        SELECT 1
        FROM calculated c
        CROSS JOIN reported r

        WHERE c.old_age <> r.old_age
           OR c.widow <> r.widow
           OR c.disability <> r.disability

    ) THEN

        RAISE EXCEPTION
            'NSAP Grand Total does not reconcile with administrative-unit totals.';

    END IF;

END $$;


-- ============================================================
-- 2. UNPIVOT PENSION SCHEME COLUMNS
-- Grain: One row per administrative unit and scheme.
-- ============================================================

CREATE TEMP TABLE pension_stage
ON COMMIT DROP
AS

SELECT

    TRIM(b.raw_record ->> 'States/UTs')
        AS administrative_unit_name,

    REGEXP_REPLACE(
        LOWER(TRIM(b.raw_record ->> 'States/UTs')),
        '[^a-z0-9]',
        '',
        'g'
    ) AS administrative_unit_normalized,

    TRIM(b.raw_record ->> 'Category')
        AS administrative_category,

    v.pension_scheme,

    REPLACE(TRIM(v.beneficiary_count), ',', '')::BIGINT
        AS beneficiary_count,

    b.source_file_name,

    b.source_sha256,

    b.source_row_number,

    b.ingestion_id

FROM bronze.nsap_pension_raw b

CROSS JOIN LATERAL (

    VALUES

        (
            'OLD_AGE',
            b.raw_record ->> 'Old Age Pension Scheme'
        ),

        (
            'WIDOW',
            b.raw_record ->> 'Widow Pension Scheme'
        ),

        (
            'DISABILITY',
            b.raw_record ->> 'Divyangjan /Disability Pension Scheme'
        )

) AS v(pension_scheme, beneficiary_count)

WHERE LOWER(TRIM(b.raw_record ->> 'States/UTs'))
      <> 'grand total';


-- ============================================================
-- 3. STAGING RECONCILIATION
-- ============================================================

DO $$
DECLARE
    staged_rows BIGINT;
    unique_units BIGINT;
    unique_schemes BIGINT;
BEGIN

    SELECT
        COUNT(*),
        COUNT(DISTINCT administrative_unit_normalized),
        COUNT(DISTINCT pension_scheme)

    INTO
        staged_rows,
        unique_units,
        unique_schemes

    FROM pension_stage;


    IF staged_rows <> 108
       OR unique_units <> 36
       OR unique_schemes <> 3 THEN

        RAISE EXCEPTION
            'Pension staging reconciliation failed. Rows: %, Units: %, Schemes: %',
            staged_rows, unique_units, unique_schemes;

    END IF;

END $$;


-- ============================================================
-- 4. INSERT INTO SILVER PENSION FACT
-- Idempotent using administrative unit and scheme.
-- ============================================================

INSERT INTO silver.fact_pension_beneficiaries (

    administrative_unit_name,

    administrative_unit_normalized,

    administrative_category,

    pension_scheme,

    beneficiary_count,

    source_file_name,

    source_sha256,

    source_row_number,

    ingestion_id

)

SELECT

    administrative_unit_name,

    administrative_unit_normalized,

    administrative_category,

    pension_scheme,

    beneficiary_count,

    source_file_name,

    source_sha256,

    source_row_number,

    ingestion_id

FROM pension_stage

ON CONFLICT (
    administrative_unit_normalized,
    pension_scheme
)

DO UPDATE SET

    administrative_unit_name =
        EXCLUDED.administrative_unit_name,

    administrative_category =
        EXCLUDED.administrative_category,

    beneficiary_count =
        EXCLUDED.beneficiary_count,

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
-- 5. POST-LOAD VALIDATION
-- ============================================================

DO $$
DECLARE
    fact_rows BIGINT;
    distinct_units BIGINT;
BEGIN

    SELECT
        COUNT(*),
        COUNT(DISTINCT administrative_unit_normalized)

    INTO
        fact_rows,
        distinct_units

    FROM silver.fact_pension_beneficiaries;


    IF fact_rows <> 108 OR distinct_units <> 36 THEN

        RAISE EXCEPTION
            'Pension fact validation failed. Rows: %, Units: %',
            fact_rows, distinct_units;

    END IF;

END $$;


-- ============================================================
-- 6. DOCUMENTATION
-- ============================================================

COMMENT ON TABLE silver.fact_pension_beneficiaries IS
'State/UT-level pension beneficiaries by scheme. Grand Total is excluded. District-level pension counts are not available in the source.';


COMMIT;

