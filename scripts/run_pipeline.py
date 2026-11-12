"""End-to-end orchestrator for the Jharkhand Mini-UDDP pipeline."""

from __future__ import annotations

import argparse
import json
import logging
import os
import shutil
import subprocess
import sys
import time
import uuid
from datetime import UTC, datetime
from pathlib import Path
from urllib.error import URLError
from urllib.request import Request, urlopen

import yaml
from dotenv import load_dotenv

PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = PROJECT_ROOT / "src"

sys.path.insert(0, str(SOURCE_DIR))

STAGE_ORDER = [
    "bronze",
    "silver",
    "source_validation",
    "data_quality",
    "gold",
    "ml",
    "export",
]

logger = logging.getLogger("jharkhand_uddp.pipeline")


def utc_now() -> str:
    """Return the current UTC timestamp."""

    return datetime.now(UTC).isoformat()


def configure_logging(config: dict) -> None:
    """Configure console and persistent file logging."""

    logging_config = config["logging"]

    log_file = PROJECT_ROOT / logging_config["log_file"]
    log_file.parent.mkdir(parents=True, exist_ok=True)

    level = getattr(
        logging,
        str(logging_config.get("level", "INFO")).upper(),
        logging.INFO,
    )

    logging.basicConfig(
        level=level,
        format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
        handlers=[
            logging.StreamHandler(),
            logging.FileHandler(log_file, encoding="utf-8"),
        ],
        force=True,
    )


def load_configuration(config_path: Path) -> dict:
    """Load and validate the pipeline configuration."""

    if not config_path.is_file():
        raise FileNotFoundError(f"Pipeline configuration not found: {config_path}")

    with config_path.open(encoding="utf-8") as config_file:
        config = yaml.safe_load(config_file)

    if not isinstance(config, dict):
        raise TypeError("Pipeline configuration must be a YAML mapping.")

    required_sections = {
        "pipeline",
        "execution",
        "logging",
        "database",
        "stages",
        "alerts",
    }

    # The execution section is nested under pipeline in pipeline.yaml.
    for section in required_sections - {"execution"}:
        if section not in config:
            raise ValueError(f"Missing configuration section: {section}")

    execution = config["pipeline"].get("execution", {})

    if not isinstance(execution, dict):
        raise TypeError("pipeline.execution must be a YAML mapping.")

    retries = int(execution.get("max_retries", 0))
    delay = float(execution.get("retry_delay_seconds", 2))
    multiplier = float(execution.get("backoff_multiplier", 2))

    if retries < 0 or delay < 0 or multiplier < 1:
        raise ValueError("Invalid retry configuration.")

    for stage in STAGE_ORDER:
        if stage not in config["stages"]:
            raise ValueError(f"Missing pipeline stage: {stage}")

    return config


def run_database_check() -> None:
    """Verify PostgreSQL connectivity and required schemas."""

    from jharkhand_uddp.database.connection import (
        check_database_connection,
        dispose_engine,
    )

    try:
        result = check_database_connection()

        logger.info(
            "Connected to database %s using PostgreSQL %s.",
            result["database_name"],
            result["server_version"],
        )

        logger.info(
            "Verified schemas: %s",
            ", ".join(result["schemas"]),
        )

    finally:
        dispose_engine()


def retry_operation(
    stage_name: str,
    operation,
    stage_record: dict,
    max_retries: int,
    retry_delay: float,
    backoff_multiplier: float,
) -> None:
    """Execute an operation with configurable exponential backoff."""

    total_attempts = max_retries + 1

    for attempt in range(1, total_attempts + 1):
        attempt_started = time.monotonic()

        try:
            logger.info(
                "Stage %s: attempt %s/%s.",
                stage_name,
                attempt,
                total_attempts,
            )

            operation()

            stage_record["attempts"].append(
                {
                    "attempt": attempt,
                    "status": "SUCCEEDED",
                    "duration_seconds": round(time.monotonic() - attempt_started, 3),
                }
            )

            return

        except Exception as exc:
            duration = round(time.monotonic() - attempt_started, 3)

            stage_record["attempts"].append(
                {
                    "attempt": attempt,
                    "status": "FAILED",
                    "duration_seconds": duration,
                    "error": str(exc),
                }
            )

            if attempt == total_attempts:
                logger.exception(
                    "Stage %s failed after %s attempt(s).",
                    stage_name,
                    attempt,
                )
                raise

            wait_time = retry_delay * (backoff_multiplier ** (attempt - 1))

            logger.warning(
                "Stage %s failed: %s. Retrying in %.1f seconds.",
                stage_name,
                exc,
                wait_time,
            )

            time.sleep(wait_time)


