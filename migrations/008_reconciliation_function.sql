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

INSERT INTO reconciliation_issues
    (run_id, issue_type, description, transfer_id)
SELECT v_run_id, 'transfer_ledger_mismatch',
       'Completed transfer has missing, extra, or incorrect ledger entries.',
       t.transfer_id
FROM transfers t
WHERE t.status = 'completed'
  AND (
      (SELECT COUNT(*) FROM ledger_entries le
       WHERE le.transfer_id = t.transfer_id) <> 2
      OR NOT EXISTS (
          SELECT 1 FROM ledger_entries le
          WHERE le.transfer_id = t.transfer_id
            AND le.entry_type = 'debit'
            AND le.wallet_id = t.source_wallet_id
            AND le.amount_minor = t.amount_minor
            AND le.currency = t.currency
      )
      OR NOT EXISTS (
          SELECT 1 FROM ledger_entries le
          WHERE le.transfer_id = t.transfer_id
            AND le.entry_type = 'credit'
            AND le.wallet_id = t.destination_wallet_id
            AND le.amount_minor = t.amount_minor
            AND le.currency = t.currency
      )
  );

INSERT INTO reconciliation_issues
    (run_id, issue_type, description, wallet_id)
SELECT v_run_id, 'funding_ledger_mismatch',
       'Completed funding has missing, extra, or incorrect ledger entries.',
       f.wallet_id
FROM wallet_fundings f
WHERE f.status = 'completed'
  AND (
      (SELECT COUNT(*) FROM ledger_entries le
       WHERE le.funding_id = f.funding_id) <> 2
      OR NOT EXISTS (
          SELECT 1 FROM ledger_entries le
          WHERE le.funding_id = f.funding_id
            AND le.entry_type = 'debit'
            AND le.wallet_id IS NULL
            AND le.system_account_id IS NOT NULL
            AND le.amount_minor = f.amount_minor
            AND le.currency = f.currency
      )
      OR NOT EXISTS (
          SELECT 1 FROM ledger_entries le
          WHERE le.funding_id = f.funding_id
            AND le.entry_type = 'credit'
            AND le.wallet_id = f.wallet_id
            AND le.system_account_id IS NULL
            AND le.amount_minor = f.amount_minor
            AND le.currency = f.currency
      )
  );

INSERT INTO reconciliation_issues
    (run_id, issue_type, description, transfer_id, wallet_id)
SELECT v_run_id, 'unbalanced_ledger_reference',
       'Ledger debit and credit totals differ, or currencies are mixed.',
       le.transfer_id, MAX(le.wallet_id)
FROM ledger_entries le
GROUP BY le.transfer_id, le.funding_id
HAVING SUM(
    CASE WHEN le.entry_type = 'credit'
         THEN le.amount_minor ELSE -le.amount_minor END
) <> 0
   OR COUNT(DISTINCT le.currency) <> 1;

INSERT INTO reconciliation_issues
    (run_id, issue_type, description, wallet_id)
SELECT v_run_id, 'negative_wallet_balance',
       'Calculated wallet balance is below zero.',
       wb.wallet_id
FROM wallet_balances wb
WHERE wb.balance_minor < 0;

SELECT COUNT(*), COUNT(DISTINCT issue_type)
INTO v_issue_count, v_failed_checks
FROM reconciliation_issues
WHERE run_id = v_run_id;

UPDATE reconciliation_runs
SET finished_at = NOW(),
    status = 'completed',
    checks_passed = 4 - v_failed_checks,
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
