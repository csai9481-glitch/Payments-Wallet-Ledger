-- Safely fund a wallet with simulated money.
-- Returns the funding ID.
-- Amounts are stored in paise.

CREATE OR REPLACE FUNCTION fund_wallet(
    p_idempotency_key VARCHAR(255),
    p_wallet_id BIGINT,
    p_amount_minor BIGINT,
    p_currency CHAR(3)
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_funding_id BIGINT;
    v_existing wallet_fundings%ROWTYPE;
    v_wallet wallets%ROWTYPE;
    v_clearing_account_id BIGINT;
BEGIN
    IF p_idempotency_key IS NULL
       OR LENGTH(TRIM(p_idempotency_key)) = 0 THEN
        RAISE EXCEPTION 'Idempotency key is required';
    END IF;

    IF p_amount_minor IS NULL OR p_amount_minor <= 0 THEN
        RAISE EXCEPTION 'Amount must be greater than zero';
    END IF;

    SELECT *
    INTO v_wallet
    FROM wallets
    WHERE wallet_id = p_wallet_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Wallet % does not exist', p_wallet_id;
    END IF;

    IF v_wallet.status <> 'active' THEN
        RAISE EXCEPTION 'Wallet is not active';
    END IF;

    IF v_wallet.currency <> p_currency THEN
        RAISE EXCEPTION 'Wallet currency does not match request';
    END IF;

    SELECT system_account_id
    INTO v_clearing_account_id
    FROM system_accounts
    WHERE account_type = 'clearing'
      AND currency = p_currency
    ORDER BY system_account_id
    LIMIT 1;

    IF v_clearing_account_id IS NULL THEN
        RAISE EXCEPTION 'Clearing account not found for currency %',
            p_currency;
    END IF;

    INSERT INTO wallet_fundings (
        idempotency_key, wallet_id, amount_minor, currency, status
    )
    VALUES (
        p_idempotency_key, p_wallet_id, p_amount_minor, p_currency, 'completed'
    )
    ON CONFLICT (idempotency_key) DO NOTHING
    RETURNING funding_id INTO v_funding_id;

    IF v_funding_id IS NULL THEN
        SELECT *
        INTO v_existing
        FROM wallet_fundings
        WHERE idempotency_key = p_idempotency_key;

        IF v_existing.wallet_id <> p_wallet_id
           OR v_existing.amount_minor <> p_amount_minor
           OR v_existing.currency <> p_currency THEN
            RAISE EXCEPTION
                'Idempotency key was already used with different details';
        END IF;

        RETURN v_existing.funding_id;
    END IF;

    INSERT INTO ledger_entries (
        funding_id, system_account_id, entry_type, amount_minor, currency
    )
    VALUES (
        v_funding_id, v_clearing_account_id, 'debit', p_amount_minor, p_currency
    );

    INSERT INTO ledger_entries (
        funding_id, wallet_id, entry_type, amount_minor, currency
    )
    VALUES (
        v_funding_id, p_wallet_id, 'credit', p_amount_minor, p_currency
    );

    RETURN v_funding_id;
END;
$$;