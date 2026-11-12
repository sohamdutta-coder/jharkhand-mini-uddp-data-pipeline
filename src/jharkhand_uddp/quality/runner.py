"""Execute data quality checks and persist their results."""

import csv
import json
import logging
import uuid
from pathlib import Path

from sqlalchemy import Engine, text

from jharkhand_uddp.quality.checks import DQ_CHECKS
from jharkhand_uddp.quality.quarantine import (
    quarantine_source_records,
)

logger = logging.getLogger(__name__)


def execute_data_quality(
    engine: Engine,
    project_root: Path,
) -> dict:
    """Execute all registered DQ checks and produce a CSV report."""

    run_id = uuid.uuid4()

    # --------------------------------------------------------
    # 1. CREATE DQ EXECUTION RECORD
    # --------------------------------------------------------

    with engine.begin() as connection:
        connection.execute(
            text(
                """
                INSERT INTO dq.data_quality_runs (
                    run_id,
                    status
                )
                VALUES (:run_id, 'RUNNING')
                """
            ),
            {"run_id": run_id},
        )
        quarantined_count = quarantine_source_records(
            engine=engine,
            run_id=run_id,
            project_root=project_root,
        )

    logger.info(
        "Quarantine processing completed: %s records.",
        quarantined_count,
    )

    results = []

    # --------------------------------------------------------
    # 2. EXECUTE INDIVIDUAL VALIDATIONS
    # --------------------------------------------------------

    for check in DQ_CHECKS:
        logger.info("Executing %s: %s", check.code, check.description)

        execution_error = None

        try:
            with engine.connect() as connection:
                violation_count = connection.execute(text(check.sql)).scalar_one()

            violation_count = int(violation_count)

            status = "PASS" if violation_count == 0 else "FAIL"

            actual_value = str(violation_count)

            details = {
                "description": check.description,
                "violation_count": violation_count,
            }

        except Exception as exc:
            logger.exception("Execution failed for %s", check.code)

            status = "FAIL"
            actual_value = "EXECUTION_ERROR"

            execution_error = str(exc)

            details = {
                "description": check.description,
                "execution_error": execution_error,
            }

        result = {
            "run_id": str(run_id),
            "check_code": check.code,
            "layer": check.layer,
            "table_name": check.table_name,
            "severity": check.severity,
            "status": status,
            "expected_value": check.expected_value,
            "actual_value": actual_value,
            "details": details,
        }

        results.append(result)

        # Persist each check independently so earlier results
        # survive if a later validation fails.

        with engine.begin() as connection:
            connection.execute(
                text(
                    """
                    INSERT INTO dq.data_quality_results (
                        run_id,
                        check_code,
                        layer,
                        table_name,
                        severity,
                        status,
                        expected_value,
                        actual_value,
                        details
                    )
                    VALUES (
                        :run_id,
                        :check_code,
                        :layer,
                        :table_name,
                        :severity,
                        :status,
                        :expected_value,
                        :actual_value,
                        CAST(:details AS JSONB)
                    )
                    """
                ),
                {
                    **result,
                    "details": json.dumps(result["details"]),
                    "run_id": run_id,
                },
            )

    # --------------------------------------------------------
    # 3. CALCULATE EXECUTION SUMMARY
    # --------------------------------------------------------

    total_checks = len(results)

    passed_checks = sum(result["status"] == "PASS" for result in results)

    failed_checks = total_checks - passed_checks

    error_failures = sum(
        result["status"] == "FAIL" and result["severity"] == "ERROR"
        for result in results
    )

    with engine.connect() as connection:
        quarantine_count = connection.execute(
            text(
                """
                SELECT COUNT(*)
                FROM dq.quarantined_records
                WHERE run_id = :run_id
                """
            ),
            {"run_id": run_id},
        ).scalar_one()

    final_status = "FAILED" if error_failures > 0 else "SUCCEEDED"

    # --------------------------------------------------------
    # 4. UPDATE DQ EXECUTION METADATA
    # --------------------------------------------------------

    with engine.begin() as connection:
        connection.execute(
            text(
                """
                UPDATE dq.data_quality_runs
                SET
                    completed_at = CURRENT_TIMESTAMP,
                    status = :status,
                    total_checks = :total_checks,
                    passed_checks = :passed_checks,
                    failed_checks = :failed_checks,
                    quarantined_records = :quarantined_records
                WHERE run_id = :run_id
                """
            ),
            {
                "run_id": run_id,
                "status": final_status,
                "total_checks": total_checks,
                "passed_checks": passed_checks,
                "failed_checks": failed_checks,
                "quarantined_records": quarantine_count,
            },
        )

    # --------------------------------------------------------
    # 5. EXPORT CSV REPORT
    # --------------------------------------------------------

    reports_directory = project_root / "reports"
    reports_directory.mkdir(parents=True, exist_ok=True)

    report_path = reports_directory / "data_quality_report.csv"

    with report_path.open(
        "w",
        encoding="utf-8",
        newline="",
    ) as report_file:
        fieldnames = [
            "run_id",
            "check_code",
            "layer",
            "table_name",
            "severity",
            "status",
            "expected_value",
            "actual_value",
            "details",
        ]

        writer = csv.DictWriter(
            report_file,
            fieldnames=fieldnames,
        )

        writer.writeheader()

        for result in results:
            writer.writerow(
                {
                    **result,
                    "details": json.dumps(result["details"]),
                }
            )

    summary = {
        "run_id": str(run_id),
        "status": final_status,
        "total_checks": total_checks,
        "passed_checks": passed_checks,
        "failed_checks": failed_checks,
        "quarantined_records": int(quarantine_count),
        "report_path": str(report_path),
        "results": results,
    }

    return summary
