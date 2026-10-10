
import os
import sys
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed

import psycopg

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://wallet_user:wallet_dev_password@localhost:5432/wallet_db",
)

TRANSFER_AMOUNT = 10
TOTAL_REQUESTS = 100
STARTING_BALANCE = 500
MAX_WORKERS = 20
RUN_PREFIX = f"concurrency-test-{uuid.uuid4().hex}-"


def create_test_wallets():
    """Create fresh wallets and fund the sender with 500 paise."""
    with psycopg.connect(DATABASE_URL) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO users (full_name, email)
                VALUES (%s, %s)
                RETURNING user_id
                """,
                ("Concurrency Test Sender", f"{RUN_PREFIX}sender@example.com"),
            )
            sender_user_id = cur.fetchone()[0]

            cur.execute(
                """
                INSERT INTO users (full_name, email)
                VALUES (%s, %s)
                RETURNING user_id
                """,
                ("Concurrency Test Receiver", f"{RUN_PREFIX}receiver@example.com"),
            )
            receiver_user_id = cur.fetchone()[0]

            cur.execute(
                """
                INSERT INTO wallets (user_id, currency, status)
                VALUES (%s, 'INR', 'active')
                RETURNING wallet_id
                """,
                (sender_user_id,),
            )
            source_wallet = cur.fetchone()[0]

            cur.execute(
                """
                INSERT INTO wallets (user_id, currency, status)
                VALUES (%s, 'INR', 'active')
                RETURNING wallet_id
                """,
                (receiver_user_id,),
            )
            destination_wallet = cur.fetchone()[0]

            cur.execute(
                "SELECT fund_wallet(%s, %s, %s, %s)",
                (
                    f"{RUN_PREFIX}funding",
                    source_wallet,
                    STARTING_BALANCE,
                    "INR",
                ),
            )
            funding_id = cur.fetchone()[0]

    return source_wallet, destination_wallet, funding_id


def make_transfer(number, source_wallet, destination_wallet):
    """Run one transfer and return its recorded status."""
    key = f"{RUN_PREFIX}{number:03d}"

    try:
        with psycopg.connect(DATABASE_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT transfer_money(%s, %s, %s, %s, %s)",
                    (
                        key,
                        source_wallet,
                        destination_wallet,
                        TRANSFER_AMOUNT,
                        "INR",
                    ),
                )
                transfer_id = cur.fetchone()[0]

                cur.execute(
                    """
                    SELECT status
                    FROM transfers
                    WHERE transfer_id = %s
                    """,
                    (transfer_id,),
                )
                status = cur.fetchone()[0]

        return {
            "number": number,
            "status": status,
            "transfer_id": transfer_id,
            "error": None,
        }

    except psycopg.Error as error:
        return {
            "number": number,
            "status": "rejected",
            "transfer_id": None,
            "error": str(error).splitlines()[0],
        }


def get_results(source_wallet, destination_wallet):
    """Read transfer statuses, balances, and ledger integrity."""
    with psycopg.connect(DATABASE_URL) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT status, COUNT(*)
                FROM transfers
                WHERE idempotency_key LIKE %s
                GROUP BY status
                """,
                (RUN_PREFIX + "%",),
            )
            status_counts = dict(cur.fetchall())

            cur.execute(
                """
                SELECT wallet_id, balance_minor
                FROM wallet_balances
                WHERE wallet_id IN (%s, %s)
                """,
                (source_wallet, destination_wallet),
            )
            balances = dict(cur.fetchall())

            cur.execute(
                """
                SELECT COUNT(*)
                FROM transfers
                WHERE idempotency_key LIKE %s
                """,
                (RUN_PREFIX + "%",),
            )
            recorded_transfers = cur.fetchone()[0]

            # Completed transfers must have exactly two balanced entries.
            cur.execute(
                """
                SELECT COUNT(*)
                FROM transfers t
                WHERE t.idempotency_key LIKE %s
                  AND t.status = 'completed'
                  AND (
                      SELECT COUNT(*)
                      FROM ledger_entries le
                      WHERE le.transfer_id = t.transfer_id
                  ) <> 2
                """,
                (RUN_PREFIX + "%",),
            )
            completed_wrong_entry_count = cur.fetchone()[0]

            cur.execute(
                """
                SELECT COUNT(*)
                FROM (
                    SELECT t.transfer_id
                    FROM transfers t
                    JOIN ledger_entries le
                      ON le.transfer_id = t.transfer_id
                    WHERE t.idempotency_key LIKE %s
                      AND t.status = 'completed'
                    GROUP BY t.transfer_id
                    HAVING SUM(
                        CASE
                            WHEN le.entry_type = 'credit'
                                THEN le.amount_minor
                            WHEN le.entry_type = 'debit'
                                THEN -le.amount_minor
                            ELSE 0
                        END
                    ) <> 0
                    OR SUM(
                        CASE
                            WHEN le.amount_minor < 0 THEN 1
                            ELSE 0
                        END
                    ) > 0
                ) AS unbalanced
                """,
                (RUN_PREFIX + "%",),
            )
            unbalanced_completed = cur.fetchone()[0]

            # Held transfers must not move money.
            cur.execute(
                """
                SELECT COUNT(*)
                FROM transfers t
                WHERE t.idempotency_key LIKE %s
                  AND t.status = 'held'
                  AND EXISTS (
                      SELECT 1
                      FROM ledger_entries le
                      WHERE le.transfer_id = t.transfer_id
                  )
                """,
                (RUN_PREFIX + "%",),
            )
            held_with_entries = cur.fetchone()[0]

            # Compare each wallet's balance with its actual ledger.
            cur.execute(
                """
                SELECT
                    w.wallet_id,
                    COALESCE(
                        SUM(
                            CASE
                                WHEN le.entry_type = 'credit'
                                    THEN le.amount_minor
                                WHEN le.entry_type = 'debit'
                                    THEN -le.amount_minor
                                ELSE 0
                            END
                        ),
                        0
                    ) AS ledger_balance
                FROM wallets w
                LEFT JOIN ledger_entries le
                    ON le.wallet_id = w.wallet_id
                WHERE w.wallet_id IN (%s, %s)
                GROUP BY w.wallet_id
                """,
                (source_wallet, destination_wallet),
            )
            ledger_balances = dict(cur.fetchall())

    return (
        status_counts,
        balances,
        ledger_balances,
        recorded_transfers,
        completed_wrong_entry_count,
        unbalanced_completed,
        held_with_entries,
    )


