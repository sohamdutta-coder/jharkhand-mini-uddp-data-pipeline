
BEGIN;

-- District Dimension

CREATE TABLE IF NOT EXISTS silver.dim_district (

    district_code SMALLINT PRIMARY KEY,

    state_code SMALLINT NOT NULL,

    state_name VARCHAR(100) NOT NULL,

    district_name VARCHAR(120) NOT NULL,

    district_name_normalized VARCHAR(120) NOT NULL UNIQUE,

    source_district_name VARCHAR(120) NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT ck_district_state
        CHECK (state_name = 'Jharkhand')

);


-- District Demographics Fact

CREATE TABLE IF NOT EXISTS silver.fact_district_demographics (

    district_code SMALLINT PRIMARY KEY
        REFERENCES silver.dim_district(district_code),

    total_population BIGINT NOT NULL,

    male_population BIGINT NOT NULL,

    female_population BIGINT NOT NULL,

    literate_population BIGINT NOT NULL,

    total_workers BIGINT NOT NULL,

    sc_population BIGINT NOT NULL,

    st_population BIGINT NOT NULL,

    total_households BIGINT NOT NULL,

    age_50_plus_population BIGINT,

    source_file_name TEXT NOT NULL,

    source_sha256 CHAR(64) NOT NULL,

    source_row_number BIGINT NOT NULL,

    ingestion_id UUID NOT NULL
        REFERENCES bronze.ingestion_metadata(ingestion_id),

    loaded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT ck_demographic_population
        CHECK (total_population > 0),

    CONSTRAINT ck_demographic_gender
        CHECK (
            male_population >= 0
            AND female_population >= 0
            AND male_population + female_population = total_population
        ),

    CONSTRAINT ck_demographic_literacy
        CHECK (
            literate_population >= 0
            AND literate_population <= total_population
        ),

    CONSTRAINT ck_demographic_workers
        CHECK (
            total_workers >= 0
            AND total_workers <= total_population
        ),

    CONSTRAINT ck_demographic_sc
        CHECK (
            sc_population >= 0
            AND sc_population <= total_population
        ),

    CONSTRAINT ck_demographic_st
        CHECK (
            st_population >= 0
            AND st_population <= total_population
        ),

    CONSTRAINT ck_demographic_households
        CHECK (total_households > 0),

    CONSTRAINT ck_demographic_age
        CHECK (
            age_50_plus_population IS NULL
            OR (
                age_50_plus_population >= 0
                AND age_50_plus_population <= total_population
            )
        ),

    CONSTRAINT uq_demographic_source_row
        UNIQUE (source_sha256, source_row_number)

);


-- District Housing Fact

