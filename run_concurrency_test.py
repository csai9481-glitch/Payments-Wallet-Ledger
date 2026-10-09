
import os
from concurrent.futures import ThreadPoolExecutor
import psycopg

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://wallet_user:wallet_dev_password@localhost:5432/wallet_db",
)

SOURCE_WALLET = 3
DESTINATION_WALLET = 4
TRANSFER_AMOUNT = 10  # 10 paise
TOTAL_REQUESTS = 100
RUN_PREFIX = "concurrency-test-run-1-"


def make_transfer(number):
    key = f"{RUN_PREFIX}{number:03d}"

    try:
        with psycopg.connect(DATABASE_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT transfer_money(%s, %s, %s, %s, %s)
                    """,
                    (
                        key,
                        SOURCE_WALLET,
                        DESTINATION_WALLET,
                        TRANSFER_AMOUNT,
                        "INR",
                    ),
                )
                transfer_id = cur.fetchone()[0]

        return True, transfer_id

    except psycopg.Error as error:
        # Insufficient balance is expected for some requests.
        return False, str(error).splitlines()[0]


def main():
    print(f"Sending {TOTAL_REQUESTS} concurrent transfer requests...")

    with ThreadPoolExecutor(max_workers=20) as executor:
        results = list(executor.map(make_transfer, range(1, TOTAL_REQUESTS + 1)))

    successful = sum(1 for ok, _ in results if ok)
    rejected = TOTAL_REQUESTS - successful

    with psycopg.connect(DATABASE_URL) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT wallet_id, balance_minor
                FROM wallet_balances
                WHERE wallet_id IN (%s, %s)
                ORDER BY wallet_id
                """,
                (SOURCE_WALLET, DESTINATION_WALLET),
            )
            balances = cur.fetchall()

            cur.execute(
                """
                SELECT COUNT(*)
                FROM transfers
                WHERE idempotency_key LIKE %s
                """,
                (RUN_PREFIX + "%",),
            )
            recorded_transfers = cur.fetchone()[0]

            cur.execute(
                """
                SELECT COUNT(*)
                FROM (
                    SELECT t.transfer_id
                    FROM transfers t
                    JOIN ledger_entries le
                      ON le.transfer_id = t.transfer_id
                    WHERE t.idempotency_key LIKE %s
                    GROUP BY t.transfer_id
                    HAVING COUNT(le.ledger_entry_id) <> 2
                       OR SUM(
                           CASE
                               WHEN le.entry_type = 'credit'
                                   THEN le.amount_minor
                               WHEN le.entry_type = 'debit'
                                   THEN -le.amount_minor
                               ELSE 0
                           END
                       ) <> 0
                ) AS unbalanced
                """,
                (RUN_PREFIX + "%",),
            )
            unbalanced_transfers = cur.fetchone()[0]

    print("\n--- Concurrency Test Results ---")
    print(f"Successful transfers: {successful}")
    print(f"Rejected requests: {rejected}")
    print(f"Recorded transfers: {recorded_transfers}")
    print(f"Wallet balances (wallet_id, paise): {balances}")
    print(f"Unbalanced transfers: {unbalanced_transfers}")

    expected_balances = [(3, 0), (4, 500)]

    if (
        successful == 50
        and rejected == 50
        and recorded_transfers == 50
        and balances == expected_balances
        and unbalanced_transfers == 0
    ):
        print("\nPASS: All concurrency checks passed.")
    else:
        print("\nCHECK FAILED: Review the results before running anything again.")


if __name__ == "__main__":
    main()