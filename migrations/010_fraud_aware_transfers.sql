-- Migration 010: Fraud-aware wallet transfers.
-- Suspicious transfers are held without moving money.
-- Normal transfers continue to complete immediately.

BEGIN;

-- Allow held transfers while preserving existing status values.
ALTER TABLE transfers
    DROP CONSTRAINT IF EXISTS transfers_status_check;

ALTER TABLE transfers
    ADD CONSTRAINT transfers_status_check
    CHECK (status IN ('pending', 'completed', 'failed', 'held'));

CREATE OR REPLACE FUNCTION transfer_money(
    p_idempotency_key VARCHAR(255),
    p_source_wallet_id BIGINT,
    p_destination_wallet_id BIGINT,
    p_amount_minor BIGINT,
    p_currency CHAR(3)
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_transfer_id BIGINT;
    v_existing transfers%ROWTYPE;
    v_source_wallet wallets%ROWTYPE;
    v_destination_wallet wallets%ROWTYPE;
    v_source_balance BIGINT;
    v_large_threshold BIGINT;
    v_velocity_window INTEGER;
    v_max_transfers INTEGER;
    v_recent_count BIGINT := 0;
    v_large_triggered BOOLEAN := FALSE;
    v_velocity_triggered BOOLEAN := FALSE;
    v_hold BOOLEAN := FALSE;
BEGIN
    IF p_idempotency_key IS NULL
       OR LENGTH(TRIM(p_idempotency_key)) = 0 THEN
        RAISE EXCEPTION 'Idempotency key is required';
    END IF;

    IF p_amount_minor IS NULL OR p_amount_minor <= 0 THEN
        RAISE EXCEPTION 'Amount must be greater than zero';
    END IF;

    IF p_source_wallet_id IS NULL
       OR p_destination_wallet_id IS NULL THEN
        RAISE EXCEPTION 'Source and destination wallets are required';
    END IF;

    IF p_source_wallet_id = p_destination_wallet_id THEN
        RAISE EXCEPTION 'Source and destination wallets must differ';
    END IF;

    IF p_currency IS NULL OR LENGTH(TRIM(p_currency)) <> 3 THEN
        RAISE EXCEPTION 'A valid three-character currency is required';
    END IF;

    -- Serialize requests using the same idempotency key.
    PERFORM pg_advisory_xact_lock(
        hashtextextended(p_idempotency_key, 0)
    );

    -- A retry must return the original transfer, not create another one.
    SELECT *
    INTO v_existing
    FROM transfers
    WHERE idempotency_key = p_idempotency_key;

    IF FOUND THEN
        IF v_existing.source_wallet_id <> p_source_wallet_id
           OR v_existing.destination_wallet_id <> p_destination_wallet_id
           OR v_existing.amount_minor <> p_amount_minor
           OR v_existing.currency <> p_currency THEN
            RAISE EXCEPTION
                'Idempotency key was used with different details';
        END IF;

        IF v_existing.status IN ('completed', 'held') THEN
            RETURN v_existing.transfer_id;
        END IF;

        RAISE EXCEPTION 'Existing transfer is not completed';
    END IF;

    -- Lock both wallets in ascending ID order.
    -- The sender wallet lock also serializes velocity checks for that sender.
    PERFORM 1
    FROM wallets
    WHERE wallet_id IN (
        p_source_wallet_id,
        p_destination_wallet_id
    )
    ORDER BY wallet_id
    FOR UPDATE;

    SELECT *
    INTO v_source_wallet
    FROM wallets
    WHERE wallet_id = p_source_wallet_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Source wallet does not exist';
    END IF;

    SELECT *
    INTO v_destination_wallet
    FROM wallets
    WHERE wallet_id = p_destination_wallet_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Destination wallet does not exist';
    END IF;

    IF v_source_wallet.status <> 'active'
       OR v_destination_wallet.status <> 'active' THEN
        RAISE EXCEPTION 'Both wallets must be active';
    END IF;

    IF v_source_wallet.currency <> p_currency
       OR v_destination_wallet.currency <> p_currency THEN
        RAISE EXCEPTION 'Wallet currency does not match request';
    END IF;

    -- Check the current balance. Held transfers do not reserve funds.
    SELECT COALESCE(
        SUM(
            CASE
                WHEN entry_type = 'credit' THEN amount_minor
                WHEN entry_type = 'debit' THEN -amount_minor
                ELSE 0
            END
        ),
        0
    )::BIGINT
    INTO v_source_balance
    FROM ledger_entries
    WHERE wallet_id = p_source_wallet_id;

    IF v_source_balance < p_amount_minor THEN
        RAISE EXCEPTION 'Insufficient wallet balance';
    END IF;

    -- Rule 1: hold transfers above the configured amount threshold.
    SELECT threshold_minor
    INTO v_large_threshold
    FROM risk_rules
    WHERE rule_name = 'large_transfer'
      AND enabled = TRUE
      AND threshold_minor IS NOT NULL;

    IF FOUND AND p_amount_minor > v_large_threshold THEN
        v_large_triggered := TRUE;
    END IF;

    -- Rule 2: hold transfers when the configured velocity limit is reached.
    SELECT window_minutes, max_transfers
    INTO v_velocity_window, v_max_transfers
    FROM risk_rules
    WHERE rule_name = 'high_transfer_velocity'
      AND enabled = TRUE
      AND window_minutes IS NOT NULL
      AND max_transfers IS NOT NULL;

    IF FOUND THEN
        SELECT COUNT(*)
        INTO v_recent_count
        FROM transfers
        WHERE source_wallet_id = p_source_wallet_id
          AND created_at >=
              NOW() - make_interval(mins => v_velocity_window)
          AND status IN ('completed', 'held', 'pending');

        -- The next transfer is held once the existing count reaches
        -- the configured limit within the time window.
        IF v_recent_count >= v_max_transfers THEN
            v_velocity_triggered := TRUE;
        END IF;
    END IF;

    v_hold := v_large_triggered OR v_velocity_triggered;

    -- Insert the transfer. The existing audit trigger records its status.
    INSERT INTO transfers (
        idempotency_key,
        source_wallet_id,
        destination_wallet_id,
        amount_minor,
        currency,
        status
    )
    VALUES (
        p_idempotency_key,
        p_source_wallet_id,
        p_destination_wallet_id,
        p_amount_minor,
        p_currency,
        'pending'
    )
    RETURNING transfer_id INTO v_transfer_id;

    IF v_hold THEN
        -- Record each rule that actually triggered.
        IF v_large_triggered THEN
            INSERT INTO risk_flags (
                transfer_id, rule_name, details
            )
            VALUES (
                v_transfer_id,
                'large_transfer',
                'Transfer amount exceeded the configured threshold.'
            );
        END IF;

        IF v_velocity_triggered THEN
            INSERT INTO risk_flags (
                transfer_id, rule_name, details
            )
            VALUES (
                v_transfer_id,
                'high_transfer_velocity',
                'Sender reached the configured transfer velocity limit.'
            );
        END IF;

        -- No ledger entries are created for a held transfer.
        UPDATE transfers
        SET status = 'held'
        WHERE transfer_id = v_transfer_id;

        RETURN v_transfer_id;
    END IF;

    -- Normal transfer: record both sides in the same transaction.
    INSERT INTO ledger_entries (
        transfer_id, wallet_id, entry_type, amount_minor, currency
    )
    VALUES (
        v_transfer_id, p_source_wallet_id,
        'debit', p_amount_minor, p_currency
    );

    INSERT INTO ledger_entries (
        transfer_id, wallet_id, entry_type, amount_minor, currency
    )
    VALUES (
        v_transfer_id, p_destination_wallet_id,
        'credit', p_amount_minor, p_currency
    );

    UPDATE transfers
    SET status = 'completed',
        completed_at = NOW()
    WHERE transfer_id = v_transfer_id;

    RETURN v_transfer_id;
END;
$$;

COMMIT;