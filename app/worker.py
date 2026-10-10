import time

from app.db import get_connection


def main():
    print("Wallet Ledger background worker started.", flush=True)

    while True:
        try:
            with get_connection() as conn:
                conn.execute("SELECT 1")

            print("Database connection OK.", flush=True)

        except Exception as exc:
            print(f"Worker database check failed: {exc}", flush=True)

        time.sleep(60)


if __name__ == "__main__":
    main()