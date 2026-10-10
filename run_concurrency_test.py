
import os
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed

import psycopg


# Safety check: this test must run only in the separate test database.
DATABASE_URL = os.environ.get("DATABASE_URL", "")

if "wallet_concurrency_db" not in DATABASE_URL:
    raise SystemExit(
        "SAFETY STOP: DATABASE_URL must point to wallet_concurrency_db."
    )

STARTING_BALANCE = 50_000  # ₹500 in paise
TRANSFER_AMOUNT = 1_000    # ₹10 in paise
TOTAL_REQUESTS = 100
MAX_WORKERS = 20
CURRENCY = "INR"

run_id = uuid.uuid4().hex[:12]
prefix = f"concurrency{run_id}"


def get_balance(conn, wallet_id):
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT COALESCE(
                SUM(
                    CASE
                        WHEN entry_type = 'credit' THEN amount_minor
                        WHEN entry_type = 'debit' THEN -amount_minor
                        ELSE 0
                    END
                ), 0
            )::bigint
            FROM ledger_entries
            WHERE wallet_id = %s
            """,
            (wallet_id,),
        )
        return cur.fetchone()[0]


def create_test_wallets():
    with psycopg.connect(DATABASE_URL) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO users (full_name, email)
                VALUES (%s, %s)
                RETURNING user_id
                """,
                ("Concurrency Test Sender", f"{prefix}-sender@example.com"),
            )
            sender_user_id = cur.fetchone()[0]

            cur.execute(
                """
                INSERT INTO users (full_name, email)
                VALUES (%s, %s)
                RETURNING user_id
                """,
                ("Concurrency Test Receiver", f"{prefix}-receiver@example.com"),
            )
            receiver_user_id = cur.fetchone()[0]

            cur.execute(
                """
                INSERT INTO wallets (user_id, currency, status)
                VALUES (%s, %s, 'active')
                RETURNING wallet_id
                """,
                (sender_user_id, CURRENCY),
            )
            sender_wallet_id = cur.fetchone()[0]

            cur.execute(
                """
                INSERT INTO wallets (user_id, currency, status)
                VALUES (%s, %s, 'active')
                RETURNING wallet_id
                """,
                (receiver_user_id, CURRENCY),
            )
            receiver_wallet_id = cur.fetchone()[0]

            cur.execute(
                """
                SELECT fund_wallet(%s, %s, %s, %s)
                """,
                (
                    f"{prefix}-funding",
                    sender_wallet_id,
                    STARTING_BALANCE,
                    CURRENCY,
                ),
            )
            cur.fetchone()

        conn.commit()

    return sender_wallet_id, receiver_wallet_id


def make_transfer(number, sender_wallet_id, receiver_wallet_id):
    key = f"{prefix}-transfer-{number}"

    try:
        with psycopg.connect(DATABASE_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT transfer_money(%s, %s, %s, %s, %s)
                    """,
                    (
                        key,
                        sender_wallet_id,
                        receiver_wallet_id,
                        TRANSFER_AMOUNT,
                        CURRENCY,
                    ),
                )
                transfer_id = cur.fetchone()[0]

                cur.execute(
                    "SELECT status FROM transfers WHERE transfer_id = %s",
                    (transfer_id,),
                )
                status = cur.fetchone()[0]

            conn.commit()

        return {"result": "recorded", "status": status}

    except psycopg.Error as exc:
        message = str(exc)

        if "Insufficient wallet balance" in message:
            return {"result": "insufficient_balance", "status": None}

        return {
            "result": "database_error",
            "status": None,
            "message": message,
        }


def verify_results(sender_wallet_id, receiver_wallet_id):
    pattern = f"{prefix}-transfer-%"

    with psycopg.connect(DATABASE_URL) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT status, COUNT(*)
                FROM transfers
                WHERE idempotency_key LIKE %s
                GROUP BY status
                ORDER BY status
                """,
                (pattern,),
            )
            status_counts = dict(cur.fetchall())

            cur.execute(
                """
                SELECT COUNT(*)
                FROM ledger_entries le
                JOIN transfers t ON t.transfer_id = le.transfer_id
                WHERE t.idempotency_key LIKE %s
                """,
                (pattern,),
            )
            ledger_entry_count = cur.fetchone()[0]

            cur.execute(
                """
                SELECT COUNT(*)
                FROM (
                    SELECT t.transfer_id
                    FROM transfers t
                    LEFT JOIN ledger_entries le
                        ON le.transfer_id = t.transfer_id
                    WHERE t.idempotency_key LIKE %s
                    GROUP BY t.transfer_id
                    HAVING COUNT(le.ledger_entry_id) <> 2
                        OR COALESCE(
                            SUM(
                                CASE
                                    WHEN le.entry_type = 'credit'
                                        THEN le.amount_minor
                                    WHEN le.entry_type = 'debit'
                                        THEN -le.amount_minor
                                    ELSE 0
                                END
                            ), 0
                        ) <> 0
                ) AS invalid_transfers
                """,
                (pattern,),
            )
            invalid_completed_ledger_count = cur.fetchone()[0]

        sender_balance = get_balance(conn, sender_wallet_id)
        receiver_balance = get_balance(conn, receiver_wallet_id)

    return (
        status_counts,
        ledger_entry_count,
        invalid_completed_ledger_count,
        sender_balance,
        receiver_balance,
    )


