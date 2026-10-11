# Database Isolation Experiments



## 1. Purpose



This document explains how PostgreSQL transaction isolation helps protect wallet data when multiple operations happen at the same time.



The experiments use separate temporary tables named `isolation_demo` and `isolation_demo_detail`. They do not modify the real wallet balances.



## 2. Read Committed



### Steps



1\. Created a test row with `amount = 100`.

2\. Session A started a transaction and read the amount.

3\. Session B updated the amount to `200` and committed.

4\. Session A read the same row again without ending its transaction.



### Observed result



- First read in Session A: `100`.

- Session B updated and committed: `200`.

- Second read in Session A: `200`.



### Conclusion



Read Committed takes a fresh snapshot for each statement. Session A saw Session B's committed change in its second query.



## 3. Repeatable Read



### Steps



1\. Session A started a Repeatable Read transaction.

2\. Session A read the amount as `200`.

3\. Session B changed the amount to `300` and committed.

4\. Session A read the amount again before committing.



### Observed result



- First read in Session A: `200`.

- Session B committed the value `300`.

- Second read in Session A: `200`.



### Conclusion



Repeatable Read keeps a consistent snapshot for the transaction. Session A continued seeing the earlier committed value.



## 4. Serializable



### Steps



1\. Two sessions started Serializable transactions.

2\. Both sessions read the same row.

3\. Session A attempted to add `10`.

4\. Session B attempted to add `20`.

5\. Session A committed successfully.



### Observed result



Session A's update succeeded and committed. Session B received this PostgreSQL error:



`could not serialize access due to concurrent update`



The failed transaction was rolled back.



### Conclusion



Serializable prevents conflicting transactions from both succeeding when their combined execution cannot be serialized safely. An application must handle serialization errors and retry eligible transactions.



## 5. Repeatable Read with a JOIN



### Steps



1\. Created a second temporary table named `isolation_demo_detail`.

2\. Session A started a Repeatable Read transaction.

3\. Session A joined both tables and read the amount and note.

4\. Session B increased the amount by `100`, changed the note to `Updated note`, and committed.

5\. Session A repeated the JOIN before committing.



### Observed result



Session A saw the following values on both reads:



| Amount | Note |

|---:|---|

| 310 | Original note |



Session B committed changes to both tables, but Session A continued seeing its earlier snapshot.



### Conclusion



Repeatable Read provides a consistent view across the tables in the JOIN for the duration of the transaction.



## 6. Concurrent Wallet Transfer Experiment



A separate test used sender wallet 3 and receiver wallet 4. The sender was funded with 500 paise, and 100 concurrent requests each attempted to transfer 10 paise.



| Check | Result |

|---|---:|

| Concurrent requests | 100 |

| Successful transfers | 50 |

| Rejected requests | 50 |

| Recorded transfers | 50 |

| Sender balance after test | 0 paise |

| Receiver balance after test | 500 paise |

| Unbalanced transfers | 0 |



### Conclusion



The locked transfer implementation allowed exactly 50 transfers. The remaining requests were rejected because the sender did not have enough funds. The recorded transfers had balanced ledger entries.



This test demonstrates the behavior of the locked implementation. It does not independently demonstrate a successful overspend race in an implementation without row locks.



## 7. Isolation and Locking Decisions



The wallet transfer implementation locks the source and destination wallet rows before checking the source balance and recording the money movement.



Wallet rows should be locked in ascending wallet ID order to reduce deadlock risk.



The balance check and ledger writes must occur in the same transaction. This prevents concurrent requests from spending the same available funds after they have obtained the required locks.



Read Committed can be suitable for a transfer when explicit row locks and transactional balance checks are correctly implemented. Stronger isolation levels can provide additional guarantees but may introduce serialization errors that applications must handle.



## 8. Test Coverage, Evidence, and Remaining Work

The project includes isolation experiments, automated API tests, concurrency testing, and performance measurements. Supporting evidence is recorded in the following files:

- `docs/concurrency-test-results.md` — documents 20 repeated concurrent-transfer test runs.
- `docs/performance-results.md` — documents query-plan measurements using a separate performance database containing 500,000 transfers and 1,000,000 ledger entries.
- `docs/test-results.txt` — records test results.
- `tests/test_api.py` — includes API tests for transfers, idempotency, and statement Q&A.
- `tests/test_reconciliation_integrity.py` — includes a reconciliation-integrity test.

### Important limitations

- The performance measurements for offset-based and cursor-based pagination did not return equivalent result sets. Their recorded timings should not be treated as a direct, like-for-like speed comparison.
- The concurrency results demonstrate the observed behavior in the tested scenarios. They do not prove that every possible concurrency issue has been eliminated.
- The full reconciliation acceptance scenario must be verified separately: use 10,000 transfers, introduce one transfer-amount mismatch, delete one credit ledger entry, change one stored balance, and confirm that reconciliation reports exactly three findings.
- Any acceptance scenario not explicitly tested should be treated as outstanding rather than assumed to have passed.

### Conclusion

The recorded experiments provide evidence for selected isolation, concurrency, and performance behaviors. Final submission readiness also depends on checking the required reconciliation scenario, reviewing the seed-data requirements, and ensuring all required documentation and demo evidence are included.


