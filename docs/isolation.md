# Database Isolation and Concurrency Testing

## 1. Purpose

This document explains how database transactions behave when multiple sessions access or update the same data.

The experiments use a separate database named `wallet_isolation_lab`. They do not modify the main wallet database or the protected performance, concurrency, and reconciliation databases.

The experiments cover:

- Read Committed isolation.
- Repeatable Read isolation.
- Serializable isolation.
- Concurrent wallet transfers.
- Database locking decisions.
- Performance and reconciliation evidence.

## 1.1 Reproducible SQL Lab

### Connect to the isolated lab database

Open two separate PowerShell or Command Prompt windows. Run the following command in each window:

```powershell
docker exec -it wallet_postgres psql -U wallet_user -d wallet_isolation_lab
```

Keep both database sessions open. Call them **Session A** and **Session B**.

Run the following setup command in either session:

```sql
CREATE TABLE IF NOT EXISTS isolation_demo (
    id INTEGER PRIMARY KEY,
    amount INTEGER NOT NULL,
    note TEXT NOT NULL
);

INSERT INTO isolation_demo (id, amount, note)
VALUES (1, 100, 'Original note')
ON CONFLICT (id) DO NOTHING;

INSERT INTO isolation_demo (id, amount, note)
VALUES (2, 100, 'Serializable test')
ON CONFLICT (id) DO NOTHING;

SELECT * FROM isolation_demo ORDER BY id;
```

The setup creates a small table for testing transaction isolation. Existing rows are not overwritten when the setup is run again.

### Experiment A: Read Committed

Read Committed allows a transaction to see changes committed by other transactions when it runs a new query.

**Session A — run first:**

```sql
BEGIN ISOLATION LEVEL READ COMMITTED;

SELECT amount
FROM isolation_demo
WHERE id = 1;
```

Note the amount returned.

**Session B — run after Session A's first query:**

```sql
UPDATE isolation_demo
SET amount = amount + 50
WHERE id = 1;

COMMIT;
```

**Session A — run after Session B commits:**

```sql
SELECT amount
FROM isolation_demo
WHERE id = 1;

COMMIT;
```

**Expected result:** Session A can see the newly committed amount in its second query. For example, if the initial amount was 200, the second query returns 250.

This demonstrates Read Committed behavior.

### Experiment B: Repeatable Read

Repeatable Read keeps a consistent snapshot for the transaction. Changes committed by another transaction after the snapshot is established are not visible to later queries in that same transaction.

**Session A — run first:**

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ;

SELECT amount
FROM isolation_demo
WHERE id = 1;
```

Note the returned amount.

**Session B — run after Session A's first query:**

```sql
UPDATE isolation_demo
SET amount = amount + 50
WHERE id = 1;

COMMIT;
```

**Session A — run after Session B commits:**

```sql
SELECT amount
FROM isolation_demo
WHERE id = 1;

COMMIT;
```

**Expected result:** Session A sees the same amount in both queries, provided Session B commits after Session A establishes its snapshot.

A new transaction can see the updated amount.

### Experiment C: Serializable

Serializable provides stronger isolation. PostgreSQL can reject a transaction if concurrent changes would make the result inconsistent with a serial execution.

First, prepare the test row in either session:

```sql
UPDATE isolation_demo
SET amount = 100,
    note = 'Serializable test'
WHERE id = 2;
```

Commit the setup:

```sql
COMMIT;
```

**Session A — run first:**

```sql
BEGIN ISOLATION LEVEL SERIALIZABLE;

SELECT amount
FROM isolation_demo
WHERE id = 2;
```

**Session B — run before Session A updates the row:**

```sql
BEGIN ISOLATION LEVEL SERIALIZABLE;

SELECT amount
FROM isolation_demo
WHERE id = 2;
```

Both sessions should read the row before either session updates it.

**Session A:**

```sql
UPDATE isolation_demo
SET amount = amount + 10
WHERE id = 2;

COMMIT;
```

**Session B:**

```sql
UPDATE isolation_demo
SET amount = amount + 20
WHERE id = 2;

