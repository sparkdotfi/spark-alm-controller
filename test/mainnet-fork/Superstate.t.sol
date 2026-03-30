// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { makeAddressAddressKey } from "../../src/libraries/RateLimitHelpers.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IAllowlistV2Like {

    function owner() external view returns (address);

    function setEntityIdForAddress(uint256 entityId, address account) external;

    function setEntityAllowedForFund(uint256 entityId, string memory fundSymbol, bool isAllowed) external;

}

interface IERC20Like {

    function transfer(address to, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

}

interface ISSTokenLike is IERC20Like {

    function calculateSuperstateTokenOut(uint256 amountIn, address stablecoin)
        external
        view
        returns (
            uint256 superstateTokenOutAmount,
            uint256 stablecoinInAmountAfterFee,
            uint256 feeOnStablecoinInAmount
        );

    function mint(address to, uint256 amount) external;

    function burn(address src, uint256 amount) external;

    function owner() external view returns (address);

    function supportedStablecoins(address stablecoin)
        external
        view
        returns (address sweepDestination, uint256 fee);

}

abstract contract Superstate_TestBase is ForkTestBase {

    IAllowlistV2Like internal constant ALLOWLIST = IAllowlistV2Like(0x02f1fA8B196d21c7b733EB2700B825611d8A38E5);

    IERC20Like   internal constant USDC = IERC20Like(Ethereum.USDC);
    ISSTokenLike internal constant USCC = ISSTokenLike(Ethereum.USCC);
    ISSTokenLike internal constant USTB = ISSTokenLike(Ethereum.USTB);

    bytes32 internal constant KEY = keccak256("LIMIT_SUPERSTATE_SUBSCRIBE");

    address internal sweepDestination;

    function setUp() public virtual override {
        super.setUp();

        ( sweepDestination, ) = USTB.supportedStablecoins(Ethereum.USDC);

        // Allowlist for USCC to be transferred to almProxy.
        vm.startPrank(ALLOWLIST.owner());
        ALLOWLIST.setEntityIdForAddress(1, address(almProxy));
        ALLOWLIST.setEntityAllowedForFund(1, "USTB", true);
        vm.stopPrank();

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(KEY, 1_000_000e6, uint256(1_000_000e6) / 1 days);
    }

    function _getBlock() internal pure override returns (uint256) {
        return 21570000;  // Jan 7, 2024
    }

}

contract MainnetController_Superstate_Subscribe_Tests is Superstate_TestBase {

    function test_subscribeSuperstate_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.subscribeSuperstate(1_000_000e6);
    }

    function test_subscribeSuperstate_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER_ROLE
        ));
        mainnetController.subscribeSuperstate(1_000_000e6);
    }

    function test_subscribeSuperstate_zeroMaxAmount() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(KEY, 0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(relayer);
        mainnetController.subscribeSuperstate(1_000_000e6);
    }

    function test_subscribeSuperstate_rateLimitBoundary() external {
        deal(Ethereum.USDC, address(almProxy), 5_000_000e6);

        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(KEY, 1_000_000e6, uint256(1_000_000e6) / 1 days);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(relayer);
        mainnetController.subscribeSuperstate(1_000_000e6 + 1);

        vm.prank(relayer);
        mainnetController.subscribeSuperstate(1_000_000e6);
    }

    function test_subscribeSuperstate() external {
        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(KEY), 1_000_000e6);

        assertEq(USDC.allowance(address(almProxy), Ethereum.USTB), 0);

        assertEq(USDC.balanceOf(address(almProxy)), 1_000_000e6);
        assertEq(USDC.balanceOf(sweepDestination),  0);

        assertEq(USTB.balanceOf(address(almProxy)), 0);

        assertEq(rateLimits.getCurrentRateLimit(KEY), 1_000_000e6);

        uint256 totalSupply = USTB.totalSupply();

        (
            uint256 expectedUSTB,
            uint256 stablecoinInAmountAfterFee,
            uint256 feeOnStablecoinInAmount
        ) = USTB.calculateSuperstateTokenOut(1_000_000e6, Ethereum.USDC);

        assertEq(expectedUSTB,               95_027.920628e6);
        assertEq(stablecoinInAmountAfterFee, 1_000_000e6);
        assertEq(feeOnStablecoinInAmount,    0);

        vm.record();

        vm.prank(relayer);
        mainnetController.subscribeSuperstate(1_000_000e6);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(rateLimits.getCurrentRateLimit(KEY), 0);

        assertEq(USDC.allowance(address(almProxy), sweepDestination), 0);

        assertEq(USDC.balanceOf(address(almProxy)), 0);
        assertEq(USDC.balanceOf(sweepDestination),  1_000_000e6);

        assertEq(USTB.balanceOf(address(almProxy)), expectedUSTB);
        assertEq(USTB.totalSupply(),                totalSupply + expectedUSTB);

        assertEq(rateLimits.getCurrentRateLimit(KEY), 0);
    }

}

