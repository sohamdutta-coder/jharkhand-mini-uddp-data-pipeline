
-- District Source Alignment Validation
-- Compare Census demographics and housing records.
-- Primary key: District Code

WITH demographics AS (

    SELECT
        TRIM(raw_record ->> 'District code') AS district_code,

        TRIM(raw_record ->> 'District name') AS district_name,

        REGEXP_REPLACE(
            LOWER(TRIM(raw_record ->> 'District name')),
            '[^a-z0-9]',
            '',
            'g'
        ) AS district_name_normalized

    FROM bronze.census_demographics_raw

    WHERE UPPER(TRIM(raw_record ->> 'State name')) = 'JHARKHAND'

),

housing AS (

    SELECT
        TRIM(raw_record ->> 'District Code') AS district_code,

        TRIM(raw_record ->> 'District Name') AS district_name,

        TRIM(raw_record ->> 'State Code') AS state_code,

        REGEXP_REPLACE(
            LOWER(TRIM(raw_record ->> 'District Name')),
            '[^a-z0-9]',
            '',
            'g'
        ) AS district_name_normalized

    FROM bronze.census_housing_raw

    WHERE UPPER(TRIM(raw_record ->> 'State Name')) = 'JHARKHAND'
      AND LOWER(TRIM(raw_record ->> 'Rural/Urban')) = 'total'

),

district_comparison AS (

    SELECT
        COALESCE(d.district_code, h.district_code) AS district_code,

        d.district_name AS demographic_name,

        h.district_name AS housing_name,

        d.district_name_normalized AS demographic_normalized,

        h.district_name_normalized AS housing_normalized,

        h.state_code,

        CASE
            WHEN d.district_code IS NULL
                THEN 'MISSING_IN_DEMOGRAPHICS'

            WHEN h.district_code IS NULL
                THEN 'MISSING_IN_HOUSING'

            WHEN d.district_name_normalized
                IS DISTINCT FROM h.district_name_normalized
                THEN 'DISTRICT_NAME_MISMATCH'

            ELSE 'MATCHED'
        END AS matching_status

    FROM demographics d

    FULL OUTER JOIN housing h
        ON d.district_code = h.district_code

)

SELECT
    COUNT(*) AS compared_districts,

    COUNT(*) FILTER (
        WHERE matching_status = 'MATCHED'
    ) AS matched_districts,

    COUNT(*) FILTER (
        WHERE matching_status = 'MISSING_IN_DEMOGRAPHICS'
    ) AS missing_in_demographics,

    COUNT(*) FILTER (
        WHERE matching_status = 'MISSING_IN_HOUSING'
    ) AS missing_in_housing,

    COUNT(*) FILTER (
        WHERE matching_status = 'DISTRICT_NAME_MISMATCH'
    ) AS name_mismatches

FROM district_comparison;


-- Display any unmatched or mismatched records.

WITH demographics AS (

    SELECT
        TRIM(raw_record ->> 'District code') AS district_code,

        TRIM(raw_record ->> 'District name') AS district_name,

        REGEXP_REPLACE(
            LOWER(TRIM(raw_record ->> 'District name')),
            '[^a-z0-9]',
            '',
            'g'
        ) AS district_name_normalized

    FROM bronze.census_demographics_raw

    WHERE UPPER(TRIM(raw_record ->> 'State name')) = 'JHARKHAND'

),

housing AS (

    SELECT
        TRIM(raw_record ->> 'District Code') AS district_code,

        TRIM(raw_record ->> 'District Name') AS district_name,

        REGEXP_REPLACE(
            LOWER(TRIM(raw_record ->> 'District Name')),
            '[^a-z0-9]',
            '',
            'g'
        ) AS district_name_normalized

    FROM bronze.census_housing_raw

    WHERE UPPER(TRIM(raw_record ->> 'State Name')) = 'JHARKHAND'
      AND LOWER(TRIM(raw_record ->> 'Rural/Urban')) = 'total'

)

SELECT
    COALESCE(d.district_code, h.district_code) AS district_code,

    d.district_name AS demographic_name,

    h.district_name AS housing_name,

    CASE
        WHEN d.district_code IS NULL
            THEN 'MISSING_IN_DEMOGRAPHICS'

        WHEN h.district_code IS NULL
            THEN 'MISSING_IN_HOUSING'

        ELSE 'DISTRICT_NAME_MISMATCH'
    END AS issue

FROM demographics d

FULL OUTER JOIN housing h
    ON d.district_code = h.district_code

WHERE d.district_code IS NULL
   OR h.district_code IS NULL
   OR d.district_name_normalized
      IS DISTINCT FROM h.district_name_normalized

ORDER BY district_code;

