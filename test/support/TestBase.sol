// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev The small subset of Foundry cheatcodes used by this project's tests.
interface TestVm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function prank(address sender) external;
    function startPrank(address sender) external;
    function stopPrank() external;
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data, address emitter) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);
    function deal(address account, uint256 balance) external;
}

/// @dev No external test dependencies, environment reads, RPCs, or filesystem access.
abstract contract TestBase {
    TestVm internal constant vm = TestVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertEq(uint256 actual, uint256 expected, string memory reason) internal pure {
        require(actual == expected, reason);
    }

    function assertEq(address actual, address expected, string memory reason) internal pure {
        require(actual == expected, reason);
    }

    function assertEq(string memory actual, string memory expected, string memory reason) internal pure {
        require(keccak256(bytes(actual)) == keccak256(bytes(expected)), reason);
    }
}
