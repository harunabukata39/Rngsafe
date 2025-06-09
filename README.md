# 🎲 Rngsafe - Fair Random Number Oracle

> 🔒 **Verifiable randomness for games and applications on Stacks blockchain**

## 🌟 Overview

Rngsafe is a decentralized random number oracle that provides verifiable randomness for games, lotteries, and any application requiring fair random number generation. Built on Stacks blockchain using Clarity smart contracts.

## ✨ Features

- 🎯 **Fair Randomness**: Combines block hashes with oracle seeds for unpredictable results
- 🔍 **Verifiable**: All random numbers can be independently verified
- 💰 **Fee-based**: Pay-per-request model with configurable fees
- 📊 **Batch Processing**: Oracle can fulfill multiple requests efficiently
- 🏷️ **Request Tracking**: Track all your random number requests
- 🛡️ **Secure**: Owner-controlled oracle with transparent operations

## 🚀 Quick Start

### Prerequisites

```bash
npm install -g @hirosystems/clarinet-cli
```

### Installation

```bash
git clone <your-repo>
cd rngsafe
clarinet check
```

## 📖 Usage

### 🎲 Request Random Number

```clarity
(contract-call? .Rngsafe request-random-number u1 u100)
```

This requests a random number between 1 and 99 (inclusive of min, exclusive of max).

### 🔍 Check Request Status

```clarity
(contract-call? .Rngsafe get-random-request u1)
```

### 📋 Get Your Requests

```clarity
(contract-call? .Rngsafe get-user-requests 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
```

### 💎 Get Random Value

```clarity
(contract-call? .Rngsafe get-random-value u1)
```

### ✅ Verify Randomness

```clarity
(contract-call? .Rngsafe verify-randomness u1)
```

## 🔧 Oracle Operations

### 🎯 Fulfill Request (Oracle Only)

```clarity
(contract-call? .Rngsafe fulfill-random-request u1 u12345)
```

### 📦 Batch Fulfill (Oracle Only)

```clarity
(contract-call? .Rngsafe batch-fulfill-requests 
  (list 
    {id: u1, seed: u12345}
    {id: u2, seed: u67890}
  )
)
```

### 💰 Set Oracle Fee (Owner Only)

```clarity
(contract-call? .Rngsafe set-oracle-fee u2000000)
```

### 💸 Withdraw Fees (Owner Only)

```clarity
(contract-call? .Rngsafe withdraw-fees u1000000)
```

## 📊 Read-Only Functions

| Function | Description |
|----------|-------------|
| `get-oracle-fee` | 💰 Current fee per request |
| `get-contract-balance` | 🏦 Total contract balance |
| `get-request-counter` | 🔢 Total requests made |
| `is-request-fulfilled` | ✅ Check if request is completed |
| `get-pending-requests-count` | ⏳ Count of unfulfilled requests |

## 🎮 Game Integration Example

```clarity
(define-public (roll-dice)
  (let
    (
      (request-id (try! (contract-call? .Rngsafe request-random-number u1 u7)))
    )
    (ok request-id)
  )
)

(define-read-only (get-dice-result (request-id uint))
  (contract-call? .Rngsafe get-random-value request-id)
)
```

## 🔐 Security Features

- **Block Hash Integration**: Uses blockchain data for entropy
- **Two-Factor Randomness**: Combines oracle seed with block hash
- **Verifiable Results**: All randomness can be independently verified
- **Access Control**: Only oracle can fulfill requests
- **Fee Protection**: Prevents spam with required payments

## 🏗️ Architecture

1. **Request Phase**: Users pay fee and submit random number request
2. **Oracle Phase**: Oracle provides seed and fulfills request
3. **Generation Phase**: Contract combines oracle seed with block hash
4. **Verification Phase**: Anyone can verify the randomness

## 📈 Error Codes

| Code | Description |
|------|-------------|
| `u100` | 🚫 Unauthorized access |
| `u101` | ❌ Invalid request |
| `u102` | 🔍 Request not found |
| `u103` | ✅ Request already fulfilled |
| `u104` | 💸 Insufficient payment |
| `u105` | 📏 Invalid range |

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## 📄 License

MIT License - see LICENSE file for details


