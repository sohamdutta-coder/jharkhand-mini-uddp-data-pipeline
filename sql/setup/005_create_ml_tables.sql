CREATE SCHEMA IF NOT EXISTS ml;

CREATE TABLE IF NOT EXISTS ml.ml_district_features (
    -- District identification
    district_code SMALLINT PRIMARY KEY,
    district_name VARCHAR(100) NOT NULL,
    census_reference_year SMALLINT NOT NULL,

    -- Demographic features
    total_population BIGINT NOT NULL,
    male_population BIGINT NOT NULL,
    female_population BIGINT NOT NULL,
    literate_population BIGINT NOT NULL,
    total_workers BIGINT NOT NULL,
    sc_population BIGINT NOT NULL,
    st_population BIGINT NOT NULL,
    total_households BIGINT NOT NULL,

    -- Demographic indicators
    population_per_household NUMERIC(14,4) NOT NULL,
    female_population_share_pct NUMERIC(7,4) NOT NULL,
    literacy_rate_pct NUMERIC(7,4) NOT NULL,
    work_participation_rate_pct NUMERIC(7,4) NOT NULL,
    sc_population_share_pct NUMERIC(7,4) NOT NULL,
    st_population_share_pct NUMERIC(7,4) NOT NULL,
    social_group_population_share_pct NUMERIC(7,4) NOT NULL,

    -- Age features (50+ proxy, not actual 60+ population)
    age_50_plus_population BIGINT NOT NULL,
    age_50_plus_population_share_pct NUMERIC(7,4) NOT NULL,

    -- Housing features
    good_housing_pct NUMERIC(7,4),
    livable_housing_pct NUMERIC(7,4),
    dilapidated_housing_pct NUMERIC(7,4),
    permanent_housing_pct NUMERIC(7,4),
    semi_permanent_housing_pct NUMERIC(7,4),
    temporary_housing_pct NUMERIC(7,4),
    serviceable_pct NUMERIC(7,4),
    non_serviceable_housing_pct NUMERIC(7,4),
    unclassifiable_pct NUMERIC(7,4),

    -- Pension features (NULL when district-level data is unavailable)
    old_age_pension_beneficiary_count BIGINT,
    widow_pension_beneficiary_count BIGINT,
    old_age_beneficiaries_per_1000_population NUMERIC(14,4),
    widow_beneficiaries_per_1000_population NUMERIC(14,4),
    old_age_beneficiaries_per_1000_households NUMERIC(14,4),
    widow_beneficiaries_per_1000_households NUMERIC(14,4),
    total_pension_beneficiaries_per_1000_households NUMERIC(14,4),
    district_pension_data_available BOOLEAN NOT NULL,

    -- Rule-based ML target
    target_high_priority SMALLINT NOT NULL,
    target_priority_category VARCHAR(10) NOT NULL,
    target_priority_rank SMALLINT NOT NULL,
    target_priority_score NUMERIC(8,4) NOT NULL,
    priority_score_method VARCHAR(100) NOT NULL,

    -- Target documentation
    target_definition TEXT NOT NULL,

    -- Pipeline metadata
    feature_generated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Basic data integrity constraints
    CONSTRAINT chk_ml_population
        CHECK (
            total_population > 0
            AND male_population >= 0
            AND female_population >= 0
            AND male_population + female_population = total_population
        ),

    CONSTRAINT chk_ml_population_counts
        CHECK (
            literate_population BETWEEN 0 AND total_population
            AND total_workers BETWEEN 0 AND total_population
            AND sc_population BETWEEN 0 AND total_population
            AND st_population BETWEEN 0 AND total_population
            AND age_50_plus_population BETWEEN 0 AND total_population
            AND total_households > 0
        ),

    CONSTRAINT chk_ml_percentage_ranges
        CHECK (
            female_population_share_pct BETWEEN 0 AND 100
            AND literacy_rate_pct BETWEEN 0 AND 100
            AND work_participation_rate_pct BETWEEN 0 AND 100
            AND sc_population_share_pct BETWEEN 0 AND 100
            AND st_population_share_pct BETWEEN 0 AND 100
            AND social_group_population_share_pct BETWEEN 0 AND 100
            AND age_50_plus_population_share_pct BETWEEN 0 AND 100
        ),

    CONSTRAINT chk_ml_priority_target
        CHECK (
            target_high_priority IN (0, 1)
            AND target_priority_category IN ('High', 'Medium', 'Low')
            AND target_priority_rank > 0
            AND target_priority_score BETWEEN 0 AND 100
        ),

    CONSTRAINT chk_ml_target_mapping
        CHECK (
            (target_priority_category = 'High' AND target_high_priority = 1)
            OR
            (target_priority_category IN ('Medium', 'Low')
                AND target_high_priority = 0)
        ),

    CONSTRAINT chk_ml_pension_availability
        CHECK (
            district_pension_data_available
            OR (
                old_age_pension_beneficiary_count IS NULL
                AND widow_pension_beneficiary_count IS NULL
                AND old_age_beneficiaries_per_1000_population IS NULL
                AND widow_beneficiaries_per_1000_population IS NULL
                AND old_age_beneficiaries_per_1000_households IS NULL
                AND widow_beneficiaries_per_1000_households IS NULL
                AND total_pension_beneficiaries_per_1000_households IS NULL
            )
        )
);

CREATE INDEX IF NOT EXISTS idx_ml_district_priority
    ON ml.ml_district_features (target_high_priority);

CREATE INDEX IF NOT EXISTS idx_ml_district_category
    ON ml.ml_district_features (target_priority_category);

COMMENT ON TABLE ml.ml_district_features IS
    'District-level demographic, housing and pension features with a rule-based priority target for ML experimentation.';

COMMENT ON COLUMN ml.ml_district_features.target_high_priority IS
    'Binary rule-based target: 1 = High priority, 0 = Medium or Low priority. Not an observed outreach outcome.';

COMMENT ON COLUMN ml.ml_district_features.age_50_plus_population IS
    'Census 2011 age 50+ proxy. This is not an exact 60+ elderly population count.';

COMMENT ON COLUMN ml.ml_district_features.district_pension_data_available IS
    'Indicates whether genuine district-level pension beneficiary data is available.';
