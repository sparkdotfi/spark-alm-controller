// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { Test, StdChains } from "../../lib/forge-std/src/Test.sol";

import { ERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { DomainHelpers } from "../../lib/xchain-helpers/src/testing/Domain.sol";

import { ApproveLib } from "../../src/libraries/ApproveLib.sol";

import { ALMProxy } from "../../src/ALMProxy.sol";

interface IERC20Like {

    function allowance(address owner, address spender) external view returns (uint256);

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

contract Harness {

    address internal _proxy;

    constructor(address proxy) {
        _proxy = proxy;
    }

    function approve(address token, address spender, uint256 amount) external {
        ApproveLib.approve(token, _proxy, spender, amount);
    }

}

contract Approve_Tests is Test {

    ALMProxy internal almProxy;
    Harness  internal harness;

    address internal admin;
    address internal spender;

    function setUp() external {
        DomainHelpers.createSelectFork(getChain("mainnet"), _getBlock());

        admin   = makeAddr("admin");
        spender = makeAddr("spender");

        almProxy = new ALMProxy(admin);
        harness  = new Harness(address(almProxy));

        vm.startPrank(admin);
        almProxy.grantRole(almProxy.CONTROLLER(), address(harness));
        vm.stopPrank();
    }

    function _getBlock() internal virtual pure returns (uint256) {
        return 20917850; //  October 7, 2024
    }

    function _approveTest(address token) internal {
        assertEq(IERC20Like(token).allowance(address(harness),  spender), 0);
        assertEq(IERC20Like(token).allowance(address(almProxy), spender), 0);

        harness.approve(token, spender, 100);

        assertEq(IERC20Like(token).allowance(address(harness),  spender), 0);
        assertEq(IERC20Like(token).allowance(address(almProxy), spender), 100);

        harness.approve(token, spender, 200);  // Would revert without setting to zero

        assertEq(IERC20Like(token).allowance(address(harness),  spender), 0);
        assertEq(IERC20Like(token).allowance(address(almProxy), spender), 200);
    }

    function test_approve_tokens() external {
        _approveTest(Ethereum.CBBTC);
        _approveTest(Ethereum.DAI);
        _approveTest(Ethereum.GNO);
        _approveTest(Ethereum.MKR);
        _approveTest(Ethereum.RETH);
        _approveTest(Ethereum.SDAI);
        _approveTest(Ethereum.SUSDE);
        _approveTest(Ethereum.SUSDS);
        _approveTest(Ethereum.USDC);
        _approveTest(Ethereum.USDE);
        _approveTest(Ethereum.USDS);
        _approveTest(Ethereum.USCC);
        _approveTest(Ethereum.USDT);
        _approveTest(Ethereum.USTB);
        _approveTest(Ethereum.WBTC);
        _approveTest(Ethereum.WEETH);
        _approveTest(Ethereum.WETH);
        _approveTest(Ethereum.WSTETH);
    }

    function test_approve_returningFalseOnExistingAllowance() external {
        ERC20ApproveFalseExistingAllowance mock = new ERC20ApproveFalseExistingAllowance("Mock", "MOCK");
        _approveTest(address(mock));
    }

    function test_approve_returningFalseOnNonZeroAmount() external {
        ERC20ApproveFalseNonZeroAmount mock = new ERC20ApproveFalseNonZeroAmount("Mock", "MOCK");

        vm.expectRevert("ApproveLib/approve-failed");
        harness.approve(address(mock), makeAddr("spender"), 100);
    }

}
