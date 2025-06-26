// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "./ForkTestBase.t.sol";

import { ForeignController } from "../../src/ForeignController.sol";
import { MainnetController } from "../../src/MainnetController.sol";

import { CurveLib } from "../../src/libraries/CurveLib.sol";

import { IALMProxy } from "../../src/interfaces/IALMProxy.sol";

import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

interface IHarness {
    function approve(address token, address spender, uint256 amount) external;
    function approveCurve(address proxy, address token, address spender, uint256 amount) external;
}

contract ERC20ApproveFalseExistingAllowance is ERC20 {

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function approve(address spender, uint256 value) public virtual override returns (bool) {
        // USDT-like resetting to 0 required. but returns false instead of reverting
        if ((value != 0) && (allowance(msg.sender, spender) != 0)) {
            return false;
        }

        return super.approve(spender, value);
    }

}

contract ERC20ApproveFalseNonZeroAmount is ERC20 {

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function approve(address spender, uint256 value) public virtual override returns (bool) {
        // Used to assert hitting second revert condition
        if (value != 0) return false;

        return super.approve(spender, value);
    }

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
        address cctp_
    ) MainnetController(admin_, proxy_, rateLimits_, vault_, psm_, daiUsds_, cctp_) {}

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
            address(mainnetController.cctp())
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

contract ERC20ApproveReturningFalseExistingAllowanceMainnetTest is MainnetControllerApproveSuccessTests {

    function test_approveReturningFalseOnExistingAllowance() public {
        ERC20ApproveFalseExistingAllowance mock = new ERC20ApproveFalseExistingAllowance("Mock", "MOCK");
        _approveTest(address(mock), harness);
        _approveCurveTest(address(mock), harness);
    }

}

contract ERC20ApproveReturningFalseNonZeroAmountMainnetTest is MainnetControllerApproveSuccessTests {

    function test_approveReturningFalseOnNonZeroAmount() public {
        ERC20ApproveFalseNonZeroAmount mock = new ERC20ApproveFalseNonZeroAmount("Mock", "MOCK");

        vm.expectRevert("MainnetController/approve-failed");
        IHarness(harness).approve(address(mock), makeAddr("spender"), 100);

        vm.expectRevert("CurveLib/approve-failed");
        IHarness(harness).approveCurve(address(almProxy), address(mock), makeAddr("spender"), 100);
    }

}

contract ERC20ApproveReturningFalseExistingAllowanceForeignTest is ForeignControllerApproveSuccessTests {

    function test_approveCustom() public {
        ERC20ApproveFalseExistingAllowance mock = new ERC20ApproveFalseExistingAllowance("Mock", "MOCK");
        _approveTest(address(mock), harness);
    }

}

contract ERC20ApproveReturningFalseNonZeroAmountForeignTest is ForeignControllerApproveSuccessTests {

    function test_approveReturningFalseOnNonZeroAmount() public {
        ERC20ApproveFalseNonZeroAmount mock = new ERC20ApproveFalseNonZeroAmount("Mock", "MOCK");

        vm.expectRevert("ForeignController/approve-failed");
        IHarness(harness).approve(address(mock), makeAddr("spender"), 100);
    }

}
