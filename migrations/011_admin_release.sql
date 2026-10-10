
-- Migration 011: Securely release held wallet transfers.
-- This function runs all release steps in one database transaction.

BEGIN;

CREATE OR REPLACE FUNCTION release_held_transfer(
    p_transfer_id BIGINT,
    p_actor VARCHAR(255)
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_transfer transfers%ROWTYPE;
    v_source_wallet wallets%ROWTYPE;
    v_destination_wallet wallets%ROWTYPE;
    v_source_balance BIGINT;
BEGIN
    -- Validate the transfer ID and reviewer identity.
    IF p_transfer_id IS NULL OR p_transfer_id <= 0 THEN
        RAISE EXCEPTION 'A valid transfer ID is required';
    END IF;

    IF p_actor IS NULL OR LENGTH(TRIM(p_actor)) = 0 THEN
        RAISE EXCEPTION 'Admin identity is required';
    END IF;

    -- Lock the transfer so two admins cannot release it simultaneously.
    SELECT *
    INTO v_transfer
    FROM transfers
    WHERE transfer_id = p_transfer_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Transfer not found';
    END IF;

    IF v_transfer.status <> 'held' THEN
        RAISE EXCEPTION 'Transfer is not held';
    END IF;

    -- Lock both wallets in ascending ID order to reduce deadlocks.
    PERFORM 1
    FROM wallets
    WHERE wallet_id IN (
        v_transfer.source_wallet_id,
        v_transfer.destination_wallet_id
    )
    ORDER BY wallet_id
    FOR UPDATE;

    SELECT *
    INTO v_source_wallet
    FROM wallets
    WHERE wallet_id = v_transfer.source_wallet_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Source wallet does not exist';
    END IF;

    SELECT *
    INTO v_destination_wallet
    FROM wallets
    WHERE wallet_id = v_transfer.destination_wallet_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Destination wallet does not exist';
    END IF;

    -- Recheck wallet status and currency before releasing the transfer.
    IF v_source_wallet.status <> 'active'
       OR v_destination_wallet.status <> 'active' THEN
        RAISE EXCEPTION 'Both wallets must be active';
    END IF;

    IF v_source_wallet.currency <> v_transfer.currency
       OR v_destination_wallet.currency <> v_transfer.currency THEN
        RAISE EXCEPTION 'Wallet currency does not match transfer';
    END IF;

    -- Held transfers do not reserve funds. Check the current balance again.
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
    WHERE wallet_id = v_transfer.source_wallet_id;

    IF v_source_balance < v_transfer.amount_minor THEN
        RAISE EXCEPTION 'Insufficient wallet balance to release transfer';
    END IF;

    -- Set the actor used by the transfer status audit trigger.
    PERFORM set_config('app.actor', TRIM(p_actor), TRUE);

    -- Create both ledger entries atomically.
    INSERT INTO ledger_entries (
        transfer_id,
        wallet_id,
        entry_type,
        amount_minor,
        currency
    )
    VALUES (
        v_transfer.transfer_id,
        v_transfer.source_wallet_id,
        'debit',
        v_transfer.amount_minor,
        v_transfer.currency
    );

    INSERT INTO ledger_entries (
        transfer_id,
        wallet_id,
        entry_type,
        amount_minor,
        currency
    )
    VALUES (
        v_transfer.transfer_id,
        v_transfer.destination_wallet_id,
        'credit',
        v_transfer.amount_minor,
        v_transfer.currency
    );

    -- Record the review against the existing risk flags.
    UPDATE risk_flags
    SET reviewed_by = TRIM(p_actor),
        reviewed_at = NOW(),
        resolution = 'released'
    WHERE transfer_id = v_transfer.transfer_id;

    -- The audit trigger records the status change and admin actor.
    UPDATE transfers
    SET status = 'completed',
        completed_at = NOW()
    WHERE transfer_id = v_transfer.transfer_id;

    RETURN v_transfer.transfer_id;
END;
$$;

COMMIT;
