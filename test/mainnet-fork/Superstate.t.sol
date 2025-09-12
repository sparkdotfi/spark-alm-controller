// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "./ForkTestBase.t.sol";

interface IAllowlistV2Like {
    function owner() external view returns (address);
    function setEntityIdForAddress(uint256 entityId, address account) external;
    function setEntityAllowedForFund(uint256 entityId, string memory fundSymbol, bool isAllowed) external;
}

interface ISSRedemptionLike {
    function calculateUsdcOut(uint256 ustbAmount) external view returns (uint256 usdcOutAmount, uint256 usdPerUstbChainlinkRaw);
    function calculateUstbIn(uint256 usdcOutAmount) external view returns (uint256 ustbInAmount, uint256 usdPerUstbChainlinkRaw);
}

contract SuperstateTestBase is ForkTestBase {

    IAllowlistV2Like allowlist = IAllowlistV2Like(0x02f1fA8B196d21c7b733EB2700B825611d8A38E5);

    function _getBlock() internal pure override returns (uint256) {
        return 21570000;  // Jan 7, 2024
    }

}

contract MainnetControllerSubscribeSuperstateFailureTests is SuperstateTestBase {

    function test_subscribeSuperstate_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.subscribeSuperstate(1_000_000e6);
    }

    function test_subscribeSuperstate_zeroMaxAmount() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainnetController.LIMIT_SUPERSTATE_SUBSCRIBE(), 0, 0);
        vm.stopPrank();

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.subscribeSuperstate(1_000_000e6);
    }

    function test_subscribeSuperstate_rateLimitBoundary() external {
        deal(address(usdc), address(almProxy), 5_000_000e6);

        bytes32 key = mainnetController.LIMIT_SUPERSTATE_SUBSCRIBE();

        vm.startPrank(allowlist.owner());
        allowlist.setEntityIdForAddress(1, address(almProxy));
        allowlist.setEntityAllowedForFund(1, "USTB", true);
        vm.stopPrank();

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.subscribeSuperstate(1_000_000e6 + 1);

        mainnetController.subscribeSuperstate(1_000_000e6);
    }

}

contract MainnetControllerSubscribeSuperstateSuccessTests is SuperstateTestBase {

    address sweepDestination;

    bytes32 key;

    function setUp() public override {
        super.setUp();

        ( sweepDestination, ) = ustb.supportedStablecoins(address(usdc));

        vm.startPrank(allowlist.owner());
        allowlist.setEntityIdForAddress(1, address(almProxy));
        allowlist.setEntityAllowedForFund(1, "USTB", true);
        vm.stopPrank();

        key = mainnetController.LIMIT_SUPERSTATE_SUBSCRIBE();

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 1_000_000e6, uint256(1_000_000e6) / 1 days);
    }

    function test_subscribeSuperstate() external {
        deal(address(usdc), address(almProxy), 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_000_000e6);

        assertEq(usdc.allowance(address(almProxy), address(ustb)), 0);

        assertEq(usdc.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(usdc.balanceOf(sweepDestination),  0);

        assertEq(ustb.balanceOf(address(almProxy)), 0);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_000_000e6);

        uint256 totalSupply = ustb.totalSupply();

        ( uint256 expectedUstb, uint256 stablecoinInAmountAfterFee, uint256 feeOnStablecoinInAmount )
            = ustb.calculateSuperstateTokenOut(1_000_000e6, address(usdc));

        assertEq(expectedUstb,               95_027.920628e6);
        assertEq(stablecoinInAmountAfterFee, 1_000_000e6);
        assertEq(feeOnStablecoinInAmount,    0);

        vm.prank(relayer);
        mainnetController.subscribeSuperstate(1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        assertEq(usdc.allowance(address(almProxy), sweepDestination), 0);

        assertEq(usdc.balanceOf(address(almProxy)), 0);
        assertEq(usdc.balanceOf(sweepDestination),  1_000_000e6);

        assertEq(ustb.balanceOf(address(almProxy)), expectedUstb);
        assertEq(ustb.totalSupply(),                totalSupply + expectedUstb);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);
    }

}

contract MainnetControllerSuperstateE2ETests is SuperstateTestBase {

    address usccDepositAddress = makeAddr("usccDepositAddress");

    function setUp() public override {
        super.setUp();

        vm.startPrank(Ethereum.SPARK_PROXY);

        // Rate limit to transfer USDC to USCC deposit addressx to mint USCC
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAssetDestinationKey(
                mainnetController.LIMIT_ASSET_TRANSFER(),
                address(usdc),
                address(usccDepositAddress)
            ),
            1_000_000e6,
            uint256(1_000_000e6) / 1 days
        );

        // Rate limit to transfer USCC to USCC to burn USCC for USDC
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAssetDestinationKey(
                mainnetController.LIMIT_ASSET_TRANSFER(),
                address(uscc),
                address(uscc)
            ),
            1_000_000e6,
            uint256(1_000_000e6) / 1 days
        );

        vm.stopPrank();

        // Allowlist for USCC to be transferred to almProxy
        vm.startPrank(allowlist.owner());
        allowlist.setEntityIdForAddress(1, address(almProxy));
        allowlist.setEntityAllowedForFund(1, "USCC", true);
        vm.stopPrank();
    }

    function test_e2e_superstateUSCCFullFlow() external {
        deal(address(usdc), address(almProxy), 1_000_000e6);

        assertEq(usdc.balanceOf(address(almProxy)),  1_000_000e6);
        assertEq(usdc.balanceOf(usccDepositAddress), 0);

        // Step 1: Transfer USDC to USCC deposit address to trigger minting USCC

        vm.prank(relayer);
        mainnetController.transferAsset(address(usdc), address(usccDepositAddress), 1_000_000e6);

        assertEq(usdc.balanceOf(address(almProxy)),  0);
        assertEq(usdc.balanceOf(usccDepositAddress), 1_000_000e6);

        assertEq(uscc.balanceOf(address(almProxy)), 0);

        uint256 totalSupply = uscc.totalSupply();

        // Step 2: Superstate owner mints USCC to the ALM Proxy

        // Mint hardcoded amount because conversions don't work yet
        vm.prank(uscc.owner());
        uscc.mint(address(almProxy), 900_000e6);

        assertEq(uscc.balanceOf(address(almProxy)), 900_000e6);
        assertEq(uscc.balanceOf(address(uscc)),     0);
        assertEq(uscc.totalSupply(),                totalSupply + 900_000e6);

        // Step 3: Transfer USCC to USCC to trigger burning USCC for USDC

        vm.prank(relayer);
        mainnetController.transferAsset(address(uscc), address(uscc), 900_000e6);

        assertEq(uscc.balanceOf(address(almProxy)), 0);
        assertEq(uscc.balanceOf(address(uscc)),     0);
        assertEq(uscc.totalSupply(),                totalSupply);  // USCC is burned on transfer

        // Step 4: Superstate owner transfers USDC to the ALM Proxy, returning to starting state

        vm.prank(usccDepositAddress);
        usdc.transfer(address(almProxy), 1_000_000e6);

        assertEq(usdc.balanceOf(address(almProxy)),  1_000_000e6);
        assertEq(usdc.balanceOf(usccDepositAddress), 0);
    }

}
