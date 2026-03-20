---
name: coti-private-erc20
description: "Deploys and manages privacy-preserving ERC20 tokens on COTI blockchain. Use when user asks to 'deploy token', 'create private token', 'mint tokens', 'transfer tokens', 'token balance', 'ERC20', 'private ERC20', 'approve spender', or 'token allowance'. Handles encrypted balances and confidential transfers."
metadata:
  author: coti-io
  version: 1.0.0
  mcp-server: coti-mcp
  category: blockchain
  tags: [coti, privacy, erc20, tokens, defi]
---

# COTI Private ERC20 Tokens

## Overview

This skill deploys and manages privacy-preserving ERC20 tokens on the COTI network. Unlike standard ERC20 tokens, COTI private tokens **encrypt balances and transfer amounts** using garbled circuits, so token holdings and transaction values remain confidential on-chain while remaining fully EVM-compatible.

Key constraints:
- **Maximum 6 decimal places** (COTI garbled-circuit integers support up to 6 decimal places, not 18)
- Balances are encrypted — raw `balanceOf()` calls return encrypted bytes, not a readable number
- Transfer amounts are confidential — on-chain observers see a transfer occurred but not the amount

## Prerequisites

- The `coti-mcp` MCP server must be connected and running
- A COTI account with AES key must be configured (use `coti-account-setup` skill)
- Native COTI balance for gas fees

## Workflow

### Deploying a New Private Token

1. Call `deploy_private_erc20_contract` with:
   - `name`: Token name (e.g., `"PrivateToken"`)
   - `symbol`: Token symbol (e.g., `"PRVT"`)
   - `decimals`: Precision, **maximum 6** (e.g., `6`)
2. Save the returned contract address — required for all subsequent operations

### Minting Tokens

1. Call `mint_private_erc20_token` with:
   - `token_address`: The deployed token contract address
   - `recipient_address`: Wallet to receive the new tokens
   - `amount_wei`: Number of tokens to mint (as a string)
2. Only the contract deployer can mint

### Transferring Tokens

1. Call `transfer_private_erc20` with:
   - `token_address`: The token contract address
   - `recipient_address`: Recipient wallet
   - `amount_wei`: Amount to transfer (as a string)
2. The transfer amount is encrypted on-chain

### Checking Balances

1. Call `get_private_erc20_balance` with the token address and account address
2. Returns the decrypted balance (visible to the account holder via the privacy layer)

### Approvals and Allowances

1. Call `approve_erc20_spender` to grant a third party permission to transfer tokens on your behalf
   - Inputs: `token_address`, `spender_address`, `amount_wei`
2. Call `get_private_erc20_allowance` to verify how much a spender is approved for
   - Inputs: `token_address`, `owner_address`, `spender_address`

## Interaction Map

```mermaid
flowchart TD
    subgraph Deploy["Deploy Token"]
        DT[deploy_private_erc20_contract\nname, symbol, decimals≤6] -->|contractAddress| Addr[(token address\nsave this!)]
    end

    subgraph Mint["Mint Tokens (owner only)"]
        Addr --> MT[mint_private_erc20_token\ntoken_address, recipient_address, amount_wei]
        MT -->|transactionHash| Supply([tokens minted])
    end

    subgraph Transfer["Transfer Tokens"]
        Addr --> TR[transfer_private_erc20\ntoken_address, recipient_address, amount_wei]
        TR -->|transactionHash\n(amount encrypted on-chain)| Sent([transfer sent])
    end

    subgraph Query["Query Token State"]
        Addr --> BAL[get_private_erc20_balance\ntoken_address, account_address]
        Addr --> SUP[get_private_erc20_total_supply\ntoken_address]
        Addr --> DEC[get_private_erc20_decimals\ntoken_address]
        BAL -->|balance or MPC decode note| BalOut([balance])
        SUP -->|supply or MPC decode note| SupOut([total supply])
        DEC -->|decimals 0-6| DecOut([precision])
    end

    subgraph Approve["Allowances"]
        Addr --> APP[approve_erc20_spender\ntoken_address, spender_address, amount_wei]
        APP -->|transactionHash| Approved([spender approved])
        Addr --> GAL[get_private_erc20_allowance\ntoken_address, owner_address, spender_address]
        GAL -->|allowance| AllOut([approved amount])
    end

    subgraph CrossSkill["Cross-Skill"]
        ACCT["coti-account-setup\n(wallet + AES key)"] --> DT
        MT --> TX["coti-transaction-tools:\nget_transaction_status"]
        TR --> TX
    end
```