CREATE TABLE IF NOT EXISTS silver.fact_district_housing (

    district_code SMALLINT PRIMARY KEY
        REFERENCES silver.dim_district(district_code),

    household_reference_base_pct NUMERIC(6,2),

    good_housing_pct NUMERIC(6,2),

    livable_housing_pct NUMERIC(6,2),

    dilapidated_housing_pct NUMERIC(6,2),

    residential_households_pct NUMERIC(6,2),

    residential_good_pct NUMERIC(6,2),

    residential_livable_pct NUMERIC(6,2),

    residential_dilapidated_pct NUMERIC(6,2),

    permanent_housing_pct NUMERIC(6,2),

    semi_permanent_housing_pct NUMERIC(6,2),

    temporary_housing_pct NUMERIC(6,2),

    non_serviceable_housing_pct NUMERIC(6,2),

    source_file_name TEXT NOT NULL,

    source_sha256 CHAR(64) NOT NULL,

    source_row_number BIGINT NOT NULL,

    ingestion_id UUID NOT NULL
        REFERENCES bronze.ingestion_metadata(ingestion_id),

    loaded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT ck_housing_percentages CHECK (

        (household_reference_base_pct IS NULL
            OR household_reference_base_pct BETWEEN 0 AND 100)

        AND (good_housing_pct IS NULL
            OR good_housing_pct BETWEEN 0 AND 100)

        AND (livable_housing_pct IS NULL
            OR livable_housing_pct BETWEEN 0 AND 100)

        AND (dilapidated_housing_pct IS NULL
            OR dilapidated_housing_pct BETWEEN 0 AND 100)

        AND (residential_households_pct IS NULL
            OR residential_households_pct BETWEEN 0 AND 100)

        AND (residential_good_pct IS NULL
            OR residential_good_pct BETWEEN 0 AND 100)

        AND (residential_livable_pct IS NULL
            OR residential_livable_pct BETWEEN 0 AND 100)

        AND (residential_dilapidated_pct IS NULL
            OR residential_dilapidated_pct BETWEEN 0 AND 100)

        AND (permanent_housing_pct IS NULL
            OR permanent_housing_pct BETWEEN 0 AND 100)

        AND (semi_permanent_housing_pct IS NULL
            OR semi_permanent_housing_pct BETWEEN 0 AND 100)

        AND (temporary_housing_pct IS NULL
            OR temporary_housing_pct BETWEEN 0 AND 100)

        AND (non_serviceable_housing_pct IS NULL
            OR non_serviceable_housing_pct BETWEEN 0 AND 100)

    ),

    CONSTRAINT uq_housing_source_row
        UNIQUE (source_sha256, source_row_number)

);


-- State Level Pension Benificiary Fact

CREATE TABLE IF NOT EXISTS silver.fact_pension_beneficiaries (

    pension_beneficiary_id BIGINT
        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    administrative_unit_name VARCHAR(150) NOT NULL,

    administrative_unit_normalized VARCHAR(150) NOT NULL,

    administrative_category VARCHAR(50) NOT NULL,

    pension_scheme VARCHAR(30) NOT NULL,

    beneficiary_count BIGINT NOT NULL,

    source_file_name TEXT NOT NULL,

    source_sha256 CHAR(64) NOT NULL,

    source_row_number BIGINT NOT NULL,

    ingestion_id UUID NOT NULL
        REFERENCES bronze.ingestion_metadata(ingestion_id),

    loaded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT ck_pension_beneficiary_count
        CHECK (beneficiary_count >= 0),

    CONSTRAINT ck_pension_scheme
        CHECK (
            pension_scheme IN (
                'OLD_AGE',
                'WIDOW',
                'DISABILITY'
            )
        ),

    CONSTRAINT ck_pension_category
        CHECK (
            administrative_category IN (
                'State',
                'NE States',
                'Union Territories'
            )
        ),

    CONSTRAINT uq_pension_unit_scheme
        UNIQUE (
            administrative_unit_normalized,
            pension_scheme
        )

);


-- Indexes

CREATE INDEX IF NOT EXISTS idx_demographics_ingestion_id
    ON silver.fact_district_demographics(ingestion_id);

CREATE INDEX IF NOT EXISTS idx_housing_ingestion_id
    ON silver.fact_district_housing(ingestion_id);

CREATE INDEX IF NOT EXISTS idx_pension_unit_name
    ON silver.fact_pension_beneficiaries(administrative_unit_normalized);


-- Table Documentation

COMMENT ON TABLE silver.dim_district IS
'Canonical dimension containing one row per standardized Jharkhand district.';

COMMENT ON TABLE silver.fact_district_demographics IS
'District-level demographic counts from Census 2011. Age_Group_50 is retained as a 50-plus age proxy, not an exact 60-plus elderly count.';

COMMENT ON TABLE silver.fact_district_housing IS
'District-level housing indicators expressed as percentages from Census 2011.';

COMMENT ON COLUMN silver.fact_district_housing.household_reference_base_pct IS
'Source denominator/reference percentage. Value 100 does not represent absolute household count.';

COMMENT ON TABLE silver.fact_pension_beneficiaries IS
'State/UT-level pension beneficiary counts by scheme. No district-level allocation is inferred.';

COMMIT;

