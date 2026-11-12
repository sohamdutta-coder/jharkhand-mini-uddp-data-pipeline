
-- ============================================================
-- HOUSING SOURCE VALIDATION
-- Jharkhand district-level aggregate records only.
-- ============================================================

\pset pager off

-- ------------------------------------------------------------
-- 1. Source completeness
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS source_rows,

    COUNT(DISTINCT raw_record ->> 'District Code')
        AS unique_district_codes,

    COUNT(*) FILTER (
        WHERE TRIM(raw_record ->> 'State Code') <> '20'
    ) AS invalid_state_codes,

    COUNT(*) FILTER (
        WHERE LOWER(TRIM(raw_record ->> 'Rural/Urban')) <> 'total'
    ) AS non_total_records

FROM bronze.census_housing_raw

WHERE UPPER(TRIM(raw_record ->> 'State Name')) = 'JHARKHAND'
  AND LOWER(TRIM(raw_record ->> 'Rural/Urban')) = 'total';


-- ------------------------------------------------------------
-- 2. Numeric field validation
-- ------------------------------------------------------------

WITH housing AS (

    SELECT raw_record

    FROM bronze.census_housing_raw

    WHERE UPPER(TRIM(raw_record ->> 'State Name')) = 'JHARKHAND'
      AND LOWER(TRIM(raw_record ->> 'Rural/Urban')) = 'total'

),

numeric_fields AS (

    SELECT
        v.column_name,
        v.raw_value

    FROM housing

    CROSS JOIN LATERAL (

        VALUES
            ('Total Number of households',
                raw_record ->> 'Total Number of households'),

            ('Total Number of Good',
                raw_record ->> 'Total Number of Good'),

            ('Total Number of Livable',
                raw_record ->> 'Total Number of Livable'),

            ('Total Number of Dilapidated',
                raw_record ->> 'Total Number of Dilapidated'),

            ('Total Number of Residence households',
                raw_record ->> 'Total Number of Residence households'),

            ('Total Number of Residence Good',
                raw_record ->> 'Total Number of Residence Good'),

            ('Total Number of Residence Livable',
                raw_record ->> 'Total Number of Residence Livable'),

            ('Total Number of Residence Dilapidated',
                raw_record ->> 'Total Number of Residence Dilapidated'),

            ('Permanents',
                raw_record ->> 'Permanents'),

            ('Semi_Permanent',
                raw_record ->> 'Semi_Permanent'),

            ('Total_Temporary',
                raw_record ->> 'Total_Temporary'),

            ('Serviceable',
                raw_record ->> 'Serviceable'),

            ('Non_Serviceable',
                raw_record ->> 'Non_Serviceable'),

            ('Unclassifiable',
                raw_record ->> 'Unclassifiable')

    ) AS v(column_name, raw_value)

),

parsed AS (

    SELECT
        column_name,
        raw_value,

        CASE
            WHEN TRIM(raw_value) ~
                '^([0-9]+|[0-9]{1,3}(,[0-9]{3})+)(\.[0-9]+)?$'
            THEN REPLACE(TRIM(raw_value), ',', '')::NUMERIC
            ELSE NULL
        END AS numeric_value

    FROM numeric_fields

)

SELECT
    column_name,

    COUNT(*) FILTER (
        WHERE raw_value IS NULL
           OR TRIM(raw_value) = ''
    ) AS missing_values,

    COUNT(*) FILTER (
        WHERE raw_value IS NOT NULL
          AND TRIM(raw_value) <> ''
          AND numeric_value IS NULL
    ) AS invalid_values,

    COUNT(*) FILTER (
        WHERE numeric_value < 0
           OR numeric_value > 100
    ) AS out_of_range_values

FROM parsed

GROUP BY column_name

ORDER BY column_name;


-- ------------------------------------------------------------
-- 3. District matching with canonical dimension
-- ------------------------------------------------------------

SELECT
    h.raw_record ->> 'District Code' AS district_code,

    h.raw_record ->> 'District Name' AS housing_name,

    d.district_name AS canonical_name

FROM bronze.census_housing_raw h

LEFT JOIN silver.dim_district d

    ON d.district_code =
       (h.raw_record ->> 'District Code')::SMALLINT

WHERE UPPER(TRIM(h.raw_record ->> 'State Name')) = 'JHARKHAND'
  AND LOWER(TRIM(h.raw_record ->> 'Rural/Urban')) = 'total'

  AND (
      d.district_code IS NULL

      OR REGEXP_REPLACE(
          LOWER(TRIM(h.raw_record ->> 'District Name')),
          '[^a-z0-9]',
          '',
          'g'
      ) IS DISTINCT FROM d.district_name_normalized
  );


-- ------------------------------------------------------------
-- 4. Housing condition percentage reconciliation
-- Good + Livable + Dilapidated should approximately equal 100.
-- Tolerance: 0.2 percentage points for source rounding.
-- ------------------------------------------------------------

WITH housing AS (

    SELECT

        raw_record ->> 'District Name' AS district_name,

        REPLACE(
            raw_record ->> 'Total Number of Good', ',', ''
        )::NUMERIC

        +

        REPLACE(
            raw_record ->> 'Total Number of Livable', ',', ''
        )::NUMERIC

        +

        REPLACE(
            raw_record ->> 'Total Number of Dilapidated', ',', ''
        )::NUMERIC AS condition_total

    FROM bronze.census_housing_raw

    WHERE UPPER(TRIM(raw_record ->> 'State Name')) = 'JHARKHAND'
      AND LOWER(TRIM(raw_record ->> 'Rural/Urban')) = 'total'

)

SELECT
    district_name,
    condition_total

FROM housing

WHERE ABS(condition_total - 100) > 0.2

ORDER BY district_name;


-- ============================================================
-- 5. RESIDENTIAL HOUSING PERCENTAGE RECONCILIATION
--
-- Residential Good + Livable + Dilapidated should equal
-- Residential households.
--
-- Tolerance: 0.2 percentage points.
-- ============================================================

WITH housing AS (

    SELECT

        raw_record ->> 'District Name' AS district_name,

        REPLACE(
            raw_record ->> 'Total Number of Residence households',
            ',',
            ''
        )::NUMERIC AS residential_households,

        REPLACE(
            raw_record ->> 'Total Number of Residence Good',
            ',',
            ''
        )::NUMERIC AS residential_good,

        REPLACE(
            raw_record ->> 'Total Number of Residence Livable',
            ',',
            ''
        )::NUMERIC AS residential_livable,

        REPLACE(
            raw_record ->> 'Total Number of Residence Dilapidated',
            ',',
            ''
        )::NUMERIC AS residential_dilapidated

    FROM bronze.census_housing_raw

    WHERE UPPER(TRIM(raw_record ->> 'State Name')) = 'JHARKHAND'
      AND LOWER(TRIM(raw_record ->> 'Rural/Urban')) = 'total'

)

SELECT

    district_name,

    residential_households,

    residential_good
        + residential_livable
        + residential_dilapidated AS residential_condition_total,

    ROUND(
        residential_households
        - (
            residential_good
            + residential_livable
            + residential_dilapidated
        ),
        4
    ) AS difference

FROM housing

WHERE ABS(
    residential_households
    - (
        residential_good
        + residential_livable
        + residential_dilapidated
    )
) > 0.2

ORDER BY district_name;