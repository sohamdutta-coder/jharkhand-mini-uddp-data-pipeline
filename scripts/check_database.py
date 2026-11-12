# Verify the PostgreSQL connection and required schemas.

import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = PROJECT_ROOT / "src"

sys.path.insert(0, str(SOURCE_DIR))


def main() -> None:
    from jharkhand_uddp.database.connection import (
        check_database_connection,
        dispose_engine,
    )

    try:
        result = check_database_connection()

        print("\nPostgreSQL connection successful!\n")

        print(f"Database     : {result['database_name']}")
        print(f"User         : {result['database_user']}")
        print(f"Server       : PostgreSQL {result['server_version']}")
        print(f"Timezone     : {result['timezone']}")

        print("\nVerified schemas:")

        for schema in result["schemas"]:
            print(f"  [OK] {schema}")

        print("\nAll database checks passed.\n")

    finally:
        dispose_engine()


if __name__ == "__main__":
    main()
