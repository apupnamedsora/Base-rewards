// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {RewardsClaim} from "../src/RewardsClaim.sol";

/**
 * @notice Deploy RewardsClaim to Base or Base Sepolia.
 *
 * Env:
 *   PRIVATE_KEY      — deployer key
 *   INITIAL_OWNER    — optional; defaults to deployer
 *   REWARD_TOKEN     — address(0) for ETH (default)
 *   REWARD_AMOUNT    — wei / token units (default 0.001 ether)
 *   COOLDOWN_SECONDS — default 86400
 *
 * Examples:
 *   forge script script/Deploy.s.sol:Deploy --rpc-url $BASE_SEPOLIA_RPC_URL --broadcast --verify
 *   forge script script/Deploy.s.sol:Deploy --rpc-url $BASE_RPC_URL --broadcast --verify
 */
contract Deploy is Script {
    function run() external returns (RewardsClaim rewards) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        address initialOwner = vm.envOr("INITIAL_OWNER", deployer);
        address rewardToken = vm.envOr("REWARD_TOKEN", address(0));
        uint256 rewardAmount = vm.envOr("REWARD_AMOUNT", uint256(0.001 ether));
        uint256 cooldown = vm.envOr("COOLDOWN_SECONDS", uint256(1 days));

        console2.log("Deployer:", deployer);
        console2.log("Owner:", initialOwner);
        console2.log("Reward token:", rewardToken);
        console2.log("Reward amount:", rewardAmount);
        console2.log("Cooldown:", cooldown);
        console2.log("Chain id:", block.chainid);

        vm.startBroadcast(pk);
        rewards = new RewardsClaim(initialOwner, rewardToken, rewardAmount, cooldown);
        vm.stopBroadcast();

        console2.log("RewardsClaim deployed at:", address(rewards));
    }
}
