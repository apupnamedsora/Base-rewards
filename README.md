# Base-rewards

Allowlisted crypto rewards claim contract for **Base** (Coinbase L2) — mainnet `8453` and Sepolia `84532`.

Claimers on an owner-managed allowlist can pull a fixed reward of **native ETH** or a **single ERC-20**, subject to a per-address cooldown. The owner must **deposit** funds first. This contract **does not mint** tokens or create free money.

## Features

- Native ETH or one configurable ERC-20 reward asset
- Owner deposits (`depositETH` / `receive`, or `depositERC20`)
- Configurable `rewardAmount` and `cooldown` (seconds)
- Allowlist (single + batch)
- `claim()` with custom errors and events
- Owner: pause/unpause, withdraw, carefully change reward token (balance must be zero)
- OpenZeppelin `Ownable`, `Pausable`, `ReentrancyGuard`, `SafeERC20`
- Checks-Effects-Interactions + non-reentrancy on claim/withdraws

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
| `REWARD_AMOUNT` | Per-claim amount (wei / token units) |
| `COOLDOWN_SECONDS` | Seconds between claims |

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

1. `setAllowlist(claimer, true)` (or `setAllowlistBatch`)
2. Fund: send ETH / call `depositETH`, or `approve` + `depositERC20`
3. Claimers call `claim()` when off cooldown

## Security notes

- **No free money**: rewards only come from deposited balances. If underfunded, `claim` reverts with `InsufficientBalance`.
- **Owner is trusted** for pause, allowlist, amounts, withdrawals, and token changes.
- Changing `rewardToken` requires **zero** current reward balance (withdraw first) to avoid mixed-asset accounting.
- Prefer a hardware wallet / multisig for mainnet ownership.
- Audit before production use; this repo is a starting point, not a formal security review.

## License

MIT
