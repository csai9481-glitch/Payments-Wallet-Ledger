\# Database Isolation Experiments



\## 1. Purpose



This document explains how database isolation affects wallet transfers when multiple requests happen at the same time.



\## 2. The Problem



Two transfers may try to spend money from the same wallet at the same time. If both requests read the old balance before either transfer updates it, both may succeed even when there is not enough money.



This can cause the wallet balance to become negative or allow more money to be spent than the wallet contains.



\## 3. Experiment Plan



We will compare two approaches:



1\. \*\*Without row locks:\*\* Run concurrent transfers and observe whether a race condition occurs.

2\. \*\*With row locks:\*\* Lock the required wallet rows in a consistent order before checking balances and updating the ledger.



\## 4. Safe Transfer Approach



The safe transfer function should:



\* Lock the source and destination wallet rows.

\* Lock wallets in ascending wallet ID order to reduce deadlock risk.

\* Check the source wallet balance after obtaining the lock.

\* Reject transfers that would make the wallet balance negative.

\* Write balanced debit and credit ledger entries in the same database transaction.



\## 5. Results



Results will be added after running the experiments against the project database. No experimental results are claimed yet.



