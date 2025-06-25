// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "./ForkTestBase.t.sol";

import { ForeignController } from "../../src/ForeignController.sol";
import { MainnetController } from "../../src/MainnetController.sol";

import { CurveLib } from "../../src/libraries/CurveLib.sol";

import { IALMProxy } from "../../src/interfaces/IALMProxy.sol";

interface IHarness {
    function approve(address token, address spender, uint256 amount) external;
    function approveCurve(address proxy, address token, address spender, uint256 amount) external;
}

contract MainnetControllerHarness is MainnetController {

    using CurveLib for IALMProxy;

    constructor(
        address admin_,
        address proxy_,
        address rateLimits_,
        address vault_,
        address psm_,
        address daiUsds_,
        address cctp_,
        MainnetController.Addresses memory addresses_
    ) MainnetController(admin_, proxy_, rateLimits_, vault_, psm_, daiUsds_, cctp_, addresses_) {}

    function approve(address token, address spender, uint256 amount) external {
        _approve(token, spender, amount);
    }

    function approveCurve(address proxy, address token, address spender, uint256 amount) external {
        IALMProxy(proxy)._approve(token, spender, amount);
    }

}

contract ForeignControllerHarness is ForeignController {

    constructor(
        address admin_,
        address proxy_,
        address rateLimits_,
        address psm_,
        address usdc_,
        address cctp_
    ) ForeignController(admin_, proxy_, rateLimits_, psm_, usdc_, cctp_) {}

    function approve(address token, address spender, uint256 amount) external {
        _approve(token, spender, amount);
    }

}

contract ApproveTestBase is ForkTestBase {

    function _approveTest(address token, address harness) internal {
        address spender = makeAddr("spender");

        assertEq(IERC20(token).allowance(harness, spender), 0);

        IHarness(harness).approve(token, spender, 100);

        assertEq(IERC20(token).allowance(address(almProxy), spender), 100);

        IHarness(harness).approve(token, spender, 200);  // Would revert without setting to zero

        assertEq(IERC20(token).allowance(address(almProxy), spender), 200);
    }

    function _approveCurveTest(address token, address harness) internal {
        address spender = makeAddr("spender");

        assertEq(IERC20(token).allowance(harness, spender), 0);

        IHarness(harness).approveCurve(address(almProxy), token, spender, 100);

        assertEq(IERC20(token).allowance(address(almProxy), spender), 100);

        IHarness(harness).approveCurve(address(almProxy), token, spender, 200);  // Would revert without setting to zero

        assertEq(IERC20(token).allowance(address(almProxy), spender), 200);
    }

}
 
