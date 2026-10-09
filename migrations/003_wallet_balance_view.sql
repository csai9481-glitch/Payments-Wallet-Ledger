-- Calculate wallet balances from ledger entries.
-- For wallet accounts, credits increase the balance
-- and debits decrease the balance.

CREATE VIEW wallet_balances AS
SELECT
    w.wallet_id,
    w.user_id,
    w.currency,
    COALESCE(
        SUM(
            CASE
                WHEN le.entry_type = 'credit' THEN le.amount_minor
                WHEN le.entry_type = 'debit' THEN -le.amount_minor
                ELSE 0
            END
        ),
        0
    )::BIGINT AS balance_minor
FROM wallets w
LEFT JOIN ledger_entries le
    ON le.wallet_id = w.wallet_id
GROUP BY
    w.wallet_id,
    w.user_id,
    w.currency;