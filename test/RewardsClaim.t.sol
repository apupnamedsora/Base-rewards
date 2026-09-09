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
    address internal recipient = makeAddr("recipient");
    address internal keeper = makeAddr("keeper");
    address internal alice = makeAddr("alice");
    address internal newRecipient = makeAddr("newRecipient");

    uint256 internal constant REWARD = 0.01 ether;
    uint256 internal constant COOLDOWN = 1 days;
    uint256 internal constant TOKEN_REWARD = 100e18;

    event Distributed(address indexed recipient, address indexed token, uint256 amount);
    event Deposited(address indexed from, address indexed token, uint256 amount);
    event Withdrawn(address indexed to, address indexed token, uint256 amount);
    event RecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event RewardAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event CooldownUpdated(uint256 oldCooldown, uint256 newCooldown);
    event RewardTokenUpdated(address indexed oldToken, address indexed newToken);

    function setUp() public {
        token = new MockERC20();

        ethRewards = new RewardsClaim(owner, address(0), REWARD, COOLDOWN, recipient);
        tokenRewards = new RewardsClaim(owner, address(token), TOKEN_REWARD, COOLDOWN, recipient);

        vm.deal(owner, 100 ether);
        vm.deal(keeper, 1 ether);
        vm.deal(alice, 1 ether);
        token.mint(owner, 1_000_000e18);
    }

    // ─── ETH deposit & distribute ──────────────────────────────────────────

    function test_DepositETH_AndDistribute() public {
        vm.prank(owner);
        ethRewards.depositETH{value: 1 ether}();

        uint256 beforeBal = recipient.balance;
        vm.expectEmit(true, true, false, true);
        emit Distributed(recipient, address(0), REWARD);

        vm.prank(keeper);
        ethRewards.distribute();

        assertEq(recipient.balance, beforeBal + REWARD);
        assertEq(ethRewards.lastDistributedAt(), block.timestamp);
        assertEq(ethRewards.rewardBalance(), 1 ether - REWARD);
    }

    function test_AnyoneCanDistribute() public {
        vm.prank(owner);
        ethRewards.depositETH{value: 1 ether}();

        vm.prank(alice);
        ethRewards.distribute();

        assertEq(recipient.balance, REWARD);
        assertEq(ethRewards.lastDistributedAt(), block.timestamp);
    }

    function test_Receive_DepositsETH() public {
        vm.prank(owner);
        (bool ok,) = address(ethRewards).call{value: 0.5 ether}("");
        assertTrue(ok);
        assertEq(ethRewards.rewardBalance(), 0.5 ether);
    }

    function test_Distribute_RevertsOnCooldown() public {
        vm.prank(owner);
        ethRewards.depositETH{value: 1 ether}();

        vm.prank(keeper);
        ethRewards.distribute();

        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(RewardsClaim.CooldownActive.selector, block.timestamp + COOLDOWN)
        );
        ethRewards.distribute();
    }

    function test_Distribute_SucceedsAfterCooldown() public {
        vm.prank(owner);
        ethRewards.depositETH{value: 1 ether}();

        vm.prank(keeper);
        ethRewards.distribute();

        vm.warp(block.timestamp + COOLDOWN);

        vm.prank(alice);
        ethRewards.distribute();

        assertEq(ethRewards.rewardBalance(), 1 ether - 2 * REWARD);
        assertEq(recipient.balance, 2 * REWARD);
    }

    function test_Distribute_AllowsWhenNeverDistributed() public {
        assertEq(ethRewards.lastDistributedAt(), 0);

        vm.prank(owner);
        ethRewards.depositETH{value: 1 ether}();

        vm.prank(keeper);
        ethRewards.distribute();

        assertEq(ethRewards.lastDistributedAt(), block.timestamp);
    }

    function test_Distribute_RevertsWhenUnderfunded() public {
        vm.prank(owner);
        ethRewards.depositETH{value: REWARD - 1}();

        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(
                RewardsClaim.InsufficientBalance.selector, REWARD - 1, REWARD
            )
        );
        ethRewards.distribute();
    }

    function test_Distribute_RevertsWhenPaused() public {
        vm.startPrank(owner);
        ethRewards.depositETH{value: 1 ether}();
        ethRewards.pause();
        vm.stopPrank();

        vm.prank(keeper);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        ethRewards.distribute();
    }

    function test_Unpause_AllowsDistributeAgain() public {
        vm.startPrank(owner);
        ethRewards.depositETH{value: 1 ether}();
        ethRewards.pause();
        ethRewards.unpause();
        vm.stopPrank();

        vm.prank(keeper);
        ethRewards.distribute();
        assertEq(ethRewards.lastDistributedAt(), block.timestamp);
        assertEq(recipient.balance, REWARD);
    }

    // ─── Recipient / config ────────────────────────────────────────────────

    function test_SetRecipient() public {
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit RecipientUpdated(recipient, newRecipient);
        ethRewards.setRecipient(newRecipient);

        assertEq(ethRewards.recipient(), newRecipient);

        vm.prank(owner);
        ethRewards.depositETH{value: 1 ether}();

        vm.prank(keeper);
        ethRewards.distribute();

        assertEq(newRecipient.balance, REWARD);
        assertEq(recipient.balance, 0);
    }

    function test_SetRecipient_RevertsZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(RewardsClaim.ZeroAddress.selector);
        ethRewards.setRecipient(address(0));
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
        ethRewards.setRecipient(newRecipient);
    }

    function test_TimeUntilDistribute() public {
        vm.prank(owner);
        ethRewards.depositETH{value: 1 ether}();

        assertEq(ethRewards.timeUntilDistribute(), 0);

        vm.prank(keeper);
        ethRewards.distribute();

        assertEq(ethRewards.timeUntilDistribute(), COOLDOWN);
        vm.warp(block.timestamp + COOLDOWN / 2);
        assertEq(ethRewards.timeUntilDistribute(), COOLDOWN / 2);
        vm.warp(block.timestamp + COOLDOWN);
        assertEq(ethRewards.timeUntilDistribute(), 0);
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

    function test_DepositERC20_AndDistribute() public {
        vm.startPrank(owner);
        token.approve(address(tokenRewards), 10_000e18);
        tokenRewards.depositERC20(10_000e18);
        vm.stopPrank();

        uint256 before = token.balanceOf(recipient);
        vm.prank(keeper);
        tokenRewards.distribute();

        assertEq(token.balanceOf(recipient), before + TOKEN_REWARD);
        assertEq(tokenRewards.rewardBalance(), 10_000e18 - TOKEN_REWARD);
        assertEq(tokenRewards.lastDistributedAt(), block.timestamp);
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
        new RewardsClaim(owner, address(0), 0, COOLDOWN, recipient);
    }

    function test_Constructor_RevertsOnZeroRecipient() public {
        vm.expectRevert(RewardsClaim.ZeroAddress.selector);
        new RewardsClaim(owner, address(0), REWARD, COOLDOWN, address(0));
    }

    function test_ZeroAmount_DepositReverts() public {
        vm.prank(owner);
        vm.expectRevert(RewardsClaim.ZeroAmount.selector);
        ethRewards.depositETH{value: 0}();
    }

    function test_Constructor_SetsRecipient() public {
        address fixedRecipient = 0x437066CAdcDbAd800DAa83625BcA4eA824718B42;
        RewardsClaim c = new RewardsClaim(owner, address(0), REWARD, COOLDOWN, fixedRecipient);
        assertEq(c.recipient(), fixedRecipient);
        assertEq(c.lastDistributedAt(), 0);
    }

    function testFuzz_DistributeAfterCooldown(uint256 warpExtra) public {
        warpExtra = bound(warpExtra, 0, 365 days);

        vm.prank(owner);
        ethRewards.depositETH{value: 10 ether}();

        vm.prank(keeper);
        ethRewards.distribute();

        vm.warp(block.timestamp + COOLDOWN + warpExtra);

        vm.prank(alice);
        ethRewards.distribute();

        assertEq(ethRewards.lastDistributedAt(), block.timestamp);
        assertEq(recipient.balance, 2 * REWARD);
    }
}