### Data Flow

| Tool | Key Inputs | Key Outputs | Notes |
|---|---|---|---|
| `deploy_private_erc20_contract` | `name`, `symbol`, `decimals` | `contractAddress` | Decimals max 6 |
| `mint_private_erc20_token` | `token_address`, `recipient_address`, `amount_wei` | `transactionHash` | Owner only |
| `transfer_private_erc20` | `token_address`, `recipient_address`, `amount_wei` | `transactionHash` | Amount encrypted on-chain |
| `get_private_erc20_balance` | `token_address`, `account_address` | balance or MPC note | May return encrypted bytes on raw call |
| `get_private_erc20_total_supply` | `token_address` | supply | May return MPC decode note |
| `get_private_erc20_decimals` | `token_address` | integer 0–6 | Use to interpret amounts |
| `approve_erc20_spender` | `token_address`, `spender_address`, `amount_wei` | `transactionHash` | — |
| `get_private_erc20_allowance` | `token_address`, `owner_address`, `spender_address` | allowance | Rich text response |

## Tool Reference

### `deploy_private_erc20_contract`
Deploys a new privacy-preserving ERC20 token. Returns the contract address. The deployer becomes the owner and can mint tokens.

### `mint_private_erc20_token`
Mints new tokens to a specified address. Only the contract owner (deployer) can call this.

### `transfer_private_erc20`
Transfers tokens between addresses. The transfer amount is encrypted on-chain — only the sender and recipient can read it through the privacy layer.

### `get_private_erc20_balance`
Returns the token balance for an account, decrypted via the privacy layer. Due to garbled-circuit encryption, this may return a "could not decode result data" message on raw calls — this is expected behavior, not an error.

### `get_private_erc20_total_supply`
Returns the total minted supply of the token. Encrypted on-chain via garbled circuits — may return a decode note.

### `get_private_erc20_decimals`
Returns the decimal precision of the token (0–6). Always use this before performing arithmetic on token amounts.

### `approve_erc20_spender`
Approves a spender address to transfer up to a specified amount of tokens on the caller's behalf (standard ERC20 allowance pattern).

### `get_private_erc20_allowance`
Returns the remaining allowance a spender has for a given owner.

## Error Handling

- **"not owner"**: Only the contract deployer can mint tokens. Verify you are using the same wallet that deployed the contract.
- **"insufficient balance"**: The sender does not have enough tokens. Check balance before transferring.
- **"insufficient allowance"**: The spender was not approved for the requested amount. Call `approve_erc20_spender` first.
- **"contract not found"**: The contract address is invalid or deployed on a different network (testnet vs mainnet).
- **"decimals must be ≤ 6"**: COTI garbled-circuit integers support a maximum of 6 decimal places. Do not use 18.
- **"could not decode result data"**: Expected behavior for garbled-circuit encrypted state reads (`totalSupply`, `balanceOf`). Values are encrypted on-chain — the tool is working correctly.

## Examples

**Deploy a private token:**
> "Create a new private token called SecureToken with symbol STOK"

1. `deploy_private_erc20_contract` with `name: "SecureToken"`, `symbol: "STOK"`, `decimals: 6`
2. Returns contract address

**Mint and transfer tokens:**
> "Mint 1000 STOK to my wallet, then send 500 to 0xRecipient"

1. `mint_private_erc20_token` with `token_address`, `recipient_address: myWallet`, `amount_wei: "1000"`
2. `transfer_private_erc20` with `token_address`, `recipient_address: "0xRecipient"`, `amount_wei: "500"`

**Set up delegated spending:**
> "Allow 0xDex to spend up to 200 STOK on my behalf"

1. `approve_erc20_spender` with `token_address`, `spender_address: "0xDex"`, `amount_wei: "200"`
2. `get_private_erc20_allowance` to confirm approval

## Important Notes

- **Decimals max 6** — do not use 18. COTI's garbled-circuit integers have a precision limit.
- Balances are encrypted on-chain — only the account holder can view their balance through the privacy layer
- Transfer amounts are confidential but sender/recipient addresses are visible
- The token is fully EVM-compatible for non-privacy operations (standard tooling works)
- Token IDs in parameter names use `token_address` (not `contractAddress`) — exact spelling matters for the MCP tool schema
- Check `get_private_erc20_decimals` before doing arithmetic — amounts are in the token's smallest unit