contract MainnetController_Superstate_E2ETests is Superstate_TestBase {

    address internal usccDepositAddress = makeAddr("usccDepositAddress");

    function setUp() public override {
        super.setUp();

        vm.startPrank(Ethereum.SPARK_PROXY);

        // Rate limit to transfer USDC to USCC deposit addressx to mint USCC
        rateLimits.setRateLimitData(
            makeAddressAddressKey(
                mainnetController.LIMIT_ASSET_TRANSFER(),
                Ethereum.USDC,
                address(usccDepositAddress)
            ),
            1_000_000e6,
            uint256(1_000_000e6) / 1 days
        );

        // Rate limit to transfer USCC to USCC to burn USCC for USDC
        rateLimits.setRateLimitData(
            makeAddressAddressKey(
                mainnetController.LIMIT_ASSET_TRANSFER(),
                Ethereum.USCC,
                Ethereum.USCC
            ),
            1_000_000e6,
            uint256(1_000_000e6) / 1 days
        );

        vm.stopPrank();
    }

    function test_e2e_superstateUSCCFullFlow() external {
        deal(Ethereum.USDC, address(almProxy), 1_000_000e6);

        assertEq(USDC.balanceOf(address(almProxy)),  1_000_000e6);
        assertEq(USDC.balanceOf(usccDepositAddress), 0);

        // Step 1: Transfer USDC to USCC deposit address to trigger minting USCC

        vm.prank(relayer);
        mainnetController.transferAsset(Ethereum.USDC, address(usccDepositAddress), 1_000_000e6);

        assertEq(USDC.balanceOf(address(almProxy)),  0);
        assertEq(USDC.balanceOf(usccDepositAddress), 1_000_000e6);

        assertEq(USCC.balanceOf(address(almProxy)), 0);

        uint256 totalSupply = USCC.totalSupply();

        // Step 2: Superstate owner mints USCC to the ALM Proxy

        // Mint hardcoded amount because conversions don't work yet
        vm.prank(USCC.owner());
        USCC.mint(address(almProxy), 900_000e6);

        assertEq(USCC.balanceOf(address(almProxy)), 900_000e6);
        assertEq(USCC.balanceOf(Ethereum.USCC),     0);
        assertEq(USCC.totalSupply(),                totalSupply + 900_000e6);

        // Step 3: Transfer USCC to USCC to trigger burning USCC for USDC

        vm.prank(relayer);
        mainnetController.transferAsset(Ethereum.USCC, Ethereum.USCC, 900_000e6);

        assertEq(USCC.balanceOf(address(almProxy)), 0);
        assertEq(USCC.balanceOf(Ethereum.USCC),     0);
        assertEq(USCC.totalSupply(),                totalSupply);  // USCC is burned on transfer

        // Step 4: Superstate owner transfers USDC to the ALM Proxy, returning to starting state

        vm.prank(usccDepositAddress);
        USDC.transfer(address(almProxy), 1_000_000e6);

        assertEq(USDC.balanceOf(address(almProxy)),  1_000_000e6);
        assertEq(USDC.balanceOf(usccDepositAddress), 0);
    }

}
