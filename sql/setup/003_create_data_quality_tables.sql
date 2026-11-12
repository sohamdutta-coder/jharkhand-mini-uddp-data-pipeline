
BEGIN;

-- ============================================================
-- 1. DATA QUALITY RUNS
-- Grain: One row per DQ execution.
-- ============================================================

CREATE TABLE IF NOT EXISTS dq.data_quality_runs (

    run_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    started_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    completed_at TIMESTAMPTZ,

    status VARCHAR(20) NOT NULL DEFAULT 'RUNNING',

    total_checks INTEGER NOT NULL DEFAULT 0,

    passed_checks INTEGER NOT NULL DEFAULT 0,

    failed_checks INTEGER NOT NULL DEFAULT 0,

    quarantined_records INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT ck_dq_run_status
        CHECK (status IN ('RUNNING', 'SUCCEEDED', 'FAILED')),

    CONSTRAINT ck_dq_run_counts CHECK (
        total_checks >= 0
        AND passed_checks >= 0
        AND failed_checks >= 0
        AND quarantined_records >= 0
    )

);


-- ============================================================
-- 2. DATA QUALITY RESULTS
-- Grain: One row per check per execution.
-- ============================================================

CREATE TABLE IF NOT EXISTS dq.data_quality_results (

    result_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    run_id UUID NOT NULL
        REFERENCES dq.data_quality_runs(run_id),

    check_code VARCHAR(100) NOT NULL,

    layer VARCHAR(20) NOT NULL,

    table_name VARCHAR(150) NOT NULL,

    severity VARCHAR(20) NOT NULL DEFAULT 'ERROR',

    status VARCHAR(10) NOT NULL,

    expected_value TEXT,

    actual_value TEXT,

    details JSONB NOT NULL DEFAULT '{}'::JSONB,

    checked_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT ck_dq_result_status
        CHECK (status IN ('PASS', 'FAIL')),

    CONSTRAINT ck_dq_result_severity
        CHECK (severity IN ('ERROR', 'WARNING', 'INFO')),

    CONSTRAINT uq_dq_run_check
        UNIQUE (run_id, check_code)

);


-- ============================================================
-- 3. QUARANTINED RECORDS
-- Grain: One source record per distinct validation reason.
-- ============================================================

CREATE TABLE IF NOT EXISTS dq.quarantined_records (

    quarantine_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    run_id UUID NOT NULL
        REFERENCES dq.data_quality_runs(run_id),

    source_name VARCHAR(150) NOT NULL,

    source_file_name TEXT NOT NULL,

    source_sha256 CHAR(64) NOT NULL,

    source_row_number BIGINT NOT NULL,

    target_table VARCHAR(150) NOT NULL,

    reason_code VARCHAR(100) NOT NULL,

    reason_description TEXT NOT NULL,

    raw_record JSONB NOT NULL,

    detected_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    resolved_at TIMESTAMPTZ,

    CONSTRAINT ck_quarantine_row_number
        CHECK (source_row_number > 0),

    CONSTRAINT uq_quarantine_reason
        UNIQUE (
            source_sha256,
            source_row_number,
            reason_code
        )

);


-- ============================================================
-- 4. INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_dq_results_run
    ON dq.data_quality_results(run_id);

CREATE INDEX IF NOT EXISTS idx_dq_results_status
    ON dq.data_quality_results(status);

CREATE INDEX IF NOT EXISTS idx_dq_quarantine_run
    ON dq.quarantined_records(run_id);

CREATE INDEX IF NOT EXISTS idx_dq_quarantine_source
    ON dq.quarantined_records(source_name);


-- ============================================================
-- 5. DOCUMENTATION
-- ============================================================

COMMENT ON TABLE dq.data_quality_runs IS
'Execution-level audit history for data-quality validation runs.';

COMMENT ON TABLE dq.data_quality_results IS
'Individual validation results recorded for every DQ execution.';

COMMENT ON TABLE dq.quarantined_records IS
'Original source records retained with explicit reasons for validation failures.';

COMMIT;

