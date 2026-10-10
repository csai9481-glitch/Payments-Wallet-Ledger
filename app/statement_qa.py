
from typing import Literal

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app.db import get_connection


router = APIRouter()


class StatementQuestion(BaseModel):
    question_type: Literal[
        "balance",
        "recent_transactions",
        "spending_summary",
        "transfer_status",
    ]
    question: str = Field(min_length=1, max_length=500)
    transfer_id: int | None = Field(default=None, gt=0)
    days: int = Field(default=30, ge=1, le=365)


BLOCKED_PHRASES = (
    "ignore previous instructions",
    "ignore all instructions",
    "reveal the system prompt",
    "drop table",
    "delete from",
    "update users",
    "union select",
    "execute sql",
)


def mock_statement_answer(question_type, data):
    """Return a predictable explanation without calling an external LLM."""
    if question_type == "balance":
        return (
            f"The user's total wallet balance is "
            f"{data['balance_minor']} paise "
            f"({data['balance_minor'] / 100:.2f} INR)."
        )

    if question_type == "recent_transactions":
        return (
            f"The statement contains {data['count']} recent ledger entries. "
            "See the transactions field for their details."
        )

    if question_type == "spending_summary":
        return (
            f"During the last {data['days']} days, outgoing entries totalled "
            f"{data['debits_minor']} paise and incoming entries totalled "
            f"{data['credits_minor']} paise."
        )

    return (
        f"Transfer {data['transfer_id']} has status "
        f"{data['status']} and amount {data['amount_minor']} paise."
    )


@router.post("/users/{user_id}/statement/ask")
def ask_statement_question(
    user_id: int,
    request: StatementQuestion,
):
    if user_id <= 0:
        raise HTTPException(status_code=422, detail="Invalid user ID")

    normalized_question = request.question.casefold()

    if any(phrase in normalized_question for phrase in BLOCKED_PHRASES):
        raise HTTPException(
            status_code=400,
            detail="Unsupported or unsafe question",
        )

    try:
        with get_connection() as conn:
            user = conn.execute(
                "SELECT user_id FROM users WHERE user_id = %s",
                (user_id,),
            ).fetchone()

            if user is None:
                raise HTTPException(
                    status_code=404,
                    detail="User not found",
                )

            if request.question_type == "balance":
                row = conn.execute(
                    """
                    SELECT COALESCE(SUM(wb.balance_minor), 0)
                    FROM wallets w
                    JOIN wallet_balances wb
                      ON wb.wallet_id = w.wallet_id
                    WHERE w.user_id = %s
                    """,
                    (user_id,),
                ).fetchone()

                data = {"balance_minor": int(row[0])}

            elif request.question_type == "recent_transactions":
                rows = conn.execute(
                    """
                    SELECT
                        le.ledger_entry_id,
                        le.transfer_id,
                        le.entry_type,
                        le.amount_minor,
                        le.currency,
                        le.created_at
                    FROM ledger_entries le
                    JOIN wallets w ON w.wallet_id = le.wallet_id
                    WHERE w.user_id = %s
                    ORDER BY le.created_at DESC, le.ledger_entry_id DESC
                    LIMIT 10
                    """,
                    (user_id,),
                ).fetchall()

                transactions = [
                    {
                        "ledger_entry_id": row[0],
                        "transfer_id": row[1],
                        "entry_type": row[2],
                        "amount_minor": row[3],
                        "currency": row[4].strip(),
                        "created_at": row[5].isoformat(),
                    }
                    for row in rows
                ]

                data = {
                    "count": len(transactions),
                    "transactions": transactions,
                }

            elif request.question_type == "spending_summary":
                row = conn.execute(
                    """
                    SELECT
                        COALESCE(
                            SUM(amount_minor)
                            FILTER (WHERE entry_type = 'debit'), 0
                        ),
                        COALESCE(
                            SUM(amount_minor)
                            FILTER (WHERE entry_type = 'credit'), 0
                        )
                    FROM ledger_entries le
                    JOIN wallets w ON w.wallet_id = le.wallet_id
                    WHERE w.user_id = %s
                      AND le.created_at >=
                          NOW() - (%s * INTERVAL '1 day')
                    """,
                    (user_id, request.days),
                ).fetchone()

                data = {
                    "days": request.days,
                    "debits_minor": int(row[0]),
                    "credits_minor": int(row[1]),
                }

            else:
                if request.transfer_id is None:
                    raise HTTPException(
                        status_code=422,
                        detail="transfer_id is required for this question",
                    )

                row = conn.execute(
                    """
                    SELECT
                        t.transfer_id,
                        t.status,
                        t.amount_minor,
                        t.currency
                    FROM transfers t
                    JOIN wallets sw
                      ON sw.wallet_id = t.source_wallet_id
                    JOIN wallets dw
                      ON dw.wallet_id = t.destination_wallet_id
                    WHERE t.transfer_id = %s
                      AND (sw.user_id = %s OR dw.user_id = %s)
                    """,
                    (request.transfer_id, user_id, user_id),
                ).fetchone()

                if row is None:
                    raise HTTPException(
                        status_code=404,
                        detail="Transfer not found for this user's accounts",
                    )

                data = {
                    "transfer_id": row[0],
                    "status": row[1],
                    "amount_minor": row[2],
                    "currency": row[3].strip(),
                }

        return {
            "user_id": user_id,
            "question_type": request.question_type,
            "answer": mock_statement_answer(request.question_type, data),
            "data": data,
            "answer_source": "mock",
        }

    except HTTPException:
        raise
    except Exception:
        raise HTTPException(
            status_code=500,
            detail="Could not answer statement question",
        )
