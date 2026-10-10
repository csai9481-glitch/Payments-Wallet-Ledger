# Payments-Grade Wallet Ledger

## About the Project

This project is a digital wallet system built using Python, FastAPI, and PostgreSQL.

Users can check wallet balances, view transaction history, and transfer money between wallets.

## Features

* Check wallet balances.
* View wallet transaction history.
* Transfer money between wallets.
* Prevent transfers when the balance is insufficient.
* Use idempotency keys to prevent duplicate transfers.
* Record debit and credit entries in the ledger.
* Validate wallet status and currency.
* Run automated tests.

## Technologies Used

* Python
* FastAPI
* PostgreSQL
* Docker
* Pytest

## How to Run

1. Start Docker Desktop.

2. Open Command Prompt in the project folder.

3. Start PostgreSQL:

   `docker compose up -d db`

4. Install the required Python packages:

   `python -m pip install -r requirements.txt`

5. Apply the database migrations in order, from `001_initial_schema.sql` to `006_transfer_function.sql`. Follow the database setup instructions in the project documentation.

6. Start the API:

   `python -m uvicorn app.main:app --reload`

7. Open the API documentation in your browser:

   `http://127.0.0.1:8000/docs`

## How to Run Tests

Run this command:

`python -m pytest -v`

The tests check API endpoints, wallet balances, idempotency, ledger entries, and transaction statements.

## Database Design

PostgreSQL stores users, wallets, transfers, and ledger entries. SQL migration files create the database tables, views, and functions. Money amounts are stored in paise to avoid floating-point calculation errors.

## What I Learned

I learned the basics of building backend APIs, using PostgreSQL, handling wallet transfers, preventing duplicate requests, and maintaining consistent financial records.

## Future Improvements

* Add authentication and authorization.
* Improve transfer failure and reversal handling.
* Add more concurrency and security tests.
* Add automated database migration setup.
