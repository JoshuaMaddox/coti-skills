# COTI Privacy Contract Patterns

## Overview

COTI extends Solidity with privacy primitives powered by garbled circuits. This reference covers common patterns for building confidential smart contracts.

## Private State Variables

COTI provides encrypted types for on-chain storage:

- `itUint64` — encrypted unsigned integer
- `itString` — encrypted string
- `itBool` — encrypted boolean

These types store ciphertext on-chain. Only authorized viewers can decrypt.

## MpcCore Library

The `MpcCore` library provides core privacy operations:

- `MpcCore.validateCiphertext(value)` — validates encrypted input
- `MpcCore.offboardToUser(value, address)` — re-encrypts for a specific viewer
- `MpcCore.setPublic(value)` — makes an encrypted value readable by anyone

## Common Pattern: Private Balance

```solidity
mapping(address => itUint64) private _balances;

function transfer(address to, itUint64 calldata encryptedAmount) external {
    MpcCore.validateCiphertext(encryptedAmount);
    // Subtract from sender, add to recipient
    // Store viewer-specific ciphertexts
}
```

## Common Pattern: Private Messaging

```solidity
struct Message {
    address from;
    address to;
    uint256 timestamp;
    itString[] chunks; // encrypted body
}

function sendMessage(address to, itString calldata encrypted) external {
    MpcCore.validateCiphertext(encrypted);
    // Store with sender-readable and recipient-readable copies
}
```

## Common Pattern: Access Control

```solidity
function viewBalance(address account) external view returns (ctUint64) {
    require(msg.sender == account || msg.sender == owner(), "Not authorized");
    return MpcCore.offboardToUser(_balances[account], msg.sender);
}
```

## Chunk Limits

- Each `itString` chunk is capped at 3 COTI string cells
- This corresponds to ~24 bytes of plaintext per chunk
- The SDK handles chunking and reassembly automatically

## Deployment Notes

- Use the `compile_and_deploy_contract` MCP tool for deployment
- Test on COTI testnet before mainnet
- Privacy operations consume more gas than standard EVM operations
- Constructor arguments for encrypted initial values need `encrypt_value` first
