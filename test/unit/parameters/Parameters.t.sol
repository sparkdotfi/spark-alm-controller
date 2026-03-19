// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../../lib/forge-std/src/Test.sol";

import { IAccessControl }           from "../../../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { IAccessControlEnumerable } from "../../../lib/openzeppelin-contracts/contracts/access/extensions/IAccessControlEnumerable.sol";
import { IERC165 }                  from "../../../lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";

import { IParameters } from "../../../src/interfaces/IParameters.sol";

import { Parameters } from "../../../src/Parameters.sol";

contract ParametersHarness is Parameters {

    constructor(address admin) Parameters(admin) {}

    function __setParameter(string calldata key, address value) external {
        __setParameter(key, bytes32(uint256(uint160(value))));
    }

    function __setParameter(string calldata key, bool value) external {
        __setParameter(key, value ? bytes32(uint256(1)) : bytes32(uint256(0)));
    }

    function __setParameter(string calldata key, uint256 value) external {
        __setParameter(key, bytes32(value));
    }

    function __setParameter(string calldata key, bytes32 value) public {
        _parameters[key] = value;
    }

}

contract Parameters_Tests is Test {

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    address internal admin        = makeAddr("admin");
    address internal deployer     = makeAddr("deployer");
    address internal controller   = makeAddr("controller");
    address internal unauthorized = makeAddr("unauthorized");

    ParametersHarness internal parameters;

    function setUp() external {
        vm.prank(deployer);
        parameters = new ParametersHarness(admin);

        vm.startPrank(admin);
        parameters.grantRole(parameters.CONTROLLER_ROLE(), controller);
        vm.stopPrank();
    }

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroAdmin() external {
        vm.expectRevert(IParameters.ZeroAdmin.selector);
        new ParametersHarness(address(0));
    }

    function test_constructor() external {
        vm.expectEmit();
        emit IAccessControl.RoleGranted(DEFAULT_ADMIN_ROLE, admin, deployer);

        vm.prank(deployer);
        Parameters parameters_ = new Parameters(admin);

        assertEq(parameters_.hasRole(DEFAULT_ADMIN_ROLE, admin), true);

        assertEq(parameters_.CONTROLLER_ROLE(), keccak256("CONTROLLER"));
    }

    /**********************************************************************************************/
    /*** Set One Tests                                                                          ***/
    /**********************************************************************************************/

    function test_set_one_notController() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                parameters.CONTROLLER_ROLE()
            )
        );

        vm.prank(unauthorized);
        parameters.set("", 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                admin,
                parameters.CONTROLLER_ROLE()
            )
        );

        vm.prank(admin);
        parameters.set("", 0);
    }

    function test_set_one() external {
        vm.expectEmit(address(parameters));
        emit IParameters.ParameterSet("this.is.a.parameter", "this.is.a.parameter", bytes32(uint256(1010101)));

        vm.prank(controller);
        parameters.set("this.is.a.parameter", bytes32(uint256(1010101)));

        assertEq(parameters.get("this.is.a.parameter"), bytes32(uint256(1010101)));
    }

    /**********************************************************************************************/
    /*** Set Several Tests                                                                      ***/
    /**********************************************************************************************/

    function test_set_several_notController() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                parameters.CONTROLLER_ROLE()
            )
        );

        vm.prank(unauthorized);
        parameters.set(new string[](0), new bytes32[](0));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                admin,
                parameters.CONTROLLER_ROLE()
            )
        );

        vm.prank(admin);
        parameters.set(new string[](0), new bytes32[](0));
    }

    function test_set_several_noKeys() external {
        vm.expectRevert(IParameters.NoKeys.selector);
        vm.prank(controller);
        parameters.set(new string[](0), new bytes32[](0));
    }

    function test_set_several_arrayLengthMismatch() external {
        vm.expectRevert(IParameters.ArrayLengthMismatch.selector);
        vm.prank(controller);
        parameters.set(new string[](1), new bytes32[](2));
    }

    function test_set_several() external {
        string[] memory keys_ = new string[](2);

        keys_[0] = "this.is.a.parameter";
        keys_[1] = "this.is.another.parameter";

        bytes32[] memory values_ = new bytes32[](2);
        values_[0] = bytes32(uint256(1010101));
        values_[1] = bytes32(uint256(2020202));

        vm.expectEmit(address(parameters));
        emit IParameters.ParameterSet(keys_[0], keys_[0], values_[0]);

        vm.expectEmit(address(parameters));
        emit IParameters.ParameterSet(keys_[1], keys_[1], values_[1]);

        vm.prank(controller);
        parameters.set(keys_, values_);

        assertEq(parameters.get(keys_[0]), bytes32(uint256(1010101)));
        assertEq(parameters.get(keys_[1]), bytes32(uint256(2020202)));
    }

    /**********************************************************************************************/
    /*** Get One Tests                                                                          ***/
    /**********************************************************************************************/

    function test_get_one() external {
        parameters.__setParameter("this.is.a.parameter", bytes32(uint256(1010101)));

        assertEq(parameters.get("this.is.a.parameter"),                           bytes32(uint256(1010101)));
        assertEq(parameters.get(string(bytes("this.is.a.parameter"))),            bytes32(uint256(1010101)));
        assertEq(parameters.get(string(abi.encodePacked("this.is.a.parameter"))), bytes32(uint256(1010101)));

        // NOTE: Encoding a string non-compactly is a different key.
        assertNotEq(parameters.get(string(abi.encode("this.is.a.parameter"))), bytes32(uint256(1010101)));
    }

    /**********************************************************************************************/
    /*** Get Several Tests                                                                      ***/
    /**********************************************************************************************/

    function test_get_several_noKeys() external {
        vm.expectRevert(IParameters.NoKeys.selector);
        parameters.get(new string[](0));
    }

    function test_get_several() external {
        string[] memory keys_ = new string[](2);

        keys_[0] = "this.is.a.parameter";
        keys_[1] = "this.is.another.parameter";

        bytes32[] memory expectedValues_ = new bytes32[](2);
        expectedValues_[0] = bytes32(uint256(1010101));
        expectedValues_[1] = bytes32(uint256(2020202));

        parameters.__setParameter(keys_[0], expectedValues_[0]);
        parameters.__setParameter(keys_[1], expectedValues_[1]);

        bytes32[] memory values_ = parameters.get(keys_);

        assertEq(values_.length, keys_.length);
        assertEq(values_[0], expectedValues_[0]);
        assertEq(values_[1], expectedValues_[1]);
    }

    /**********************************************************************************************/
    /*** supportsInterface Tests                                                                ***/
    /**********************************************************************************************/

    function test_supportsInterface() external view {
        assertEq(parameters.supportsInterface(type(IParameters).interfaceId),              true);
        assertEq(parameters.supportsInterface(type(IAccessControlEnumerable).interfaceId), true);
        assertEq(parameters.supportsInterface(type(IAccessControl).interfaceId),           true);
        assertEq(parameters.supportsInterface(type(IERC165).interfaceId),                  true);
    }

}
