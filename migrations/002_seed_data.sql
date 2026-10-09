-- Sample data for local development

INSERT INTO users (full_name, email)
VALUES
    ('Alice Sharma', 'alice@example.com'),
    ('Bob Kumar', 'bob@example.com')
ON CONFLICT (email) DO NOTHING;

INSERT INTO wallets (user_id, currency)
SELECT user_id, 'INR'
FROM users
WHERE email IN ('alice@example.com', 'bob@example.com')
ON CONFLICT (user_id, currency) DO NOTHING;

INSERT INTO system_accounts (account_name, account_type, currency)
VALUES
    ('Platform Fee Revenue', 'fee_revenue', 'INR'),
    ('Clearing Account', 'clearing', 'INR')
ON CONFLICT (account_name) DO NOTHING;