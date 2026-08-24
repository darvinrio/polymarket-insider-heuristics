# Problems

## Case 

Wallet : 0x1abc2b469b5ded495d6c8b21fc79dcb8d8f345e7
Token : 26478042894873829049001052570815865237527140127064054622215302548578606383208
Condition : 0xd8bc7b2461e41908ae01b6b837e60378b3576552e8c4e53115a56b0dd8c26ad2

Ledger Actions:

1. Buys `12.85` shares on CLOB for `12.83715` USD
2. Transfers `12.85` shares to `0x8B8b9c565C8dCA43cfb767F0F2C20B2B323d2512`

Ledger PnL:

- `-12.83715` USD

API PnL:

- `0` USD

Theory: 
Maybe API uses Price at the time of transfer. 

Validation:
If recipient PnL matches the expected PnL

Recipient Activity:

1. Receives  `8.17` shares from `0x69f0c154a3412f2b3fa7eb22c6d08e6b5b32fb27`
2. Receives `12.85` shares from `0x1abc2b469b5ded495d6c8b21fc79dcb8d8f345e7`
3. Receives `19.11` shares from `0x4e72c22cd76f9973a48aedfd79feeaacc8b7ffb9`

Recipient API:

- Pnl - `0.0001`
- Bought - `0`
- AvgPrice - `0.999`

Ledger Activity:
1. Receives  `8.17` shares from `0x69f0c154a3412f2b3fa7eb22c6d08e6b5b32fb27`
2. Receives `12.85` shares from `0x1abc2b469b5ded495d6c8b21fc79dcb8d8f345e7`
3. Receives `19.11` shares from `0x4e72c22cd76f9973a48aedfd79feeaacc8b7ffb9`
4. Convert `2` shares for `1.8` USD
5. Convert `38` shares for `33.77` USD

Ledger PnL:
  38.129999999999995
