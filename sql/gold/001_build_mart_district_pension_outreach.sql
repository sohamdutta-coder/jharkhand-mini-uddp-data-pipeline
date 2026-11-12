
BEGIN;

-- ============================================================
-- 1. SOURCE VALIDATION
-- ============================================================

DO $$
DECLARE
    district_count BIGINT;
    demographic_count BIGINT;
    housing_count BIGINT;
    missing_inputs BIGINT;
    invalid_social_share BIGINT;
BEGIN

    SELECT COUNT(*) INTO district_count
    FROM silver.dim_district;

    SELECT COUNT(*) INTO demographic_count
    FROM silver.fact_district_demographics;

    SELECT COUNT(*) INTO housing_count
    FROM silver.fact_district_housing;

    IF district_count <> 24
       OR demographic_count <> 24
       OR housing_count <> 24 THEN

        RAISE EXCEPTION
            'Gold source reconciliation failed. Districts: %, Demographics: %, Housing: %',
            district_count, demographic_count, housing_count;

    END IF;

    SELECT COUNT(*)
    INTO missing_inputs
    FROM silver.dim_district d
    JOIN silver.fact_district_demographics dem
        ON d.district_code = dem.district_code
    JOIN silver.fact_district_housing h
        ON d.district_code = h.district_code
    WHERE dem.age_50_plus_population IS NULL
       OR h.dilapidated_housing_pct IS NULL
       OR dem.total_population <= 0
       OR dem.total_households <= 0;

    IF missing_inputs > 0 THEN
        RAISE EXCEPTION
            'Missing or invalid Gold source inputs: %',
            missing_inputs;
    END IF;

    SELECT COUNT(*)
    INTO invalid_social_share
    FROM silver.fact_district_demographics
    WHERE sc_population + st_population > total_population;

    IF invalid_social_share > 0 THEN
        RAISE EXCEPTION
            'SC and ST combined population exceeds total population in % districts.',
            invalid_social_share;
    END IF;

END $$;


-- ============================================================
-- 2. BUILD DISTRICT-LEVEL BASE FEATURES
-- ============================================================

CREATE TEMP TABLE gold_base
ON COMMIT DROP
AS

SELECT

    d.district_code,
    d.district_name,
    d.state_name,

    dem.total_population,
    dem.male_population,
    dem.female_population,
    dem.literate_population,
    dem.total_workers,
    dem.sc_population,
    dem.st_population,
    dem.total_households,

    ROUND(
        dem.total_population::NUMERIC
        / NULLIF(dem.total_households, 0),
        4
    ) AS population_per_household,

    ROUND(
        100.0 * dem.female_population
        / dem.total_population,
        4
    ) AS female_population_share_pct,

    ROUND(
        100.0 * dem.literate_population
        / dem.total_population,
        4
    ) AS literacy_rate_pct,

    ROUND(
        100.0 * dem.total_workers
        / dem.total_population,
        4
    ) AS work_participation_rate_pct,

    ROUND(
        100.0 * dem.sc_population
        / dem.total_population,
        4
    ) AS sc_population_share_pct,

    ROUND(
        100.0 * dem.st_population
        / dem.total_population,
        4
    ) AS st_population_share_pct,

    ROUND(
        100.0 * (dem.sc_population + dem.st_population)
        / dem.total_population,
        4
    ) AS social_group_population_share_pct,

    dem.age_50_plus_population,

    ROUND(
        100.0 * dem.age_50_plus_population
        / dem.total_population,
        4
    ) AS age_50_plus_population_share_pct,

    h.good_housing_pct,
    h.livable_housing_pct,
    h.dilapidated_housing_pct,
    h.permanent_housing_pct,
    h.semi_permanent_housing_pct,
    h.temporary_housing_pct,
    h.serviceable_pct,
    h.non_serviceable_housing_pct,
    h.unclassifiable_pct,

    dem.source_file_name AS demographics_source_file,
    dem.source_sha256 AS demographics_source_sha256,
    dem.source_row_number AS demographics_source_row_number,
    dem.ingestion_id AS demographics_ingestion_id,

    h.source_file_name AS housing_source_file,
    h.source_sha256 AS housing_source_sha256,
    h.source_row_number AS housing_source_row_number,
    h.ingestion_id AS housing_ingestion_id

