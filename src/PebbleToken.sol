// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Immutable, fixed-supply ERC-20 for Pebble Agent (PEBBLE).
/// @dev The constructor caller receives all tokens, including when deployed by a factory.
contract PebbleToken is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("Pebble Agent", "PEBBLE") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
