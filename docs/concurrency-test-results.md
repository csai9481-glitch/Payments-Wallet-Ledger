# Concurrency Test Results



## Test Setup

- Starting wallet balance: ₹500

- Transfer amount: ₹10

- Concurrent requests per run: 100

- Worker threads: 20

- Total test runs: 20

- Test database: wallet_concurrency_db



## Results

- Test runs passed: 20 out of 20

- Successful transfers per run: 50

- Insufficient-balance rejections per run: 50

- Database errors: 0

- Invalid transfer ledger records: 0

- Ledger entries per run: 100

- Final sender balance: ₹0

- Final receiver balance: ₹500



## Conclusion

All 20 concurrency test runs passed. The wallet did not spend more money than it had. Each successful transfer created two matching ledger entries. All extra transfer attempts were rejected because the sender had insufficient funds.



These results confirm that the tested concurrent transfer scenario worked correctly.