def run_command(
    command: list[str],
    description: str,
    environment: dict[str, str] | None = None,
) -> None:
    """Execute a subprocess and report failures."""

    logger.info("Executing: %s", description)

    result = subprocess.run(
        command,
        cwd=PROJECT_ROOT,
        env=environment,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )

    if result.stdout:
        for line in result.stdout.rstrip().splitlines():
            logger.info("%s", line)

    if result.stderr:
        for line in result.stderr.rstrip().splitlines():
            if result.returncode == 0:
                logger.info("%s", line)
            else:
                logger.error("%s", line)

    if result.returncode != 0:
        raise RuntimeError(f"{description} failed with exit code {result.returncode}.")


def run_sql_file(
    relative_path: str,
    config: dict,
) -> None:
    """Execute one SQL file through the PostgreSQL command-line client."""

    sql_path = PROJECT_ROOT / relative_path

    if not sql_path.is_file():
        raise FileNotFoundError(f"SQL file not found: {sql_path}")

    psql_path = shutil.which(config["database"].get("client", "psql"))

    if not psql_path:
        raise RuntimeError("PostgreSQL psql client was not found on PATH.")

    environment = os.environ.copy()

    db_variables = {
        "PGHOST": "DB_HOST",
        "PGPORT": "DB_PORT",
        "PGDATABASE": "DB_NAME",
        "PGUSER": "DB_USER",
        "PGPASSWORD": "DB_PASSWORD",
    }

    for pg_variable, db_variable in db_variables.items():
        value = os.getenv(db_variable)

        if not value:
            raise RuntimeError(f"Missing database environment variable: {db_variable}")

        environment[pg_variable] = value

    environment["PGCONNECT_TIMEOUT"] = "10"

    command = [
        psql_path,
        "-X",
        "-v",
        "ON_ERROR_STOP=1",
        "-f",
        str(sql_path),
    ]

    run_command(
        command,
        description=f"SQL: {relative_path}",
        environment=environment,
    )


def run_sql_stage(stage_name: str, config: dict) -> None:
    """Execute all SQL files configured for a stage."""

    sql_files = config["stages"][stage_name].get("sql_files", [])

    if not sql_files:
        raise ValueError(f"No SQL files configured for {stage_name}.")

    for sql_file in sql_files:
        run_sql_file(sql_file, config)


def run_python_script(script_path: str) -> None:
    """Execute an existing Python pipeline entry point."""

    path = PROJECT_ROOT / script_path

    if not path.is_file():
        raise FileNotFoundError(f"Python script not found: {path}")

    run_command(
        [sys.executable, str(path)],
        description=script_path,
    )


def run_bronze() -> None:
    """Execute Bronze ingestion for all registered sources."""

    run_command(
        [
            sys.executable,
            str(PROJECT_ROOT / "scripts" / "ingest_bronze.py"),
            "--all",
        ],
        description="Bronze ingestion",
    )


def run_data_quality() -> None:
    """Execute data quality checks and quarantine."""

    run_python_script("scripts/run_data_quality.py")


def execute_stage(
    stage_name: str,
    operation,
    config: dict,
    run_summary: dict,
    retryable: bool = True,
) -> None:
    """Execute a pipeline stage and record its execution metadata."""

    stage_record = {
        "stage": stage_name,
        "status": "RUNNING",
        "started_at": utc_now(),
        "attempts": [],
    }

    run_summary["stages"].append(stage_record)

    started = time.monotonic()

    execution = config["pipeline"]["execution"]

    max_retries = int(execution.get("max_retries", 0)) if retryable else 0

    try:
        retry_operation(
            stage_name=stage_name,
            operation=operation,
            stage_record=stage_record,
            max_retries=max_retries,
            retry_delay=float(execution.get("retry_delay_seconds", 2)),
            backoff_multiplier=float(execution.get("backoff_multiplier", 2)),
        )

        stage_record["status"] = "SUCCEEDED"

        logger.info("Stage %s completed successfully.", stage_name)

    except Exception as exc:
        stage_record["status"] = "FAILED"
        stage_record["error"] = str(exc)
        run_summary["failed_stage"] = stage_name
        raise

    finally:
        stage_record["completed_at"] = utc_now()
        stage_record["duration_seconds"] = round(time.monotonic() - started, 3)


