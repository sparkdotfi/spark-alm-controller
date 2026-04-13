// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { EnumerableSet } from "../../../lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import { ApproveLib }     from "../../libraries/ApproveLib.sol";
import { makeAddressKey } from "../../libraries/RateLimitHelpers.sol";

import { IALMProxy }   from "../../interfaces/IALMProxy.sol";
import { IRateLimits } from "../../interfaces/IRateLimits.sol";

import { FacetBase } from "../FacetBase.sol";

import { INFATHaloFacet } from "./INFATHaloFacet.sol";

interface INFATFacilityLike {

    function gem() external view returns (address);

    function ownerOf(uint256 tokenId) external view returns (address);

    function repay(uint256 tokenId, uint256 amount) external;

}

contract NFATHaloFacet is INFATHaloFacet, FacetBase {

    using EnumerableSet for EnumerableSet.AddressSet;

    /**********************************************************************************************/
    /*** NFATHaloFacet Storage Domain                                                           ***/
    /**********************************************************************************************/

    /// @custom:storage-location erc7201:sky.pau.storage.NFATHaloFacet
    struct FacetStorage {
        EnumerableSet.AddressSet allowedRepayRecipients;
    }

    // keccak256(abi.encode(uint256(keccak256("sky.pau.storage.NFATHaloFacet")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant FACET_STORAGE_LOCATION =
        0x3465848ce3041b2584b22510cec9b33d7e088a88dd0fc9d03037f560a3b91a00;

    function _getFacetStorage() internal pure returns (FacetStorage storage $) {
        assembly {
            $.slot := FACET_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant LIMIT_REPAY = keccak256("LIMIT_NFAT_REPAY");

    /**********************************************************************************************/
    /*** External interactive functions                                                         ***/
    /**********************************************************************************************/

    function setAllowedRepayRecipient(address recipient, bool isAllowed)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(recipient != address(0), "NFATHaloFacet/recipient-zero-address");

        EnumerableSet.AddressSet storage set = _getFacetStorage().allowedRepayRecipients;

        if (isAllowed) set.add(recipient);
        else           set.remove(recipient);

        emit NFATAllowedRepayRecipientSet(recipient, isAllowed);
    }

    function repay(address nfatFacility, uint256 tokenId, uint256 amount)
        external
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        require(
            _getFacetStorage().allowedRepayRecipients.contains(
                INFATFacilityLike(nfatFacility).ownerOf(tokenId)
            ),
            "NFATHaloFacet/recipient-not-allowed"
        );

        SharedControllerStorage storage $ = _getSharedControllerStorage();

        IRateLimits($.rateLimits).triggerRateLimitDecrease(
            makeAddressKey(LIMIT_REPAY, nfatFacility),
            amount
        );

        address proxy = $.proxy;

        ApproveLib.approve(INFATFacilityLike(nfatFacility).gem(), proxy, nfatFacility, amount);

        IALMProxy(proxy).doCall(
            nfatFacility,
            abi.encodeCall(INFATFacilityLike.repay, (tokenId, amount))
        );
    }

    /**********************************************************************************************/
    /*** Public view/pure functions                                                             ***/
    /**********************************************************************************************/

    function getAllowedRepayRecipients() external view returns (address[] memory) {
        return _getFacetStorage().allowedRepayRecipients.values();
    }

    function isAllowedRepayRecipient(address recipient) external view returns (bool) {
        return _getFacetStorage().allowedRepayRecipients.contains(recipient);
    }

}
