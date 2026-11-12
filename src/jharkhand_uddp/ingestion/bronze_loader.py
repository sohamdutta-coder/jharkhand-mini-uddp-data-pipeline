# Reusable PostgreSQL Bronze ingestion engine.

import json
import logging
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import ClassVar

from sqlalchemy import Engine, text

from jharkhand_uddp.ingestion.file_reader import read_csv_source
from jharkhand_uddp.ingestion.source_registry import SourceDefinition

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class IngestionResult:
    source_name: str
    ingestion_id: str
    status: str
    source_row_count: int
    loaded_row_count: int
    skipped: bool = False


class BronzeLoader:
    TABLES: ClassVar[set[str]] = {
        "census_demographics_raw",
        "census_housing_raw",
        "nsap_pension_raw",
    }

    BATCH_SIZE = 500
    PIPELINE_VERSION = "0.1.0"

    def __init__(self, engine: Engine) -> None:
        self.engine = engine

    def _reserve_ingestion(
        self,
        source: SourceDefinition,
        source_sha256: str,
        file_path: Path,
        project_root: Path,
        file_size_bytes: int,
        row_count: int,
    ) -> tuple[uuid.UUID, bool]:
        # Create or reuse an ingestion metadata record.

        ingestion_id = uuid.uuid4()

        with self.engine.begin() as connection:
            existing = (
                connection.execute(
                    text(
                        """
                    SELECT
                        ingestion_id,
                        status,
                        loaded_row_count,
                        started_at
                    FROM bronze.ingestion_metadata
                    WHERE source_name = :source_name
                      AND source_sha256 = :source_sha256
                    FOR UPDATE
                    """
                    ),
                    {
                        "source_name": source.source_name,
                        "source_sha256": source_sha256,
                    },
                )
                .mappings()
                .one_or_none()
            )

            if existing:
                ingestion_id = existing["ingestion_id"]

                if existing["status"] == "SUCCEEDED":
                    if existing["loaded_row_count"] != row_count:
                        raise RuntimeError(
                            "Previously ingested source has an unexpected row count."
                        )

                    return ingestion_id, True

                if existing["status"] == "STARTED":
                    stale = connection.execute(
                        text(
                            """
                            SELECT
                                started_at <
                                CURRENT_TIMESTAMP - INTERVAL '1 hour'
                            FROM bronze.ingestion_metadata
                            WHERE ingestion_id = :ingestion_id
                            """
                        ),
                        {"ingestion_id": ingestion_id},
                    ).scalar_one()

                    if not stale:
                        raise RuntimeError(
                            "An ingestion for this source file is already in progress."
                        )

                    logger.warning(
                        "Recovering a stale ingestion record: %s",
                        ingestion_id,
                    )

                connection.execute(
                    text(
                        """
                        UPDATE bronze.ingestion_metadata
                        SET
                            status = 'STARTED',
                            source_file_name = :filename,
                            source_relative_path = :relative_path,
                            source_file_size_bytes = :file_size,
                            source_row_count = :row_count,
                            loaded_row_count = 0,
                            rejected_row_count = 0,
                            started_at = CURRENT_TIMESTAMP,
                            completed_at = NULL,
                            error_message = NULL
                        WHERE ingestion_id = :ingestion_id
                        """
                    ),
                    {
                        "filename": file_path.name,
                        "relative_path": file_path.relative_to(project_root).as_posix(),
                        "file_size": file_size_bytes,
                        "row_count": row_count,
                        "ingestion_id": ingestion_id,
                    },
                )

            else:
                connection.execute(
                    text(
                        """
                        INSERT INTO bronze.ingestion_metadata (
                            ingestion_id,
                            source_name,
                            source_file_name,
                            source_relative_path,
                            source_sha256,
                            source_file_size_bytes,
                            source_row_count,
                            status,
                            pipeline_version
                        )
                        VALUES (
                            :ingestion_id,
                            :source_name,
                            :filename,
                            :relative_path,
                            :sha256,
                            :file_size,
                            :row_count,
                            'STARTED',
                            :pipeline_version
                        )
                        """
                    ),
                    {
                        "ingestion_id": ingestion_id,
                        "source_name": source.source_name,
                        "filename": file_path.name,
                        "relative_path": file_path.relative_to(project_root).as_posix(),
                        "sha256": source_sha256,
                        "file_size": file_size_bytes,
                        "row_count": row_count,
                        "pipeline_version": self.PIPELINE_VERSION,
                    },
                )

        return ingestion_id, False

    def _load_records(
        self,
        source: SourceDefinition,
        ingestion_id: uuid.UUID,
        source_sha256: str,
        source_file_name: str,
        records: tuple[dict[str, str], ...],
    ) -> int:

        if source.table_name not in self.TABLES:
            raise ValueError(f"Unregistered Bronze table: {source.table_name}")

        table_name = f"bronze.{source.table_name}"

        insert_sql = text(
            f"""
            INSERT INTO {table_name} (
                ingestion_id,
                source_file_name,
                source_sha256,
                source_row_number,
                raw_record
            )
            VALUES (
                :ingestion_id,
                :source_file_name,
                :source_sha256,
                :source_row_number,
                CAST(:raw_record AS JSONB)
            )
            ON CONFLICT (
                source_sha256,
                source_row_number
            )
            DO NOTHING
            """
        )

        with self.engine.begin() as connection:
            for start in range(0, len(records), self.BATCH_SIZE):
                batch = records[start : start + self.BATCH_SIZE]

                parameters = [
                    {
                        "ingestion_id": ingestion_id,
                        "source_file_name": source_file_name,
                        "source_sha256": source_sha256,
                        "source_row_number": start + index + 1,
                        "raw_record": json.dumps(
                            record,
                            ensure_ascii=False,
                        ),
                    }
                    for index, record in enumerate(batch)
                ]

                connection.execute(insert_sql, parameters)

            loaded_count = connection.execute(
                text(
                    f"""
                    SELECT COUNT(*)
                    FROM {table_name}
                    WHERE source_sha256 = :source_sha256
                    """
                ),
                {"source_sha256": source_sha256},
            ).scalar_one()

            if loaded_count != len(records):
                raise RuntimeError(
                    f"Row-count reconciliation failed for "
                    f"{source.table_name}: "
                    f"expected {len(records)}, got {loaded_count}."
                )

            connection.execute(
                text(
                    """
                    UPDATE bronze.ingestion_metadata
                    SET
                        status = 'SUCCEEDED',
                        loaded_row_count = :loaded_count,
                        rejected_row_count = 0,
                        completed_at = CURRENT_TIMESTAMP,
                        error_message = NULL
                    WHERE ingestion_id = :ingestion_id
                      AND status = 'STARTED'
                    """
                ),
                {
                    "loaded_count": loaded_count,
                    "ingestion_id": ingestion_id,
                },
            )

        return loaded_count

    def ingest(
        self,
        source: SourceDefinition,
        file_path: Path,
        project_root: Path,
    ) -> IngestionResult:

        logger.info("Starting ingestion: %s", source.source_name)

        csv_source = read_csv_source(
            file_path,
            source.required_columns,
        )

        ingestion_id, skipped = self._reserve_ingestion(
            source=source,
            source_sha256=csv_source.sha256,
            file_path=file_path,
            project_root=project_root,
            file_size_bytes=csv_source.file_size_bytes,
            row_count=csv_source.row_count,
        )

        if skipped:
            logger.info(
                "Source already ingested successfully. Skipping: %s",
                source.source_name,
            )

            return IngestionResult(
                source_name=source.source_name,
                ingestion_id=str(ingestion_id),
                status="SUCCEEDED",
                source_row_count=csv_source.row_count,
                loaded_row_count=csv_source.row_count,
                skipped=True,
            )

        try:
            loaded_count = self._load_records(
                source=source,
                ingestion_id=ingestion_id,
                source_sha256=csv_source.sha256,
                source_file_name=file_path.name,
                records=csv_source.records,
            )

            logger.info(
                "Successfully ingested %s records from %s",
                loaded_count,
                source.source_name,
            )

            return IngestionResult(
                source_name=source.source_name,
                ingestion_id=str(ingestion_id),
                status="SUCCEEDED",
                source_row_count=csv_source.row_count,
                loaded_row_count=loaded_count,
            )

        except Exception as exc:
            logger.exception(
                "Ingestion failed for %s",
                source.source_name,
            )

            with self.engine.begin() as connection:
                connection.execute(
                    text(
                        """
                        UPDATE bronze.ingestion_metadata
                        SET
                            status = 'FAILED',
                            completed_at = CURRENT_TIMESTAMP,
                            error_message = :error_message
                        WHERE ingestion_id = :ingestion_id
                          AND status = 'STARTED'
                        """
                    ),
                    {
                        "error_message": str(exc)[:4000],
                        "ingestion_id": ingestion_id,
                    },
                )

            raise
