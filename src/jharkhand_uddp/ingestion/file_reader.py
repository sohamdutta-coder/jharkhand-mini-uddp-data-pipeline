# CSV source reading

import csv
import hashlib
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class CsvSource:
    file_path: Path
    sha256: str
    file_size_bytes: int
    headers: tuple[str, ...]
    records: tuple[dict[str, str], ...]

    @property
    def row_count(self) -> int:
        return len(self.records)


def calculate_sha256(file_path: Path) -> str:

    sha256 = hashlib.sha256()

    with file_path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            sha256.update(chunk)

    return sha256.hexdigest()


def read_csv_source(
    file_path: Path,
    required_columns: tuple[str, ...],
) -> CsvSource:
    """
    Read and validate a CSV file.

    Original source values are retained as strings.
    No cleaning or type conversion is performed.
    """

    if not file_path.is_file():
        raise FileNotFoundError(f"Source file not found: {file_path}")

    records = []

    try:
        with file_path.open(
            "r",
            encoding="utf-8-sig",
            newline="",
        ) as file:
            reader = csv.DictReader(file)

            if not reader.fieldnames:
                raise ValueError("CSV headers are missing.")

            headers = tuple(reader.fieldnames)

            if len(headers) != len(set(headers)):
                raise ValueError("Duplicate CSV column names detected.")

            missing_columns = sorted(set(required_columns) - set(headers))

            if missing_columns:
                raise ValueError(f"Required columns are missing: {missing_columns}")

            for row_number, row in enumerate(reader, start=1):
                if None in row or any(value is None for value in row.values()):
                    raise ValueError(f"Malformed CSV record at data row {row_number}.")

                records.append(dict(row))

    except (csv.Error, UnicodeError) as exc:
        raise ValueError(f"Unable to parse source CSV: {exc}") from exc

    return CsvSource(
        file_path=file_path,
        sha256=calculate_sha256(file_path),
        file_size_bytes=file_path.stat().st_size,
        headers=headers,
        records=tuple(records),
    )