def main():
    print("Creating fresh test wallets...")
    sender_wallet_id, receiver_wallet_id = create_test_wallets()

    print(f"Sender wallet: {sender_wallet_id}")
    print(f"Receiver wallet: {receiver_wallet_id}")
    print("Starting balance: ₹500.00")
    print("Each transfer: ₹10.00")
    print(f"Concurrent requests: {TOTAL_REQUESTS}")
    print(f"Worker threads: {MAX_WORKERS}")
    print("Running transfers...\n")

    outcomes = []

    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = [
            executor.submit(
                make_transfer,
                number,
                sender_wallet_id,
                receiver_wallet_id,
            )
            for number in range(1, TOTAL_REQUESTS + 1)
        ]

        for future in as_completed(futures):
            outcomes.append(future.result())

    completed_requests = sum(
        result["result"] == "recorded"
        and result["status"] == "completed"
        for result in outcomes
    )
    held_requests = sum(
        result["result"] == "recorded"
        and result["status"] == "held"
        for result in outcomes
    )
    insufficient_requests = sum(
        result["result"] == "insufficient_balance"
        for result in outcomes
    )
    database_errors = [
        result for result in outcomes
        if result["result"] == "database_error"
    ]
    other_recorded_statuses = sum(
        result["result"] == "recorded"
        and result["status"] not in ("completed", "held")
        for result in outcomes
    )

    (
        status_counts,
        ledger_entry_count,
        invalid_ledger_count,
        sender_balance,
        receiver_balance,
    ) = verify_results(sender_wallet_id, receiver_wallet_id)

    print("----- RESULTS -----")
    print(f"Completed transfers: {completed_requests}")
    print(f"Held transfers: {held_requests}")
    print(f"Insufficient-balance rejections: {insufficient_requests}")
    print(f"Database errors: {len(database_errors)}")
    print(f"Other recorded statuses: {other_recorded_statuses}")
    print(f"Recorded transfer statuses: {status_counts}")
    print(f"Transfer ledger entries: {ledger_entry_count}")
    print(f"Invalid transfer ledger records: {invalid_ledger_count}")
    print(f"Sender final balance: {sender_balance} paise")
    print(f"Receiver final balance: {receiver_balance} paise")

    if database_errors:
        print("\nDatabase error details:")
        for error in database_errors[:5]:
            print(error.get("message", "Unknown database error"))

    passed = (
        len(outcomes) == TOTAL_REQUESTS
        and completed_requests == 50
        and held_requests == 0
        and insufficient_requests == 50
        and not database_errors
        and other_recorded_statuses == 0
        and status_counts.get("completed", 0) == 50
        and status_counts.get("held", 0) == 0
        and ledger_entry_count == 100
        and invalid_ledger_count == 0
        and sender_balance == 0
        and receiver_balance == STARTING_BALANCE
    )

    if passed:
        print("\nPASS: Concurrency, balance, and ledger checks passed.")
    else:
        print("\nFAIL: One or more checks did not match expectations.")
        print("Review the results above before changing any risk rules.")


if __name__ == "__main__":
    main()
