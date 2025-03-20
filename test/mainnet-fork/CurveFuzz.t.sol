// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { IERC4626 } from "lib/forge-std/src/interfaces/IERC4626.sol";

import "./ForkTestBase.t.sol";

import { ICurvePoolLike } from "../../src/MainnetController.sol";

interface ICurvePool is IERC20, ICurvePoolLike {
    function balances(uint256 index) external view returns (uint256);
}

contract ControllerHandler is Test {

    address immutable almProxy;
    address immutable relayer;

    IERC20 immutable asset1;
    IERC20 immutable asset2;

    ICurvePool        immutable pool;
    MainnetController immutable controller;

    uint256 immutable asset1Precision;
    uint256 immutable asset2Precision;

    uint256 public totalValueDeposited;
    uint256 public totalValueWithdrawn;

    constructor(
        address almProxy_,
        address controller_,
        address pool_,
        address relayer_,
        address asset1_,
        address asset2_
    ) {
        almProxy = almProxy_;
        relayer  = relayer_;

        asset1 = IERC20(asset1_);
        asset2 = IERC20(asset2_);

        asset1Precision = 10 ** asset1.decimals();
        asset2Precision = 10 ** asset2.decimals();

        pool       = ICurvePool(pool_);
        controller = MainnetController(controller_);
    }

    function addLiquidity(uint256 asset1Amount, uint256 asset2Amount) public {
        // Using a higher lower bound to have reasonable and practical precision calculations
        asset1Amount = _bound(asset1Amount, 1 * asset1Precision, 100_000_000 * asset1Precision);
        asset2Amount = _bound(asset2Amount, 1 * asset2Precision, 100_000_000 * asset2Precision);

        deal(address(asset1), almProxy, asset1Amount);
        deal(address(asset2), almProxy, asset2Amount);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = asset1Amount;
        amounts[1] = asset2Amount;

        uint256[] memory rates = pool.stored_rates();

        uint256 totalDeposit = (asset1Amount * rates[0] + asset2Amount * rates[1]) / 1e18;

        totalValueDeposited += totalDeposit;

        uint256 minLpAmount = totalDeposit
            * (controller.maxSlippages(address(pool)) + 0.0001e18)
            / pool.get_virtual_price();

        vm.prank(relayer);
        controller.addLiquidityCurve(address(pool), amounts, minLpAmount);

        uint256 lpValue = pool.balanceOf(address(almProxy)) * pool.get_virtual_price() / 1e18;

        console.log("\n--- Deposit");
        console.log("asset1Amount", asset1Amount * 1e12);
        console.log("asset2Amount", asset2Amount);
        console.log("lpValue     ", lpValue);
        console.log("totalDeposit", totalDeposit);
    }

    function removeLiquidity(uint256 lpAmount) public {
        // Using a higher lower bound to have reasonable and practical precision calculations
        if (pool.balanceOf(almProxy) < 0.5e18) return;

        lpAmount = _bound(lpAmount, 0.5e18, pool.balanceOf(almProxy));

        uint256 lpValue = lpAmount * pool.get_virtual_price() / 1e18;


        uint256 claimableAsset1 = pool.balances(0) * lpAmount / pool.totalSupply();
        uint256 claimableAsset2 = pool.balances(1) * lpAmount / pool.totalSupply();

        uint256[] memory minAmounts = new uint256[](2);
        minAmounts[0] = claimableAsset1;
        minAmounts[1] = claimableAsset2;

        vm.prank(relayer);
        uint256[] memory amounts = controller.removeLiquidityCurve(address(pool), lpAmount, minAmounts);

        uint256[] memory rates = pool.stored_rates();

        uint256 totalWithdraw = (amounts[0] * rates[0] + amounts[1] * rates[1]) / 1e18;

        totalValueWithdrawn += totalWithdraw;

        console.log("\n--- Withdraw");
        console.log("claimableAsset1", claimableAsset1 * 1e12);
        console.log("claimableAsset2", claimableAsset2);
        console.log("lpBurned       ", lpValue);
        console.log("totalWithdraw  ", totalWithdraw);
    }

}

contract CurveFuzzTestsBase is ForkTestBase {

    address constant RLUSD      = 0x8292Bb45bf1Ee4d140127049757C2E0fF06317eD;
    address constant CURVE_POOL = 0xD001aE433f254283FeCE51d4ACcE8c53263aa186;

    IERC20 rlUsd = IERC20(RLUSD);

    ICurvePool curvePool = ICurvePool(CURVE_POOL);

    ControllerHandler handler;

    function setUp() public virtual override  {
        super.setUp();

        bytes32 curveDepositKey  = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_DEPOSIT(),  CURVE_POOL);
        bytes32 curveSwapKey     = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_SWAP(),     CURVE_POOL);
        bytes32 curveWithdrawKey = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_WITHDRAW(), CURVE_POOL);

        vm.startPrank(SPARK_PROXY);
        rateLimits.setUnlimitedRateLimitData(curveDepositKey);
        rateLimits.setUnlimitedRateLimitData(curveSwapKey);
        rateLimits.setUnlimitedRateLimitData(curveWithdrawKey);
        vm.stopPrank();

        // Set a higher slippage to allow for successes
        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(CURVE_POOL, 0.99e18);

        handler = new ControllerHandler(
            address(almProxy),
            address(mainnetController),
            CURVE_POOL,
            relayer,
            address(usdc),
            RLUSD
        );

        targetContract(address(handler));
    }

    function _getBlock() internal pure override returns (uint256) {
        return 22000000;  // March 8, 2025
    }

    function statefulFuzz_curve_test() public {
        uint256 lpValue = curvePool.balanceOf(address(almProxy)) * curvePool.get_virtual_price() / 1e18;

        console.log("\n--- Test");

        console.log("lpValue ", lpValue);
        console.log("deposit ", handler.totalValueDeposited());
        console.log("withdraw", handler.totalValueWithdrawn());

        assertGe(lpValue, (handler.totalValueDeposited() - handler.totalValueWithdrawn()) * 99/100);
    }

}


