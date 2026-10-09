
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.db import get_connection
from app.main import app


client = TestClient(app)


def create_test_wallets():
    """Create two dedicated wallets for an idempotency test."""
    suffix = uuid4().hex

    with get_connection() as conn:
        sender_user = conn.execute(
            """
            INSERT INTO users (full_name, email)
            VALUES (%s, %s)
            RETURNING user_id
            """,
            (f"Test Sender {suffix}", f"sender-{suffix}@example.com"),
        ).fetchone()[0]

        receiver_user = conn.execute(
            """
            INSERT INTO users (full_name, email)
            VALUES (%s, %s)
            RETURNING user_id
            """,
            (f"Test Receiver {suffix}", f"receiver-{suffix}@example.com"),
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
            """
            SELECT fund_wallet(%s, %s, %s, %s)
            """,
            (f"test-funding-{suffix}", sender_wallet, 1000, "INR"),
        )

    return sender_wallet, receiver_wallet


def get_balance(wallet_id):
    with get_connection() as conn:
        row = conn.execute(
            """
            SELECT balance_minor
            FROM wallet_balances
            WHERE wallet_id = %s
            """,
            (wallet_id,),
        ).fetchone()

    return row[0]


def test_home_endpoint():
    response = client.get("/")
    assert response.status_code == 200
    assert response.json()["message"] == "Wallet Ledger API is running"


def test_health_endpoint():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"
    assert response.json()["database"] == "connected"


def test_alice_wallet_balance():
    response = client.get("/wallets/1/balance")
    assert response.status_code == 200
    data = response.json()
    assert data["wallet_id"] == 1
    assert data["currency"] == "INR"
    assert data["balance_minor"] == 70000
    assert data["balance"] == 700.0


def test_bob_wallet_balance():
    response = client.get("/wallets/2/balance")
    assert response.status_code == 200
    data = response.json()
    assert data["wallet_id"] == 2
    assert data["currency"] == "INR"
    assert data["balance_minor"] == 30000
    assert data["balance"] == 300.0


def test_missing_wallet():
    response = client.get("/wallets/999999/balance")
    assert response.status_code == 404
    assert response.json()["detail"] == "Wallet not found"


def test_repeated_transfer_uses_same_transfer():
    sender, receiver = create_test_wallets()
    key = f"test-idempotency-{uuid4().hex}"

    payload = {
        "idempotency_key": key,
        "source_wallet_id": sender,
        "destination_wallet_id": receiver,
        "amount_minor": 100,
        "currency": "INR",
    }

    responses = [
        client.post("/transfers", json=payload)
        for _ in range(5)
    ]

    assert all(response.status_code == 200 for response in responses)

    transfer_ids = [
        response.json()["transfer_id"]
        for response in responses
    ]
    assert len(set(transfer_ids)) == 1

    with get_connection() as conn:
        count = conn.execute(
            """
            SELECT COUNT(*)
            FROM transfers
            WHERE idempotency_key = %s
            """,
            (key,),
        ).fetchone()[0]

    assert count == 1
    assert get_balance(sender) == 900
    assert get_balance(receiver) == 100


def test_idempotency_key_with_different_amount_returns_422():
    sender, receiver = create_test_wallets()
    key = f"test-idempotency-mismatch-{uuid4().hex}"

    payload = {
        "idempotency_key": key,
        "source_wallet_id": sender,
        "destination_wallet_id": receiver,
        "amount_minor": 100,
        "currency": "INR",
    }

    first_response = client.post("/transfers", json=payload)
    assert first_response.status_code == 200

    changed_payload = {
        **payload,
        "amount_minor": 200,
    }

    second_response = client.post("/transfers", json=changed_payload)
    assert second_response.status_code == 422

    assert get_balance(sender) == 900
    assert get_balance(receiver) == 100