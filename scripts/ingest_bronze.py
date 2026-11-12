# Command-line entry point for Bronze ingestion.

import argparse
import logging
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = PROJECT_ROOT / "src"
RAW_DATA_DIR = PROJECT_ROOT / "data" / "raw"

sys.path.insert(0, str(SOURCE_DIR))

from jharkhand_uddp.database.connection import (
    dispose_engine,
    get_engine,
)
from jharkhand_uddp.ingestion.bronze_loader import (
    BronzeLoader,
)
from jharkhand_uddp.ingestion.source_registry import (
    SOURCE_REGISTRY,
)


def configure_logging() -> None:
    """Configure ingestion logging."""

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Jharkhand Mini UDDP Bronze Ingestion")

    parser.add_argument(
        "--source",
        choices=[source.table_name for source in SOURCE_REGISTRY],
        help="Ingest a specific source.",
    )

    parser.add_argument(
        "--all",
        action="store_true",
        help="Ingest all registered sources.",
    )

    args = parser.parse_args()

    if not args.all and not args.source:
        parser.error("Specify either --source or --all.")

    configure_logging()

    sources = (
        list(SOURCE_REGISTRY)
        if args.all
        else [source for source in SOURCE_REGISTRY if source.table_name == args.source]
    )

    engine = get_engine()

    try:
        loader = BronzeLoader(engine)

        for source in sources:
            file_path = RAW_DATA_DIR / source.filename

            result = loader.ingest(
                source=source,
                file_path=file_path,
                project_root=PROJECT_ROOT,
            )

            print("\nIngestion Result")
            print("----------------")
            print(f"Source: {result.source_name}")
            print(f"Run ID: {result.ingestion_id}")
            print(f"Status: {result.status}")
            print(f"Expected rows: {result.source_row_count}")
            print(f"Loaded rows: {result.loaded_row_count}")
            print(f"Skipped: {result.skipped}")

    finally:
        dispose_engine()


if __name__ == "__main__":
    main()