FROM silver.dim_district d

INNER JOIN silver.fact_district_demographics dem
    ON d.district_code = dem.district_code

INNER JOIN silver.fact_district_housing h
    ON d.district_code = h.district_code;


-- ============================================================
-- 3. CALCULATE MIN-MAX NORMALIZATION BOUNDARIES
-- ============================================================

CREATE TEMP TABLE gold_normalization
ON COMMIT DROP
AS

SELECT

    b.*,

    MIN(age_50_plus_population_share_pct)
        OVER () AS age_min,

    MAX(age_50_plus_population_share_pct)
        OVER () AS age_max,

    MIN(dilapidated_housing_pct)
        OVER () AS housing_min,

    MAX(dilapidated_housing_pct)
        OVER () AS housing_max,

    MIN(social_group_population_share_pct)
        OVER () AS social_min,

    MAX(social_group_population_share_pct)
        OVER () AS social_max,

    MIN(literacy_rate_pct)
        OVER () AS literacy_min,

    MAX(literacy_rate_pct)
        OVER () AS literacy_max,

    MIN(work_participation_rate_pct)
        OVER () AS work_min,

    MAX(work_participation_rate_pct)
        OVER () AS work_max,

    MIN(population_per_household)
        OVER () AS household_min,

    MAX(population_per_household)
        OVER () AS household_max,

    MIN(female_population_share_pct)
        OVER () AS female_min,

    MAX(female_population_share_pct)
        OVER () AS female_max

FROM gold_base b;


-- ============================================================
-- 4. NORMALIZE VULNERABILITY COMPONENTS
-- Each component ranges from 0 to 1.
-- Higher values represent greater relative vulnerability.
-- ============================================================

CREATE TEMP TABLE gold_components
ON COMMIT DROP
AS

SELECT

    n.*,

    CASE
        WHEN age_max = age_min THEN 0
        ELSE
            (age_50_plus_population_share_pct - age_min)
            / NULLIF(age_max - age_min, 0)
    END AS age_vulnerability_component,

    CASE
        WHEN housing_max = housing_min THEN 0
        ELSE
            (dilapidated_housing_pct - housing_min)
            / NULLIF(housing_max - housing_min, 0)
    END AS housing_vulnerability_component,

    CASE
        WHEN social_max = social_min THEN 0
        ELSE
            (social_group_population_share_pct - social_min)
            / NULLIF(social_max - social_min, 0)
    END AS social_vulnerability_component,

    CASE
        WHEN literacy_max = literacy_min THEN 0
        ELSE
            (literacy_max - literacy_rate_pct)
            / NULLIF(literacy_max - literacy_min, 0)
    END AS literacy_vulnerability_component,

    CASE
        WHEN work_max = work_min THEN 0
        ELSE
            (work_max - work_participation_rate_pct)
            / NULLIF(work_max - work_min, 0)
    END AS work_vulnerability_component,

    CASE
        WHEN household_max = household_min THEN 0
        ELSE
            (population_per_household - household_min)
            / NULLIF(household_max - household_min, 0)
    END AS household_pressure_component,

    CASE
        WHEN female_max = female_min THEN 0
        ELSE
            (female_population_share_pct - female_min)
            / NULLIF(female_max - female_min, 0)
    END AS female_population_component

FROM gold_normalization n;


-- ============================================================
-- 5. CALCULATE WEIGHTED PRIORITY SCORE
-- ============================================================

CREATE TEMP TABLE gold_scored
ON COMMIT DROP
AS

SELECT

    c.*,

    ROUND(
        100 * (
            0.25 * age_vulnerability_component
          + 0.20 * housing_vulnerability_component
          + 0.15 * social_vulnerability_component
          + 0.15 * literacy_vulnerability_component
          + 0.10 * work_vulnerability_component
          + 0.10 * household_pressure_component
          + 0.05 * female_population_component
        ),
        4
    ) AS pension_outreach_priority_score

