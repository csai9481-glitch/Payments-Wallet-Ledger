-- Migration 009: Fraud rules and transfer status audit history.

-- Store user phone and KYC status.
ALTER TABLE users
ADD COLUMN IF NOT EXISTS phone VARCHAR(30),
ADD COLUMN IF NOT EXISTS kyc_status VARCHAR(20) NOT NULL DEFAULT 'pending';

-- Configurable fraud rules.
CREATE TABLE IF NOT EXISTS risk_rules (
    rule_id BIGSERIAL PRIMARY KEY,
    rule_name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    threshold_minor BIGINT,
    window_minutes INTEGER,
    max_transfers INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (threshold_minor IS NULL OR threshold_minor > 0),
    CHECK (window_minutes IS NULL OR window_minutes > 0),
    CHECK (max_transfers IS NULL OR max_transfers > 0)
);

-- Record the fraud rules triggered by a transfer.
CREATE TABLE IF NOT EXISTS risk_flags (
    risk_flag_id BIGSERIAL PRIMARY KEY,
    transfer_id BIGINT NOT NULL REFERENCES transfers(transfer_id),
    rule_name VARCHAR(100) NOT NULL,
    details TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_by VARCHAR(255),
    reviewed_at TIMESTAMPTZ,
    resolution VARCHAR(30)
);

-- Record every transfer status change.
CREATE TABLE IF NOT EXISTS transfer_status_audit (
    audit_id BIGSERIAL PRIMARY KEY,
    transfer_id BIGINT NOT NULL REFERENCES transfers(transfer_id),
    old_status VARCHAR(30),
    new_status VARCHAR(30) NOT NULL,
    actor VARCHAR(255) NOT NULL,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_risk_flags_transfer
ON risk_flags(transfer_id);

CREATE INDEX IF NOT EXISTS idx_transfer_audit_transfer_time
ON transfer_status_audit(transfer_id, changed_at DESC);

-- Record status changes automatically.
CREATE OR REPLACE FUNCTION audit_transfer_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO transfer_status_audit (
            transfer_id, old_status, new_status, actor
        )
        VALUES (
            NEW.transfer_id,
            NULL,
            NEW.status,
            COALESCE(
                NULLIF(current_setting('app.actor', TRUE), ''),
                'system'
            )
        );
    ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO transfer_status_audit (
            transfer_id, old_status, new_status, actor
        )
        VALUES (
            NEW.transfer_id,
            OLD.status,
            NEW.status,
            COALESCE(
                NULLIF(current_setting('app.actor', TRUE), ''),
                'system'
            )
        );
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_transfer_status
ON transfers;

CREATE TRIGGER trg_audit_transfer_status
AFTER INSERT OR UPDATE OF status ON transfers
FOR EACH ROW
EXECUTE FUNCTION audit_transfer_status_change();

-- Initial configurable rules.
INSERT INTO risk_rules (
    rule_name, description, threshold_minor,
    window_minutes, max_transfers
)
VALUES
(
    'large_transfer',
    'Hold transfers above the configured amount threshold.',
    1000000,
    NULL,
    NULL
),
(
    'high_transfer_velocity',
    'Hold transfers when the sender exceeds the configured transfer count.',
    NULL,
    10,
    20
)
ON CONFLICT (rule_name) DO NOTHING;