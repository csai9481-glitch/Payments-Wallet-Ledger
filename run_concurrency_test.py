
import os
import sys
import uuid
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
EXPECTED_STARTING_BALANCE = 500  # 500 paise
RUN_PREFIX = f"concurrency-test-{uuid.uuid4().hex}-"


def make_transfer(number):
    key = f"{RUN_PREFIX}{number:03d}"

    try:
        with psycopg.connect(DATABASE_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT transfer_money(%s, %s, %s, %s, %s)",
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
        message = str(error).splitlines()[0]
        return False, message


def get_balances(cur):
    cur.execute(
        """
        SELECT wallet_id, balance_minor
        FROM wallet_balances
        WHERE wallet_id IN (%s, %s)
        ORDER BY wallet_id
        """,
        (SOURCE_WALLET, DESTINATION_WALLET),
    )
    return cur.fetchall()


def main():
    print("Checking test wallets before running...")

    with psycopg.connect(DATABASE_URL) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT wallet_id, status, currency
                FROM wallets
                WHERE wallet_id IN (%s, %s)
                ORDER BY wallet_id
                """,
                (SOURCE_WALLET, DESTINATION_WALLET),
            )
            wallets = cur.fetchall()
            balances = get_balances(cur)

    if len(wallets) != 2:
        print("FAIL: Both test wallets must exist.")
        return 1

    if any(status != "active" or currency != "INR"
           for _, status, currency in wallets):
        print("FAIL: Both test wallets must be active INR wallets.")
        return 1

    expected_wallet_ids = [SOURCE_WALLET, DESTINATION_WALLET]
    if [wallet_id for wallet_id, _ in balances] != expected_wallet_ids:
        print("FAIL: Could not read both wallet balances.")
        return 1

    source_balance = balances[0][1]
    destination_balance = balances[1][1]

    # The receiver starts at zero so this run's results are easy to verify.
    if destination_balance != 0:
        print(
            f"FAIL: Receiver wallet {DESTINATION_WALLET} has "
            f"{destination_balance} paise; expected 0."
        )
        print("No money was changed. Review the test wallet first.")
        return 1

    # Fund only the difference needed to bring the sender to 500 paise.
    if source_balance > EXPECTED_STARTING_BALANCE:
        print(
            f"FAIL: Sender has {source_balance} paise, more than "
            f"the expected {EXPECTED_STARTING_BALANCE} paise."
        )
        print("No money was changed.")
        return 1

    amount_to_fund = EXPECTED_STARTING_BALANCE - source_balance

    if amount_to_fund > 0:
        funding_key = f"{RUN_PREFIX}funding"

        with psycopg.connect(DATABASE_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT fund_wallet(%s, %s, %s, %s)",
                    (
                        funding_key,
                        SOURCE_WALLET,
                        amount_to_fund,
                        "INR",
                    ),
                )
                funding_id = cur.fetchone()[0]

        print(
            f"Funded sender with {amount_to_fund} paise "
            f"(funding ID {funding_id})."
        )

    with psycopg.connect(DATABASE_URL) as conn:
        with conn.cursor() as cur:
            balances = get_balances(cur)

    if balances != [
        (SOURCE_WALLET, EXPECTED_STARTING_BALANCE),
        (DESTINATION_WALLET, 0),
    ]:
        print(f"FAIL: Unexpected starting balances: {balances}")
        return 1

    print(f"Run prefix: {RUN_PREFIX}")
    print(f"Sending {TOTAL_REQUESTS} concurrent transfers...")

    with ThreadPoolExecutor(max_workers=20) as executor:
        results = list(
            executor.map(make_transfer, range(1, TOTAL_REQUESTS + 1))
        )

    successful = sum(1 for ok, _ in results if ok)
    rejected = TOTAL_REQUESTS - successful

    with psycopg.connect(DATABASE_URL) as conn:
        with conn.cursor() as cur:
            balances = get_balances(cur)

            cur.execute(
                "SELECT COUNT(*) FROM transfers WHERE idempotency_key LIKE %s",
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

    expected_balances = [
        (SOURCE_WALLET, 0),
        (DESTINATION_WALLET, EXPECTED_STARTING_BALANCE),
    ]

    print("\n--- Concurrency Test Results ---")
    print(f"Successful transfers: {successful}")
    print(f"Rejected requests: {rejected}")
    print(f"Recorded transfers: {recorded_transfers}")
    print(f"Wallet balances (wallet_id, paise): {balances}")
    print(f"Unbalanced transfers: {unbalanced_transfers}")

    passed = (
        successful == 50
        and rejected == 50
        and recorded_transfers == 50
        and balances == expected_balances
        and unbalanced_transfers == 0
    )

    if passed:
        print("\nPASS: All concurrency checks passed.")
        return 0

    print("\nFAIL: One or more concurrency checks did not pass.")
    print("Inspect the results before attempting another run.")
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except psycopg.Error as error:
        print(f"\nDATABASE ERROR: {error}")
        sys.exit(1)
