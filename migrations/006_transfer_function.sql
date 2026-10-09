
-- Safely transfer money between two wallets.
-- Amounts are stored in paise.

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
BEGIN
    -- Validate the request.
    IF p_idempotency_key IS NULL
       OR LENGTH(TRIM(p_idempotency_key)) = 0 THEN
        RAISE EXCEPTION 'Idempotency key is required';
    END IF;

    IF p_amount_minor IS NULL OR p_amount_minor <= 0 THEN
        RAISE EXCEPTION 'Amount must be greater than zero';
    END IF;

    IF p_source_wallet_id = p_destination_wallet_id THEN
        RAISE EXCEPTION 'Source and destination wallets must differ';
    END IF;

    -- Check whether this request was already processed.
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

        IF v_existing.status = 'completed' THEN
            RETURN v_existing.transfer_id;
        END IF;

        RAISE EXCEPTION 'Existing transfer is not completed';
    END IF;

    -- Lock both wallets in ID order to reduce deadlock risk.
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

    -- Calculate the source wallet's current balance.
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

    -- Create the transfer record.
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

    -- Debit the sender.
    INSERT INTO ledger_entries (
        transfer_id,
        wallet_id,
        entry_type,
        amount_minor,
        currency
    )
    VALUES (
        v_transfer_id,
        p_source_wallet_id,
        'debit',
        p_amount_minor,
        p_currency
    );

    -- Credit the receiver.
    INSERT INTO ledger_entries (
        transfer_id,
        wallet_id,
        entry_type,
        amount_minor,
        currency
    )
    VALUES (
        v_transfer_id,
        p_destination_wallet_id,
        'credit',
        p_amount_minor,
        p_currency
    );

    -- Mark the transfer completed.
    UPDATE transfers
    SET status = 'completed',
        completed_at = NOW()
    WHERE transfer_id = v_transfer_id;

    RETURN v_transfer_id;
END;
$$;