contract MainnetControllerApproveSuccessTests is ApproveTestBase {

    address harness;

    function setUp() public virtual override {
        super.setUp();

        MainnetControllerHarness harnessCode = new MainnetControllerHarness(
            SPARK_PROXY,
            address(mainnetController.proxy()),
            address(mainnetController.rateLimits()),
            address(mainnetController.vault()),
            address(mainnetController.psm()),
            address(mainnetController.daiUsds()),
            address(mainnetController.cctp()),
            MainnetController.Addresses({
                USDS                  : address(mainnetController.usds()),
                USDE                  : address(mainnetController.usde()),
                SUSDE                 : address(mainnetController.susde()),
                USTB                  : address(mainnetController.ustb()),
                ETHENA_MINTER         : address(mainnetController.ethenaMinter()),
                SUPERSTATE_REDEMPTION : address(mainnetController.superstateRedemption())
            })
        );

        vm.etch(address(mainnetController), address(harnessCode).code);

        harness = address(MainnetControllerHarness(address(mainnetController)));
    }

    function test_approveTokens() public {
        _approveTest(Ethereum.CBBTC,  harness);
        _approveTest(Ethereum.DAI,    harness);
        _approveTest(Ethereum.GNO,    harness);
        _approveTest(Ethereum.MKR,    harness);
        _approveTest(Ethereum.RETH,   harness);
        _approveTest(Ethereum.SDAI,   harness);
        _approveTest(Ethereum.SUSDE,  harness);
        _approveTest(Ethereum.SUSDS,  harness);
        _approveTest(Ethereum.USDC,   harness);
        _approveTest(Ethereum.USDE,   harness);
        _approveTest(Ethereum.USDS,   harness);
        _approveTest(Ethereum.USCC,   harness);
        _approveTest(Ethereum.USDT,   harness);
        _approveTest(Ethereum.USTB,   harness);
        _approveTest(Ethereum.WBTC,   harness);
        _approveTest(Ethereum.WEETH,  harness);
        _approveTest(Ethereum.WETH,   harness);
        _approveTest(Ethereum.WSTETH, harness);
    }

    function test_approveCurveTokens() public {
        _approveCurveTest(Ethereum.CBBTC,  harness);
        _approveCurveTest(Ethereum.DAI,    harness);
        _approveCurveTest(Ethereum.GNO,    harness);
        _approveCurveTest(Ethereum.MKR,    harness);
        _approveCurveTest(Ethereum.RETH,   harness);
        _approveCurveTest(Ethereum.SDAI,   harness);
        _approveCurveTest(Ethereum.SUSDE,  harness);
        _approveCurveTest(Ethereum.SUSDS,  harness);
        _approveCurveTest(Ethereum.USDC,   harness);
        _approveCurveTest(Ethereum.USDE,   harness);
        _approveCurveTest(Ethereum.USDS,   harness);
        _approveCurveTest(Ethereum.USCC,   harness);
        _approveCurveTest(Ethereum.USDT,   harness);
        _approveCurveTest(Ethereum.USTB,   harness);
        _approveCurveTest(Ethereum.WBTC,   harness);
        _approveCurveTest(Ethereum.WEETH,  harness);
        _approveCurveTest(Ethereum.WETH,   harness);
        _approveCurveTest(Ethereum.WSTETH, harness);
    }

}

// NOTE: This code is running against mainnet, but is used to demonstrate equivalent approve behaviour
//       for USDT-type contracts. Because of this, the foreignController has to be onboarded in the same
//       way as the mainnetController.
contract ForeignControllerApproveSuccessTests is ApproveTestBase {

    address harness;

    function setUp() public virtual override {
        super.setUp();

        // NOTE: This etching setup is necessary to get coverage to work

        ForeignController foreignController = new ForeignController(
            SPARK_PROXY,
            address(almProxy),
            makeAddr("rateLimits"),
            makeAddr("psm"),
            makeAddr("usdc"),
            makeAddr("cctp")
        );

        ForeignControllerHarness harnessCode = new ForeignControllerHarness(
            SPARK_PROXY,
            address(almProxy),
            makeAddr("rateLimits"),
            makeAddr("psm"),
            makeAddr("usdc"),
            makeAddr("cctp")
        );

        // Allow the foreign controller to call the ALMProxy
        vm.startPrank(SPARK_PROXY);
        almProxy.grantRole(almProxy.CONTROLLER(), address(foreignController));
        vm.stopPrank();

        vm.etch(address(foreignController), address(harnessCode).code);

        harness = address(ForeignControllerHarness(address(foreignController)));
    }

    function test_approveTokens() public {
        _approveTest(Ethereum.CBBTC,  harness);
        _approveTest(Ethereum.DAI,    harness);
        _approveTest(Ethereum.GNO,    harness);
        _approveTest(Ethereum.MKR,    harness);
        _approveTest(Ethereum.RETH,   harness);
        _approveTest(Ethereum.SDAI,   harness);
        _approveTest(Ethereum.SUSDE,  harness);
        _approveTest(Ethereum.SUSDS,  harness);
        _approveTest(Ethereum.USDC,   harness);
        _approveTest(Ethereum.USDE,   harness);
        _approveTest(Ethereum.USDS,   harness);
        _approveTest(Ethereum.USCC,   harness);
        _approveTest(Ethereum.USDT,   harness);
        _approveTest(Ethereum.USTB,   harness);
        _approveTest(Ethereum.WBTC,   harness);
        _approveTest(Ethereum.WEETH,  harness);
        _approveTest(Ethereum.WETH,   harness);
        _approveTest(Ethereum.WSTETH, harness);
    }

}