def send_failure_alert(config: dict, run_summary: dict) -> None:
    """Send an optional JSON failure notification to a webhook."""

    alerts = config.get("alerts", {})

    variable_name = alerts.get(
        "webhook_environment_variable",
        "PIPELINE_ALERT_WEBHOOK",
    )

    webhook_url = os.getenv(variable_name)

    if not webhook_url:
        logger.info("No alert webhook configured; skipping notification.")
        return

    payload = {
        "event": "pipeline_failed",
        "pipeline": run_summary["pipeline"],
        "run_id": run_summary["run_id"],
        "failed_stage": run_summary.get("failed_stage"),
        "error": run_summary.get("error"),
        "timestamp": run_summary.get("completed_at"),
    }

    request = Request(
        webhook_url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        timeout = float(alerts.get("timeout_seconds", 5))

        with urlopen(request, timeout=timeout) as response:
            logger.info(
                "Failure notification delivered. HTTP status: %s",
                response.status,
            )

    except (URLError, TimeoutError, ValueError) as exc:
        logger.warning("Failure notification could not be delivered: %s", exc)


def save_run_summary(
    config: dict,
    run_summary: dict,
) -> Path:
    """Persist the execution summary as JSON."""

    runs_directory = PROJECT_ROOT / config["logging"].get(
        "runs_directory",
        "logs/pipeline_runs",
    )

    runs_directory.mkdir(parents=True, exist_ok=True)

    output_path = runs_directory / (f"{run_summary['run_id']}.json")

    temporary_path = output_path.with_suffix(".json.tmp")

    temporary_path.write_text(
        json.dumps(run_summary, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )

    temporary_path.replace(output_path)

    return output_path


def parse_arguments() -> argparse.Namespace:
    """Parse command-line arguments."""

    parser = argparse.ArgumentParser(
        description="Jharkhand Mini-UDDP Pipeline Orchestrator"
    )

    parser.add_argument(
        "--config",
        default="config/pipeline.yaml",
        help="Path to pipeline YAML configuration.",
    )

    parser.add_argument(
        "--start-at",
        choices=STAGE_ORDER,
        default="bronze",
        help=(
            "Start execution from a particular stage. "
            "Useful for rebuilding downstream layers."
        ),
    )

    return parser.parse_args()


def main() -> int:
    """Run the complete pipeline."""

    args = parse_arguments()

    load_dotenv(PROJECT_ROOT / ".env")

    config_path = Path(args.config)

    if not config_path.is_absolute():
        config_path = PROJECT_ROOT / config_path

        try:
            config = load_configuration(config_path)
            configure_logging(config)

        except (
            OSError,
            yaml.YAMLError,
            ValueError,
            TypeError,
            KeyError,
        ) as exc:
            print(f"Pipeline configuration error: {exc}", file=sys.stderr)
            return 1

    run_id = str(uuid.uuid4())

    run_summary = {
        "pipeline": config["pipeline"]["name"],
        "pipeline_version": config["pipeline"]["version"],
        "run_id": run_id,
        "status": "RUNNING",
        "start_at": args.start_at,
        "started_at": utc_now(),
        "stages": [],
    }

    pipeline_started = time.monotonic()

    logger.info("=" * 65)
    logger.info("STARTING %s", run_summary["pipeline"])
    logger.info("Run ID: %s", run_id)
    logger.info("Start stage: %s", args.start_at)
    logger.info("=" * 65)

    try:
        execute_stage(
            "database_connectivity",
            run_database_check,
            config,
            run_summary,
        )

        start_index = STAGE_ORDER.index(args.start_at)
        selected_stages = STAGE_ORDER[start_index:]

        if start_index > 0:
            logger.warning(
                "Backfill mode: skipping stages %s.",
                ", ".join(STAGE_ORDER[:start_index]),
            )

        for stage in selected_stages:
            if stage == "bronze":
                operation = run_bronze

            elif stage in {
                "silver",
                "source_validation",
                "gold",
                "ml",
            }:
                operation = lambda name=stage: run_sql_stage(name, config)

            elif stage == "data_quality":
                operation = run_data_quality

            elif stage == "export":
                operation = lambda: [
                    run_python_script(script)
                    for script in config["stages"]["export"].get("scripts", [])
                ]

            else:
                raise ValueError(f"Unknown pipeline stage: {stage}")

            execute_stage(
                stage,
                operation,
                config,
                run_summary,
                retryable=(stage != "data_quality"),
            )

        run_summary["status"] = "SUCCEEDED"

    except KeyboardInterrupt:
        run_summary["status"] = "INTERRUPTED"
        run_summary["error"] = "Pipeline interrupted by the user."
        logger.warning("Pipeline interrupted.")

    except Exception as exc:
        run_summary["status"] = "FAILED"
        run_summary["error"] = str(exc)
        logger.exception("Pipeline execution failed.")

    finally:
        run_summary["completed_at"] = utc_now()
        run_summary["duration_seconds"] = round(time.monotonic() - pipeline_started, 3)

        logger.info("=" * 65)
        logger.info("PIPELINE STATUS: %s", run_summary["status"])
        logger.info(
            "Total duration: %.3f seconds",
            run_summary["duration_seconds"],
        )

        try:
            summary_path = save_run_summary(config, run_summary)
            run_summary["summary_path"] = str(summary_path)

            logger.info("Execution summary: %s", summary_path)

        except OSError:
            logger.exception("Could not save pipeline execution summary.")

        if run_summary["status"] == "FAILED":
            send_failure_alert(config, run_summary)

        logger.info("=" * 65)

    return (
        130
        if run_summary["status"] == "INTERRUPTED"
        else (0 if run_summary["status"] == "SUCCEEDED" else 1)
    )


if __name__ == "__main__":
    raise SystemExit(main())
