// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title RewardsClaim
 * @notice Allowlisted claimers can claim a fixed reward of native ETH or a single ERC-20
 *         on a cooldown. The owner must deposit funds; the contract never mints rewards.
 * @dev Compatible with Base mainnet (8453) and Base Sepolia (84532).
 */
contract RewardsClaim is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice address(0) means native ETH rewards; otherwise the ERC-20 reward token.
    address public rewardToken;

    /// @notice Amount paid per successful claim (wei for ETH, token decimals for ERC-20).
    uint256 public rewardAmount;

    /// @notice Minimum seconds between claims for the same address.
    uint256 public cooldown;

    /// @notice Allowlisted claimers.
    mapping(address => bool) public allowlist;

    /// @notice Timestamp of each account's last successful claim (0 if never claimed).
    mapping(address => uint256) public lastClaimAt;

    error NotAllowlisted(address account);
    error CooldownActive(address account, uint256 readyAt);
    error InsufficientBalance(uint256 available, uint256 required);
    error ZeroAmount();
    error ZeroAddress();
    error RewardBalanceNonZero(uint256 balance);
    error EthTransferFailed();
    error NativeDepositWhenErc20();
    error Erc20DepositWhenNative();

    event Claimed(address indexed claimer, address indexed token, uint256 amount);
    event Deposited(address indexed from, address indexed token, uint256 amount);
    event Withdrawn(address indexed to, address indexed token, uint256 amount);
    event AllowlistUpdated(address indexed account, bool allowed);
    event RewardAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event CooldownUpdated(uint256 oldCooldown, uint256 newCooldown);
    event RewardTokenUpdated(address indexed oldToken, address indexed newToken);

    /**
     * @param initialOwner Contract owner (deployer typically).
     * @param rewardToken_ address(0) for ETH, else ERC-20.
     * @param rewardAmount_ Per-claim payout.
     * @param cooldown_ Seconds between claims per address.
     */
    constructor(
        address initialOwner,
        address rewardToken_,
        uint256 rewardAmount_,
        uint256 cooldown_
    ) Ownable(initialOwner) {
        if (rewardAmount_ == 0) revert ZeroAmount();
        rewardToken = rewardToken_;
        rewardAmount = rewardAmount_;
        cooldown = cooldown_;
    }

    /// @notice Accept native ETH deposits when the reward asset is ETH.
    receive() external payable {
        if (rewardToken != address(0)) revert NativeDepositWhenErc20();
        if (msg.value == 0) revert ZeroAmount();
        emit Deposited(msg.sender, address(0), msg.value);
    }

    /// @notice Explicit ETH deposit (same rules as `receive`).
    function depositETH() external payable whenNotPaused {
        if (rewardToken != address(0)) revert NativeDepositWhenErc20();
        if (msg.value == 0) revert ZeroAmount();
        emit Deposited(msg.sender, address(0), msg.value);
    }

    /**
     * @notice Deposit ERC-20 reward tokens. Caller must `approve` this contract first.
     * @param amount Token amount to transfer in.
     */
    function depositERC20(uint256 amount) external whenNotPaused {
        if (rewardToken == address(0)) revert Erc20DepositWhenNative();
        if (amount == 0) revert ZeroAmount();
        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(msg.sender, rewardToken, amount);
    }

    /**
     * @notice Claim one reward unit if allowlisted, funded, and off cooldown.
     * @dev Checks → Effects → Interactions; non-reentrant.
     */
    function claim() external nonReentrant whenNotPaused {
        if (!allowlist[msg.sender]) revert NotAllowlisted(msg.sender);

        uint256 last = lastClaimAt[msg.sender];
        if (last != 0 && block.timestamp < last + cooldown) {
            revert CooldownActive(msg.sender, last + cooldown);
        }

        uint256 amount = rewardAmount;
        uint256 bal = _rewardBalance();
        if (bal < amount) revert InsufficientBalance(bal, amount);

        // Effects
        lastClaimAt[msg.sender] = block.timestamp;
        address token = rewardToken;
        emit Claimed(msg.sender, token, amount);

        // Interactions
        if (token == address(0)) {
            (bool ok,) = msg.sender.call{value: amount}("");
            if (!ok) revert EthTransferFailed();
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }
    }

    // ─── Owner configuration ───────────────────────────────────────────────

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setRewardAmount(uint256 newAmount) external onlyOwner {
        if (newAmount == 0) revert ZeroAmount();
        uint256 old = rewardAmount;
        rewardAmount = newAmount;
        emit RewardAmountUpdated(old, newAmount);
    }

    function setCooldown(uint256 newCooldown) external onlyOwner {
        uint256 old = cooldown;
        cooldown = newCooldown;
        emit CooldownUpdated(old, newCooldown);
    }

    function setAllowlist(address account, bool allowed) external onlyOwner {
        if (account == address(0)) revert ZeroAddress();
        allowlist[account] = allowed;
        emit AllowlistUpdated(account, allowed);
    }

    function setAllowlistBatch(address[] calldata accounts, bool allowed) external onlyOwner {
        uint256 len = accounts.length;
        for (uint256 i = 0; i < len; ++i) {
            address account = accounts[i];
            if (account == address(0)) revert ZeroAddress();
            allowlist[account] = allowed;
            emit AllowlistUpdated(account, allowed);
        }
    }

    /**
     * @notice Change reward token. Current reward balance must be zero first
     *         (withdraw remaining funds), so claims cannot mix assets mid-stream.
     * @param newToken address(0) for ETH, else ERC-20.
     */
    function setRewardToken(address newToken) external onlyOwner {
        uint256 bal = _rewardBalance();
        if (bal != 0) revert RewardBalanceNonZero(bal);
        address old = rewardToken;
        rewardToken = newToken;
        emit RewardTokenUpdated(old, newToken);
    }

    function withdrawETH(address payable to, uint256 amount) external nonReentrant onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        uint256 bal = address(this).balance;
        if (bal < amount) revert InsufficientBalance(bal, amount);
        emit Withdrawn(to, address(0), amount);
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert EthTransferFailed();
    }

    function withdrawERC20(address token, address to, uint256 amount)
        external
        nonReentrant
        onlyOwner
    {
        if (to == address(0) || token == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        uint256 bal = IERC20(token).balanceOf(address(this));
        if (bal < amount) revert InsufficientBalance(bal, amount);
        emit Withdrawn(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    // ─── Views ─────────────────────────────────────────────────────────────

    function rewardBalance() external view returns (uint256) {
        return _rewardBalance();
    }

    function timeUntilClaim(address account) external view returns (uint256) {
        uint256 last = lastClaimAt[account];
        if (last == 0) return 0;
        uint256 readyAt = last + cooldown;
        if (block.timestamp >= readyAt) return 0;
        return readyAt - block.timestamp;
    }

    function _rewardBalance() internal view returns (uint256) {
        if (rewardToken == address(0)) {
            return address(this).balance;
        }
        return IERC20(rewardToken).balanceOf(address(this));
    }
}
