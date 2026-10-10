# Payments-Grade Wallet Ledger

## About the Project

This project is a digital wallet system built using Python, FastAPI, and PostgreSQL. It allows users to check wallet balances, view transaction history, and transfer money between wallets.

It also includes a ledger, fraud checks, reconciliation, and protected admin operations.

## Features

- Check wallet balances.
- View transaction history with pagination.
- Transfer money between wallets.
- Prevent transfers when funds are insufficient.
- Use idempotency keys to prevent duplicate transfers.
- Record debit and credit ledger entries.
- Validate wallet status and currency.
- Handle concurrent transfers safely.
- Flag risky transfers for review.
- Run reconciliation checks and save the results.
- Protect administrative endpoints with an admin token.
- Release held transfers safely.
- Run automated tests.

## Technologies Used

- Python
- FastAPI
- PostgreSQL
- Docker and Docker Compose
- Pytest
- Git and GitHub

## Project Structure

- `app/` - API and worker code.
- `migrations/` - SQL database migrations.
- `tests/` - Automated tests.
- `docs/` - Database design and transaction isolation notes.
- `docker-compose.yml` - Docker services.
- `Dockerfile` - API container setup.
- `requirements.txt` - Python dependencies.

## How to Run

### 1. Start Docker Desktop

Make sure Docker Desktop is running.

### 2. Configure the admin token

Create a local `.env` file in the project folder with a strong, private `ADMIN_API_TOKEN` value.

Do not commit `.env` to GitHub or share the token.

### 3. Start the services

Run:

`docker compose up -d --build`

### 4. Open the API documentation

Open this address in your browser:

`http://127.0.0.1:8000/docs`

### 5. Check the API health

Open:

`http://127.0.0.1:8000/health`

## Database Setup

The project uses PostgreSQL and SQL migration files in the `migrations/` folder.

**For a fresh database on Windows:**

1. Make sure Docker Desktop is running.
2. Create the `.env` file with a private `ADMIN_API_TOKEN`, as explained above.
3. Start only the database:

   ```cmd
   docker compose up -d db
   ```

4. Apply all SQL migrations in order. Run this command in Windows Command Prompt from the project folder:

   ```cmd
   for %f in (migrations\*.sql) do docker exec -i wallet_postgres psql -U wallet_user -d wallet_db -v ON_ERROR_STOP=1 < "%f"
   ```

5. Build and start the API and worker:

   ```cmd
   docker compose up -d --build
   ```

6. Open `http://127.0.0.1:8000/docs` to explore the API.

**Important:** The migration command above is for a fresh database only. Do not run all migrations again against an existing database. Check which migrations have already been applied first. The application does not automatically apply migrations when its containers start.

Migration `012_risk_flag_explanations.sql` saves an explanation for each fraud risk flag.

## API Endpoints

- `GET /` - Project information.
- `GET /health` - API and database health.
- `GET /wallets/{wallet_id}/balance` - Wallet balance.
- `GET /wallets/{wallet_id}/statement` - Wallet transaction history.
- `POST /transfers` - Transfer money between wallets.
- `POST /admin/reconciliation/run` - Run reconciliation.
- `POST /admin/transfers/{transfer_id}/release` - Release a held transfer.

Admin endpoints require the `X-Admin-Token` request header. Requests without a valid token are rejected.

## Reconciliation

Reconciliation checks whether wallet balances and ledger records are consistent. Results are saved in the database.

The project includes a manual admin endpoint and a worker that runs checks on a schedule.

## Money and Ledger Safety

Money amounts are stored in paise using integer minor units.

Transfers use database transactions and wallet locking to help prevent inconsistent balances and overspending. Idempotency keys help prevent duplicate transfer requests.

Debit and credit ledger entries record the movement of money.

## How to Run Tests

Run:

`python -m pytest -v`

The tests cover API endpoints, wallet balances, transfers, idempotency,