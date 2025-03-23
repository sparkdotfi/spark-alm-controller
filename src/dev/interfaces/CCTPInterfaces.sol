// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

interface ICCTPLike {

    function depositForBurn(
        uint256 amount,
        uint32  destinationDomain,
        bytes32 mintRecipient,
        address burnToken
    ) external returns (uint64 nonce);

    function localMinter() external view returns (ICCTPTokenMinterLike);

}

interface ICCTPTokenMinterLike {
    function burnLimitsPerMessage(address) external view returns (uint256);
}
