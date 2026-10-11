# Payments-Grade Wallet Ledger

## 1. About the Project

Payments-Grade Wallet Ledger is a digital wallet backend built using Python, FastAPI, and PostgreSQL.

The project demonstrates how a wallet system can manage balances, transfer money, record financial transactions, prevent duplicate requests, check for risky transfers, and identify inconsistencies in financial records.

The main goal is to maintain accurate financial records and handle transfers safely, including when multiple requests happen at the same time.

## 2. Features

- Check wallet balances.
- View wallet transaction history with pagination.
- Transfer money between wallets.
- Reject transfers when the sender has insufficient funds.
- Use idempotency keys to prevent duplicate transfers.
- Record debit and credit entries in a financial ledger.
- Validate wallet status and currency.
- Use database transactions and wallet locking.
- Apply risk checks and flag transfers for review.
- Support administrator operations through protected endpoints.
- Run reconciliation checks and save results.
- Run automated tests using Pytest.
- Start the application services using Docker Compose.
- Run automated tests through GitHub Actions.

## 3. Technologies Used

- **Python** — backend programming language.
- **FastAPI** — REST API framework.
- **PostgreSQL** — relational database.
- **SQL** — database tables, functions, views, and migrations.
- **Docker and Docker Compose** — application and database setup.
- **Pytest** — automated testing.
- **Git and GitHub** — version control and source code hosting.
- **GitHub Actions** — automated test workflow.

## 4. Project Structure

- `app/` — API, database connection, and worker code.
- `migrations/` — SQL schema changes, database functions, and supporting scripts.
- `tests/` — automated tests.
- `docs/schema.md` — database design documentation.
- `docs/isolation.md` — transaction isolation notes and experiments.
- `docs/concurrency-test-results.md` — concurrency test results.
- `docs/performance-results.md` — performance measurements.
- `docker-compose.yml` — Docker service configuration.
- `Dockerfile` — API container setup.
- `requirements.txt` — Python dependencies.
- `.github/workflows/tests.yml` — automated test workflow.
- `run_concurrency_test.py` — separate concurrency test script.

## 5. Requirements

Install or configure the following:

- Python 3.12 or a compatible Python version.
- Docker Desktop.
- Git.

Start Docker Desktop before running the application.

## 6. How to Run the Project

Open Windows Command Prompt and move to the project folder:

```cmd
cd /d C:\Users\USER\Desktop\Payments-Wallet-Ledger
```

### Configure the environment

Open the local environment file:

```cmd
notepad .env
```

Make sure it contains this line. Replace the example value with your own long, private token:

```text
ADMIN_API_TOKEN=replace-with-a-long-random-private-token
```

Save the file. Do not commit `.env` or share your real token publicly.

### Start the services

Run:

```cmd
docker compose up -d --build
```

Check the service status:

```cmd
docker compose ps
```

Open the API documentation:

http://127.0.0.1:8000/docs

Check the health endpoint:

http://127.0.0.1:8000/health

### Database setup

On a brand-new PostgreSQL data directory, Docker Compose automatically runs the numbered SQL migration files in `migrations/` in order during database initialization.

Start the services with:

```cmd
docker compose up -d --build
```

Check their status with `docker compose ps`.

**Important:** Initialization scripts run only when the PostgreSQL data directory is empty. Starting services with an existing database does not rerun migrations. Do not delete the database volume or blindly rerun migrations.

The `performance_seed.sql` and `performance_scale.sql` scripts are for a dedicated `wallet_perf_db` database only. Never run them against your normal development database.


## 7. API Endpoints

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `/` | Project information |
| GET | `/health` | Check application health |
| GET | `/wallets/{wallet_id}/balance` | Get a wallet balance |
| GET | `/wallets/{wallet_id}/statement` | Get wallet transaction history |
| POST | `/transfers` | Create a money transfer |
| POST | `/admin/reconciliation/run` | Run reconciliation |
| POST | `/admin/transfers/{transfer_id}/release` | Request release of a held transfer |

Administrative endpoints require the configured admin token in the `X-Admin-Token` request header.

Use the Swagger documentation at `/docs` to inspect request fields, response formats, and available endpoints.

## 8. Database Design

The database uses relational tables to represent users, wallets, transfers, ledger entries, system accounts, and supporting operational records.

The main relationships are:

- One user can have multiple wallets.
- One wallet can have multiple ledger entries.
- Each transfer identifies a sending wallet and a receiving wallet.
- Transfers have associated financial ledger entries.
- System accounts support financial movements involving non-user accounts.
- Supporting tables store information such as funding records, reconciliation results, risk flags, and transfer status changes.

Foreign keys help maintain relationships between related records.

See `docs/schema.md` for more details about the database tables, relationships, and schema design.

## 9. Money Representation and Ledger Safety

### Money representation

Monetary amounts are represented using integer minor units.

For Indian rupees, one rupee equals 100 paise.

Examples:

- ₹10.00 = 1,000 paise.
- ₹100.00 = 10,000 paise.
- ₹500.00 = 50,000 paise.

Using integer minor units avoids common floating-point rounding errors when representing money.

### Double-entry ledger

A completed transfer records a debit for the sender and a matching credit for the receiver.

The debit and credit amounts for a valid transfer should balance.

