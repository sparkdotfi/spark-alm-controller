// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/**
 * @title Interface defining errors for Parameter Helpers library.
 * @dev   This interface should be inherited by any contract that uses the Parameter Helpers library
 *        in order to expose the errors that may be thrown by the library.
 */
interface IParameterHelpersErrors {

    /// @notice Thrown when the parameter is out of type bounds.
    error ParameterOutOfTypeBounds();

}
