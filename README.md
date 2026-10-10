# Payments-Grade Wallet Ledger

## 1. About the Project

Payments-Grade Wallet Ledger is a digital wallet backend built using Python, FastAPI, and PostgreSQL.

It supports wallet balances, transaction history, money transfers, ledger records, idempotency, fraud checks, and reconciliation.

The main goal is to handle money safely, prevent duplicate transfers, and maintain consistent financial records.

## 2. Features

- Check wallet balances.
- View transaction history with pagination.
- Transfer money between wallets.
- Reject transfers when funds are insufficient.
- Use idempotency keys to help prevent duplicate transfers.
- Record debit and credit ledger entries.
- Validate wallet status and currency.
- Use database transactions and wallet locking.
- Flag risky transfers for review.
- Release held transfers through a protected admin endpoint.
- Run reconciliation checks and save results.
- Protect administrative operations with an admin token.
- Run automated tests using Pytest.
- Run the project using Docker Compose.

## 3. Technologies Used

- **Python** - backend programming language.
- **FastAPI** - REST API framework.
- **PostgreSQL** - relational database.
- **SQL** - database schema, functions, and migrations.
- **Docker and Docker Compose** - application and database setup.
- **Pytest** - automated testing.
- **Git and GitHub** - version control and source code hosting.
- **GitHub Actions** - automated test workflow.

## 4. Project Structure

- `app/` - API, database connection, and worker code.
- `migrations/` - SQL schema changes and database functions.
- `tests/` - automated tests.
- `docs/schema.md` - database design documentation.
- `docs/isolation.md` - transaction isolation notes and experiments.
- `docker-compose.yml` - Docker service configuration.
- `Dockerfile` - API container setup.
- `requirements.txt` - Python dependencies.
- `.github/workflows/tests.yml` - automated test workflow.
- `run_concurrency_test.py` - concurrency test script.

## 5. How to Run

### Requirements

Install or configure:

- Python 3.12 or a compatible Python version.
- Docker Desktop.
- Git.

### Configure the project

1. Open the project folder in Windows Command Prompt.
2. Start Docker Desktop.
3. Create a local `.env` file containing a strong, private `ADMIN_API_TOKEN`.
4. Do not commit `.env` or share the admin token.

### Start the services

Run:

```cmd
docker compose up -d --build
```

Check the running containers:

```cmd
docker compose ps
```

Open the API documentation:

http://127.0.0.1:8000/docs

Check the health endpoint:

http://127.0.0.1:8000/health

### Database setup

For a new database, start PostgreSQL first:

```cmd
docker compose up -d db
```

Apply the SQL migration files in numerical order, from `001_initial_schema.sql` through the latest migration. Follow the database setup instructions for the configured PostgreSQL container and credentials.

Then start the application services:

```cmd
docker compose up -d --build
```

**Important:** Apply migrations only when setting up a fresh database or when applying a specific migration that has not already run. Do not blindly run every migration against an existing database. Back up important data before making database changes.

The application does not automatically apply all migrations when its containers start.

## 6. API Endpoints

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `/` | Project information |
| GET | `/health` | Check application and database health |
| GET | `/wallets/{wallet_id}/balance` | Get a wallet balance |
| GET | `/wallets/{wallet_id}/statement` | Get wallet transaction history |
| POST | `/transfers` | Create a money transfer |
| POST | `/admin/reconciliation/run` | Run reconciliation |
| POST | `/admin/transfers/{transfer_id}/release` | Release a held transfer |

Admin endpoints require the `X-Admin-Token` request header. Requests without a valid token should be rejected.

Use the Swagger documentation at `/docs` to inspect the request and response formats.

## 7. Database Design

The database uses relational tables to store users, wallets, transfers, ledger entries, system accounts, and supporting operational information.

The schema and later migrations also support features such as funding, reconciliation, idempotency, risk checks, and risk flag explanations.

The main relationships are:

- One user can have multiple wallets.
- A wallet can have multiple ledger entries.
- A transfer connects a sending wallet and a receiving wallet.
- A transfer can have multiple ledger entries.
- System accounts support financial movements that are not ordinary user-to-user transfers.
- Supporting tables store operational records such as reconciliation results and risk flags.

See `docs/schema.md` for the detailed schema documentation and database relationships.

## 8. Money and Ledger Safety

### Money representation

Money is represented using integer minor units. For INR, one rupee equals 100 paise.

For example:

- ₹10.00 = 1,000 paise.
- ₹100.00 = 10,000 paise.
- ₹500.00 = 50,000 paise.