FROM gold_components c;


-- ============================================================
-- 6. RANK DISTRICTS AND CLASSIFY PRIORITIES
--
-- NTILE(3):
-- 1 = High
-- 2 = Medium
-- 3 = Low
--
-- Ties are resolved deterministically using district code.
-- ============================================================

CREATE TEMP TABLE gold_stage
ON COMMIT DROP
AS

SELECT

    s.*,

    ROW_NUMBER() OVER (
        ORDER BY
            pension_outreach_priority_score DESC,
            district_code ASC
    )::SMALLINT AS priority_rank,

    NTILE(3) OVER (
        ORDER BY
            pension_outreach_priority_score DESC,
            district_code ASC
    ) AS priority_bucket,

    CASE
        WHEN NTILE(3) OVER (
            ORDER BY
                pension_outreach_priority_score DESC,
                district_code ASC
        ) = 1 THEN 'High'

        WHEN NTILE(3) OVER (
            ORDER BY
                pension_outreach_priority_score DESC,
                district_code ASC
        ) = 2 THEN 'Medium'

        ELSE 'Low'
    END AS priority_category

FROM gold_scored s;


-- ============================================================
-- 7. VALIDATE THE COMPLETE GOLD STAGING RESULT
-- ============================================================

DO $$
DECLARE

    staged_rows BIGINT;
    unique_districts BIGINT;

    high_count BIGINT;
    medium_count BIGINT;
    low_count BIGINT;

    invalid_components BIGINT;
    invalid_scores BIGINT;
    invalid_ranks BIGINT;

BEGIN

    SELECT
        COUNT(*),
        COUNT(DISTINCT district_code),

        COUNT(*) FILTER (
            WHERE priority_category = 'High'
        ),

        COUNT(*) FILTER (
            WHERE priority_category = 'Medium'
        ),

        COUNT(*) FILTER (
            WHERE priority_category = 'Low'
        ),

        COUNT(*) FILTER (
            WHERE age_vulnerability_component NOT BETWEEN 0 AND 1
               OR housing_vulnerability_component NOT BETWEEN 0 AND 1
               OR social_vulnerability_component NOT BETWEEN 0 AND 1
               OR literacy_vulnerability_component NOT BETWEEN 0 AND 1
               OR work_vulnerability_component NOT BETWEEN 0 AND 1
               OR household_pressure_component NOT BETWEEN 0 AND 1
               OR female_population_component NOT BETWEEN 0 AND 1
        ),

        COUNT(*) FILTER (
            WHERE pension_outreach_priority_score NOT BETWEEN 0 AND 100
        ),

        COUNT(*) FILTER (
            WHERE priority_rank NOT BETWEEN 1 AND 24
        )

    INTO
        staged_rows,
        unique_districts,
        high_count,
        medium_count,
        low_count,
        invalid_components,
        invalid_scores,
        invalid_ranks

    FROM gold_stage;


    IF staged_rows <> 24 OR unique_districts <> 24 THEN

        RAISE EXCEPTION
            'Gold staging row-count validation failed. Rows: %, Districts: %',
            staged_rows, unique_districts;

    END IF;


    IF high_count <> 8
       OR medium_count <> 8
       OR low_count <> 8 THEN

        RAISE EXCEPTION
            'Priority classification failed. High: %, Medium: %, Low: %',
            high_count, medium_count, low_count;

    END IF;


    IF invalid_components > 0
       OR invalid_scores > 0
       OR invalid_ranks > 0 THEN

        RAISE EXCEPTION
            'Gold scoring validation failed. Components: %, Scores: %, Ranks: %',
            invalid_components, invalid_scores, invalid_ranks;

    END IF;

END $$;


-- ============================================================
-- 8. REMOVE DISTRICTS NO LONGER PRESENT IN THE SOURCE
-- ============================================================

DELETE FROM gold.mart_district_pension_outreach g
WHERE NOT EXISTS (
    SELECT 1
    FROM gold_stage s
    WHERE s.district_code = g.district_code
);


