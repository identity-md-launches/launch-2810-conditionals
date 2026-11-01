// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Conditionals (COND)
/// @notice A fixed supply of one billion tokens, with 18 decimals, minted to the deployer.
contract Conditionals is ERC20 {
    /// @notice The entire supply, expressed in the smallest token units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev The immediate deployer receives all tokens, including when deployed by a factory.
    constructor() ERC20("Conditionals", "COND") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
