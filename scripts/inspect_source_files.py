# Inspect source datasets before Bronze ingestion.

import csv
import hashlib
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]

SOURCE_DIR = PROJECT_ROOT / "src"

RAW_DATA_DIR = PROJECT_ROOT / "data" / "raw"


PROJECT_ROOT = Path(__file__).resolve().parents[1]
RAW_DATA_DIR = PROJECT_ROOT / "data" / "raw"


def calculate_sha256(file_path: Path) -> str:

    sha256 = hashlib.sha256()

    with file_path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            sha256.update(chunk)

    return sha256.hexdigest()


def inspect_source(source) -> bool:

    file_path = RAW_DATA_DIR / source.filename

    print(f"\n{'=' * 65}")
    print(f"Source: {source.source_name}")
    print(f"File:   {source.filename}")
    print(f"{'=' * 65}")

    if not file_path.is_file():
        print("[FAILED] Source file not found.")
        return False

    try:
        checksum = calculate_sha256(file_path)

        with file_path.open(
            "r",
            encoding="utf-8-sig",
            newline="",
        ) as file:
            reader = csv.DictReader(file)

            headers = reader.fieldnames or []

            if not headers:
                print("[FAILED] CSV header is missing.")
                return False

            duplicate_headers = sorted(
                {header for header in headers if headers.count(header) > 1}
            )

            missing_columns = sorted(set(source.required_columns) - set(headers))

            row_count = 0
            jharkhand_count = 0
            malformed_rows = 0
            district_names = set()
            duplicate_districts = set()

            for row in reader:
                row_count += 1

                if None in row or None in row.values():
                    malformed_rows += 1

                state = (row.get(source.state_column) or "").strip()

                if state.casefold() == "jharkhand":
                    jharkhand_count += 1

                    if source.district_name_column:
                        district_name = (
                            row.get(source.district_name_column) or ""
                        ).strip()

                        if district_name in district_names:
                            duplicate_districts.add(district_name)

                        district_names.add(district_name)

        print(f"File size:            {file_path.stat().st_size:,} bytes")
        print(f"SHA-256:              {checksum}")
        print(f"Column count:         {len(headers)}")
        print(f"Total source rows:    {row_count}")
        print(f"Jharkhand rows:       {jharkhand_count}")
        print(f"Distinct districts:   {len(district_names)}")
        print(f"Malformed rows:       {malformed_rows}")
        print(f"Duplicate districts:  {len(duplicate_districts)}")

        if missing_columns:
            print(f"[FAILED] Missing columns: {missing_columns}")

        if duplicate_headers:
            print(f"[FAILED] Duplicate headers: {duplicate_headers}")

        if duplicate_districts:
            print(f"[WARNING] Duplicate district names: {duplicate_districts}")

        if malformed_rows:
            print("[WARNING] Rows with inconsistent CSV field counts detected.")

        if missing_columns or duplicate_headers or malformed_rows:
            return False

        print("[PASSED] Source structure verified.")
        return True

    except (OSError, csv.Error, UnicodeError) as exc:
        print(f"[FAILED] Unable to inspect source: {exc}")
        return False


def main() -> None:

    if str(SOURCE_DIR) not in sys.path:
        sys.path.insert(0, str(SOURCE_DIR))

    from jharkhand_uddp.ingestion.source_registry import SOURCE_REGISTRY

    print("\nJHARKHAND MINI UDDP - SOURCE VALIDATION")
    print(f"Raw data directory: {RAW_DATA_DIR}")

    results = [inspect_source(source) for source in SOURCE_REGISTRY]

    print(f"\n{'=' * 65}")
    print(f"Sources validated: {sum(results)}/{len(results)}")
    print(f"{'=' * 65}")

    if not all(results):
        raise SystemExit(1)

    print("\nAll source files passed structural validation.")


if __name__ == "__main__":
    main()