-- ============================================================
-- 9. INSERT / REFRESH GOLD MART
--
-- District-level pension information remains NULL because
-- NSAP contains state-level counts only.
-- ============================================================

INSERT INTO gold.mart_district_pension_outreach (

    district_code,
    district_name,
    state_name,

    total_population,
    male_population,
    female_population,
    literate_population,
    total_workers,
    sc_population,
    st_population,
    total_households,

    population_per_household,
    female_population_share_pct,
    literacy_rate_pct,
    work_participation_rate_pct,
    sc_population_share_pct,
    st_population_share_pct,
    social_group_population_share_pct,
    age_50_plus_population,
    age_50_plus_population_share_pct,

    good_housing_pct,
    livable_housing_pct,
    dilapidated_housing_pct,
    permanent_housing_pct,
    semi_permanent_housing_pct,
    temporary_housing_pct,
    serviceable_pct,
    non_serviceable_housing_pct,
    unclassifiable_pct,

    old_age_pension_beneficiary_count,
    widow_pension_beneficiary_count,

    old_age_beneficiaries_per_1000_population,
    widow_beneficiaries_per_1000_population,

    old_age_beneficiaries_per_1000_households,
    widow_beneficiaries_per_1000_households,

    total_pension_beneficiaries_per_1000_households,

    district_pension_data_available,

    age_vulnerability_component,
    housing_vulnerability_component,
    social_vulnerability_component,
    literacy_vulnerability_component,
    work_vulnerability_component,
    household_pressure_component,
    female_population_component,

    pension_outreach_priority_score,
    priority_rank,
    priority_category,
    priority_score_method,

    census_reference_year,

    demographics_source_file,
    demographics_source_sha256,
    demographics_source_row_number,
    demographics_ingestion_id,

    housing_source_file,
    housing_source_sha256,
    housing_source_row_number,
    housing_ingestion_id

)

SELECT

    district_code,
    district_name,
    state_name,

    total_population,
    male_population,
    female_population,
    literate_population,
    total_workers,
    sc_population,
    st_population,
    total_households,

    population_per_household,
    female_population_share_pct,
    literacy_rate_pct,
    work_participation_rate_pct,
    sc_population_share_pct,
    st_population_share_pct,
    social_group_population_share_pct,
    age_50_plus_population,
    age_50_plus_population_share_pct,

    good_housing_pct,
    livable_housing_pct,
    dilapidated_housing_pct,
    permanent_housing_pct,
    semi_permanent_housing_pct,
    temporary_housing_pct,
    serviceable_pct,
    non_serviceable_housing_pct,
    unclassifiable_pct,

    NULL::BIGINT,
    NULL::BIGINT,

    NULL::NUMERIC,
    NULL::NUMERIC,

    NULL::NUMERIC,
    NULL::NUMERIC,

    NULL::NUMERIC,

    FALSE,

    age_vulnerability_component,
    housing_vulnerability_component,
    social_vulnerability_component,
    literacy_vulnerability_component,
    work_vulnerability_component,
    household_pressure_component,
    female_population_component,

    pension_outreach_priority_score,
    priority_rank,
    priority_category,
    'VULNERABILITY_PROXY_V1',

    2011,

    demographics_source_file,
    demographics_source_sha256,
    demographics_source_row_number,
    demographics_ingestion_id,

    housing_source_file,
    housing_source_sha256,
    housing_source_row_number,
    housing_ingestion_id

FROM gold_stage

ON CONFLICT (district_code)

