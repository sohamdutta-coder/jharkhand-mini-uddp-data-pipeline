
BEGIN;

CREATE TABLE IF NOT EXISTS gold.mart_district_pension_outreach (

    -- ========================================================
    -- DISTRICT IDENTIFICATION
    -- ========================================================

    district_code SMALLINT PRIMARY KEY
        REFERENCES silver.dim_district(district_code),

    district_name VARCHAR(120) NOT NULL,

    state_name VARCHAR(100) NOT NULL DEFAULT 'Jharkhand',


    -- ========================================================
    -- DEMOGRAPHIC INDICATORS
    -- ========================================================

    total_population BIGINT NOT NULL,

    male_population BIGINT NOT NULL,

    female_population BIGINT NOT NULL,

    literate_population BIGINT NOT NULL,

    total_workers BIGINT NOT NULL,

    sc_population BIGINT NOT NULL,

    st_population BIGINT NOT NULL,

    total_households BIGINT NOT NULL,


    -- ========================================================
    -- CALCULATED DEMOGRAPHIC FEATURES
    -- ========================================================

    population_per_household NUMERIC(12,4) NOT NULL,

    female_population_share_pct NUMERIC(8,4) NOT NULL,

    literacy_rate_pct NUMERIC(8,4) NOT NULL,

    work_participation_rate_pct NUMERIC(8,4) NOT NULL,

    sc_population_share_pct NUMERIC(8,4) NOT NULL,

    st_population_share_pct NUMERIC(8,4) NOT NULL,

    social_group_population_share_pct NUMERIC(8,4) NOT NULL,

    age_50_plus_population BIGINT NOT NULL,

    age_50_plus_population_share_pct NUMERIC(8,4) NOT NULL,


    -- ========================================================
    -- HOUSING INDICATORS
    -- ========================================================

    good_housing_pct NUMERIC(6,2),

    livable_housing_pct NUMERIC(6,2),

    dilapidated_housing_pct NUMERIC(6,2),

    permanent_housing_pct NUMERIC(6,2),

    semi_permanent_housing_pct NUMERIC(6,2),

    temporary_housing_pct NUMERIC(6,2),

    serviceable_pct NUMERIC(6,2),

    non_serviceable_housing_pct NUMERIC(6,2),

    unclassifiable_pct NUMERIC(6,2),


    -- ========================================================
    -- PENSION BENEFICIARY INDICATORS
    -- District-level figures unavailable in the source.
    -- NULL means unavailable, not zero.
    -- ========================================================

    old_age_pension_beneficiary_count BIGINT,

    widow_pension_beneficiary_count BIGINT,

    old_age_beneficiaries_per_1000_population NUMERIC(12,4),

    widow_beneficiaries_per_1000_population NUMERIC(12,4),

    old_age_beneficiaries_per_1000_households NUMERIC(12,4),

    widow_beneficiaries_per_1000_households NUMERIC(12,4),

    total_pension_beneficiaries_per_1000_households NUMERIC(12,4),

    district_pension_data_available BOOLEAN NOT NULL DEFAULT FALSE,


    -- ========================================================
    -- PRIORITY SCORE COMPONENTS
    -- Components are normalized between 0 and 1.
    -- ========================================================

    age_vulnerability_component NUMERIC(10,8) NOT NULL,

    housing_vulnerability_component NUMERIC(10,8) NOT NULL,

    social_vulnerability_component NUMERIC(10,8) NOT NULL,

    literacy_vulnerability_component NUMERIC(10,8) NOT NULL,

    work_vulnerability_component NUMERIC(10,8) NOT NULL,

    household_pressure_component NUMERIC(10,8) NOT NULL,

    female_population_component NUMERIC(10,8) NOT NULL,


    -- ========================================================
    -- PRIORITIZATION OUTPUT
    -- ========================================================

    pension_outreach_priority_score NUMERIC(10,4) NOT NULL,

    priority_rank SMALLINT NOT NULL,

    priority_category VARCHAR(10) NOT NULL,

    priority_score_method VARCHAR(50) NOT NULL
        DEFAULT 'VULNERABILITY_PROXY_V1',


    -- ========================================================
    -- DATA LINEAGE
    -- ========================================================

    census_reference_year SMALLINT NOT NULL DEFAULT 2011,

    demographics_source_file TEXT NOT NULL,

    demographics_source_sha256 CHAR(64) NOT NULL,

    demographics_source_row_number BIGINT NOT NULL,

    demographics_ingestion_id UUID NOT NULL,

    housing_source_file TEXT NOT NULL,

    housing_source_sha256 CHAR(64) NOT NULL,

    housing_source_row_number BIGINT NOT NULL,

    housing_ingestion_id UUID NOT NULL,


    -- ========================================================
    -- AUDIT INFORMATION
    -- ========================================================

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    refreshed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,


    -- ========================================================
    -- CONSTRAINTS
    -- ========================================================

    CONSTRAINT ck_gold_population
        CHECK (total_population > 0),

    CONSTRAINT ck_gold_households
        CHECK (
            total_households > 0
            AND total_households <= total_population
        ),

    CONSTRAINT ck_gold_gender
        CHECK (
            male_population + female_population = total_population
        ),

    CONSTRAINT ck_gold_pension_counts
        CHECK (
            (old_age_pension_beneficiary_count IS NULL
                OR old_age_pension_beneficiary_count >= 0)
            AND
            (widow_pension_beneficiary_count IS NULL
                OR widow_pension_beneficiary_count >= 0)
        ),

    CONSTRAINT ck_gold_priority_score
        CHECK (
            pension_outreach_priority_score BETWEEN 0 AND 100
        ),

    CONSTRAINT ck_gold_priority_rank
        CHECK (priority_rank BETWEEN 1 AND 24),

    CONSTRAINT ck_gold_priority_category
        CHECK (
            priority_category IN ('High', 'Medium', 'Low')
        ),

    CONSTRAINT ck_gold_priority_components
        CHECK (
            age_vulnerability_component BETWEEN 0 AND 1
            AND housing_vulnerability_component BETWEEN 0 AND 1
            AND social_vulnerability_component BETWEEN 0 AND 1
            AND literacy_vulnerability_component BETWEEN 0 AND 1
            AND work_vulnerability_component BETWEEN 0 AND 1
            AND household_pressure_component BETWEEN 0 AND 1
            AND female_population_component BETWEEN 0 AND 1
        ),

    CONSTRAINT ck_gold_pension_availability
        CHECK (
            district_pension_data_available = FALSE
            OR (
                old_age_pension_beneficiary_count IS NOT NULL
                AND widow_pension_beneficiary_count IS NOT NULL
            )
        )

);


-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_gold_priority_category
    ON gold.mart_district_pension_outreach(priority_category);

CREATE INDEX IF NOT EXISTS idx_gold_priority_score
    ON gold.mart_district_pension_outreach(
        pension_outreach_priority_score DESC
    );


-- ============================================================
-- TABLE DOCUMENTATION
-- ============================================================

COMMENT ON TABLE gold.mart_district_pension_outreach IS
'District-level Jharkhand pension outreach analytical mart. District-level pension beneficiary counts are unavailable in the state-level NSAP source. Priority scores are vulnerability-based proxies, not measured pension coverage gaps.';

COMMENT ON COLUMN gold.mart_district_pension_outreach.age_50_plus_population_share_pct IS
'Population aged 50 and above as a proxy. The source does not provide an exact 60-plus population.';

COMMENT ON COLUMN gold.mart_district_pension_outreach.pension_outreach_priority_score IS
'Explainable vulnerability-based score calculated using normalized demographic, housing and household indicators. Range: 0-100.';

COMMENT ON COLUMN gold.mart_district_pension_outreach.district_pension_data_available IS
'False because the supplied NSAP dataset contains state-level rather than district-level beneficiary counts.';

COMMIT;

