-- Migration 012: Save explanations for fraud risk flags.

ALTER TABLE risk_flags
ADD COLUMN IF NOT EXISTS explanation TEXT;

-- Add explanations to existing risk flags.
UPDATE risk_flags
SET explanation = CASE
    WHEN rule_name = 'large_transfer' THEN
        'This transfer was flagged because its amount exceeded the configured large-transfer threshold. Review the transfer before releasing it.'
    WHEN rule_name = 'high_transfer_velocity' THEN
        'This transfer was flagged because the sender reached the configured transfer frequency limit. Review recent activity before releasing it.'
    ELSE
        'This transfer was flagged for review. Reason: ' || details
END
WHERE explanation IS NULL OR BTRIM(explanation) = '';

-- Automatically explain new risk flags.
CREATE OR REPLACE FUNCTION set_risk_flag_explanation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.explanation IS NULL OR BTRIM(NEW.explanation) = '' THEN
        NEW.explanation := CASE
            WHEN NEW.rule_name = 'large_transfer' THEN
                'This transfer was flagged because its amount exceeded the configured large-transfer threshold. Review the transfer before releasing it.'
            WHEN NEW.rule_name = 'high_transfer_velocity' THEN
                'This transfer was flagged because the sender reached the configured transfer frequency limit. Review recent activity before releasing it.'
            ELSE
                'This transfer was flagged for review. Reason: ' ||
                COALESCE(NEW.details, 'No additional details were recorded.')
        END;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_risk_flag_explanation ON risk_flags;

CREATE TRIGGER trg_risk_flag_explanation
BEFORE INSERT OR UPDATE ON risk_flags
FOR EACH ROW
EXECUTE FUNCTION set_risk_flag_explanation();