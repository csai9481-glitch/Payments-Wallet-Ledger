BEGIN;

CREATE TABLE IF NOT EXISTS job_locks (
    job_name TEXT PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO job_locks (job_name)
VALUES ('reconciliation')
ON CONFLICT (job_name) DO NOTHING;

ALTER FUNCTION run_reconciliation()
RENAME TO run_reconciliation_unlocked;

CREATE FUNCTION run_reconciliation()
RETURNS BIGINT
LANGUAGE plpgsql
AS $function$
DECLARE
    v_job_name TEXT;
BEGIN
    SELECT job_name
    INTO v_job_name
    FROM job_locks
    WHERE job_name = 'reconciliation'
    FOR UPDATE NOWAIT;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reconciliation lock row is missing';
    END IF;

    RETURN run_reconciliation_unlocked();
END;
$function$;

COMMIT;
