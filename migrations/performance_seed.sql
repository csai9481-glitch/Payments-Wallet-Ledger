
-- Synthetic performance dataset.
-- Run ONLY in the separate wallet_perf_db database.
-- Creates 1,000 users, 2,000 wallets, 100,000 transfers,
-- and 200,000 balanced ledger entries.

BEGIN;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM transfers
        WHERE idempotency_key LIKE 'perf-seed-v1-%'
    ) THEN
        RAISE EXCEPTION
            'Performance seed already exists. Use a fresh performance database.';
    END IF;
END $$;

-- Create 1,000 dedicated users.
INSERT INTO users (full_name, email, kyc_status)
SELECT
    'Performance User ' || n,
    'perf-seed-v1-' || n || '@example.test',
    'verified'
FROM generate_series(1, 1000) AS n;

-- Create two wallets per performance user.
INSERT INTO wallets (user_id, currency, status)
SELECT u.user_id, c.currency, 'active'
FROM users u
CROSS JOIN (VALUES ('INR'), ('USD')) AS c(currency)
WHERE u.email LIKE 'perf-seed-v1-%@example.test';

-- Create 50,000 INR and 50,000 USD transfers.
-- Each currency group forms a balanced cycle across 1,000 wallets.
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
    CROSS JOIN generate_series(1, 50000) AS g(n)
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
    'perf-seed-v1-' || currency || '-' || n,
    source_wallet_id,
    destination_wallet_id,
    100,
    currency,
    'completed',
    NOW()
FROM transfer_rows;

-- Add exactly one debit and one credit for each seeded transfer.
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
WHERE t.idempotency_key LIKE 'perf-seed-v1-%';

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
WHERE t.idempotency_key LIKE 'perf-seed-v1-%';

COMMIT;

-- Show the created dataset counts.
SELECT 'performance users' AS item, COUNT(*) AS total
FROM users
WHERE email LIKE 'perf-seed-v1-%@example.test'
UNION ALL
SELECT 'performance wallets', COUNT(*)
FROM wallets w
JOIN users u ON u.user_id = w.user_id
WHERE u.email LIKE 'perf-seed-v1-%@example.test'
UNION ALL
SELECT 'performance transfers', COUNT(*)
FROM transfers
WHERE idempotency_key LIKE 'perf-seed-v1-%'
UNION ALL
SELECT 'performance ledger entries', COUNT(*)
FROM ledger_entries le
JOIN transfers t ON t.transfer_id = le.transfer_id
WHERE t.idempotency_key LIKE 'perf-seed-v1-%';
