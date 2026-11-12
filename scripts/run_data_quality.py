"""Command-line entry point for data quality execution."""

import logging
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = PROJECT_ROOT / "src"

sys.path.insert(0, str(SOURCE_DIR))


def main() -> None:
    from jharkhand_uddp.database.connection import (
        dispose_engine,
        get_engine,
    )
    from jharkhand_uddp.quality.runner import execute_data_quality

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    engine = get_engine()

    try:
        summary = execute_data_quality(
            engine=engine,
            project_root=PROJECT_ROOT,
        )

        print("\n" + "=" * 55)
        print("JHARKHAND MINI UDDP - DATA QUALITY REPORT")
        print("=" * 55)

        print(f"Run ID             : {summary['run_id']}")
        print(f"Status             : {summary['status']}")
        print(f"Total checks       : {summary['total_checks']}")
        print(f"Passed checks      : {summary['passed_checks']}")
        print(f"Failed checks      : {summary['failed_checks']}")
        print(f"Quarantined records: {summary['quarantined_records']}")

        print("\nReport generated:")
        print(summary["report_path"])

        print("\nIndividual results:")

        for result in summary["results"]:
            print(
                f"{result['check_code']} | "
                f"{result['status']} | "
                f"{result['description'] if 'description' in result else result['table_name']}"
            )

        print("=" * 55)

        if summary["status"] == "FAILED":
            raise SystemExit(1)

    finally:
        dispose_engine()


if __name__ == "__main__":
    main()