def main():
    print("Creating fresh concurrency-test wallets...")
    source_wallet, destination_wallet, funding_id = create_test_wallets()

    print(f"Sender wallet: {source_wallet}")
    print(f"Receiver wallet: {destination_wallet}")
    print(f"Funding record: {funding_id}")
    print(f"Starting balance: {STARTING_BALANCE} paise")
    print(f"Each transfer: {TRANSFER_AMOUNT} paise")
    print(f"Concurrent requests: {TOTAL_REQUESTS}")
    print(f"Worker threads: {MAX_WORKERS}")
    print("\nSending requests...")

    results = []
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = [
            executor.submit(
                make_transfer, number, source_wallet, destination_wallet
            )
            for number in range(1, TOTAL_REQUESTS + 1)
        ]
        for future in as_completed(futures):
            results.append(future.result())

    status_counts, balances, ledger_balances, recorded, wrong_count, unbalanced, held_entries = (
        get_results(source_wallet, destination_wallet)
    )

    completed = status_counts.get("completed", 0)
    held = status_counts.get("held", 0)
    pending = status_counts.get("pending", 0)
    failed = status_counts.get("failed", 0)
    rejected = sum(1 for result in results if result["status"] == "rejected")

    expected_sender_balance = STARTING_BALANCE - completed * TRANSFER_AMOUNT
    expected_receiver_balance = completed * TRANSFER_AMOUNT

    print("\n--- Concurrency Test Results ---")
    print(f"Completed transfers: {completed}")
    print(f"Held transfers: {held}")
    print(f"Pending transfers: {pending}")
    print(f"Failed transfers: {failed}")
    print(f"Requests with database errors: {rejected}")
    print(f"Recorded transfers: {recorded}")
    print(f"Final wallet balances: {balances}")
    print(f"Ledger balances: {ledger_balances}")
    print(f"Completed transfers with wrong entry count: {wrong_count}")
    print(f"Unbalanced completed transfers: {unbalanced}")
    print(f"Held transfers with ledger entries: {held_entries}")

    expected_balances = {
        source_wallet: expected_sender_balance,
        destination_wallet: expected_receiver_balance,
    }

    passed = (
        len(results) == TOTAL_REQUESTS
        and rejected == 0
        and recorded == TOTAL_REQUESTS
        and pending == 0
        and failed == 0
        and completed + held == TOTAL_REQUESTS
        and completed <= STARTING_BALANCE // TRANSFER_AMOUNT
        and balances == expected_balances
        and ledger_balances == expected_balances
        and wrong_count == 0
        and unbalanced == 0
        and held_entries == 0
        and expected_sender_balance + expected_receiver_balance
            == STARTING_BALANCE
    )

    if passed:
        print("\nPASS: Concurrency, balance, and ledger checks passed.")
        print("Risk rules remained enabled.")
        return 0

    print("\nFAIL: One or more checks did not pass.")
    print("Keep all database records and share this output for investigation.")
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except psycopg.Error as error:
        print(f"\nDATABASE ERROR: {error}")
        sys.exit(1)
