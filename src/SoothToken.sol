// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Sooth Protocol (SOOTH)
/// @notice Fixed-supply ERC-20 with the entire supply minted to its deployer.
/// @dev On the IdentityMD launch path, msg.sender is the launch factory.
///      There are no public mint, burn, owner, or upgrade functions.
contract SoothToken is ERC20 {
    /// @notice One billion SOOTH, expressed in its 18-decimal base units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("Sooth Protocol", "SOOTH") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}

