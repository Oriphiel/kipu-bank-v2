# KipuBankV2: An Advanced Multi-Token Smart Contract Bank

![Solidity](https://img.shields.io/badge/Solidity-%5E0.8.30-lightgrey)
![License](https://img.shields.io/badge/License-MIT-blue.svg)

## 📜 General Overview

**KipuBankV2** is a significant evolution of the original KipuBank contract, refactored into a robust, secure, and flexible decentralized application that aligns with production-grade standards. This project integrates advanced design patterns and essential ecosystem tools like **OpenZeppelin** and **Chainlink** to create a multi-asset bank with dynamic risk management, administrative controls, and a secure asset management framework.

## ✨ Key Upgrades & Features

This new version introduces several critical improvements that address the limitations of the original V1 contract:

### 1. 🏦 Secure, Admin-Managed Multi-Token Support
*   **V1 Problem:** Could only handle native ETH and lacked token vetting.
*   **V2 Solution:** The contract now supports ETH and a curated list of ERC-20 tokens. A **supported asset registry (whitelist)**, managed exclusively by the contract owner, ensures that only approved tokens can be deposited, preventing malicious or spam tokens from interacting with the bank.

### 2. 🛡️ Robust Token Handling with `SafeERC20`
*   **V1 Problem:** Direct `IERC20` calls were incompatible with non-standard tokens (like USDT) and vulnerable to fee-on-transfer tokens.
*   **V2 Solution:** All ERC-20 interactions now use OpenZeppelin's **`SafeERC20`** library. This ensures compatibility with a wider range of tokens and enables secure accounting patterns. The `depositToken` function uses a **"balance difference" check** to accurately credit users for the exact amount received, even if the token charges a fee on transfer.

### 3. 💹 Dynamic USD-Denominated Capital Limit
*   **V1 Problem:** The bank's deposit limit was a static ETH value, susceptible to market volatility.
*   **V2 Solution:** A **Chainlink Price Feed Oracle (ETH/USD)** has been integrated. The `bankCap` is now defined in USD, providing a far more stable risk ceiling. The value of every ETH deposit is checked against this USD cap in real-time.

### 4. 🔐 Advanced Security & Admin Controls
*   **V1 Problem:** Lacked administrative roles and advanced security measures.
*   **V2 Solution:** The contract now inherits from three core OpenZeppelin security contracts: **`Ownable`**, **`ReentrancyGuard`**, and **`Pausable`**, providing role-based access control, defense-in-depth against re-entrancy, and an emergency circuit-breaker mechanism.

## ⚖️ Design Decisions & Trade-offs

*   **Whitelisted Asset Management:** To ensure the security and integrity of the bank's assets, a whitelist pattern (`isTokenSupported` mapping) has been implemented. This is a deliberate choice favoring security over permissionless access, which is standard for protocols managing user funds.
*   **"Balance Difference" Pattern over C-E-I:** The `depositToken` function uses the "balance difference" pattern to safely handle fee-on-transfer tokens. This necessarily places the external call (`safeTransferFrom`) before the state update (`userBalances`), deviating from the strict Checks-Effects-Interactions pattern. The security of this approach is guaranteed by the mandatory use of the **`nonReentrant` modifier**, which prevents re-entrancy attacks during the external call.
*   **Single Oracle for ETH:** For this project's scope, a single ETH/USD oracle is used. The `depositToken` function for ERC-20s does not check against the USD cap. A full-scale production system would require a more complex oracle registry to value each whitelisted token.

---

## 🚀 Deployment & Interaction Guide (Using Remix IDE)

Follow these steps to deploy and interact with the `KipuBankV2` contract on a public testnet.

### Step 1: Prerequisites

1.  **Remix IDE:** Have the [Remix IDE](https://remix.ethereum.org/) open.
2.  **MetaMask:** Have the MetaMask browser extension installed and your wallet unlocked.
3.  **Sepolia Test ETH:** Ensure your wallet is connected to the **Sepolia Test Network** and funded with test ETH from a faucet.
4.  **Chainlink Oracle Address:** You need the official ETH/USD Price Feed address for the Sepolia network.
    *   **Address:** `0x694AA1769357215DE4FAC081bf1f309aDC325306`

### Step 2: Compilation

1.  Create a new file in Remix named `KipuBankV2.sol` and paste the entire contract code into it.
2.  Go to the **Solidity Compiler** tab.
3.  Select a **Compiler Version** compatible with the pragma (e.g., `0.8.20` or higher).
4.  Click **Compile KipuBankV2.sol** and wait for the green checkmark.

### Step 3: Deployment

1.  Go to the **Deploy & Run Transactions** tab.
2.  Set the **ENVIRONMENT** to **Browser Wallet - MetaMask**. Approve the connection.
3.  From the **CONTRACT** dropdown, select `KipuBankV2`.
4.  Provide the two constructor arguments:
    *   `_priceFeedAddress (address)`: Paste the **Chainlink oracle address** from Step 1.
    *   `_initialBankCapUSD (uint256)`: This is the USD cap with **8 decimal places**. For a **$500,000 USD** cap, enter: `50000000000000`
5.  Click **transact** and **Confirm** the transaction in MetaMask.
6.  Once mined, copy the contract's address from the "Deployed Contracts" panel.

### Step 4: Verification on Etherscan

1.  Go to [**sepolia.etherscan.io**](https://sepolia.etherscan.io), search for your contract address.
2.  On the contract's page, click **Contract** -> **Verify & Publish**.
3.  Fill in the form: `Solidity (Single File)`, the exact **Compiler Version**, and `MIT License`.
4.  Click **Continue**. Paste the **entire source code** into the editor.
5.  Click **Verify and Publish**.

### Step 5: Interaction

You can now interact with your verified contract directly on Etherscan's `Read Contract` and `Write Contract` tabs.

#### **User Functions:**

*   **Deposit ETH:** Call `depositNative()` and send ETH in the transaction's `value` field.
*   **Deposit ERC-20 Tokens:**
    1.  **Crucial First Step:** The contract `owner` must have already added the token to the whitelist (see Admin Functions).
    2.  As a user, you must `approve()` the KipuBankV2 contract address on the ERC-20 token's contract.
    3.  Then, call `depositToken(tokenAddress, amount)` on KipuBankV2.
*   **Withdraw Funds:** Call `withdraw(tokenAddress, amount)`. Use `0x00...000` (the zero address) for `tokenAddress` to withdraw ETH.

#### **Admin Functions (Owner Only):**

*   **Manage Supported Tokens:**
    *   **Add a Token:** Call `supportNewToken(tokenAddress)` with the official ERC-20 contract address of the token you want to accept.
    *   **Remove a Token:** Call `removeTokenSupport(tokenAddress)`.
*   **Emergency Controls:**
    *   **Pause Contract:** Call `pause()` to halt all primary functions.
    *   **Unpause Contract:** Call `unpause()` to resume normal operations.
*   **Manage Bank Parameters:** Call `setBankCap(newCapUSD)` or `setPriceFeed(newOracleAddress)`.

---
**Deployed Contract Address (Sepolia Testnet):**
`https://sepolia.etherscan.io/address/0x7bCD8cf21519DB30f3f9b4b8690Fb993C9d4bDFE`