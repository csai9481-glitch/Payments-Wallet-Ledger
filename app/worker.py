import os
import time
import traceback

from app.db import get_connection

INTERVAL = int(os.getenv("RECONCILIATION_INTERVAL_SECONDS", "86400"))

def run_reconciliation():
    with get_connection() as conn:
        with conn.transaction():
            conn.execute("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")
            locked = conn.execute("SELECT pg_try_advisory_xact_lock(%s)", (LOCK_ID,)).fetchone()[0]
            if not locked:
                print("Reconciliation skipped: lock is held.", flush=True)
                return
            run_id = conn.execute("SELECT run_reconciliation()").fetchone()[0]
            result = conn.execute("SELECT status, checks_passed, issues_found FROM reconciliation_runs WHERE run_id = %s", (run_id,)).fetchone()
            if result is None:
                raise RuntimeError("Reconciliation result was not saved.")
            print(f"Run {run_id}: status={result[0]}, checks={result[1]}, issues={result[2]}", flush=True)

def main():
    print(f"Wallet Ledger worker started; interval={INTERVAL}s", flush=True)
    while True:
        try:
            run_reconciliation()
        except Exception:
            print("Reconciliation failed:", flush=True)
            traceback.print_exc()
        time.sleep(INTERVAL)

if __name__ == "__main__":
    main()
