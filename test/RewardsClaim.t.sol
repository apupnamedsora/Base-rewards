// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {RewardsClaim} from "../src/RewardsClaim.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Reward", "MRWD") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract RewardsClaimTest is Test {
    RewardsClaim internal ethRewards;
    RewardsClaim internal tokenRewards;
    MockERC20 internal token;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal charlie = makeAddr("charlie");

    uint256 internal constant REWARD = 0.01 ether;
    uint256 internal constant COOLDOWN = 1 days;
    uint256 internal constant TOKEN_REWARD = 100e18;

    event Claimed(address indexed claimer, address indexed token, uint256 amount);
    event Deposited(address indexed from, address indexed token, uint256 amount);
    event Withdrawn(address indexed to, address indexed token, uint256 amount);
    event AllowlistUpdated(address indexed account, bool allowed);
    event RewardAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event CooldownUpdated(uint256 oldCooldown, uint256 newCooldown);
    event RewardTokenUpdated(address indexed oldToken, address indexed newToken);

    function setUp() public {
        token = new MockERC20();

        ethRewards = new RewardsClaim(owner, address(0), REWARD, COOLDOWN);
        tokenRewards = new RewardsClaim(owner, address(token), TOKEN_REWARD, COOLDOWN);

        vm.deal(owner, 100 ether);
        vm.deal(alice, 1 ether);
        token.mint(owner, 1_000_000e18);
    }

    // ─── ETH deposit & claim ───────────────────────────────────────────────

    function test_DepositETH_AndClaim() public {
        vm.prank(owner);
        ethRewards.setAllowlist(alice, true);

        vm.prank(owner);
        ethRewards.depositETH{value: 1 ether}();

        uint256 beforeBal = alice.balance;
        vm.expectEmit(true, true, false, true);
        emit Claimed(alice, address(0), REWARD);

        vm.prank(alice);
        ethRewards.claim();

        assertEq(alice.balance, beforeBal + REWARD);
        assertEq(ethRewards.lastClaimAt(alice), block.timestamp);
        assertEq(ethRewards.rewardBalance(), 1 ether - REWARD);
    }

    function test_Receive_DepositsETH() public {
        vm.prank(owner);
        (bool ok,) = address(ethRewards).call{value: 0.5 ether}("");
        assertTrue(ok);
        assertEq(ethRewards.rewardBalance(), 0.5 ether);
    }

    function test_Claim_RevertsWhenNotAllowlisted() public {
        vm.prank(owner);
        ethRewards.depositETH{value: 1 ether}();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RewardsClaim.NotAllowlisted.selector, alice));
        ethRewards.claim();
    }

    function test_Claim_RevertsOnCooldown() public {
        vm.startPrank(owner);
        ethRewards.setAllowlist(alice, true);
        ethRewards.depositETH{value: 1 ether}();
        vm.stopPrank();

        vm.prank(alice);
        ethRewards.claim();

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                RewardsClaim.CooldownActive.selector, alice, block.timestamp + COOLDOWN
            )
        );
        ethRewards.claim();
    }

    function test_Claim_SucceedsAfterCooldown() public {
        vm.startPrank(owner);
        ethRewards.setAllowlist(alice, true);
        ethRewards.depositETH{value: 1 ether}();
        vm.stopPrank();

        vm.prank(alice);
        ethRewards.claim();

        vm.warp(block.timestamp + COOLDOWN);

        vm.prank(alice);
        ethRewards.claim();

        assertEq(ethRewards.rewardBalance(), 1 ether - 2 * REWARD);
    }

    function test_Claim_RevertsWhenUnderfunded() public {
        vm.prank(owner);
        ethRewards.setAllowlist(alice, true);

        // deposit less than one reward
        vm.prank(owner);
        ethRewards.depositETH{value: REWARD - 1}();

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                RewardsClaim.InsufficientBalance.selector, REWARD - 1, REWARD
            )
        );
        ethRewards.claim();
    }

    function test_Claim_RevertsWhenPaused() public {
        vm.startPrank(owner);
        ethRewards.setAllowlist(alice, true);
        ethRewards.depositETH{value: 1 ether}();
        ethRewards.pause();
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        ethRewards.claim();
    }

    function test_Unpause_AllowsClaimAgain() public {
        vm.startPrank(owner);
        ethRewards.setAllowlist(alice, true);
        ethRewards.depositETH{value: 1 ether}();
        ethRewards.pause();
        ethRewards.unpause();
        vm.stopPrank();

        vm.prank(alice);
        ethRewards.claim();
        assertEq(ethRewards.lastClaimAt(alice), block.timestamp);
    }

    // ─── Allowlist / config ────────────────────────────────────────────────

    function test_SetAllowlistBatch() public {
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;

        vm.prank(owner);
        ethRewards.setAllowlistBatch(accounts, true);

        assertTrue(ethRewards.allowlist(alice));
        assertTrue(ethRewards.allowlist(bob));
        assertFalse(ethRewards.allowlist(charlie));
    }

    function test_SetRewardAmount_AndCooldown() public {
        vm.startPrank(owner);
        vm.expectEmit(false, false, false, true);
        emit RewardAmountUpdated(REWARD, 0.02 ether);
        ethRewards.setRewardAmount(0.02 ether);

        vm.expectEmit(false, false, false, true);
        emit CooldownUpdated(COOLDOWN, 2 hours);
        ethRewards.setCooldown(2 hours);
        vm.stopPrank();

        assertEq(ethRewards.rewardAmount(), 0.02 ether);
        assertEq(ethRewards.cooldown(), 2 hours);
    }

    function test_OnlyOwner_Modifiers() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        ethRewards.setRewardAmount(1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        ethRewards.pause();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        ethRewards.setAllowlist(bob, true);
    }

    function test_TimeUntilClaim() public {
        vm.startPrank(owner);
        ethRewards.setAllowlist(alice, true);
        ethRewards.depositETH{value: 1 ether}();
        vm.stopPrank();

        assertEq(ethRewards.timeUntilClaim(alice), 0);

        vm.prank(alice);
        ethRewards.claim();

        assertEq(ethRewards.timeUntilClaim(alice), COOLDOWN);
        vm.warp(block.timestamp + COOLDOWN / 2);
        assertEq(ethRewards.timeUntilClaim(alice), COOLDOWN / 2);
        vm.warp(block.timestamp + COOLDOWN);
        assertEq(ethRewards.timeUntilClaim(alice), 0);
    }

    // ─── Withdraw ──────────────────────────────────────────────────────────

    function test_WithdrawETH() public {
        vm.prank(owner);
        ethRewards.depositETH{value: 1 ether}();

        uint256 before = owner.balance;
        vm.prank(owner);
        ethRewards.withdrawETH(payable(owner), 0.4 ether);
        assertEq(owner.balance, before + 0.4 ether);
        assertEq(address(ethRewards).balance, 0.6 ether);
    }

    function test_WithdrawETH_RevertsUnauthorized() public {
        vm.prank(owner);
        ethRewards.depositETH{value: 1 ether}();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        ethRewards.withdrawETH(payable(alice), 0.1 ether);
    }

    // ─── ERC-20 path ───────────────────────────────────────────────────────

    function test_DepositERC20_AndClaim() public {
        vm.startPrank(owner);
        tokenRewards.setAllowlist(alice, true);
        token.approve(address(tokenRewards), 10_000e18);
        tokenRewards.depositERC20(10_000e18);
        vm.stopPrank();

        uint256 before = token.balanceOf(alice);
        vm.prank(alice);
        tokenRewards.claim();

        assertEq(token.balanceOf(alice), before + TOKEN_REWARD);
        assertEq(tokenRewards.rewardBalance(), 10_000e18 - TOKEN_REWARD);
    }

    function test_DepositETH_RevertsWhenConfiguredForERC20() public {
        vm.prank(owner);
        vm.expectRevert(RewardsClaim.NativeDepositWhenErc20.selector);
        tokenRewards.depositETH{value: 1 ether}();
    }

    function test_DepositERC20_RevertsWhenConfiguredForETH() public {
        vm.startPrank(owner);
        token.approve(address(ethRewards), 100e18);
        vm.expectRevert(RewardsClaim.Erc20DepositWhenNative.selector);
        ethRewards.depositERC20(100e18);
        vm.stopPrank();
    }

    function test_WithdrawERC20() public {
        vm.startPrank(owner);
        token.approve(address(tokenRewards), 500e18);
        tokenRewards.depositERC20(500e18);
        tokenRewards.withdrawERC20(address(token), owner, 200e18);
        vm.stopPrank();

        assertEq(token.balanceOf(address(tokenRewards)), 300e18);
    }

    function test_SetRewardToken_RequiresZeroBalance() public {
        vm.prank(owner);
        ethRewards.depositETH{value: 1 ether}();

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(RewardsClaim.RewardBalanceNonZero.selector, 1 ether)
        );
        ethRewards.setRewardToken(address(token));

        vm.prank(owner);
        ethRewards.withdrawETH(payable(owner), 1 ether);

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit RewardTokenUpdated(address(0), address(token));
        ethRewards.setRewardToken(address(token));

        assertEq(ethRewards.rewardToken(), address(token));
    }

    function test_Constructor_RevertsOnZeroReward() public {
        vm.expectRevert(RewardsClaim.ZeroAmount.selector);
        new RewardsClaim(owner, address(0), 0, COOLDOWN);
    }

    function test_ZeroAmount_DepositReverts() public {
        vm.prank(owner);
        vm.expectRevert(RewardsClaim.ZeroAmount.selector);
        ethRewards.depositETH{value: 0}();
    }

    function testFuzz_ClaimAfterCooldown(uint256 warpExtra) public {
        warpExtra = bound(warpExtra, 0, 365 days);

        vm.startPrank(owner);
        ethRewards.setAllowlist(alice, true);
        ethRewards.depositETH{value: 10 ether}();
        vm.stopPrank();

        vm.prank(alice);
        ethRewards.claim();

        vm.warp(block.timestamp + COOLDOWN + warpExtra);

        vm.prank(alice);
        ethRewards.claim();

        assertEq(ethRewards.lastClaimAt(alice), block.timestamp);
    }
}
