\# Payments-Grade Wallet Ledger



\## About the Project



This is a wallet ledger project built using Python, FastAPI, and PostgreSQL.



The main goal of this project is to understand how a wallet system works. Users can check their wallet balance and transfer money to another wallet.



\## What This Project Can Do



\* Check the balance of a wallet.

\* Transfer money between two wallets.

\* Prevent transfers when there is not enough balance.

\* Store transaction details in the database.

\* Avoid processing the same transfer more than once using an idempotency key.

\* Keep the debit and credit entries consistent.

\* Run tests to check whether the API works correctly.



\## Technologies Used



\* Python

\* FastAPI

\* PostgreSQL

\* Docker

\* Pytest



\## How to Run the Project



1\. Start Docker Desktop.



2\. Open Command Prompt in the project folder.



3\. Start the database using:



&#x20;  `docker compose up -d`



4\. Install the required packages:



&#x20;  `python -m pip install -r requirements.txt`



5\. Start the API:



&#x20;  `python -m uvicorn app.main:app --reload`



6\. Open `http://127.0.0.1:8000/docs` in your browser to try the API.



\## How to Run Tests



Run this command in Command Prompt:



`python -m pytest -v`



The tests check the API endpoints and wallet balance responses.



\## What I Learned



Through this project, I am learning how to build backend APIs, work with PostgreSQL, manage wallet transactions, and use database transactions to keep financial records consistent.



