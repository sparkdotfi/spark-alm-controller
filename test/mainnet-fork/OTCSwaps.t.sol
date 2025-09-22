// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "./ForkTestBase.t.sol";

contract MainnetControllerOTCSwapBase is ForkTestBase {

    event OTCBufferSet(
        address indexed exchange,
        address indexed newOTCBuffer,
        address indexed oldOTCBuffer
    );
    event OTCRechargeRateSet(address indexed exchange, uint256 oldRate18, uint256 newRate18);

}

contract MainnetControllerOTCSwapFailureTests is MainnetControllerOTCSwapBase {

    // set otc buffer: admin @ exchange 0 @ exchange == otcbuffer
    // set otcConfigs[ex].buffer @ emit

    // set otc recharge rate: admin @ 
    // set otcConfigs[ex].rechargeRate18 @ emit

    // 3f + 1s + 1f + 1s = 4f + 2s

    // otcSwapSend: non-relayer @ rate-limited

    // otcSwapClaim: 
}

contract MainnetControllerOTCSwapSuccessTests is MainnetControllerOTCSwapBase {

    function test_otcSwap() external {
        uint256 usdsBalContr = usds.balanceOf(address(mainnetController));
        uint256 usdcBalContr = usdc.balanceOf(address(mainnetController));

        // Define swap parameters
        uint256 swapAmount = 1000e18; // 1000 USDS
        address recipient = makeAddr("recipient");

        // Ensure controller has sufficient USDS balance
        deal(address(usds), address(mainnetController), swapAmount);

        // Execute OTC swap (assuming a swap function exists)
        vm.prank(relayer);
        mainnetController.otcSwapSend(address(usds), address(usdc), swapAmount, recipient);

        // Verify balances changed as expected
        assertEq(usds.balanceOf(address(mainnetController)), usdsBalContr);
        assertGt(usdc.balanceOf(recipient), 0);

        // Verify rate limits were properly enforced
        // Add rate limit checks here
    }

}

