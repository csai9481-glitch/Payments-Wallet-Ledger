
from uuid import uuid4

from fastapi.testclient import TestClient

from app.db import get_connection
from app.main import app


client = TestClient(app)


def test_reconciliation_detects_extra_transfer_ledger_entry():
    """Reconciliation should detect an extra entry and clean up the test data."""
    suffix = uuid4().hex
    extra_entry_id = None

    # Create fresh wallets for this test.
    with get_connection() as conn:
        sender_user = conn.execute(
            """
            INSERT INTO users (full_name, email)
            VALUES (%s, %s)
            RETURNING user_id
            """,
            (f"Reconciliation Sender {suffix}",
             f"recon-sender-{suffix}@example.com"),
        ).fetchone()[0]

        receiver_user = conn.execute(
            """
            INSERT INTO users (full_name, email)
            VALUES (%s, %s)
            RETURNING user_id
            """,
            (f"Reconciliation Receiver {suffix}",
             f"recon-receiver-{suffix}@example.com"),
        ).fetchone()[0]

        sender_wallet = conn.execute(
            """
            INSERT INTO wallets (user_id, currency)
            VALUES (%s, 'INR')
            RETURNING wallet_id
            """,
            (sender_user,),
        ).fetchone()[0]

        receiver_wallet = conn.execute(
            """
            INSERT INTO wallets (user_id, currency)
            VALUES (%s, 'INR')
            RETURNING wallet_id
            """,
            (receiver_user,),
        ).fetchone()[0]

        conn.execute(
            "SELECT fund_wallet(%s, %s, %s, %s)",
            (f"recon-funding-{suffix}", sender_wallet, 1000, "INR"),
        )

    # Make a real transfer using the existing API.
    response = client.post(
        "/transfers",
        headers={"Idempotency-Key": f"recon-transfer-{suffix}"},
        json={
            "source_wallet_id": sender_wallet,
            "destination_wallet_id": receiver_wallet,
            "amount_minor": 100,
            "currency": "INR",
        },
    )

    assert response.status_code == 200, response.text
    assert response.json()["status"] == "completed"

    transfer_id = response.json()["transfer_id"]

    try:
        # Add one temporary extra ledger entry to simulate corruption.
        with get_connection() as conn:
            extra_entry_id = conn.execute(
                """
                INSERT INTO ledger_entries
                    (transfer_id, wallet_id, system_account_id,
                     entry_type, amount_minor, currency)
                VALUES (%s, %s, NULL, 'debit', %s, 'INR')
                RETURNING ledger_entry_id
                """,
                (transfer_id, sender_wallet, 100),
            ).fetchone()[0]

        # Run reconciliation against the deliberately inconsistent ledger.
        with get_connection() as conn:
            run_id = conn.execute(
                "SELECT run_reconciliation()"
            ).fetchone()[0]

            issue = conn.execute(
                """
                SELECT issue_type
                FROM reconciliation_issues
                WHERE run_id = %s
                  AND transfer_id = %s
                  AND issue_type = 'transfer_ledger_mismatch'
                """,
                (run_id, transfer_id),
            ).fetchone()

        assert issue is not None, (
            "Reconciliation did not detect the extra ledger entry"
        )

    finally:
        # Remove only the extra entry created by this test.
        if extra_entry_id is not None:
            with get_connection() as conn:
                conn.execute(
                    """
                    DELETE FROM ledger_entries
                    WHERE ledger_entry_id = %s
                    """,
                    (extra_entry_id,),
                )
