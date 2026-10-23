// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SoothToken} from "../src/SoothToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TestBase} from "./support/TestBase.sol";

/// @dev Local deployment/custody harness; not a production factory or AMM.
contract TokenFactoryHarness {
    function deploy(bytes32 salt) external returns (SoothToken) {
        return new SoothToken{salt: salt}();
    }

    function forward(SoothToken token, address recipient, uint256 amount) external {
        require(token.transfer(recipient, amount), "forward failed");
    }
}

contract SoothTokenLaunchTest is TestBase {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    // Local test actors represent the launch roles; no actor address is a deployment parameter.
    address private constant DISTRIBUTOR = address(0xD157);
    address private constant POOL_CUSTODY = address(0x9001);
    address private constant CLAIMANT = address(0xC1A1);
    address private constant TRADER = address(0x7ADE);
    address private constant ROUTER = address(0xB00);
    address private constant REMAINDER = 0xd6302976E590b9b947DA8774b7f1246164e0ce98;

    function test_create2MintsToImmediateDeployerAndRequiresNoInitialization() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        bytes32 salt = keccak256("SOOTH deployment test");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(SoothToken).creationCode))
                    )
                )
            )
        );
        SoothToken token = factory.deploy(salt);
        assertEq(address(token), predicted, "CREATE2 address");
        assertEq(token.balanceOf(address(factory)), SUPPLY, "factory receives entire supply");
        assertEq(token.balanceOf(address(this)), 0, "factory caller receives nothing");
        assertEq(token.totalSupply(), SUPPLY, "supply at construction");
        assertEq(token.decimals(), 18, "ready without initialization");
        require(address(token).code.length > 0 && address(token).code.length <= 24_576, "deployable runtime size");
    }

    function test_exactLaunchAllocationsClaimsAndTradingTransferPaths() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        SoothToken token = factory.deploy(keccak256("SOOTH launch flow test"));
        uint256 swarmShare = SUPPLY / 10;
        uint256 poolShare = SUPPLY * 8 / 10;
        uint256 remainderShare = SUPPLY - swarmShare - poolShare;

        factory.forward(token, DISTRIBUTOR, swarmShare);
        factory.forward(token, POOL_CUSTODY, poolShare);
        factory.forward(token, REMAINDER, remainderShare);
        assertEq(token.balanceOf(address(factory)), 0, "factory fully distributed");
        assertEq(token.balanceOf(DISTRIBUTOR), swarmShare, "exact swarm allocation");
        assertEq(token.balanceOf(POOL_CUSTODY), poolShare, "exact pool allocation");
        assertEq(token.balanceOf(REMAINDER), remainderShare, "exact remainder allocation");

        vm.prank(DISTRIBUTOR);
        require(token.transfer(CLAIMANT, swarmShare), "claim transfer");
        assertEq(token.balanceOf(CLAIMANT), swarmShare, "claim has no fee");
        assertEq(token.balanceOf(DISTRIBUTOR), 0, "full claim");

        // Exercises token custody movements only. The protected launch harness tests actual v4 swaps.
        uint256 bought = 5_000 ether;
        vm.prank(POOL_CUSTODY);
        require(token.transfer(TRADER, bought), "pool pays buyer");
        assertEq(token.balanceOf(TRADER), bought, "buyer receives full output");
        vm.prank(TRADER);
        require(token.transfer(POOL_CUSTODY, bought), "seller pays pool");
        assertEq(token.balanceOf(TRADER), 0, "buyer can sell entire holding");
        assertEq(token.balanceOf(POOL_CUSTODY), poolShare, "direct trading round trip");

        vm.prank(POOL_CUSTODY);
        require(token.transfer(TRADER, bought), "second buy");
        vm.prank(TRADER);
        require(token.approve(ROUTER, bought), "router approval");
        vm.prank(ROUTER);
        require(token.transferFrom(TRADER, POOL_CUSTODY, bought), "approved sale settlement");
        assertEq(token.balanceOf(POOL_CUSTODY), poolShare, "approved trading round trip");
        assertEq(token.allowance(TRADER, ROUTER), 0, "spent router approval");
        assertEq(token.totalSupply(), SUPPLY, "no launch or trading supply change");
        assertEq(
            token.balanceOf(CLAIMANT) + token.balanceOf(POOL_CUSTODY) + token.balanceOf(REMAINDER),
            SUPPLY,
            "all launch tokens accounted for"
        );
    }

    function test_factoryHasNoAuthorityOverDistributedTokens() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        SoothToken token = factory.deploy(keccak256("SOOTH permissions test"));
        factory.forward(token, CLAIMANT, SUPPLY);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(factory), 0, 1)
        );
        vm.prank(address(factory));
        token.transferFrom(CLAIMANT, address(factory), 1);
        vm.prank(CLAIMANT);
        require(token.transfer(TRADER, SUPPLY), "holder can transfer all tokens");
        assertEq(token.balanceOf(TRADER), SUPPLY, "no deployer privilege or freeze");
    }
}
