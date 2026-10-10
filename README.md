# Payments-Grade Wallet Ledger

## About the Project

This project is a digital wallet system built using Python, FastAPI, and PostgreSQL. It allows users to check wallet balances, view transaction history, and transfer money between wallets.

The project also includes a reconciliation process to check whether wallet records and ledger entries are consistent.

## Features

* Check wallet balances.
* View wallet transaction history with pagination.
* Transfer money between wallets.
* Prevent transfers when the wallet has insufficient balance.
* Use idempotency keys to prevent duplicate transfers.
* Record debit and credit entries in the ledger.
* Validate wallet status and currency.
* Handle concurrent transfers safely.
* Run reconciliation checks and store the results.
* Run automated API and database tests.

## Technologies Used

* Python
* FastAPI
* PostgreSQL
* Docker and Docker Compose
* Pytest
* Git and GitHub

## Project Structure

* `app/` — API, database connection, and worker code.
* `migrations/` — SQL files for database tables, functions, views, and reconciliation.
* `tests/` — Automated tests.
* `docs/` — Database design and transaction isolation notes.
* `docker-compose.yml` — Services required to run the project.
* `Dockerfile` — API container setup.
* `requirements.txt` — Python dependencies.

## How to Run

### 1. Start Docker Desktop

Make sure Docker Desktop is running.

### 2. Start PostgreSQL

Open Command Prompt in the project folder and run:

`docker compose up -d db`

### 3. Install Python packages

`python -m pip install -r requirements.txt`

### 4. Set up the database

Apply the SQL migration files in numerical order, from `001_initial_schema.sql` through `008_reconciliation_function.sql`.

If the database is already set up, do not run the initial setup again without checking which migrations have already been applied.

### 5. Start the API

`python -m uvicorn app.main:app --reload`

### 6. Open the API documentation

Open this address in your browser:

`http://127.0.0.1:8000/docs`

### 7. Check the API health

Open:

`http://127.0.0.1:8000/health`

A successful response shows that the API can connect to PostgreSQL.

## How to Run Tests

Run:

`python -m pytest -v`

The tests cover API endpoints, wallet balances, transfers, idempotency, ledger entries, statements, reconciliation, and concurrent transfers.

## Reconciliation Worker

The worker runs reconciliation checks at a scheduled interval. The default interval is 24 hours.

The project also provides an API endpoint to run reconciliation manually:

`POST /admin/reconciliation/run`

The result includes the run status, number of checks passed, and number of issues found.

## Database Design

PostgreSQL stores users, wallets, transfers, and ledger entries. SQL migrations create the database objects and reconciliation functions.

Money is stored in paise as integer minor units to avoid floating-point errors in financial calculations.

Transfers use database transactions and wallet locking to help maintain consistent balances during concurrent requests.

## What I Learned

I learned how to build backend APIs, work with PostgreSQL, create SQL migrations, handle wallet transfers, prevent duplicate requests, write automated tests, and check financial records through reconciliation.

## Future Improvements

* Add authentication and authorization.
* Add role-based access to administrative endpoints.
* Improve transfer reversal and failure handling.
* Add more security and failure-recovery tests.
* Automate database migration setup.
* Add more monitoring and operational documentation.
