// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { Address } from '../lib/openzeppelin-contracts/contracts/utils/Address.sol';

// TODO: Implementation should not be a struct, but instead a custom type packed into one stack item (bytes32).

contract ALMProxy {

    /**********************************************************************************************/
    /*** Structs                                                                                ***/
    /**********************************************************************************************/

    struct Implementation {
        address implementation;
        bytes4  functionSelector;
    }

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event ALMProxy_AdminSet(address indexed admin);

    event ALMProxy_ImplementationSet(
        bytes4  indexed exposedFunctionSelector,
        address indexed implementationAddress,
        bytes4  indexed implementationFunctionSelector
    );

    /**********************************************************************************************/
    /*** Errors                                                                                 ***/
    /**********************************************************************************************/

    error ALMProxy_NotAdmin(address sender);

    error ALMProxy_InvalidImplementation();

    error ALMProxy_FunctionSelectorNotSet(bytes4 functionSelector);

    /**********************************************************************************************/
    /*** UUPS Storage                                                                           ***/
    /**********************************************************************************************/

    /**
     * @custom:storage-location erc7201:sky.storage.ALMProxy
     * @notice The UUPS storage for the ALM proxy.
     */
    struct ALMProxyStorage {
        address admin;
        mapping(bytes4 functionSelector => Implementation implementation) implementations;
        bytes4[] functionSelectors;
    }

    // keccak256(abi.encode(uint256(keccak256('sky.storage.ALMProxy')) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _ALM_PROXY_STORAGE_LOCATION =
        0xecaf10aa029fa936ea42e5f15011e2f38c8598ffef434459a36a3d154fde2a00; // TODO: Update this.

    function _getALMProxyStorage() internal pure returns (ALMProxyStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := _ALM_PROXY_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Initialization                                                                         ***/
    /**********************************************************************************************/

    constructor(address admin_) {
        _setAdmin(admin_);
    }

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    function setAdmin(address admin_) external {
        _revertIfNotAdmin();
        _setAdmin(admin_);
    }

    function delegateCall(
        address contract_,
        bytes calldata callData_
    ) external returns (bytes memory result_) {
        _revertIfNotAdmin();
        return Address.functionDelegateCall(contract_, callData_);
    }

    function setImplementations(
        bytes4[]         calldata functionSelectors_,
        Implementation[] calldata implementations_
    ) external {
        _revertIfNotAdmin();

        for (uint256 i_ = 0; i_ < functionSelectors_.length; ++i_) {
            _setImplementation(functionSelectors_[i_], implementations_[i_]);
        }
    }

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    function admin() external view returns (address admin_) {
        return _getALMProxyStorage().admin;
    }

    function extSloads(bytes32[] calldata slots_) external view returns (bytes32[] memory results_) {
        results_ = new bytes32[](slots_.length);

        for (uint256 i; i < slots_.length;) {
            bytes32 slot_ = slots_[i++];

            // slither-disable-next-line assembly
            assembly ('memory-safe') {
                mstore(add(results_, mul(i, 32)), sload(slot_))
            }
        }
    }

    function getFunctionSelectors() external view returns (bytes4[] memory functionSelectors_) {
        return _getALMProxyStorage().functionSelectors;
    }

    function getImplementations(
        bytes4[] calldata functionSelectors_
    ) external view returns (Implementation[] memory implementations_) {
        implementations_ = new Implementation[](functionSelectors_.length);

        for (uint256 i_; i_ < functionSelectors_.length; ++i_) {
            implementations_[i_] = getImplementation(functionSelectors_[i_]);
        }
    }

    function getImplementation(bytes4 functionSelector_) public view returns (Implementation memory implementation_) {
        return _getALMProxyStorage().implementations[functionSelector_];
    }

    function implementations() external view returns (bytes4[] memory functionSelectors_, Implementation[] memory implementations_) {
        functionSelectors_ = _getALMProxyStorage().functionSelectors;

        implementations_ = new Implementation[](functionSelectors_.length);

        for (uint256 i_; i_ < functionSelectors_.length; ++i_) {
            implementations_[i_] = getImplementation(functionSelectors_[i_]);
        }
    }

    function isImplemented(bytes4 functionSelector_) external view returns (bool isImplemented_) {
        return _getALMProxyStorage().implementations[functionSelector_].implementation != address(0);
    }

    /**********************************************************************************************/
    /*** Internal functions                                                                     ***/
    /**********************************************************************************************/

    function _revertIfNotAdmin() internal view {
        if (msg.sender != _getALMProxyStorage().admin) revert ALMProxy_NotAdmin(msg.sender);
    }

    function _setAdmin(address admin_) internal {
        emit ALMProxy_AdminSet(_getALMProxyStorage().admin = admin_);
    }

    function _setImplementation(bytes4 functionSelector_, Implementation calldata implementation_) internal {
        emit ALMProxy_ImplementationSet(
            functionSelector_,
            implementation_.implementation,
            implementation_.functionSelector
        );

        // If the incoming implementation is the zero address, ...
        if (implementation_.implementation == address(0)) {
            // ... revert if the incoming function selector is not the zero selector.
            if (implementation_.functionSelector != bytes4(0)) revert ALMProxy_InvalidImplementation();

            // ... remove the function selector from the function selectors array and delete the implementation.
            _removeFunctionSelector(functionSelector_);
            delete _getALMProxyStorage().implementations[functionSelector_];

            return;
        }

        Implementation storage currentImplementation_ = _getALMProxyStorage().implementations[functionSelector_];

        // If the current implementation is the zero address, ...
        if (currentImplementation_.implementation == address(0)) {
            // ... add the function selector to the function selectors array.
            _getALMProxyStorage().functionSelectors.push(functionSelector_);
        }

        // Set the new implementation (overwriting the previous implementation if it existed).
        _getALMProxyStorage().implementations[functionSelector_] = implementation_;
    }

    function _removeFunctionSelector(bytes4 functionSelector_) internal {
        bytes4[] storage functionSelectors_ = _getALMProxyStorage().functionSelectors;

        for (uint256 i_; i_ < functionSelectors_.length; ++i_) {
            if (functionSelectors_[i_] != functionSelector_) continue;

            functionSelectors_[i_] = functionSelectors_[functionSelectors_.length - 1];
            functionSelectors_.pop();

            return;
        }

        revert ALMProxy_FunctionSelectorNotSet(functionSelector_);
    }

    /**********************************************************************************************/
    /*** Fallback Functions                                                                     ***/
    /**********************************************************************************************/

    // slither-disable-next-line locked-ether
    fallback() external payable {
        Implementation memory implementation_ = _getALMProxyStorage().implementations[msg.sig];

        address implementationAddress_ = implementation_.implementation;
        bytes4  implementationFunctionSelector_ = implementation_.functionSelector;

        // slither-disable-next-line assembly
        assembly {
            // allocate memory for the new calldata
            let ptr := mload(0x40)

            // store the 4-byte implementationFunctionSelector_ at ptr
            mstore(ptr, implementationFunctionSelector_)

            // copy (calldatasize() - 4) bytes from calldata (starting after the first 4 bytes) just after the function selector
            let tail := sub(calldatasize(), 4)
            calldatacopy(add(ptr, 4), 4, tail)

            // perform the delegatecall using implementationAddress_
            let result_ := delegatecall(
                gas(),
                implementationAddress_,
                ptr,
                add(tail, 4),
                0,
                0
            )

            // copy return data
            returndatacopy(0, 0, returndatasize())

            // handle result
            switch result_
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    receive() external payable {}

}
