-- Payments-Grade Wallet Ledger
-- Initial database schema

CREATE TABLE users (
    user_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE wallets (
    wallet_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(user_id),
    currency CHAR(3) NOT NULL DEFAULT 'INR',
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT wallets_status_check
        CHECK (status IN ('active', 'frozen', 'closed')),
    CONSTRAINT wallets_user_currency_unique
        UNIQUE (user_id, currency)
);

CREATE TABLE system_accounts (
    system_account_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_name VARCHAR(100) NOT NULL UNIQUE,
    account_type VARCHAR(30) NOT NULL,
    currency CHAR(3) NOT NULL DEFAULT 'INR',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT system_accounts_type_check
        CHECK (account_type IN ('fee_revenue', 'clearing', 'suspense'))
);

CREATE TABLE transfers (
    transfer_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    idempotency_key VARCHAR(255) NOT NULL UNIQUE,
    source_wallet_id BIGINT NOT NULL REFERENCES wallets(wallet_id),
    destination_wallet_id BIGINT NOT NULL REFERENCES wallets(wallet_id),
    amount_minor BIGINT NOT NULL,
    currency CHAR(3) NOT NULL DEFAULT 'INR',
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    CONSTRAINT transfers_amount_check CHECK (amount_minor > 0),
    CONSTRAINT transfers_different_wallets_check
        CHECK (source_wallet_id <> destination_wallet_id),
    CONSTRAINT transfers_status_check
        CHECK (status IN ('pending', 'completed', 'failed'))
);

CREATE TABLE ledger_entries (
    ledger_entry_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    transfer_id BIGINT NOT NULL REFERENCES transfers(transfer_id),
    wallet_id BIGINT REFERENCES wallets(wallet_id),
    system_account_id BIGINT REFERENCES system_accounts(system_account_id),
    entry_type VARCHAR(10) NOT NULL,
    amount_minor BIGINT NOT NULL,
    currency CHAR(3) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT ledger_entry_type_check
        CHECK (entry_type IN ('debit', 'credit')),
    CONSTRAINT ledger_entry_amount_check CHECK (amount_minor > 0),
    CONSTRAINT ledger_entry_account_check CHECK (
        (wallet_id IS NOT NULL AND system_account_id IS NULL)
        OR
        (wallet_id IS NULL AND system_account_id IS NOT NULL)
    )
);

CREATE INDEX idx_transfers_source_created
    ON transfers(source_wallet_id, created_at DESC);

CREATE INDEX idx_transfers_destination_created
    ON transfers(destination_wallet_id, created_at DESC);

CREATE INDEX idx_ledger_entries_transfer
    ON ledger_entries(transfer_id);

CREATE INDEX idx_ledger_entries_wallet_created
    ON ledger_entries(wallet_id, created_at DESC);