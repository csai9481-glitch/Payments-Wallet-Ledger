
-- Add 400,000 synthetic transfers and 800,000 ledger entries.
-- Run only in wallet_perf_db.

BEGIN;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM transfers
        WHERE idempotency_key LIKE 'perf-scale-v1-%'
    ) THEN
        RAISE EXCEPTION
            'Scale-up data already exists. Do not rerun this script.';
    END IF;
END $$;

WITH numbered_wallets AS (
    SELECT
        w.wallet_id,
        w.currency,
        ROW_NUMBER() OVER (
            PARTITION BY w.currency ORDER BY w.wallet_id
        ) AS wallet_number
    FROM wallets w
    JOIN users u ON u.user_id = w.user_id
    WHERE u.email LIKE 'perf-seed-v1-%@example.test'
),
transfer_rows AS (
    SELECT
        c.currency,
        g.n,
        src.wallet_id AS source_wallet_id,
        dst.wallet_id AS destination_wallet_id
    FROM (VALUES ('INR'), ('USD')) AS c(currency)
    CROSS JOIN generate_series(1, 200000) AS g(n)
    JOIN numbered_wallets src
      ON src.currency = c.currency
     AND src.wallet_number = ((g.n - 1) % 1000) + 1
    JOIN numbered_wallets dst
      ON dst.currency = c.currency
     AND dst.wallet_number = (g.n % 1000) + 1
)
INSERT INTO transfers (
    idempotency_key,
    source_wallet_id,
    destination_wallet_id,
    amount_minor,
    currency,
    status,
    completed_at
)
SELECT
    'perf-scale-v1-' || currency || '-' || n,
    source_wallet_id,
    destination_wallet_id,
    100,
    currency,
    'completed',
    NOW()
FROM transfer_rows;

INSERT INTO ledger_entries (
    transfer_id, wallet_id, entry_type, amount_minor, currency
)
SELECT
    t.transfer_id,
    t.source_wallet_id,
    'debit',
    t.amount_minor,
    t.currency
FROM transfers t
WHERE t.idempotency_key LIKE 'perf-scale-v1-%';

INSERT INTO ledger_entries (
    transfer_id, wallet_id, entry_type, amount_minor, currency
)
SELECT
    t.transfer_id,
    t.destination_wallet_id,
    'credit',
    t.amount_minor,
    t.currency
FROM transfers t
WHERE t.idempotency_key LIKE 'perf-scale-v1-%';

COMMIT;

SELECT
    COUNT(*) AS total_ledger_entries
FROM ledger_entries le
JOIN transfers t ON t.transfer_id = le.transfer_id
WHERE t.idempotency_key LIKE 'perf-seed-v1-%'
   OR t.idempotency_key LIKE 'perf-scale-v1-%';
