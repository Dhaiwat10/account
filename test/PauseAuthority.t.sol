// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./Base.t.sol";

contract PauseAuthorityTest is BaseTest {
    function testPauseUnauthorizedBeforeTimeoutReverts() public {
        vm.warp(0);
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        oc.pause(true);
    }

    function testPauseAuthorizedAfterTimeoutSucceeds() public {
        vm.warp(5 weeks);
        oc.pause(true);
        assertEq(oc.pauseFlag(), 1);
    }

    function testUnpauseUnauthorizedBeforeTimeoutReverts() public {
        vm.warp(5 weeks);
        oc.pause(true);
        // Attempt unpause by non-admin before timeout
        address notAdmin = address(uint160(uint256(keccak256("notAdmin"))));
        vm.prank(notAdmin);
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        oc.pause(false);
        // Still paused
        assertEq(oc.pauseFlag(), 1);
    }

    function testUnpauseAuthorizedByAdminSucceeds() public {
        vm.warp(5 weeks);
        oc.pause(true);
        // Unpause by admin (this test contract is admin by default via constructor)
        oc.pause(false);
        assertEq(oc.pauseFlag(), 0);
    }

    function testCannotRePauseBeforeTimeoutPlusBuffer() public {
        // First pause after sufficient time
        vm.warp(5 weeks);
        oc.pause(true);
        // Unpause
        oc.pause(false);
        // Try to pause again immediately (before PAUSE_TIMEOUT + 1 week from lastPaused)
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        oc.pause(true);
        // Advance just past the required window and pause should succeed
        vm.warp(block.timestamp + oc.PAUSE_TIMEOUT() + 1 weeks + 1);
        oc.pause(true);
        assertEq(oc.pauseFlag(), 1);
    }
    function testUnpauseByAnyoneAfterTimeoutSucceeds() public {
        vm.warp(5 weeks);
        oc.pause(true);
        // Advance past PAUSE_TIMEOUT (4 weeks) from lastPaused
        vm.warp(block.timestamp + oc.PAUSE_TIMEOUT() + 1);
        address anyone = address(uint160(uint256(keccak256("anyone"))));
        vm.prank(anyone);
        oc.pause(false);
        assertEq(oc.pauseFlag(), 0);
    }

    function testSetPauseAuthorityOnlyAdmin() public {
        // Unauthorized cannot set
        address newAdmin = address(uint160(uint256(keccak256("newAdmin"))));
        address rando = address(uint160(uint256(keccak256("rando"))));
        vm.prank(rando);
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        oc.setPauseAuthority(newAdmin);

        // Admin can set
        oc.setPauseAuthority(newAdmin);
        (address admin,) = oc.getPauseConfig();
        assertEq(admin, newAdmin);
    }
}


