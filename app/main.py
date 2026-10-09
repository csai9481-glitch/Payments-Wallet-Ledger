
from typing import Annotated

from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, Field

from app.db import get_connection


app = FastAPI(
    title="Payments-Grade Wallet Ledger",
    description="A simple API for wallet balances, statements, and transfers.",
    version="1.1.0",
)


class TransferRequest(BaseModel):
    idempotency_key: Annotated[str, Field(min_length=1, max_length=255)]
    source_wallet_id: int = Field(gt=0)
    destination_wallet_id: int = Field(gt=0)
    amount_minor: int = Field(gt=0)
    currency: Annotated[str, Field(min_length=3, max_length=3)] = "INR"


@app.get("/")
def home():
    return {"message": "Wallet Ledger API is running"}


@app.get("/health")
def health():
    try:
        with get_connection() as conn:
            conn.execute("SELECT 1")

        return {"status": "ok", "database": "connected"}

    except Exception:
        raise HTTPException(
            status_code=503,
            detail="Database connection failed",
        )


@app.get("/wallets/{wallet_id}/balance")
def get_wallet_balance(wallet_id: int):
    try:
        with get_connection() as conn:
            row = conn.execute(
                """
                SELECT wallet_id, currency, balance_minor
                FROM wallet_balances
                WHERE wallet_id = %s
                """,
                (wallet_id,),
            ).fetchone()

        if row is None:
            raise HTTPException(status_code=404, detail="Wallet not found")

        return {
            "wallet_id": row[0],
            "currency": row[1].strip(),
            "balance_minor": row[2],
            "balance": row[2] / 100,
        }

    except HTTPException:
        raise
    except Exception:
        raise HTTPException(
            status_code=500,
            detail="Could not retrieve wallet balance",
        )


@app.get("/wallets/{wallet_id}/statement")
def get_wallet_statement(
    wallet_id: int,
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
):
    try:
        with get_connection() as conn:
            wallet = conn.execute(
                """
                SELECT wallet_id, currency
                FROM wallets
                WHERE wallet_id = %s
                """,
                (wallet_id,),
            ).fetchone()

            if wallet is None:
                raise HTTPException(
                    status_code=404,
                    detail="Wallet not found",
                )

            rows = conn.execute(
                """
                SELECT
                    ledger_entry_id,
                    transfer_id,
                    entry_type,
                    amount_minor,
                    currency,
                    created_at
                FROM ledger_entries
                WHERE wallet_id = %s
                ORDER BY created_at DESC, ledger_entry_id DESC
                LIMIT %s OFFSET %s
                """,
                (wallet_id, limit, offset),
            ).fetchall()

            total = conn.execute(
                """
                SELECT COUNT(*)
                FROM ledger_entries
                WHERE wallet_id = %s
                """,
                (wallet_id,),
            ).fetchone()[0]

        return {
            "wallet_id": wallet[0],
            "currency": wallet[1].strip(),
            "limit": limit,
            "offset": offset,
            "total": total,
            "transactions": [
                {
                    "ledger_entry_id": row[0],
                    "transfer_id": row[1],
                    "entry_type": row[2],
                    "amount_minor": row[3],
                    "currency": row[4].strip(),
                    "created_at": row[5].isoformat(),
                }
                for row in rows
            ],
        }

    except HTTPException:
        raise
    except Exception:
        raise HTTPException(
            status_code=500,
            detail="Could not retrieve wallet statement",
        )


@app.post("/transfers")
def create_transfer(request: TransferRequest):
    try:
        with get_connection() as conn:
            row = conn.execute(
                """
                SELECT transfer_money(%s, %s, %s, %s, %s)
                """,
                (
                    request.idempotency_key,
                    request.source_wallet_id,
                    request.destination_wallet_id,
                    request.amount_minor,
                    request.currency,
                ),
            ).fetchone()

        return {
            "transfer_id": row[0],
            "status": "completed",
            "amount_minor": request.amount_minor,
            "currency": request.currency,
        }

    except Exception as exc:
        message = str(exc)

        if "Idempotency key" in message and "different details" in message:
            raise HTTPException(status_code=422, detail=message)

        if "Insufficient wallet balance" in message:
            raise HTTPException(status_code=400, detail=message)

        if (
            "Idempotency key" in message
            or "must differ" in message
            or "Amount must be greater than zero" in message
            or "Wallet" in message
            or "wallet" in message
            or "currency" in message
        ):
            raise HTTPException(status_code=400, detail=message)

        raise HTTPException(
            status_code=500,
            detail="Transfer could not be completed",
        )