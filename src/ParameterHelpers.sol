// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { IParameterHelpersErrors } from "./interfaces/IParameterHelpersErrors.sol";

/**
* @notice Helper functions for converting between parameter types and bytes32.
* @dev    NOTE: Right aligned bytes32 (i.e. zero-padded on the left) for all source types, including
*         bytesN (e.g. bytes1, bytes2, etc.).
*/
library ParameterHelpers {

    /**********************************************************************************************/
    /*** Boolean Functions                                                                      ***/
    /**********************************************************************************************/

    function fromBool(bool value) internal pure returns (bytes32 parameter) {
        return bytes32(value ? uint256(1) : uint256(0));
    }

    function toBool(bytes32 parameter) internal pure returns (bool value) {
        require(
            uint256(parameter) <= uint256(1),
            IParameterHelpersErrors.ParameterOutOfTypeBounds()
        );

        return uint256(parameter) == uint256(1);
    }

    /**********************************************************************************************/
    /*** Address Functions                                                                      ***/
    /**********************************************************************************************/

    function fromAddress(address value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint160(value)));
    }

    function toAddress(bytes32 parameter) internal pure returns (address value) {
        require(
            uint256(parameter) <= type(uint160).max,
            IParameterHelpersErrors.ParameterOutOfTypeBounds()
        );

        return address(uint160(uint256(parameter)));
    }

    /**********************************************************************************************/
    /*** Bytes Functions                                                                        ***/
    /**********************************************************************************************/

    function fromBytes1(bytes1 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint8(value)));
    }

    function toBytes1(bytes32 parameter) internal pure returns (bytes1 value) {
        _checkBytes(parameter, type(uint8).max);
        return bytes1(uint8(uint256(parameter)));
    }

    function fromBytes2(bytes2 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint16(value)));
    }

    function toBytes2(bytes32 parameter) internal pure returns (bytes2 value) {
        _checkBytes(parameter, type(uint16).max);
        return bytes2(uint16(uint256(parameter)));
    }

    function fromBytes3(bytes3 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint24(value)));
    }

    function toBytes3(bytes32 parameter) internal pure returns (bytes3 value) {
        _checkBytes(parameter, type(uint24).max);
        return bytes3(uint24(uint256(parameter)));
    }

    function fromBytes4(bytes4 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint32(value)));
    }

    function toBytes4(bytes32 parameter) internal pure returns (bytes4 value) {
        _checkBytes(parameter, type(uint32).max);
        return bytes4(uint32(uint256(parameter)));
    }

    function fromBytes5(bytes5 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint40(value)));
    }

    function toBytes5(bytes32 parameter) internal pure returns (bytes5 value) {
        _checkBytes(parameter, type(uint40).max);
        return bytes5(uint40(uint256(parameter)));
    }

    function fromBytes6(bytes6 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint48(value)));
    }

    function toBytes6(bytes32 parameter) internal pure returns (bytes6 value) {
        _checkBytes(parameter, type(uint48).max);
        return bytes6(uint48(uint256(parameter)));
    }

    function fromBytes7(bytes7 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint56(value)));
    }

    function toBytes7(bytes32 parameter) internal pure returns (bytes7 value) {
        _checkBytes(parameter, type(uint56).max);
        return bytes7(uint56(uint256(parameter)));
    }

    function fromBytes8(bytes8 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint64(value)));
    }

    function toBytes8(bytes32 parameter) internal pure returns (bytes8 value) {
        _checkBytes(parameter, type(uint64).max);
        return bytes8(uint64(uint256(parameter)));
    }

    function fromBytes9(bytes9 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint72(value)));
    }

    function toBytes9(bytes32 parameter) internal pure returns (bytes9 value) {
        _checkBytes(parameter, type(uint72).max);
        return bytes9(uint72(uint256(parameter)));
    }

    function fromBytes10(bytes10 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint80(value)));
    }

    function toBytes10(bytes32 parameter) internal pure returns (bytes10 value) {
        _checkBytes(parameter, type(uint80).max);
        return bytes10(uint80(uint256(parameter)));
    }

    function fromBytes11(bytes11 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint88(value)));
    }

    function toBytes11(bytes32 parameter) internal pure returns (bytes11 value) {
        _checkBytes(parameter, type(uint88).max);
        return bytes11(uint88(uint256(parameter)));
    }

    function fromBytes12(bytes12 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint96(value)));
    }

    function toBytes12(bytes32 parameter) internal pure returns (bytes12 value) {
        _checkBytes(parameter, type(uint96).max);
        return bytes12(uint96(uint256(parameter)));
    }

    function fromBytes13(bytes13 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint104(value)));
    }

    function toBytes13(bytes32 parameter) internal pure returns (bytes13 value) {
        _checkBytes(parameter, type(uint104).max);
        return bytes13(uint104(uint256(parameter)));
    }

    function fromBytes14(bytes14 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint112(value)));
    }

    function toBytes14(bytes32 parameter) internal pure returns (bytes14 value) {
        _checkBytes(parameter, type(uint112).max);
        return bytes14(uint112(uint256(parameter)));
    }

    function fromBytes15(bytes15 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint120(value)));
    }

    function toBytes15(bytes32 parameter) internal pure returns (bytes15 value) {
        _checkBytes(parameter, type(uint120).max);
        return bytes15(uint120(uint256(parameter)));
    }

    function fromBytes16(bytes16 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint128(value)));
    }

    function toBytes16(bytes32 parameter) internal pure returns (bytes16 value) {
        _checkBytes(parameter, type(uint128).max);
        return bytes16(uint128(uint256(parameter)));
    }

    function fromBytes17(bytes17 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint136(value)));
    }

    function toBytes17(bytes32 parameter) internal pure returns (bytes17 value) {
        _checkBytes(parameter, type(uint136).max);
        return bytes17(uint136(uint256(parameter)));
    }

    function fromBytes18(bytes18 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint144(value)));
    }

    function toBytes18(bytes32 parameter) internal pure returns (bytes18 value) {
        _checkBytes(parameter, type(uint144).max);
        return bytes18(uint144(uint256(parameter)));
    }

    function fromBytes19(bytes19 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint152(value)));
    }

    function toBytes19(bytes32 parameter) internal pure returns (bytes19 value) {
        _checkBytes(parameter, type(uint152).max);
        return bytes19(uint152(uint256(parameter)));
    }

    function fromBytes20(bytes20 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint160(value)));
    }

    function toBytes20(bytes32 parameter) internal pure returns (bytes20 value) {
        _checkBytes(parameter, type(uint160).max);
        return bytes20(uint160(uint256(parameter)));
    }

    function fromBytes21(bytes21 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint168(value)));
    }

    function toBytes21(bytes32 parameter) internal pure returns (bytes21 value) {
        _checkBytes(parameter, type(uint168).max);
        return bytes21(uint168(uint256(parameter)));
    }

    function fromBytes22(bytes22 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint176(value)));
    }

    function toBytes22(bytes32 parameter) internal pure returns (bytes22 value) {
        _checkBytes(parameter, type(uint176).max);
        return bytes22(uint176(uint256(parameter)));
    }

    function fromBytes23(bytes23 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint184(value)));
    }

    function toBytes23(bytes32 parameter) internal pure returns (bytes23 value) {
        _checkBytes(parameter, type(uint184).max);
        return bytes23(uint184(uint256(parameter)));
    }

    function fromBytes24(bytes24 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint192(value)));
    }

    function toBytes24(bytes32 parameter) internal pure returns (bytes24 value) {
        _checkBytes(parameter, type(uint192).max);
        return bytes24(uint192(uint256(parameter)));
    }

    function fromBytes25(bytes25 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint200(value)));
    }

    function toBytes25(bytes32 parameter) internal pure returns (bytes25 value) {
        _checkBytes(parameter, type(uint200).max);
        return bytes25(uint200(uint256(parameter)));
    }

    function fromBytes26(bytes26 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint208(value)));
    }

    function toBytes26(bytes32 parameter) internal pure returns (bytes26 value) {
        _checkBytes(parameter, type(uint208).max);
        return bytes26(uint208(uint256(parameter)));
    }

    function fromBytes27(bytes27 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint216(value)));
    }

    function toBytes27(bytes32 parameter) internal pure returns (bytes27 value) {
        _checkBytes(parameter, type(uint216).max);
        return bytes27(uint216(uint256(parameter)));
    }

    function fromBytes28(bytes28 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint224(value)));
    }

    function toBytes28(bytes32 parameter) internal pure returns (bytes28 value) {
        _checkBytes(parameter, type(uint224).max);
        return bytes28(uint224(uint256(parameter)));
    }

    function fromBytes29(bytes29 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint232(value)));
    }

    function toBytes29(bytes32 parameter) internal pure returns (bytes29 value) {
        _checkBytes(parameter, type(uint232).max);
        return bytes29(uint232(uint256(parameter)));
    }

    function fromBytes30(bytes30 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint240(value)));
    }

    function toBytes30(bytes32 parameter) internal pure returns (bytes30 value) {
        _checkBytes(parameter, type(uint240).max);
        return bytes30(uint240(uint256(parameter)));
    }

    function fromBytes31(bytes31 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(uint248(value)));
    }

    function toBytes31(bytes32 parameter) internal pure returns (bytes31 value) {
        _checkBytes(parameter, type(uint248).max);
        return bytes31(uint248(uint256(parameter)));
    }

    function fromBytes32(bytes32 value) internal pure returns (bytes32 parameter) {
        return value;
    }

    function toBytes32(bytes32 parameter) internal pure returns (bytes32 value) {
        return parameter;
    }

    /**********************************************************************************************/
    /*** Int Functions                                                                          ***/
    /**********************************************************************************************/

    function fromInt8(int8 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt8(bytes32 parameter) internal pure returns (int8 value) {
        _checkInt(parameter, type(int8).min, type(int8).max);
        return int8(int256(uint256(parameter)));
    }

    function fromInt16(int16 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt16(bytes32 parameter) internal pure returns (int16 value) {
        _checkInt(parameter, type(int16).min, type(int16).max);
        return int16(int256(uint256(parameter)));
    }

    function fromInt24(int24 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt24(bytes32 parameter) internal pure returns (int24 value) {
        _checkInt(parameter, type(int24).min, type(int24).max);
        return int24(int256(uint256(parameter)));
    }

    function fromInt32(int32 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt32(bytes32 parameter) internal pure returns (int32 value) {
        _checkInt(parameter, type(int32).min, type(int32).max);
        return int32(int256(uint256(parameter)));
    }

    function fromInt40(int40 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt40(bytes32 parameter) internal pure returns (int40 value) {
        _checkInt(parameter, type(int40).min, type(int40).max);
        return int40(int256(uint256(parameter)));
    }

    function fromInt48(int48 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt48(bytes32 parameter) internal pure returns (int48 value) {
        _checkInt(parameter, type(int48).min, type(int48).max);
        return int48(int256(uint256(parameter)));
    }

    function fromInt56(int56 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt56(bytes32 parameter) internal pure returns (int56 value) {
        _checkInt(parameter, type(int56).min, type(int56).max);
        return int56(int256(uint256(parameter)));
    }

    function fromInt64(int64 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt64(bytes32 parameter) internal pure returns (int64 value) {
        _checkInt(parameter, type(int64).min, type(int64).max);
        return int64(int256(uint256(parameter)));
    }

    function fromInt72(int72 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt72(bytes32 parameter) internal pure returns (int72 value) {
        _checkInt(parameter, type(int72).min, type(int72).max);
        return int72(int256(uint256(parameter)));
    }

    function fromInt80(int80 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt80(bytes32 parameter) internal pure returns (int80 value) {
        _checkInt(parameter, type(int80).min, type(int80).max);
        return int80(int256(uint256(parameter)));
    }

    function fromInt88(int88 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt88(bytes32 parameter) internal pure returns (int88 value) {
        _checkInt(parameter, type(int88).min, type(int88).max);
        return int88(int256(uint256(parameter)));
    }

    function fromInt96(int96 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt96(bytes32 parameter) internal pure returns (int96 value) {
        _checkInt(parameter, type(int96).min, type(int96).max);
        return int96(int256(uint256(parameter)));
    }

    function fromInt104(int104 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt104(bytes32 parameter) internal pure returns (int104 value) {
        _checkInt(parameter, type(int104).min, type(int104).max);
        return int104(int256(uint256(parameter)));
    }

    function fromInt112(int112 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt112(bytes32 parameter) internal pure returns (int112 value) {
        _checkInt(parameter, type(int112).min, type(int112).max);
        return int112(int256(uint256(parameter)));
    }

    function fromInt120(int120 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt120(bytes32 parameter) internal pure returns (int120 value) {
        _checkInt(parameter, type(int120).min, type(int120).max);
        return int120(int256(uint256(parameter)));
    }

    function fromInt128(int128 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt128(bytes32 parameter) internal pure returns (int128 value) {
        _checkInt(parameter, type(int128).min, type(int128).max);
        return int128(int256(uint256(parameter)));
    }

    function fromInt136(int136 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt136(bytes32 parameter) internal pure returns (int136 value) {
        _checkInt(parameter, type(int136).min, type(int136).max);
        return int136(int256(uint256(parameter)));
    }

    function fromInt144(int144 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt144(bytes32 parameter) internal pure returns (int144 value) {
        _checkInt(parameter, type(int144).min, type(int144).max);
        return int144(int256(uint256(parameter)));
    }

    function fromInt152(int152 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt152(bytes32 parameter) internal pure returns (int152 value) {
        _checkInt(parameter, type(int152).min, type(int152).max);
        return int152(int256(uint256(parameter)));
    }

    function fromInt160(int160 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt160(bytes32 parameter) internal pure returns (int160 value) {
        _checkInt(parameter, type(int160).min, type(int160).max);
        return int160(int256(uint256(parameter)));
    }

    function fromInt168(int168 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt168(bytes32 parameter) internal pure returns (int168 value) {
        _checkInt(parameter, type(int168).min, type(int168).max);
        return int168(int256(uint256(parameter)));
    }

    function fromInt176(int176 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt176(bytes32 parameter) internal pure returns (int176 value) {
        _checkInt(parameter, type(int176).min, type(int176).max);
        return int176(int256(uint256(parameter)));
    }

    function fromInt184(int184 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt184(bytes32 parameter) internal pure returns (int184 value) {
        _checkInt(parameter, type(int184).min, type(int184).max);
        return int184(int256(uint256(parameter)));
    }

    function fromInt192(int192 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt192(bytes32 parameter) internal pure returns (int192 value) {
        _checkInt(parameter, type(int192).min, type(int192).max);
        return int192(int256(uint256(parameter)));
    }

    function fromInt200(int200 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt200(bytes32 parameter) internal pure returns (int200 value) {
        _checkInt(parameter, type(int200).min, type(int200).max);
        return int200(int256(uint256(parameter)));
    }

    function fromInt208(int208 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt208(bytes32 parameter) internal pure returns (int208 value) {
        _checkInt(parameter, type(int208).min, type(int208).max);
        return int208(int256(uint256(parameter)));
    }

    function fromInt216(int216 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt216(bytes32 parameter) internal pure returns (int216 value) {
        _checkInt(parameter, type(int216).min, type(int216).max);
        return int216(int256(uint256(parameter)));
    }

    function fromInt224(int224 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt224(bytes32 parameter) internal pure returns (int224 value) {
        _checkInt(parameter, type(int224).min, type(int224).max);
        return int224(int256(uint256(parameter)));
    }

    function fromInt232(int232 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt232(bytes32 parameter) internal pure returns (int232 value) {
        _checkInt(parameter, type(int232).min, type(int232).max);
        return int232(int256(uint256(parameter)));
    }

    function fromInt240(int240 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt240(bytes32 parameter) internal pure returns (int240 value) {
        _checkInt(parameter, type(int240).min, type(int240).max);
        return int240(int256(uint256(parameter)));
    }

    function fromInt248(int248 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(int256(value)));
    }

    function toInt248(bytes32 parameter) internal pure returns (int248 value) {
        _checkInt(parameter, type(int248).min, type(int248).max);
        return int248(int256(uint256(parameter)));
    }

    function fromInt256(int256 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toInt256(bytes32 parameter) internal pure returns (int256 value) {
        return int256(uint256(parameter));
    }

    /**********************************************************************************************/
    /*** Uint Functions                                                                         ***/
    /**********************************************************************************************/

    function fromUint8(uint8 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint8(bytes32 parameter) internal pure returns (uint8 value) {
        _checkUint(parameter, type(uint8).max);
        return uint8(uint256(parameter));
    }

    function fromUint16(uint16 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint16(bytes32 parameter) internal pure returns (uint16 value) {
        _checkUint(parameter, type(uint16).max);
        return uint16(uint256(parameter));
    }

    function fromUint24(uint24 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint24(bytes32 parameter) internal pure returns (uint24 value) {
        _checkUint(parameter, type(uint24).max);
        return uint24(uint256(parameter));
    }

    function fromUint32(uint32 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint32(bytes32 parameter) internal pure returns (uint32 value) {
        _checkUint(parameter, type(uint32).max);
        return uint32(uint256(parameter));
    }

    function fromUint40(uint40 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint40(bytes32 parameter) internal pure returns (uint40 value) {
        _checkUint(parameter, type(uint40).max);
        return uint40(uint256(parameter));
    }

    function fromUint48(uint48 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint48(bytes32 parameter) internal pure returns (uint48 value) {
        _checkUint(parameter, type(uint48).max);
        return uint48(uint256(parameter));
    }

    function fromUint56(uint56 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint56(bytes32 parameter) internal pure returns (uint56 value) {
        _checkUint(parameter, type(uint56).max);
        return uint56(uint256(parameter));
    }

    function fromUint64(uint64 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint64(bytes32 parameter) internal pure returns (uint64 value) {
        _checkUint(parameter, type(uint64).max);
        return uint64(uint256(parameter));
    }

    function fromUint72(uint72 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint72(bytes32 parameter) internal pure returns (uint72 value) {
        _checkUint(parameter, type(uint72).max);
        return uint72(uint256(parameter));
    }

    function fromUint80(uint80 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint80(bytes32 parameter) internal pure returns (uint80 value) {
        _checkUint(parameter, type(uint80).max);
        return uint80(uint256(parameter));
    }

    function fromUint88(uint88 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint88(bytes32 parameter) internal pure returns (uint88 value) {
        _checkUint(parameter, type(uint88).max);
        return uint88(uint256(parameter));
    }

    function fromUint96(uint96 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint96(bytes32 parameter) internal pure returns (uint96 value) {
        _checkUint(parameter, type(uint96).max);
        return uint96(uint256(parameter));
    }

    function fromUint104(uint104 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint104(bytes32 parameter) internal pure returns (uint104 value) {
        _checkUint(parameter, type(uint104).max);
        return uint104(uint256(parameter));
    }

    function fromUint112(uint112 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint112(bytes32 parameter) internal pure returns (uint112 value) {
        _checkUint(parameter, type(uint112).max);
        return uint112(uint256(parameter));
    }

    function fromUint120(uint120 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint120(bytes32 parameter) internal pure returns (uint120 value) {
        _checkUint(parameter, type(uint120).max);
        return uint120(uint256(parameter));
    }

    function fromUint128(uint128 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint128(bytes32 parameter) internal pure returns (uint128 value) {
        _checkUint(parameter, type(uint128).max);
        return uint128(uint256(parameter));
    }

    function fromUint136(uint136 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint136(bytes32 parameter) internal pure returns (uint136 value) {
        _checkUint(parameter, type(uint136).max);
        return uint136(uint256(parameter));
    }

    function fromUint144(uint144 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint144(bytes32 parameter) internal pure returns (uint144 value) {
        _checkUint(parameter, type(uint144).max);
        return uint144(uint256(parameter));
    }

    function fromUint152(uint152 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint152(bytes32 parameter) internal pure returns (uint152 value) {
        _checkUint(parameter, type(uint152).max);
        return uint152(uint256(parameter));
    }

    function fromUint160(uint160 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint160(bytes32 parameter) internal pure returns (uint160 value) {
        _checkUint(parameter, type(uint160).max);
        return uint160(uint256(parameter));
    }

    function fromUint168(uint168 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint168(bytes32 parameter) internal pure returns (uint168 value) {
        _checkUint(parameter, type(uint168).max);
        return uint168(uint256(parameter));
    }

    function fromUint176(uint176 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint176(bytes32 parameter) internal pure returns (uint176 value) {
        _checkUint(parameter, type(uint176).max);
        return uint176(uint256(parameter));
    }

    function fromUint184(uint184 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint184(bytes32 parameter) internal pure returns (uint184 value) {
        _checkUint(parameter, type(uint184).max);
        return uint184(uint256(parameter));
    }

    function fromUint192(uint192 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint192(bytes32 parameter) internal pure returns (uint192 value) {
        _checkUint(parameter, type(uint192).max);
        return uint192(uint256(parameter));
    }

    function fromUint200(uint200 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint200(bytes32 parameter) internal pure returns (uint200 value) {
        _checkUint(parameter, type(uint200).max);
        return uint200(uint256(parameter));
    }

    function fromUint208(uint208 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint208(bytes32 parameter) internal pure returns (uint208 value) {
        _checkUint(parameter, type(uint208).max);
        return uint208(uint256(parameter));
    }

    function fromUint216(uint216 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint216(bytes32 parameter) internal pure returns (uint216 value) {
        _checkUint(parameter, type(uint216).max);
        return uint216(uint256(parameter));
    }

    function fromUint224(uint224 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint224(bytes32 parameter) internal pure returns (uint224 value) {
        _checkUint(parameter, type(uint224).max);
        return uint224(uint256(parameter));
    }

    function fromUint232(uint232 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint232(bytes32 parameter) internal pure returns (uint232 value) {
        _checkUint(parameter, type(uint232).max);
        return uint232(uint256(parameter));
    }

    function fromUint240(uint240 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint240(bytes32 parameter) internal pure returns (uint240 value) {
        _checkUint(parameter, type(uint240).max);
        return uint240(uint256(parameter));
    }

    function fromUint248(uint248 value) internal pure returns (bytes32 parameter) {
        return bytes32(uint256(value));
    }

    function toUint248(bytes32 parameter) internal pure returns (uint248 value) {
        _checkUint(parameter, type(uint248).max);
        return uint248(uint256(parameter));
    }

    function fromUint256(uint256 value) internal pure returns (bytes32 parameter) {
        return bytes32(value);
    }

    function toUint256(bytes32 parameter) internal pure returns (uint256 value) {
        return uint256(parameter);
    }

    /**********************************************************************************************/
    /*** Private Functions                                                                      ***/
    /**********************************************************************************************/

    function _checkBytes(bytes32 parameter, uint256 max) private pure {
        require(uint256(parameter) <= max, IParameterHelpersErrors.ParameterOutOfTypeBounds());
    }

    function _checkInt(bytes32 parameter, int256 min, int256 max) private pure {
        require(
            int256(uint256(parameter)) <= max,
            IParameterHelpersErrors.ParameterOutOfTypeBounds()
        );

        require(
            int256(uint256(parameter)) >= min,
            IParameterHelpersErrors.ParameterOutOfTypeBounds()
        );
    }

    function _checkUint(bytes32 parameter, uint256 max) private pure {
        require(uint256(parameter) <= max, IParameterHelpersErrors.ParameterOutOfTypeBounds());
    }

}