COMMIT;
```

Depending on the transaction schedule, PostgreSQL may reject Session B with a serialization error.

If a transaction fails, run the following in that session before continuing:

```sql
ROLLBACK;
```

**Observed result:** A serialization error, including `could not serialize access due to concurrent update`, was observed during the lab experiments.

This demonstrates that an application must be prepared to roll back and safely retry transactions that fail due to serialization conflicts.

## 2. Read Committed Results

The Read Committed experiment demonstrated that a second query can see a change committed by another session while the first transaction remains open.

For example:

1. Session A reads an amount.
2. Session B updates the amount and commits.
3. Session A runs the same query again.
4. Session A sees the updated amount.

This behavior is useful for many application queries, but balance-changing operations require additional protection against concurrent updates.

## 3. Repeatable Read Results

The Repeatable Read experiment demonstrated snapshot behavior.

When Session A establishes its snapshot and Session B commits an update afterward, Session A continues to see the original value in subsequent queries within that transaction.

The result depends on the transaction order. Session B must commit after Session A has established its snapshot for this demonstration.

## 4. Serializable Results

The Serializable experiment produced a PostgreSQL serialization error during concurrent updates.

The application must treat this as a failed transaction, roll it back, and retry the complete operation when appropriate. It must not assume that every transaction will commit successfully.

Serializable isolation is useful for operations that need stronger guarantees, but it may require retries under concurrent load.

## 5. Concurrent Wallet Transfer Experiment

The wallet concurrency test checks that simultaneous transfers do not cause the sender to spend more money than the available balance.

The test uses an isolated concurrency database rather than the main wallet database.

### Test setup

- Sender starting balance: 500 paise (₹5.00).
- Receiver starting balance: 0 paise.
- Concurrent requests: 100.
- Workers: 20.
- Transfer amount: 10 paise per request.
- Test repetitions: 20.

### Results

Across the repeated test runs:

- 50 transfers succeeded per run.
- 50 transfers were rejected because the sender did not have enough money.
- 0 database errors were reported.
- 0 invalid ledger records were reported.
- Final sender balance: 0 paise.
- Final receiver balance: 500 paise.
- The total money transferred matched the sender's original balance.

These results support the balance-protection behavior under the tested concurrency workload.

See `docs/concurrency-test-results.md` for the detailed results.

## 6. Isolation and Locking Decisions

The wallet transfer operation uses database transactions and explicit row locking to protect wallet balances.

The main decisions are:

1. Lock the source and destination wallet rows before checking and changing balances.
2. Acquire wallet locks in ascending wallet ID order to reduce the risk of deadlocks.
3. Check that the sender has enough available funds before completing the transfer.
4. Record the transfer and corresponding ledger entries within the transaction.
5. Commit the transaction only when the operation succeeds.
6. Roll back the transaction if an error prevents a valid transfer.

Read Committed isolation with explicit wallet row locks is suitable for the tested transfer design because the locks protect the critical balance checks and updates.

## 7. Reconciliation Acceptance Test

The reconciliation acceptance test was run in the separate `wallet_reconciliation_db` database.

The test dataset contained:

- 10,000 transfers.
- 20,000 ledger entries.

Deliberate data corruption was introduced to check whether reconciliation could identify inconsistencies.

The reconciliation process reported three findings:

- Two `transfer_ledger_mismatch` findings.
- One `wallet_balance_mismatch` finding.

After the test data was restored, reconciliation reported zero issues.

The test demonstrates that reconciliation can identify the tested inconsistencies. It does not prove that every possible type of corruption has been tested.

See `tests/test_reconciliation_integrity.py` and the reconciliation acceptance-test results for supporting evidence.

## 8. Performance and Additional Evidence

The performance dataset is maintained in the separate `wallet_perf_db` database.

The verified dataset contains:

- 1,000 seed users.
- 2,000 seed wallets.
- 100,000 transfers from the initial seed.
- 400,000 additional transfers from the scale seed.
- 500,000 transfers in total.
- 1,000,000 ledger entries.

The OFFSET and cursor-pagination query results were not equivalent in the recorded comparison. Therefore, that comparison should not be treated as proof that both pagination approaches return identical results.

Related evidence:

- `docs/performance-results.md`
- `docs/concurrency-test-results.md`
- `docs/test-results.txt`
- `tests/test_api.py`
- `tests/test_reconciliation_integrity.py`

## 9. Limitations

The experiments cover specific transaction schedules and test cases. They do not prove that every possible concurrency problem or data-integrity failure has been eliminated.

The results depend on the order in which sessions execute and commit their transactions.

The performance and concurrency datasets are isolated from the main development database to avoid accidental modification of the normal development data.

A full demo video and any remaining submission-specific requirements should be checked separately before final submission.

## 10. Conclusion

The isolation experiments demonstrate how PostgreSQL handles concurrent transactions under Read Committed, Repeatable Read, and Serializable isolation.

The wallet concurrency test supports the use of database transactions and wallet row locks to protect balances under the tested workload. The reconciliation acceptance test demonstrates detection of the deliberately introduced inconsistencies.

Together, these experiments provide evidence for the wallet ledger's transaction safety, concurrency handling, and reconciliation behavior within the tested scenarios.