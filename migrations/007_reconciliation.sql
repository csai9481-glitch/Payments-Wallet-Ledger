-- Store the result of each reconciliation run.
CREATE TABLE IF NOT EXISTS reconciliation_runs (
run_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
finished_at TIMESTAMPTZ,
status VARCHAR(20) NOT NULL DEFAULT 'running',
checks_passed INTEGER NOT NULL DEFAULT 0,
issues_found INTEGER NOT NULL DEFAULT 0,
CONSTRAINT reconciliation_runs_status_check
CHECK (status IN ('running', 'completed', 'failed'))
);

-- Store each problem found during a reconciliation run.
CREATE TABLE IF NOT EXISTS reconciliation_issues (
issue_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
run_id BIGINT NOT NULL REFERENCES reconciliation_runs(run_id),
issue_type VARCHAR(100) NOT NULL,
description TEXT NOT NULL,
transfer_id BIGINT REFERENCES transfers(transfer_id),
wallet_id BIGINT REFERENCES wallets(wallet_id),
created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_reconciliation_issues_run
ON reconciliation_issues(run_id);
