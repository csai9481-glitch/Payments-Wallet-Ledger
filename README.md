# Payments-Grade Wallet Ledger

## About the Project

This project is a simple digital wallet system built using Python, FastAPI, and PostgreSQL.

Users can check wallet balances, view transaction history, and transfer money between wallets.

## Features

- Check wallet balance.
- View wallet transaction history.
- Transfer money between wallets.
- Prevent transfers when the balance is insufficient.
- Use idempotency keys to prevent duplicate transfers.
- Record debit and credit entries in the ledger.
- Validate wallet status and currency.
- Run automated tests.

## Technologies Used

- Python
- FastAPI
- PostgreSQL
- Docker
- Pytest

## How to Run

1. Start Docker Desktop.
2. Open CMD in the project folder.
3. Start the database: `docker compose up -d`
4. Install packages: `python -m pip install -r requirements.txt`
5. Start the API: `python -m uvicorn app.main:app --reload`
6. Open http://127.0.0.1:8000/docs in your browser.

## How to Run Tests

Run: `python -m pytest -v`

The tests check API endpoints, wallet balances, transfers, idempotency, and transaction statements.

## Database Design

PostgreSQL stores users, wallets, transfers, and ledger entries. SQL migration files create the tables and database functions. Money is stored in paise to avoid floating-point calculations.

## What I Learned

I am learning to build backend APIs, use PostgreSQL, manage wallet transfers, prevent duplicate requests, and maintain consistent financial records.

## Future Improvements

- Add authentication and authorization.
- Improve transfer failure and reversal handling.
- Add more concurrency and security tests.
- Run the API and database together using Docker Compose.
