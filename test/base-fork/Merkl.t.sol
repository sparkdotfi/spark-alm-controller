// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Base as GroveBase } from "../../lib/grove-address-registry/src/Base.sol";
import { Base as SparkBase } from "../../lib/spark-address-registry/src/Base.sol";

import { IMerklFacet } from "../../src/facets/merkl/IMerklFacet.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IMerklDistributorLike {

    function toggleOperator(address user, address operator) external;

    function operators(address user, address operator) external view returns (uint256);

    function claim(
        address[]   calldata users,
        address[]   calldata tokens,
        uint256[]   calldata amounts,
        bytes32[][] calldata proofs
    ) external;

}

abstract contract Merkl_TestBase is ForkTestBase {

    event OperatorToggled(address indexed user, address indexed operator, bool isWhitelisted);

    address operator1 = makeAddr("operator1");
    address operator2 = makeAddr("operator2");

    IMerklDistributorLike merklDistributor = IMerklDistributorLike(GroveBase.MERKL_DISTRIBUTOR);

    function setUp() public override {
        super.setUp();

        vm.prank(SparkBase.SPARK_EXECUTOR);
        foreignController.setMerklDistributor(address(merklDistributor));
    }

}

contract ForeignController_Merkl_ToggleOperator_FailureTests is Merkl_TestBase {

    function test_toggleOperatorMerkl_notAllocator() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            ALLOCATOR_ROLE
        ));
        foreignController.toggleOperatorMerkl(operator1);
    }

}

contract ForeignController_Merkl_ToggleOperator_SuccessTests is Merkl_TestBase {

    function test_toggleOperatorMerkl_singleOperator() external {
        assertEq(merklDistributor.operators(address(almProxy), operator1), 0);

        vm.expectEmit(address(merklDistributor));
        emit OperatorToggled({
            user          : address(almProxy),
            operator      : operator1,
            isWhitelisted : true
        });

        vm.expectEmit(address(foreignController));
        emit IMerklFacet.MerklToggleOperator(operator1);

        vm.prank(allocator);
        foreignController.toggleOperatorMerkl(operator1);

        assertEq(merklDistributor.operators(address(almProxy), operator1), 1);

        vm.expectEmit(address(merklDistributor));
        emit OperatorToggled({
            user          : address(almProxy),
            operator      : operator1,
            isWhitelisted : false
        });

        vm.expectEmit(address(foreignController));
        emit IMerklFacet.MerklToggleOperator(operator1);

        vm.prank(allocator);
        foreignController.toggleOperatorMerkl(operator1);

        assertEq(merklDistributor.operators(address(almProxy), operator1), 0);

        vm.expectEmit(address(merklDistributor));
        emit OperatorToggled({
            user          : address(almProxy),
            operator      : operator1,
            isWhitelisted : true
        });

        vm.expectEmit(address(foreignController));
        emit IMerklFacet.MerklToggleOperator(operator1);

        vm.prank(allocator);
        foreignController.toggleOperatorMerkl(operator1);

        assertEq(merklDistributor.operators(address(almProxy), operator1), 1);
    }

    function test_toggleOperatorMerkl_multipleOperators() external {
        assertEq(merklDistributor.operators(address(almProxy), operator1), 0);
        assertEq(merklDistributor.operators(address(almProxy), operator2), 0);

        vm.expectEmit(address(foreignController));
        emit IMerklFacet.MerklToggleOperator(operator1);

        vm.prank(allocator);
        foreignController.toggleOperatorMerkl(operator1);

        assertEq(merklDistributor.operators(address(almProxy), operator1), 1);
        assertEq(merklDistributor.operators(address(almProxy), operator2), 0);

        vm.expectEmit(address(foreignController));
        emit IMerklFacet.MerklToggleOperator(operator1);

        vm.prank(allocator);
        foreignController.toggleOperatorMerkl(operator1);

        assertEq(merklDistributor.operators(address(almProxy), operator1), 0);
        assertEq(merklDistributor.operators(address(almProxy), operator2), 0);

        vm.expectEmit(address(foreignController));
        emit IMerklFacet.MerklToggleOperator(operator1);

        vm.prank(allocator);
        foreignController.toggleOperatorMerkl(operator1);

        assertEq(merklDistributor.operators(address(almProxy), operator1), 1);
        assertEq(merklDistributor.operators(address(almProxy), operator2), 0);

        vm.expectEmit(address(foreignController));
        emit IMerklFacet.MerklToggleOperator(operator2);

        vm.prank(allocator);
        foreignController.toggleOperatorMerkl(operator2);

        assertEq(merklDistributor.operators(address(almProxy), operator1), 1);
        assertEq(merklDistributor.operators(address(almProxy), operator2), 1);
    }

    function test_toggleOperatorMerkl_attemptClaim() external {
        address[]   memory users   = new address[](1);
        address[]   memory tokens  = new address[](1);
        uint256[]   memory amounts = new uint256[](1);
        bytes32[][] memory proofs  = new bytes32[][](1);

        users[0]     = address(almProxy);
        tokens[0]    = address(0);
        amounts[0]   = 299_033.458789039331965803e18;
        proofs[0]    = new bytes32[](1);
        proofs[0][0] = bytes32(0);

        vm.expectRevert(abi.encodeWithSignature("NotWhitelisted()"));
        vm.prank(operator1);
        merklDistributor.claim(users, tokens, amounts, proofs);

        vm.prank(allocator);
        foreignController.toggleOperatorMerkl(operator1);

        // Hitting the InvalidProof() error proves that we are whitelisted as operator1
        // (https://github.com/AngleProtocol/merkl-contracts/blob/e4c49c1fbfb274029d31969adf70ca6aeec689f0/contracts/Distributor.sol#L378-L383)
        vm.expectRevert(abi.encodeWithSignature("InvalidProof()"));
        vm.prank(operator1);
        merklDistributor.claim(users, tokens, amounts, proofs);
    }

}
