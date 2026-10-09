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



\### Concurrent Transfer Experiment



We created a separate test sender wallet (wallet 3) and receiver wallet (wallet 4). The sender was funded with 500 paise (₹5.00).



We then sent 100 concurrent transfer requests using 20 worker threads. Each request attempted to transfer 10 paise (₹0.10).



\*\*Observed results:\*\*



| Check                       |    Result |

| --------------------------- | --------: |

| Concurrent requests         |       100 |

| Successful transfers        |        50 |

| Rejected requests           |        50 |

| Recorded transfers          |        50 |

| Sender balance after test   |   0 paise |

| Receiver balance after test | 500 paise |

| Unbalanced transfers        |         0 |



\### Conclusion



The experiment passed. The sender could not spend more money than the wallet contained. Exactly 50 transfers succeeded, and the remaining 50 requests were rejected. Each recorded transfer had two balanced ledger entries.



The transfer function locks both wallet rows in ascending wallet ID order before checking the sender's balance. This helps prevent concurrent transfers from spending the same funds twice.



This experiment tested the locked transfer implementation. A separate experiment without row locks is still needed to demonstrate the race condition directly.



