-- Add a separate record for simulated wallet funding.

CREATE TABLE wallet_fundings (
    funding_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    idempotency_key VARCHAR(255) NOT NULL UNIQUE,
    wallet_id BIGINT NOT NULL REFERENCES wallets(wallet_id),
    amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
    currency CHAR(3) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'completed',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT wallet_fundings_status_check
        CHECK (status IN ('completed', 'failed'))
);

-- Allow a ledger entry to reference either a transfer or a funding record.
ALTER TABLE ledger_entries
    ALTER COLUMN transfer_id DROP NOT NULL;

ALTER TABLE ledger_entries
    ADD COLUMN funding_id BIGINT REFERENCES wallet_fundings(funding_id);

ALTER TABLE ledger_entries
    ADD CONSTRAINT ledger_entry_reference_check
    CHECK (
        (transfer_id IS NOT NULL AND funding_id IS NULL)
        OR
        (transfer_id IS NULL AND funding_id IS NOT NULL)
    );

CREATE INDEX idx_wallet_fundings_wallet_created
    ON wallet_fundings(wallet_id, created_at DESC);