// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

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

contract ERC20ApproveZeroResetReturnsFalse is ERC20 {

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function approve(address spender, uint256 value) public virtual override returns (bool) {
        // USDT-like: returns false when changing a non-zero allowance to non-zero (triggers fallback).
        if (value != 0 && allowance(msg.sender, spender) != 0) return false;

        bool result = super.approve(spender, value);

        // The zero-reset succeeds on-chain but (mis)reports false; ApproveLib discards this value.
        if (value == 0) return false;

        return result;
    }

}

contract ERC20ApproveZeroResetReverts is ERC20 {

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function approve(address spender, uint256 value) public virtual override returns (bool) {
        // The zero-reset reverts instead of returning a value.
        if (value == 0) revert("MockToken/approve-zero-reverts");

        // Returns false when changing a non-zero allowance to non-zero (triggers the fallback).
        if (allowance(msg.sender, spender) != 0) return false;

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

    function _getBlock() internal pure virtual returns (uint256) {
        return 20917850; // October 7, 2024
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

    function test_approve_zeroResetReturnsFalseButSucceeds() external {
        ERC20ApproveZeroResetReturnsFalse mock = new ERC20ApproveZeroResetReturnsFalse("Mock", "MOCK");

        harness.approve(address(mock), spender, 100);

        assertEq(IERC20Like(address(mock)).allowance(address(almProxy), spender), 100);

        // The second approval triggers the fallback: approve(0) returns false (discarded by
        // ApproveLib) but resets the allowance, so the re-approval succeeds gracefully.
        harness.approve(address(mock), spender, 200);

        assertEq(IERC20Like(address(mock)).allowance(address(almProxy), spender), 200);
    }

    function test_approve_zeroResetReverts() external {
        ERC20ApproveZeroResetReverts mock = new ERC20ApproveZeroResetReverts("Mock", "MOCK");

        harness.approve(address(mock), spender, 100);

        // The second approval triggers the fallback, whose approve(0) reverts, the revert propagates
        // unchanged (it is NOT transformed into "ApproveLib/approve-failed").
        vm.expectRevert("MockToken/approve-zero-reverts");
        harness.approve(address(mock), spender, 200);
    }

}
