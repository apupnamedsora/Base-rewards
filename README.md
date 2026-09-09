# Base-rewards

Permissionless reward distribution contract for **Base** (Coinbase L2) — mainnet `8453` and Sepolia `84532`.

A fixed `rewardAmount` of **native ETH** or a **single ERC-20** is pushed to a configured `recipient` wallet via `distribute()`, subject to a global cooldown. The owner must **deposit** funds first. This contract **does not mint** tokens or create free money.

Anyone (a keeper, cron job, or any EOA) can call `distribute()` when the cooldown has elapsed and the contract is funded. The contract itself cannot self-cron — an external caller is required.

## Features

- Native ETH or one configurable ERC-20 reward asset
- Owner deposits (`depositETH` / `receive`, or `depositERC20`)
- Fixed `recipient` (constructor arg; owner can `setRecipient`)
- Configurable `rewardAmount` and `cooldown` (seconds)
- Permissionless `distribute()` — pushes `rewardAmount` to `recipient`
- `lastDistributedAt` / `timeUntilDistribute()` for keeper scheduling
- Owner: pause/unpause, withdraw, carefully change reward token (balance must be zero)
- OpenZeppelin `Ownable`, `Pausable`, `ReentrancyGuard`, `SafeERC20`
- Checks-Effects-Interactions + non-reentrancy on distribute/withdraws

## Project layout

```
src/RewardsClaim.sol      # Main contract
test/RewardsClaim.t.sol   # Forge tests
script/Deploy.s.sol       # Deploy to Base / Base Sepolia
lib/                      # forge-std + OpenZeppelin (git submodules)
foundry.toml
remappings.txt
.env.example
```

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge`, `cast`, `anvil`)
- Submodules: `git submodule update --init --recursive`

## Build & test

```bash
forge build
forge test
forge test -vvv   # verbose
```

## Configuration

Copy `.env.example` → `.env` (never commit `.env`):

| Variable | Purpose |
|----------|---------|
| `PRIVATE_KEY` | Deployer key (local/CI only; **no real keys in git**) |
| `BASE_RPC_URL` | Base mainnet RPC |
| `BASE_SEPOLIA_RPC_URL` | Base Sepolia RPC |
| `BASESCAN_API_KEY` | Optional verification |
| `INITIAL_OWNER` | Owner address (default: deployer) |
| `REWARD_TOKEN` | `address(0)` = ETH, else ERC-20 |
| `REWARD_AMOUNT` | Per-distribution amount (wei / token units) |
| `COOLDOWN_SECONDS` | Seconds between distributions |
| `RECIPIENT` | Fixed payout wallet (default `0x437066CAdcDbAd800DAa83625BcA4eA824718B42`) |

## Deploy

**Base Sepolia**

```bash
source .env
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --broadcast \
  --verify \
  -vvvv
```

**Base mainnet**

```bash
source .env
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $BASE_RPC_URL \
  --broadcast \
  --verify \
  -vvvv
```

After deploy, as owner:

1. Fund: send ETH / call `depositETH`, or `approve` + `depositERC20`
2. Optionally adjust `setRewardAmount`, `setCooldown`, or `setRecipient`
3. When due, anyone (keeper/cron/EOA) calls `distribute()` to push `rewardAmount` to `recipient`

## How distribute works

- `lastDistributedAt == 0` (never distributed) → first call is allowed immediately (if funded).
- After a successful distribution, callers must wait `cooldown` seconds.
- If the contract balance is below `rewardAmount`, `distribute` reverts with `InsufficientBalance`.
- Emits `Distributed(recipient, token, amount)`.

## Security notes

- **No free money**: rewards only come from deposited balances. If underfunded, `distribute` reverts with `InsufficientBalance`.
- **Owner is trusted** for pause, recipient, amounts, withdrawals, and token changes.
- Changing `rewardToken` requires **zero** current reward balance (withdraw first) to avoid mixed-asset accounting.
- Prefer a hardware wallet / multisig for mainnet ownership.
- Audit before production use; this repo is a starting point, not a formal security review.

## License

MIT
