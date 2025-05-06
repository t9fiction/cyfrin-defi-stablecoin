
# USD Stablecoin

A decentralized, algorithmic stablecoin pegged to the US Dollar (USD), backed by exogenous crypto assets.

> 📣 **Built with ❤️ using [Cyfrin's Updraft Program](https://www.cyfrin.io/updraft)** | 🙏 Thanks to [Patrick Collins](https://www.linkedin.com/in/patrickalphac/)

## Overview

USD Stablecoin is designed with three key principles:

1. **Anchored/Pegged to USD**
   - Utilizes Chainlink price feeds to maintain the USD value
   - Functions for exchanging ETH & BTC collateral to mint USD tokens

2. **Algorithmic Decentralized Stability Mechanism**
   - Maintains stability through overcollateralization
   - Users can only mint USD with sufficient collateral
   - Implements a 50% liquidation threshold
   - 10% liquidation bonus incentivizes external liquidators

3. **Exogenous Crypto Collateral**
   - Supported collateral assets:
     - Wrapped Bitcoin (wBTC)
     - Wrapped Ethereum (wETH)

## Smart Contract Architecture

### DecentralizedStableCoin.sol
- ERC20 token implementation for the USD stablecoin
- Implements minting and burning functionality
- Controlled by the DSCEngine contract

### DSCEngine.sol
- Core contract managing the business logic
- Handles collateral deposits and redemptions
- Controls minting and burning of USD tokens
- Implements health factor calculations and liquidations
- Utilizes Chainlink price feeds for collateral valuation

## Features

- **Overcollateralized Positions**: All USD minting requires overcollateralization
- **Liquidation System**: Positions that fall below health factor thresholds can be liquidated
- **Multi-Collateral Support**: Deposit and use multiple types of collateral
- **No Governance**: No governance controls or admin keys (fully algorithmic)
- **No Fees**: No platform fees for usage

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Git](https://git-scm.com/downloads)

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/cyfrin-defi-stablecoin.git
   cd cyfrin-defi-stablecoin
   ```

2. Install dependencies:
   ```bash
   forge install
   ```

3. Build the project:
   ```bash
   forge build
   ```

### Testing

Run the test suite:
```bash
forge test
```

For more detailed test output:
```bash
forge test -vvv
```

For test coverage:
```bash
forge coverage
```

## Usage Guide

### Depositing Collateral

Users can deposit wBTC or wETH as collateral:

```solidity
// Deposit collateral
dscEngine.depositCollateral(tokenAddress, amountCollateral);

// Deposit collateral and mint USD in one transaction
dscEngine.depositCollateralAndMintDSC(tokenAddress, amountCollateral, amountToMint);
```

### Minting USD

Once collateral is deposited, users can mint USD tokens:

```solidity
// Mint USD (requires sufficient collateral)
dscEngine.mintDSC(amountToMint);
```

### Redeeming Collateral

Users can redeem their collateral:

```solidity
// Redeem collateral
dscEngine.redeemCollateral(tokenAddress, amountCollateral);

// Burn USD and redeem collateral in one transaction
dscEngine.redeemCollateralForDSC(tokenAddress, amountCollateral, amountToBurn);
```

### Burning USD

Users can burn their USD tokens:

```solidity
// Burn USD
dscEngine.burnDSC(amountToBurn);
```

### Liquidations

If a user's position falls below the required health factor (1.0), anyone can liquidate it:

```solidity
// Liquidate an unhealthy position
dscEngine.liquidate(tokenCollateralAddress, userAddress, debtToCover);
```

## Deployment

To deploy to a local network:

```bash
forge script script/DeployDSC.s.sol --rpc-url http://localhost:8545 --private-key $PRIVATE_KEY
```

To deploy to a testnet or mainnet:

```bash
forge script script/DeployDSC.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
```

## Security Considerations

- **Collateral Volatility**: The system relies on the value of crypto collateral, which can be volatile
- **Oracle Risk**: Depends on Chainlink price feeds for accurate pricing information
- **Liquidation Thresholds**: Uses a 50% liquidation threshold with a 10% liquidation bonus
- **Health Factor**: Positions must maintain a minimum health factor of 1.0

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🚀 Credits & Attribution (Cyfrin + Patrick Collins + Team)

> ⚠️ This project is heavily inspired by the excellent work of **Patrick Collins** and his team at **Cyfrin** through their DeFi course and the **[Updraft Accelerator Program](https://www.cyfrin.io/updraft)**.  
>
> 🙏 Huge thanks to **[Patrick Collins (LinkedIn)](https://www.linkedin.com/in/patrickalphac/)** and everyone at Cyfrin for their continuous efforts in educating and empowering Web3 developers.  
>
> This repo would not exist without their open-source contributions and educational guidance.

## Acknowledgments

- Built with [Foundry](https://github.com/foundry-rs/foundry)
- Uses [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts) smart contracts
- Integrates [Chainlink](https://chain.link/) price feeds