DO UPDATE SET

    district_name = EXCLUDED.district_name,
    state_name = EXCLUDED.state_name,

    total_population = EXCLUDED.total_population,
    male_population = EXCLUDED.male_population,
    female_population = EXCLUDED.female_population,
    literate_population = EXCLUDED.literate_population,
    total_workers = EXCLUDED.total_workers,
    sc_population = EXCLUDED.sc_population,
    st_population = EXCLUDED.st_population,
    total_households = EXCLUDED.total_households,

    population_per_household = EXCLUDED.population_per_household,
    female_population_share_pct = EXCLUDED.female_population_share_pct,
    literacy_rate_pct = EXCLUDED.literacy_rate_pct,
    work_participation_rate_pct = EXCLUDED.work_participation_rate_pct,
    sc_population_share_pct = EXCLUDED.sc_population_share_pct,
    st_population_share_pct = EXCLUDED.st_population_share_pct,
    social_group_population_share_pct = EXCLUDED.social_group_population_share_pct,
    age_50_plus_population = EXCLUDED.age_50_plus_population,
    age_50_plus_population_share_pct = EXCLUDED.age_50_plus_population_share_pct,

    good_housing_pct = EXCLUDED.good_housing_pct,
    livable_housing_pct = EXCLUDED.livable_housing_pct,
    dilapidated_housing_pct = EXCLUDED.dilapidated_housing_pct,
    permanent_housing_pct = EXCLUDED.permanent_housing_pct,
    semi_permanent_housing_pct = EXCLUDED.semi_permanent_housing_pct,
    temporary_housing_pct = EXCLUDED.temporary_housing_pct,
    serviceable_pct = EXCLUDED.serviceable_pct,
    non_serviceable_housing_pct = EXCLUDED.non_serviceable_housing_pct,
    unclassifiable_pct = EXCLUDED.unclassifiable_pct,

    old_age_pension_beneficiary_count = NULL,
    widow_pension_beneficiary_count = NULL,

    old_age_beneficiaries_per_1000_population = NULL,
    widow_beneficiaries_per_1000_population = NULL,

    old_age_beneficiaries_per_1000_households = NULL,
    widow_beneficiaries_per_1000_households = NULL,

    total_pension_beneficiaries_per_1000_households = NULL,

    district_pension_data_available = FALSE,

    age_vulnerability_component = EXCLUDED.age_vulnerability_component,
    housing_vulnerability_component = EXCLUDED.housing_vulnerability_component,
    social_vulnerability_component = EXCLUDED.social_vulnerability_component,
    literacy_vulnerability_component = EXCLUDED.literacy_vulnerability_component,
    work_vulnerability_component = EXCLUDED.work_vulnerability_component,
    household_pressure_component = EXCLUDED.household_pressure_component,
    female_population_component = EXCLUDED.female_population_component,

    pension_outreach_priority_score = EXCLUDED.pension_outreach_priority_score,
    priority_rank = EXCLUDED.priority_rank,
    priority_category = EXCLUDED.priority_category,
    priority_score_method = EXCLUDED.priority_score_method,

    census_reference_year = EXCLUDED.census_reference_year,

    demographics_source_file = EXCLUDED.demographics_source_file,
    demographics_source_sha256 = EXCLUDED.demographics_source_sha256,
    demographics_source_row_number = EXCLUDED.demographics_source_row_number,
    demographics_ingestion_id = EXCLUDED.demographics_ingestion_id,

    housing_source_file = EXCLUDED.housing_source_file,
    housing_source_sha256 = EXCLUDED.housing_source_sha256,
    housing_source_row_number = EXCLUDED.housing_source_row_number,
    housing_ingestion_id = EXCLUDED.housing_ingestion_id,

    refreshed_at = CURRENT_TIMESTAMP;


-- ============================================================
-- 10. DOCUMENTATION
-- ============================================================

COMMENT ON TABLE gold.mart_district_pension_outreach IS
'Jharkhand district-level outreach mart. Priority score is a relative vulnerability proxy, not a measured pension coverage gap. District-level NSAP beneficiary counts are unavailable.';

COMMENT ON COLUMN gold.mart_district_pension_outreach.female_population_component IS
'Low-weight demographic context indicator. Female population share is not a measure of widow prevalence.';

COMMENT ON COLUMN gold.mart_district_pension_outreach.pension_outreach_priority_score IS
'Weighted min-max normalized vulnerability score from 0 to 100. Formula version VULNERABILITY_PROXY_V1.';

COMMIT;

