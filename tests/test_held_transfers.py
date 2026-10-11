from uuid import uuid4

from fastapi.testclient import TestClient

from app.db import get_connection
from app.main import app


client = TestClient(app)


def test_held_transfer_can_be_released_without_moving_money_early(monkeypatch):
    """Held transfers must not move money until an admin releases them."""
    monkeypatch.setenv("ADMIN_API_TOKEN", "test-only-admin-token")
    suffix = uuid4().hex

    with get_connection() as conn:
        sender_user = conn.execute(
            "INSERT INTO users (full_name, email) VALUES (%s, %s) RETURNING user_id",
            (f"Held Sender {suffix}", f"held-sender-{suffix}@example.com"),
        ).fetchone()[0]
        receiver_user = conn.execute(
            "INSERT INTO users (full_name, email) VALUES (%s, %s) RETURNING user_id",
            (f"Held Receiver {suffix}", f"held-receiver-{suffix}@example.com"),
        ).fetchone()[0]

        sender = conn.execute(
            "INSERT INTO wallets (user_id, currency) VALUES (%s, 'INR') RETURNING wallet_id",
            (sender_user,),
        ).fetchone()[0]
        receiver = conn.execute(
            "INSERT INTO wallets (user_id, currency) VALUES (%s, 'INR') RETURNING wallet_id",
            (receiver_user,),
        ).fetchone()[0]

        conn.execute(
            "SELECT fund_wallet(%s, %s, %s, %s)",
            (f"held-funding-{suffix}", sender, 2_000_000, "INR"),
        )

    response = client.post(
        "/transfers",
        headers={"Idempotency-Key": f"held-transfer-{suffix}"},
        json={
            "source_wallet_id": sender,
            "destination_wallet_id": receiver,
            "amount_minor": 1_000_001,
            "currency": "INR",
        },
    )

    assert response.status_code == 200, response.text
    transfer = response.json()
    assert transfer["status"] == "held"
    transfer_id = transfer["transfer_id"]

    with get_connection() as conn:
        entry_count = conn.execute(
            "SELECT COUNT(*) FROM ledger_entries WHERE transfer_id = %s",
            (transfer_id,),
        ).fetchone()[0]

    assert entry_count == 0, "A held transfer must not create ledger entries"

    release_response = client.post(
        f"/admin/transfers/{transfer_id}/release",
        headers={"X-Admin-Token": "test-only-admin-token"},
    )

    assert release_response.status_code == 200, release_response.text
    assert release_response.json()["status"] == "completed"

    with get_connection() as conn:
        final_status = conn.execute(
            "SELECT status FROM transfers WHERE transfer_id = %s",
            (transfer_id,),
        ).fetchone()[0]
        entry_count = conn.execute(
            "SELECT COUNT(*) FROM ledger_entries WHERE transfer_id = %s",
            (transfer_id,),
        ).fetchone()[0]

    assert final_status == "completed"
    assert entry_count == 2, "Released transfer must create both ledger entries"
