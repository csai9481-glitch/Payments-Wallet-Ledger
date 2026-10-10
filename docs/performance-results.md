# Performance Test Results



## 1. Test Setup



Performance testing was done using the separate PostgreSQL database `wallet_perf_db`. The main application database was not used for these tests.



- Total transfers: 500,000

- Total ledger entries: 1,000,000

- Database: PostgreSQL

- Measurement command: `EXPLAIN (ANALYZE, BUFFERS)`



These results are from one test run on the development environment. Execution times can change with hardware, database cache, and system load.



## 2. Indexes



The ledger table has these indexes:



- `ledger_entries_pkey` on `ledger_entry_id`

- `idx_ledger_entries_transfer` on `transfer_id`

- `idx_ledger_entries_wallet_created` on `(wallet_id, created_at DESC)`



The wallet-and-created-time index helps retrieve recent statement entries. The transfer index helps find the debit and credit entries belonging to a transfer.



## 3. Measured Query Results



| Query | Index or plan | Execution time |

|---|---|---:|

| Latest 20 ledger entries for wallet 1001 | Wallet-and-created-time index scan | 0.333 ms |

| Ledger entries for transfer 100001 | Transfer index scan | 2.485 ms |

| Deep pagination with `OFFSET 100000` | Bitmap heap scan and sort | 34.895 ms |

| Cursor-based pagination after a known entry | Index scan and incremental sort | 0.300 ms |



### Important limitation



Wallet 1001 had only 500 ledger entries in this dataset. Therefore, the `OFFSET 100000` query returned zero rows. The cursor query returned 20 rows.



These two pagination measurements are not a like-for-like comparison. The results illustrate query-plan behavior but do not prove a direct speed improvement for equivalent pages.



## 4. Query Plan Observations



### Recent wallet statement



The query used `idx_ledger_entries_wallet_created` and returned 20 rows in 0.333 ms. This index supports filtering by wallet and retrieving entries in descending creation-time order.



### Transfer lookup



The query used `idx_ledger_entries_transfer` and returned two entries in 2.485 ms. A normal completed transfer should have matching debit and credit ledger entries.



### Deep OFFSET pagination



The query took 34.895 ms and returned no rows. PostgreSQL performed a bitmap heap scan and a sort. Large offsets can require the database to process and discard many rows before returning a page.



### Cursor-based pagination



The query returned 20 rows in 0.300 ms using the wallet-and-created-time index and an incremental sort. Cursor pagination avoids skipping a large number of preceding rows. A composite index that also supports the unique ledger entry ID ordering may improve this query further.



## 5. Full Scans and Indexes



An index can reduce the number of table rows PostgreSQL needs to examine for selective lookups. Without a suitable index, the database may scan many or all ledger rows.



However, indexes require storage and add work to inserts and updates. They should be selected based on actual query patterns and measured plans.



## 6. Conclusion



The test database contains one million ledger entries and half a million transfers. The measured selective queries used the expected indexes. Deep OFFSET pagination and cursor-based pagination produced different workloads in this test, so a fair comparison requires a wallet with more than 100,000 entries and queries that return equivalent pages.



These measurements are development results, not a production performance guarantee.



