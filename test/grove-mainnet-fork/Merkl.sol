// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { Ethereum } from "lib/grove-address-registry/src/Ethereum.sol";

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

    address constant A_ETH_RLUSD = 0x72eEED8043Dcce2Fe7CdAC950D928F80f472ab80;

    event OperatorToggled(address indexed user, address indexed operator, bool isWhitelisted);

    address operator1 = makeAddr("operator1");
    address operator2 = makeAddr("operator2");

    IMerklDistributorLike merklDistributor = IMerklDistributorLike(Ethereum.MERKL_DISTRIBUTOR);

    function _getBlock() internal pure override returns (uint256) {
        return 23827450;  // Nov 18, 2025
    }
}

contract MainnetControllerToggleOperatorMerklFailureTests is MerklBaseTest {

    function test_toggleOperatorMerkl_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.toggleOperatorMerkl(operator1);
    }

}

contract MainnetControllerToggleOperatorMerklSuccessTests is MerklBaseTest {

    function test_toggleOperatorMerkl_singleOperator() external {
        assertEq(merklDistributor.operators(address(almProxy), operator1), 0);

        vm.prank(relayer);
        vm.expectEmit(address(merklDistributor));
        emit OperatorToggled(address(almProxy), operator1, true);
        mainnetController.toggleOperatorMerkl(operator1);

        assertEq(merklDistributor.operators(address(almProxy), operator1), 1);

        vm.prank(relayer);
        vm.expectEmit(address(merklDistributor));
        emit OperatorToggled(address(almProxy), operator1, false);
        mainnetController.toggleOperatorMerkl(operator1);

        assertEq(merklDistributor.operators(address(almProxy), operator1), 0);

        vm.prank(relayer);
        vm.expectEmit(address(merklDistributor));
        emit OperatorToggled(address(almProxy), operator1, true);
        mainnetController.toggleOperatorMerkl(operator1);

        assertEq(merklDistributor.operators(address(almProxy), operator1), 1);
    }

    function test_toggleOperatorMerkl_multipleOperators() external {
        assertEq(merklDistributor.operators(address(almProxy), operator1), 0);
        assertEq(merklDistributor.operators(address(almProxy), operator2), 0);

        vm.prank(relayer);
        mainnetController.toggleOperatorMerkl(operator1);

        assertEq(merklDistributor.operators(address(almProxy), operator1), 1);
        assertEq(merklDistributor.operators(address(almProxy), operator2), 0);

        vm.prank(relayer);
        mainnetController.toggleOperatorMerkl(operator1);

        assertEq(merklDistributor.operators(address(almProxy), operator1), 0);
        assertEq(merklDistributor.operators(address(almProxy), operator2), 0);

        vm.prank(relayer);
        mainnetController.toggleOperatorMerkl(operator1);

        assertEq(merklDistributor.operators(address(almProxy), operator1), 1);
        assertEq(merklDistributor.operators(address(almProxy), operator2), 0);

        vm.prank(relayer);
        mainnetController.toggleOperatorMerkl(operator2);

        assertEq(merklDistributor.operators(address(almProxy), operator1), 1);
        assertEq(merklDistributor.operators(address(almProxy), operator2), 1);
    }

    function test_toggleOperatorMerkl_attemptClaim() external {
        address[]   memory users   = new address[](1);
        address[]   memory tokens  = new address[](1);
        uint256[]   memory amounts = new uint256[](1);
        bytes32[][] memory proofs  = new bytes32[][](1);

        users[0]     = address(almProxy);
        tokens[0]    = A_ETH_RLUSD;
        amounts[0]   = 299_033.458789039331965803e18;
        proofs[0]    = new bytes32[](1);
        proofs[0][0] = bytes32(0);

        vm.expectRevert(abi.encodeWithSignature("NotWhitelisted()"));
        vm.prank(operator1);
        merklDistributor.claim(users, tokens, amounts, proofs);

        vm.prank(relayer);
        mainnetController.toggleOperatorMerkl(operator1);

        // Hitting the InvalidProof() error proves that we are whitelisted as operator1
        // (https://github.com/AngleProtocol/merkl-contracts/blob/e4c49c1fbfb274029d31969adf70ca6aeec689f0/contracts/Distributor.sol#L378-L383)
        vm.expectRevert(abi.encodeWithSignature("InvalidProof()"));
        vm.prank(operator1);
        merklDistributor.claim(users, tokens, amounts, proofs);
    }

}
