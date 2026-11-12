
BEGIN;

-- 1. SOURCE INTEGRITY VALIDATION

DO $$
DECLARE
    demo_rows BIGINT;
    demo_codes BIGINT;
    housing_rows BIGINT;
    housing_codes BIGINT;
    name_mismatches BIGINT;
    invalid_state_codes BIGINT;
BEGIN

    SELECT
        COUNT(*),
        COUNT(DISTINCT NULLIF(
            TRIM(raw_record ->> 'District code'), ''
        ))
    INTO demo_rows, demo_codes
    FROM bronze.census_demographics_raw
    WHERE UPPER(TRIM(raw_record ->> 'State name')) = 'JHARKHAND';

    SELECT
        COUNT(*),
        COUNT(DISTINCT NULLIF(
            TRIM(raw_record ->> 'District Code'), ''
        )),
        COUNT(*) FILTER (
            WHERE COALESCE(
                NULLIF(TRIM(raw_record ->> 'State Code'), ''),
                ''
            ) <> '20'
        )
    INTO housing_rows, housing_codes, invalid_state_codes
    FROM bronze.census_housing_raw
    WHERE UPPER(TRIM(raw_record ->> 'State Name')) = 'JHARKHAND'
      AND LOWER(TRIM(raw_record ->> 'Rural/Urban')) = 'total';

    IF demo_rows <> 24 OR demo_codes <> 24 THEN
        RAISE EXCEPTION
            'Demographic district validation failed. Rows: %, Unique codes: %',
            demo_rows, demo_codes;
    END IF;

    IF housing_rows <> 24 OR housing_codes <> 24 THEN
        RAISE EXCEPTION
            'Housing district validation failed. Rows: %, Unique codes: %',
            housing_rows, housing_codes;
    END IF;

    IF invalid_state_codes <> 0 THEN
        RAISE EXCEPTION
            'Unexpected Jharkhand state codes found: %',
            invalid_state_codes;
    END IF;

    SELECT COUNT(*)
    INTO name_mismatches
    FROM bronze.census_demographics_raw d
    JOIN bronze.census_housing_raw h
      ON TRIM(d.raw_record ->> 'District code')
       = TRIM(h.raw_record ->> 'District Code')
    WHERE UPPER(TRIM(d.raw_record ->> 'State name')) = 'JHARKHAND'
      AND UPPER(TRIM(h.raw_record ->> 'State Name')) = 'JHARKHAND'
      AND LOWER(TRIM(h.raw_record ->> 'Rural/Urban')) = 'total'
      AND REGEXP_REPLACE(
            LOWER(TRIM(d.raw_record ->> 'District name')),
            '[^a-z0-9]', '', 'g'
          )
          IS DISTINCT FROM
          REGEXP_REPLACE(
            LOWER(TRIM(h.raw_record ->> 'District Name')),
            '[^a-z0-9]', '', 'g'
          );

    IF name_mismatches <> 0 THEN
        RAISE EXCEPTION
            'District-name mismatches detected: %',
            name_mismatches;
    END IF;

END $$;



-- 2. POPULATE CANONICAL DISTRICT DIMENSION
-- Demographics provides canonical district names.
-- Housing provides the Jharkhand state code.


INSERT INTO silver.dim_district (
    district_code,
    state_code,
    state_name,
    district_name,
    district_name_normalized,
    source_district_name
)

SELECT
    (d.raw_record ->> 'District code')::SMALLINT,

    (h.raw_record ->> 'State Code')::SMALLINT,

    'Jharkhand',

    TRIM(d.raw_record ->> 'District name'),

    REGEXP_REPLACE(
        LOWER(TRIM(d.raw_record ->> 'District name')),
        '[^a-z0-9]',
        '',
        'g'
    ),

    TRIM(d.raw_record ->> 'District name')

FROM bronze.census_demographics_raw d

INNER JOIN bronze.census_housing_raw h
    ON TRIM(d.raw_record ->> 'District code')
     = TRIM(h.raw_record ->> 'District Code')

WHERE UPPER(TRIM(d.raw_record ->> 'State name')) = 'JHARKHAND'
  AND UPPER(TRIM(h.raw_record ->> 'State Name')) = 'JHARKHAND'
  AND LOWER(TRIM(h.raw_record ->> 'Rural/Urban')) = 'total'

ON CONFLICT (district_code)
DO UPDATE SET

    state_code = EXCLUDED.state_code,
    state_name = EXCLUDED.state_name,
    district_name = EXCLUDED.district_name,
    district_name_normalized = EXCLUDED.district_name_normalized,
    source_district_name = EXCLUDED.source_district_name;


-- 3. POST-LOAD VALIDATION

DO $$
DECLARE
    district_count BIGINT;
    unique_code_count BIGINT;
    unique_name_count BIGINT;
BEGIN

    SELECT
        COUNT(*),
        COUNT(DISTINCT district_code),
        COUNT(DISTINCT district_name_normalized)
    INTO district_count, unique_code_count, unique_name_count
    FROM silver.dim_district;

    IF district_count <> 24
       OR unique_code_count <> 24
       OR unique_name_count <> 24 THEN

        RAISE EXCEPTION
            'District dimension validation failed. Rows: %, Unique codes: %, Unique names: %',
            district_count, unique_code_count, unique_name_count;

    END IF;

END $$;

COMMIT;

