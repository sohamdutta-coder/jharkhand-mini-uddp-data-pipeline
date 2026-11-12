BEGIN;

INSERT INTO ml.ml_district_features (
    district_code,
    district_name,
    census_reference_year,

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

    target_high_priority,
    target_priority_category,
    target_priority_rank,
    target_priority_score,
    priority_score_method,
    target_definition
)
SELECT
    g.district_code,
    g.district_name,
    g.census_reference_year,

    g.total_population,
    g.male_population,
    g.female_population,
    g.literate_population,
    g.total_workers,
    g.sc_population,
    g.st_population,
    g.total_households,

    g.population_per_household,
    g.female_population_share_pct,
    g.literacy_rate_pct,
    g.work_participation_rate_pct,
    g.sc_population_share_pct,
    g.st_population_share_pct,
    g.social_group_population_share_pct,

    g.age_50_plus_population,
    g.age_50_plus_population_share_pct,

    g.good_housing_pct,
    g.livable_housing_pct,
    g.dilapidated_housing_pct,
    g.permanent_housing_pct,
    g.semi_permanent_housing_pct,
    g.temporary_housing_pct,
    g.serviceable_pct,
    g.non_serviceable_housing_pct,
    g.unclassifiable_pct,

    g.old_age_pension_beneficiary_count,
    g.widow_pension_beneficiary_count,
    g.old_age_beneficiaries_per_1000_population,
    g.widow_beneficiaries_per_1000_population,
    g.old_age_beneficiaries_per_1000_households,
    g.widow_beneficiaries_per_1000_households,
    g.total_pension_beneficiaries_per_1000_households,
    g.district_pension_data_available,

    CASE
        WHEN g.priority_category = 'High' THEN 1
        ELSE 0
    END AS target_high_priority,

    g.priority_category AS target_priority_category,
    g.priority_rank AS target_priority_rank,
    g.pension_outreach_priority_score AS target_priority_score,
    g.priority_score_method,

    'Rule-based proxy label: 1 = High priority (top tercile); '
    || '0 = Medium or Low priority. Derived from the Gold priority '
    || 'classification, not from observed pension enrolment or '
    || 'outreach outcomes.' AS target_definition

FROM gold.mart_district_pension_outreach AS g

ON CONFLICT (district_code)
DO UPDATE SET
    district_name = EXCLUDED.district_name,
    census_reference_year = EXCLUDED.census_reference_year,

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

    old_age_pension_beneficiary_count = EXCLUDED.old_age_pension_beneficiary_count,
    widow_pension_beneficiary_count = EXCLUDED.widow_pension_beneficiary_count,
    old_age_beneficiaries_per_1000_population = EXCLUDED.old_age_beneficiaries_per_1000_population,
    widow_beneficiaries_per_1000_population = EXCLUDED.widow_beneficiaries_per_1000_population,
    old_age_beneficiaries_per_1000_households = EXCLUDED.old_age_beneficiaries_per_1000_households,
    widow_beneficiaries_per_1000_households = EXCLUDED.widow_beneficiaries_per_1000_households,
    total_pension_beneficiaries_per_1000_households = EXCLUDED.total_pension_beneficiaries_per_1000_households,
    district_pension_data_available = EXCLUDED.district_pension_data_available,

    target_high_priority = EXCLUDED.target_high_priority,
    target_priority_category = EXCLUDED.target_priority_category,
    target_priority_rank = EXCLUDED.target_priority_rank,
    target_priority_score = EXCLUDED.target_priority_score,
    priority_score_method = EXCLUDED.priority_score_method,
    target_definition = EXCLUDED.target_definition,

    feature_generated_at = NOW();

-- Remove districts no longer present in the Gold mart.
DELETE FROM ml.ml_district_features AS m
WHERE NOT EXISTS (
    SELECT 1
    FROM gold.mart_district_pension_outreach AS g
    WHERE g.district_code = m.district_code
);

-- Fail the transaction if the resulting dataset is inconsistent.
DO $$
DECLARE
    district_count INTEGER;
    high_count INTEGER;
    medium_count INTEGER;
    low_count INTEGER;
    unavailable_pension_count INTEGER;
BEGIN
    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE target_priority_category = 'High'),
        COUNT(*) FILTER (WHERE target_priority_category = 'Medium'),
        COUNT(*) FILTER (WHERE target_priority_category = 'Low'),
        COUNT(*) FILTER (WHERE district_pension_data_available = FALSE)
    INTO
        district_count,
        high_count,
        medium_count,
        low_count,
        unavailable_pension_count
    FROM ml.ml_district_features;

    IF district_count <> 24 THEN
        RAISE EXCEPTION 'Expected 24 districts, found %', district_count;
    END IF;

    IF high_count <> 8 OR medium_count <> 8 OR low_count <> 8 THEN
        RAISE EXCEPTION
            'Unexpected target distribution: High %, Medium %, Low %',
            high_count, medium_count, low_count;
    END IF;

    IF unavailable_pension_count <> 24 THEN
        RAISE EXCEPTION
            'Expected district-level pension data to be unavailable for all 24 districts; found %',
            unavailable_pension_count;
    END IF;

    RAISE NOTICE
        'ML feature build passed: % districts; High %, Medium %, Low %.',
        district_count, high_count, medium_count, low_count;
END $$;

COMMIT;