Using integer paise avoids common floating-point rounding problems.

### Double-entry ledger

A completed transfer records a debit against the sender and a matching credit for the receiver.

The total debits and credits for a transfer should balance.

The ledger provides an audit trail of money movements. Wallet balances should be checked against the underlying financial records.

### Transactions and concurrent requests

Transfers use database transactions to keep related changes together.

Wallets are locked in a consistent order to reduce deadlocks. The sender's available balance must be checked while the appropriate locks are held.

If the sender does not have enough money, the transfer should be rejected instead of allowing a negative user wallet balance.

## 9. Idempotency

Idempotency helps prevent the same request from creating multiple transfers when a client retries after a timeout or network failure.

The server records information about a request and its result. A repeated request using the same key and the same request body should return the saved result rather than create another transfer.

Reusing a key with a different request body should be rejected.

This is important for payment systems because a client may not know whether a request completed when a network connection fails.

## 10. Fraud Checks and Held Transfers

The project includes database-backed risk checks to identify transfers that may need review.

A transfer that triggers a configured rule can be held instead of immediately moving money. An authorized administrator can review and release a held transfer through the protected admin endpoint.

Risk flag explanations are stored in the database. A risk explanation is supporting information for review, not proof that a transaction is fraudulent.

## 11. Reconciliation

Reconciliation checks financial records for inconsistencies.

The project includes reconciliation functionality and a manual admin endpoint. Results are saved in the database, and a worker is configured for scheduled checks.

Reconciliation is intended to help identify issues such as:

- Unbalanced ledger entries.
- Transfers whose ledger records do not balance.
- Differences between stored balances and calculated balances.
- Invalid negative wallet balances.
- Missing or inconsistent financial records.

The exact checks and database queries are documented in the implementation and migrations.

## 12. Statement and Transaction Questions

The project includes statement-related functionality for answering questions about wallet activity.

Questions must be handled using validated inputs and database queries that are restricted to the relevant user's wallets. User-provided text should never be treated as trusted SQL or as instructions to bypass access controls.

Responses should be based on actual database records rather than invented transaction information.

## 13. Error Handling and Security

Important safety measures include:

- Validate request data before processing it.
- Represent monetary amounts using integer minor units.
- Check wallet status and currency.
- Reject transfers that exceed the available balance.
- Use database transactions for related financial changes.
- Use parameterized SQL queries.
- Protect admin operations with a private token.
- Keep credentials and secrets out of source control.
- Test repeated requests and concurrent transfers.

API errors should provide useful information without exposing credentials, private data, or internal database details.

## 14. Running Automated Tests

Run the tests from the project folder:

```cmd
python -m pytest -v
```

The tests cover API endpoints, wallet balances, transfer behavior, idempotency, ledger consistency, statements, reconciliation, concurrency-related behavior, and risk-related functionality.

GitHub Actions also runs the automated test workflow when changes are pushed to the configured branch or a pull request is opened.

A successful test run confirms that the tests passed in that environment. It does not, by itself, prove every production-scale or failure-recovery scenario.

## 15. Design Trade-offs

- **PostgreSQL transactions:** Keep related financial changes atomic, but require careful handling of locks and transaction failures.
- **Wallet locking:** Protects balances during concurrent transfers, but may reduce throughput when many requests use the same wallet.
- **Idempotency:** Makes retries safer, but requires storing and validating request information.
- **Integer paise:** Avoids floating-point rounding, but the API must consistently validate and document the monetary unit.
- **Ledger-based records:** Improve auditability, but require reconciliation and careful control of financial writes.
- **Fraud holds:** Allow risky transfers to be reviewed, but introduce additional operational work.
- **Scheduled reconciliation:** Can detect inconsistencies after they occur, but does not replace transaction-level safety checks.

## 16. Future Improvements

Possible improvements include:

- Expand load testing and repeat concurrency experiments in a clean, isolated test database.
- Test reconciliation against deliberately introduced inconsistencies.
- Add monitoring, structured logs, and production-grade secret management.
- Improve cursor-based pagination for very large statements.
- Add stronger authentication and authorization for individual users.
- Test worker recovery, database failures, and repeated job execution.
- Measure query performance using realistic large datasets.

## 17. Conclusion

This project demonstrates the core backend concepts needed for a digital wallet: relational database design, financial ledger entries, safe transfers, idempotency, transaction locking, fraud checks, reconciliation, API development, and automated testing.

The main priority is to keep financial records consistent and prevent duplicate or invalid money movements.
