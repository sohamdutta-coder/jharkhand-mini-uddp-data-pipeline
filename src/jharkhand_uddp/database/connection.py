# PostgreSQL connection management.

from __future__ import annotations

import os
from functools import lru_cache

from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL, Engine

load_dotenv()


@lru_cache(maxsize=1)
def get_engine() -> Engine:

    required_variables = [
        "DB_HOST",
        "DB_PORT",
        "DB_NAME",
        "DB_USER",
        "DB_PASSWORD",
    ]

    missing_variables = [
        variable for variable in required_variables if not os.getenv(variable)
    ]

    if missing_variables:
        raise RuntimeError(
            "Missing required environment variables: " + ", ".join(missing_variables)
        )

    try:
        db_port = int(os.environ["DB_PORT"])
    except ValueError as exc:
        raise RuntimeError("DB_PORT must be a valid integer.") from exc

    if not 1 <= db_port <= 65535:
        raise RuntimeError("DB_PORT must be between 1 and 65535.")

    database_url = URL.create(
        drivername="postgresql+psycopg",
        username=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        host=os.environ["DB_HOST"],
        port=db_port,
        database=os.environ["DB_NAME"],
    )

    engine = create_engine(
        database_url,
        pool_pre_ping=True,
        pool_size=5,
        max_overflow=5,
        pool_timeout=30,
        pool_recycle=1800,
        connect_args={"application_name": "jharkhand-mini-uddp-data-pipeline"},
    )

    return engine


def check_database_connection() -> dict:

    engine = get_engine()

    expected_schemas = {
        "bronze",
        "silver",
        "gold",
        "ml",
        "dq",
    }

    with engine.connect() as connection:
        database_info = (
            connection.execute(
                text(
                    """
                SELECT
                    current_database() AS database_name,
                    current_user AS database_user,
                    current_setting('server_version') AS server_version,
                    current_setting('TimeZone') AS timezone
                """
                )
            )
            .mappings()
            .one()
        )

        existing_schemas = set(
            connection.execute(
                text(
                    """
                    SELECT schema_name
                    FROM information_schema.schemata
                    WHERE schema_name = ANY(:schemas)
                    """
                ),
                {"schemas": list(expected_schemas)},
            )
            .scalars()
            .all()
        )

    missing_schemas = expected_schemas - existing_schemas

    if missing_schemas:
        raise RuntimeError(
            "Required database schemas are missing: "
            + ", ".join(sorted(missing_schemas))
        )

    result = dict(database_info)
    result["schemas"] = sorted(existing_schemas)

    return result


def dispose_engine() -> None:

    if get_engine.cache_info().currsize:
        get_engine().dispose()
        get_engine.cache_clear()
