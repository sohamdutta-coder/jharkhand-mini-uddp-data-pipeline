BEGIN;

-- Ingestion Metadata

CREATE TABLE IF NOT EXISTS bronze.ingestion_metadata (
    ingestion_id UUID PRIMARY KEY,

    source_name VARCHAR(150) NOT NULL,
    source_file_name TEXT NOT NULL,
    source_relative_path TEXT NOT NULL,

    source_sha256 CHAR(64) NOT NULL,
    source_file_size_bytes BIGINT NOT NULL,
    source_row_count BIGINT NOT NULL,

    loaded_row_count BIGINT NOT NULL DEFAULT 0,
    rejected_row_count BIGINT NOT NULL DEFAULT 0,

    status VARCHAR(20) NOT NULL,

    pipeline_version VARCHAR(30) NOT NULL DEFAULT '0.1.0',

    started_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMPTZ,

    error_message TEXT,

    CONSTRAINT uq_source_file_version
        UNIQUE (source_name, source_sha256),

    CONSTRAINT ck_source_sha256
        CHECK (source_sha256 ~ '^[0-9a-f]{64}$'),

    CONSTRAINT ck_source_file_size
        CHECK (source_file_size_bytes >= 0),

    CONSTRAINT ck_source_row_count
        CHECK (source_row_count >= 0),

    CONSTRAINT ck_loaded_row_count
        CHECK (loaded_row_count >= 0),

    CONSTRAINT ck_rejected_row_count
        CHECK (rejected_row_count >= 0),

    CONSTRAINT ck_ingestion_status
        CHECK (status IN ('STARTED', 'SUCCEEDED', 'FAILED')),

    CONSTRAINT ck_ingestion_completion
        CHECK (
            (status = 'STARTED' AND completed_at IS NULL)
            OR
            (status IN ('SUCCEEDED', 'FAILED')
                AND completed_at IS NOT NULL)
        )
);


-- Cencus Demographics Raw

CREATE TABLE IF NOT EXISTS bronze.census_demographics_raw (
    raw_record_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    ingestion_id UUID NOT NULL
        REFERENCES bronze.ingestion_metadata(ingestion_id),

    source_file_name TEXT NOT NULL,
    source_sha256 CHAR(64) NOT NULL,

    source_row_number BIGINT NOT NULL,

    ingested_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    raw_record JSONB NOT NULL,

    CONSTRAINT uq_demographics_source_row
        UNIQUE (source_sha256, source_row_number),

    CONSTRAINT ck_demographics_row_number
        CHECK (source_row_number > 0),

    CONSTRAINT ck_demographics_json
        CHECK (jsonb_typeof(raw_record) = 'object')
);


-- Census Housing Raw

CREATE TABLE IF NOT EXISTS bronze.census_housing_raw (
    raw_record_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    ingestion_id UUID NOT NULL
        REFERENCES bronze.ingestion_metadata(ingestion_id),

    source_file_name TEXT NOT NULL,
    source_sha256 CHAR(64) NOT NULL,

    source_row_number BIGINT NOT NULL,

    ingested_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    raw_record JSONB NOT NULL,

    CONSTRAINT uq_housing_source_row
        UNIQUE (source_sha256, source_row_number),

    CONSTRAINT ck_housing_row_number
        CHECK (source_row_number > 0),

    CONSTRAINT ck_housing_json
        CHECK (jsonb_typeof(raw_record) = 'object')
);


-- NSAP Pension Raw

CREATE TABLE IF NOT EXISTS bronze.nsap_pension_raw (
    raw_record_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    ingestion_id UUID NOT NULL
        REFERENCES bronze.ingestion_metadata(ingestion_id),

    source_file_name TEXT NOT NULL,
    source_sha256 CHAR(64) NOT NULL,

    source_row_number BIGINT NOT NULL,

    ingested_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    raw_record JSONB NOT NULL,

    CONSTRAINT uq_nsap_source_row
        UNIQUE (source_sha256, source_row_number),

    CONSTRAINT ck_nsap_row_number
        CHECK (source_row_number > 0),

    CONSTRAINT ck_nsap_json
        CHECK (jsonb_typeof(raw_record) = 'object')
);


-- Indexes

CREATE INDEX IF NOT EXISTS idx_ingestion_metadata_status
    ON bronze.ingestion_metadata(status);

CREATE INDEX IF NOT EXISTS idx_demographics_ingestion
    ON bronze.census_demographics_raw(ingestion_id);

CREATE INDEX IF NOT EXISTS idx_housing_ingestion
    ON bronze.census_housing_raw(ingestion_id);

CREATE INDEX IF NOT EXISTS idx_nsap_ingestion
    ON bronze.nsap_pension_raw(ingestion_id);


-- Table Documentation

COMMENT ON TABLE bronze.ingestion_metadata IS
'Audit metadata for source file ingestion runs.';

COMMENT ON TABLE bronze.census_demographics_raw IS
'Unmodified Census 2011 demographic source records stored as JSONB.';

COMMENT ON TABLE bronze.census_housing_raw IS
'Unmodified Census 2011 housing source records stored as JSONB.';

COMMENT ON TABLE bronze.nsap_pension_raw IS
'Unmodified NSAP state-level pension beneficiary source records stored as JSONB.';

COMMIT;
