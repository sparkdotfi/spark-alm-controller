// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { IERC4626 } from "lib/forge-std/src/interfaces/IERC4626.sol";

import "./ForkTestBase.t.sol";

import { ICurvePoolLike } from "../../src/MainnetController.sol";

contract ControllerHandler is Test {

    address immutable almProxy;
    address immutable relayer;

    IERC20 immutable token1;
    IERC20 immutable token2;

    ICurvePoolLike    immutable pool;
    MainnetController immutable controller;

    uint256 immutable token1Precision;
    uint256 immutable token2Precision;

    constructor(
        address almProxy_,
        address controller_,
        address pool_,
        address relayer_,
        address token1_,
        address token2_
    ) {
        almProxy = almProxy_;
        relayer  = relayer_;

        token1 = IERC20(token1_);
        token2 = IERC20(token2_);

        token1Precision = 10 ** token1.decimals();
        token2Precision = 10 ** token2.decimals();

        pool       = ICurvePoolLike(pool_);
        controller = MainnetController(controller_);
    }

    function addLiquidity(uint256 token1Amount, uint256 token2Amount) public {
        token1Amount = _bound(token1Amount, 0, 100_000_000 * token1Precision);
        token2Amount = _bound(token2Amount, 0, 100_000_000 * token1Precision);

        deal(address(token1), almProxy, token1Amount);
        deal(address(token2), almProxy, token2Amount);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = token1Amount;
        amounts[1] = token2Amount;

        uint256[] memory rates = pool.stored_rates();

        uint256 minLpAmount = (token1Amount * rates[0] + token2Amount * rates[1])
            / 1e18
            * controller.maxSlippages(address(pool))
            / pool.get_virtual_price();

        vm.prank(relayer);
        controller.addLiquidityCurve(address(pool), amounts, minLpAmount);
    }

}

contract CurveFuzzTestsBase is ForkTestBase {

    address constant RLUSD      = 0x8292Bb45bf1Ee4d140127049757C2E0fF06317eD;
    address constant CURVE_POOL = 0xD001aE433f254283FeCE51d4ACcE8c53263aa186;

    IERC20 rlUsd   = IERC20(RLUSD);
    IERC20 curveLp = IERC20(CURVE_POOL);

    ICurvePoolLike curvePool = ICurvePoolLike(CURVE_POOL);

    bytes32 curveDepositKey;
    bytes32 curveSwapKey;
    bytes32 curveWithdrawKey;

    function setUp() public virtual override  {
        super.setUp();

        curveDepositKey  = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_DEPOSIT(),  CURVE_POOL);
        curveSwapKey     = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_SWAP(),     CURVE_POOL);
        curveWithdrawKey = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_WITHDRAW(), CURVE_POOL);

        vm.startPrank(SPARK_PROXY);
        rateLimits.setRateLimitData(curveDepositKey,  2_000_000e18, uint256(2_000_000e18) / 1 days);
        rateLimits.setRateLimitData(curveSwapKey,     1_000_000e18, uint256(1_000_000e18) / 1 days);
        rateLimits.setRateLimitData(curveWithdrawKey, 3_000_000e18, uint256(3_000_000e18) / 1 days);
        vm.stopPrank();

        // Set a higher slippage to allow for successes
        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(CURVE_POOL, 0.98e18);

        ControllerHandler handler = new ControllerHandler(
            address(almProxy),
            address(mainnetController),
            CURVE_POOL,
            relayer,
            RLUSD,
            address(usdc)
        );
    }

    function statefulFuzz_curve_test() public {
        // assertEq(rlUsd.balanceOf(address(this)), 0);
    }
}


