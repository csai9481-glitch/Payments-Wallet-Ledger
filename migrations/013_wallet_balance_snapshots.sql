
BEGIN;

-- 1. Create a separate stored balance snapshot for each wallet.
CREATE TABLE IF NOT EXISTS wallet_balance_snapshots (
    wallet_id BIGINT PRIMARY KEY
        REFERENCES wallets(wallet_id) ON DELETE CASCADE,
    balance_minor BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Initialize snapshots using the current ledger-derived balances.
INSERT INTO wallet_balance_snapshots (wallet_id, balance_minor)
SELECT wallet_id, balance_minor
FROM wallet_balances
ON CONFLICT (wallet_id) DO NOTHING;

-- 3. Automatically initialize a snapshot when a wallet is created.
CREATE OR REPLACE FUNCTION initialize_wallet_balance_snapshot()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO wallet_balance_snapshots (wallet_id, balance_minor)
    VALUES (NEW.wallet_id, 0)
    ON CONFLICT (wallet_id) DO NOTHING;

    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_initialize_wallet_balance_snapshot
ON wallets;

CREATE TRIGGER trg_initialize_wallet_balance_snapshot
AFTER INSERT ON wallets
FOR EACH ROW
EXECUTE FUNCTION initialize_wallet_balance_snapshot();

-- 4. Maintain the stored snapshot when ledger entries change.
CREATE OR REPLACE FUNCTION maintain_wallet_balance_snapshot()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $function$
DECLARE
    v_delta BIGINT;
BEGIN
    IF TG_OP = 'INSERT' THEN

        IF NEW.wallet_id IS NOT NULL THEN
            v_delta := CASE
                WHEN NEW.entry_type = 'credit' THEN NEW.amount_minor
                ELSE -NEW.amount_minor
            END;

            INSERT INTO wallet_balance_snapshots
                (wallet_id, balance_minor)
            VALUES (NEW.wallet_id, v_delta)
            ON CONFLICT (wallet_id) DO UPDATE
            SET balance_minor =
                    wallet_balance_snapshots.balance_minor
                    + EXCLUDED.balance_minor,
                updated_at = NOW();
        END IF;

        RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN

        IF OLD.wallet_id IS NOT NULL THEN
            v_delta := CASE
                WHEN OLD.entry_type = 'credit' THEN OLD.amount_minor
                ELSE -OLD.amount_minor
            END;

            UPDATE wallet_balance_snapshots
            SET balance_minor = balance_minor - v_delta,
                updated_at = NOW()
            WHERE wallet_id = OLD.wallet_id;
        END IF;

        RETURN OLD;

    ELSE

        -- Reverse the old entry's effect.
        IF OLD.wallet_id IS NOT NULL THEN
            v_delta := CASE
                WHEN OLD.entry_type = 'credit' THEN OLD.amount_minor
                ELSE -OLD.amount_minor
            END;

            UPDATE wallet_balance_snapshots
            SET balance_minor = balance_minor - v_delta,
                updated_at = NOW()
            WHERE wallet_id = OLD.wallet_id;
        END IF;

        -- Apply the updated entry's effect.
        IF NEW.wallet_id IS NOT NULL THEN
            v_delta := CASE
                WHEN NEW.entry_type = 'credit' THEN NEW.amount_minor
                ELSE -NEW.amount_minor
            END;

            INSERT INTO wallet_balance_snapshots
                (wallet_id, balance_minor)
            VALUES (NEW.wallet_id, v_delta)
            ON CONFLICT (wallet_id) DO UPDATE
            SET balance_minor =
                    wallet_balance_snapshots.balance_minor
                    + EXCLUDED.balance_minor,
                updated_at = NOW();
        END IF;

        RETURN NEW;
    END IF;
END;
$function$;

DROP TRIGGER IF EXISTS trg_maintain_wallet_balance_snapshot
ON ledger_entries;

CREATE TRIGGER trg_maintain_wallet_balance_snapshot
AFTER INSERT OR UPDATE OR DELETE ON ledger_entries
FOR EACH ROW
EXECUTE FUNCTION maintain_wallet_balance_snapshot();

-- 5. Update reconciliation to check transfer ledger entries,
-- funding ledger entries, ledger balance, negative balances,
-- and stored wallet balance snapshots.
CREATE OR REPLACE FUNCTION run_reconciliation()
RETURNS BIGINT
LANGUAGE plpgsql
AS $function$
DECLARE
    v_run_id BIGINT;
    v_issue_count INTEGER;
    v_failed_checks INTEGER;
BEGIN
    INSERT INTO reconciliation_runs (status)
    VALUES ('running')
    RETURNING run_id INTO v_run_id;

    -- Check completed transfers for missing or incorrect entries.
    INSERT INTO reconciliation_issues
        (run_id, issue_type, description, transfer_id)
    SELECT
        v_run_id,
        'transfer_ledger_mismatch',
        'Completed transfer has missing, extra, or incorrect ledger entries.',
        t.transfer_id
    FROM transfers t
    WHERE t.status = 'completed'
      AND (
          (SELECT COUNT(*)
           FROM ledger_entries le
           WHERE le.transfer_id = t.transfer_id) <> 2

          OR NOT EXISTS (
              SELECT 1
              FROM ledger_entries le
              WHERE le.transfer_id = t.transfer_id
                AND le.entry_type = 'debit'
                AND le.wallet_id = t.source_wallet_id
                AND le.amount_minor = t.amount_minor
                AND le.currency = t.currency
          )

          OR NOT EXISTS (
              SELECT 1
              FROM ledger_entries le
              WHERE le.transfer_id = t.transfer_id
                AND le.entry_type = 'credit'
                AND le.wallet_id = t.destination_wallet_id
                AND le.amount_minor = t.amount_minor
                AND le.currency = t.currency
          )
      );

    -- Check completed funding operations.
    INSERT INTO reconciliation_issues
        (run_id, issue_type, description, wallet_id)
    SELECT
        v_run_id,
        'funding_ledger_mismatch',
        'Completed funding has missing, extra, or incorrect ledger entries.',
        f.wallet_id
    FROM wallet_fundings f
    WHERE f.status = 'completed'
      AND (
          (SELECT COUNT(*)
           FROM ledger_entries le
           WHERE le.funding_id = f.funding_id) <> 2

          OR NOT EXISTS (
              SELECT 1
              FROM ledger_entries le
              WHERE le.funding_id = f.funding_id
                AND le.entry_type = 'debit'
                AND le.wallet_id IS NULL
                AND le.system_account_id IS NOT NULL
                AND le.amount_minor = f.amount_minor
                AND le.currency = f.currency
          )

          OR NOT EXISTS (
              SELECT 1
              FROM ledger_entries le
              WHERE le.funding_id = f.funding_id
                AND le.entry_type = 'credit'
                AND le.wallet_id = f.wallet_id
                AND le.system_account_id IS NULL
                AND le.amount_minor = f.amount_minor
                AND le.currency = f.currency
          )
      );

    -- Report unbalanced ledger groups, but avoid duplicate transfer
    -- findings when the transfer was already flagged above.
    INSERT INTO reconciliation_issues
        (run_id, issue_type, description, transfer_id, wallet_id)
    SELECT
        v_run_id,
        'unbalanced_ledger_reference',
        'Ledger debit and credit totals differ, or currencies are mixed.',
        le.transfer_id,
        MAX(le.wallet_id)
    FROM ledger_entries le
    GROUP BY le.transfer_id, le.funding_id
    HAVING (
        SUM(
            CASE
                WHEN le.entry_type = 'credit' THEN le.amount_minor
                ELSE -le.amount_minor
            END
        ) <> 0
        OR COUNT(DISTINCT le.currency) <> 1
    )
    AND NOT (
        le.transfer_id IS NOT NULL
        AND EXISTS (
            SELECT 1
            FROM reconciliation_issues ri
            WHERE ri.run_id = v_run_id
              AND ri.issue_type = 'transfer_ledger_mismatch'
              AND ri.transfer_id = le.transfer_id
        )
    );

    -- Report negative ledger-derived wallet balances.
    INSERT INTO reconciliation_issues
        (run_id, issue_type, description, wallet_id)
    SELECT
        v_run_id,
        'negative_wallet_balance',
        'Calculated wallet balance is below zero.',
        wb.wallet_id
    FROM wallet_balances wb
    WHERE wb.balance_minor < 0;

    -- Detect missing snapshots and mismatches with ledger balances.
    INSERT INTO reconciliation_issues
        (run_id, issue_type, description, wallet_id)
    SELECT
        v_run_id,
        'wallet_balance_mismatch',
        'Stored wallet balance snapshot differs from ledger-derived balance.',
        w.wallet_id
    FROM wallets w
    LEFT JOIN wallet_balance_snapshots s
        ON s.wallet_id = w.wallet_id
    LEFT JOIN wallet_balances wb
        ON wb.wallet_id = w.wallet_id
    WHERE s.wallet_id IS NULL
       OR wb.wallet_id IS NULL
       OR s.balance_minor IS DISTINCT FROM wb.balance_minor;

    -- Save the result of this reconciliation run.
    SELECT
        COUNT(*),
        COUNT(DISTINCT issue_type)
    INTO v_issue_count, v_failed_checks
    FROM reconciliation_issues
    WHERE run_id = v_run_id;

    UPDATE reconciliation_runs
    SET finished_at = NOW(),
        status = 'completed',
        checks_passed = 5 - v_failed_checks,
        issues_found = v_issue_count
    WHERE run_id = v_run_id;

    RETURN v_run_id;

EXCEPTION WHEN OTHERS THEN
    IF v_run_id IS NOT NULL THEN
        UPDATE reconciliation_runs
        SET finished_at = NOW(),
            status = 'failed'
        WHERE run_id = v_run_id;
    END IF;

    RAISE;
END;
$function$;

COMMIT;
