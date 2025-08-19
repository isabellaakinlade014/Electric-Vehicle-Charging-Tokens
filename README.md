# ⚡ Electric Vehicle Charging Tokens

A Clarity smart contract for managing EV charging payments through tokenized credits on the Stacks blockchain.

## 🚗 Features

- **Token Management**: Mint, transfer, and burn charging tokens
- **Charging Station Registry**: Register and manage EV charging stations
- **Payment Processing**: Pay for charging sessions using tokens
- **Session Tracking**: Start/end charging sessions with consumption tracking
- **Multi-user Support**: Batch operations for tokens and transfers
- **Station Management**: Update pricing and status for charging stations

## 🛠️ Contract Functions

### Token Operations
- `mint-tokens(amount, recipient)` - Mint new tokens (owner only)
- `transfer-tokens(amount, sender, recipient)` - Transfer tokens between users
- `purchase-tokens(stx-amount)` - Buy tokens with STX
- `burn-tokens(amount)` - Burn user's tokens
- `bulk-mint-tokens(recipients)` - Mint tokens to multiple users

### Charging Station Management
- `register-charging-station(location, price-per-kwh)` - Register new station
- `update-station-status(station-id, is-active)` - Enable/disable station
- `update-station-price(station-id, new-price)` - Update pricing
- `emergency-pause-station(station-id)` - Emergency stop (owner only)

### Charging Sessions
- `start-charging-session(station-id)` - Begin charging session
- `end-charging-session(session-id, kwh-consumed)` - Complete session and pay
- `refund-session(session-id)` - Refund completed session

### Read Functions
- `get-balance(user)` - Check user token balance
- `get-station-info(station-id)` - Get station details
- `get-session-info(session-id)` - Get session details
- `get-session-cost(station-id, kwh-amount)` - Calculate charging cost
- `can-afford-charging(user, station-id, kwh-amount)` - Check affordability

## 📋 Usage Examples

### Purchase Tokens
```clarity
(contract-call? .Electric-Vehicle-Charging-Tokens purchase-tokens u5000000)
```

### Register Charging Station
```clarity
(contract-call? .Electric-Vehicle-Charging-Tokens register-charging-station "Downtown Mall" u50)
```

### Start Charging Session
```clarity
(contract-call? .Electric-Vehicle-Charging-Tokens start-charging-session u1)
```

### End Session and Pay
```clarity
(contract-call? .Electric-Vehicle-Charging-Tokens end-charging-session u1 u25)
```

## 💰 Token Economics

- **Base Price**: 1,000,000 microSTX per token (adjustable by owner)
- **Charging Cost**: Varies by station (set by station owner)
- **Payment Flow**: Users → Station Owners via token transfers

## 🔧 Development

### Prerequisites
- [Clarinet](https://github.com/hirosystems/clarinet)
- Node.js (for testing)

### Setup
```bash
npm install
clarinet check
```

### Testing
```bash
npm test
```

## 📊 Contract Statistics

Use `get-contract-stats()` to view:
- Total token supply
- Current token price
- Number of registered stations
- Total charging sessions

## 🚨 Error Codes

- `u100` - Owner only operation
- `u101` - Insufficient token balance
- `u102` - Charging station not found
- `u103` - Charging station inactive
- `u104` - Invalid amount provided
- `u105` - Charging session not found
- `u106` - Session already completed
- `u107` - Unauthorized operation

## 🔒 Security Features

- Owner-only administrative functions
- Session authorization checks
- Balance validation before transfers
- Station ownership verification
- Emergency pause functionality
