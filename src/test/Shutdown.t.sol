pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";

contract ShutdownTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_shutdownCanWithdraw(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");
        assertEq(strategy.totalDebt(), _amount, "!totalDebt");
        assertEq(strategy.totalIdle(), 0, "!totalIdle");

        // Earn Interest
        skip(1 days);

        // Shutdown the strategy
        vm.prank(management);
        strategy.shutdownStrategy();

        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");
        assertEq(strategy.totalDebt(), _amount, "!totalDebt");
        assertEq(strategy.totalIdle(), 0, "!totalIdle");

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertApproxEq(
            asset.balanceOf(user),
            balanceBefore + _amount,
            _amount / 1000,
            "!final balance"
        );
    }

    // TODO: Add tests for any emergency function added.
}