The ledger provides an audit trail of financial movements and is the source used to calculate wallet balances in this project.

### Wallet balances

Wallet balances are calculated from ledger entries using a database view rather than stored as a separate balance value in the `wallets` table.

This design avoids maintaining two separate representations of the wallet balance. However, calculating balances from ledger entries can become more expensive as the ledger grows, so appropriate indexes and query optimization are important.

A system using separately stored balances could offer faster reads, but it would need additional safeguards to keep those balances synchronized with the ledger.

### Transactions and concurrent requests

Database transactions keep related financial changes together.

Wallet locking helps prevent concurrent transfers from spending the same available funds more than once. Consistent lock ordering also helps reduce deadlocks.

The sender's available balance must be checked safely while the relevant database locks are held. Transfers that exceed the available balance should be rejected.

## 10. Idempotency

Idempotency helps prevent duplicate transfers when a client retries a request after a timeout or network failure.

The server records request information and the result associated with an idempotency key.

When the same key and request are submitted again, the existing result should be returned instead of creating another transfer. Reusing a key with a different request should be rejected.

This is important in payment systems because a client may not know whether a request succeeded when its network connection fails.

## 11. Risk Checks and Held Transfers

The project includes database-backed risk checks to identify transfers that may require additional review.

Transfers that trigger applicable rules can be held for review rather than immediately completing the money movement.

The project also includes protected administrative functionality for releasing held transfers and stores risk-related information in the database.

A risk flag is a signal for further review. It is not, by itself, proof of fraudulent activity.

## 12. Reconciliation

Reconciliation helps identify inconsistencies in financial records.

The project includes reconciliation functionality, a manual administrative endpoint, saved reconciliation results, and a worker configured to run scheduled checks.

The implemented checks cover selected conditions involving transfers, funding records, ledger entries, and wallet balances.

Reconciliation is useful for identifying financial inconsistencies that need investigation. Its coverage depends on the checks implemented in the database functions.

Wallet balances in this project are derived from the ledger. Therefore, comparing them against a separate stored wallet balance is not applicable to the current schema.

See the SQL migrations and database documentation for details about the implemented checks.

## 13. Statement and Transaction Questions

The project includes statement-related functionality for answering supported questions about wallet activity.

Requests should be validated, and database queries should be restricted to the relevant user's authorized wallet records.

User-provided text must not be treated as trusted SQL or as permission to bypass access controls.

Answers should be based on actual database records. When a response refers to a transfer, the corresponding transaction identifier should be included where required.

## 14. Security and Error Handling

Important safety measures include:

- Validate request data before processing it.
- Represent monetary amounts using integer minor units.
- Check wallet status and currency.
- Reject transfers that exceed available funds.
- Use database transactions for related financial changes.
- Use parameterized SQL queries.
- Protect administrative operations with a private token.
- Keep credentials and secrets out of source control.
- Test repeated requests and concurrent transfers.
- Avoid exposing credentials and sensitive internal details in error messages.

Production deployments would require additional work on user authentication, authorization, secret management, monitoring, and operational recovery.

## 15. Running Automated Tests

Run the automated tests from the project folder:

```cmd
python -m pytest tests -v
```

The test suite covers selected API endpoints, wallet balances, transfer behavior, idempotency, ledger consistency, statements, reconciliation, concurrency-related behavior, and risk-related functionality.

GitHub Actions also runs the configured automated test workflow when supported repository events occur.

A passing test suite confirms that the included tests passed in that environment. It does not prove that every production failure scenario or assignment acceptance criterion has been covered.

## 16. Design Trade-offs

- **PostgreSQL transactions:** Keep related financial changes atomic, but require careful transaction and error handling.
- **Wallet locking:** Protects against concurrent overspending, but can reduce throughput when requests compete for the same wallet.
- **Idempotency:** Makes retries safer, but requires storing request information and validating repeated requests.
- **Integer minor units:** Avoids floating-point rounding errors, but requires consistent monetary units across API and database operations.
- **Ledger-derived balances:** Provide an auditable source for balance calculations, but can make reads more expensive as the ledger grows.
- **Risk holds:** Allow suspicious transfers to be reviewed, but require an operational review and release process.
- **Reconciliation:** Helps detect inconsistencies, but does not replace transaction-level validation and financial safeguards.
- **Scheduled workers:** Automate background tasks, but require safe retries, monitoring, and recovery procedures.

## 17. Future Improvements

Possible improvements include:

- Expand automated tests for missing idempotency keys and parallel requests using the same key.
- Test reconciliation against deliberately introduced financial inconsistencies.
- Expand reconciliation coverage and document its transaction isolation guarantees.
- Improve cursor-based pagination for large wallet statements.
- Add stronger user authentication and authorization.
- Improve worker monitoring, retry handling, and recovery.
- Add production-grade logging and secret management.
- Run additional performance tests using realistic workloads.
- Validate all required assignment acceptance criteria before production use.

## 18. Conclusion

This project demonstrates important wallet-backend concepts, including relational database design, financial ledger entries, money transfers, idempotency, transaction locking, risk checks, reconciliation, REST API development, and automated testing.

The main goal is to maintain accurate financial records and reduce the risk of duplicate or invalid money movements.

This project is an educational backend implementation and should undergo further validation before being used to process real customer funds.