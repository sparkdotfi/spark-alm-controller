// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { Base } from "lib/grove-address-registry/src/Base.sol";

import "./ForkTestBase.t.sol";

interface IMerklDistributorLike {
    function toggleOperator(address user, address operator) external;
    function operators(address user, address operator) external view returns (uint256);
    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external;
}

contract MerklBaseTest is ForkTestBase {

    event OperatorToggled(address indexed user, address indexed operator, bool isWhitelisted);

    address operator1 = makeAddr("operator1");
    address operator2 = makeAddr("operator2");

    IMerklDistributorLike merklDistributor = IMerklDistributorLike(Base.MERKL_DISTRIBUTOR);
}

contract ForeignControllerToggleOperatorMerklFailureTests is MerklBaseTest {

    function test_toggleOperatorMerkl_merklDistributorNotSet() external {
        vm.expectRevert("ForeignController/merkl-distributor-not-set");

        vm.prank(relayer);
        foreignController.toggleOperatorMerkl(operator1);
    }

    function test_toggleOperatorMerkl_notRelayer() external {
        vm.prank(Base.GROVE_EXECUTOR);
        foreignController.setMerklDistributor(address(merklDistributor));

        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        foreignController.toggleOperatorMerkl(operator1);
    }

}

contract ForeignControllerToggleOperatorMerklSuccessTests is MerklBaseTest {

    function setUp() public override {
        super.setUp();

        vm.prank(Base.GROVE_EXECUTOR);
        foreignController.setMerklDistributor(address(merklDistributor));
    }

    function test_toggleOperatorMerkl_singleOperator() external {
        assertEq(merklDistributor.operators(address(almProxy), operator1), 0);

        vm.prank(relayer);
        vm.expectEmit(address(merklDistributor));
        emit OperatorToggled(address(almProxy), operator1, true);
        foreignController.toggleOperatorMerkl(operator1);

        assertEq(merklDistributor.operators(address(almProxy), operator1), 1);

        vm.prank(relayer);
        vm.expectEmit(address(merklDistributor));
        emit OperatorToggled(address(almProxy), operator1, false);
        foreignController.toggleOperatorMerkl(operator1);

        assertEq(merklDistributor.operators(address(almProxy), operator1), 0);

        vm.prank(relayer);
        vm.expectEmit(address(merklDistributor));
        emit OperatorToggled(address(almProxy), operator1, true);
        foreignController.toggleOperatorMerkl(operator1);

        assertEq(merklDistributor.operators(address(almProxy), operator1), 1);
    }

    function test_toggleOperatorMerkl_multipleOperators() external {
        assertEq(merklDistributor.operators(address(almProxy), operator1), 0);
        assertEq(merklDistributor.operators(address(almProxy), operator2), 0);

        vm.prank(relayer);
        foreignController.toggleOperatorMerkl(operator1);

        assertEq(merklDistributor.operators(address(almProxy), operator1), 1);
        assertEq(merklDistributor.operators(address(almProxy), operator2), 0);

        vm.prank(relayer);
        foreignController.toggleOperatorMerkl(operator1);

        assertEq(merklDistributor.operators(address(almProxy), operator1), 0);
        assertEq(merklDistributor.operators(address(almProxy), operator2), 0);

        vm.prank(relayer);
        foreignController.toggleOperatorMerkl(operator1);

        assertEq(merklDistributor.operators(address(almProxy), operator1), 1);
        assertEq(merklDistributor.operators(address(almProxy), operator2), 0);

        vm.prank(relayer);
        foreignController.toggleOperatorMerkl(operator2);

        assertEq(merklDistributor.operators(address(almProxy), operator1), 1);
        assertEq(merklDistributor.operators(address(almProxy), operator2), 1);
    }

}
