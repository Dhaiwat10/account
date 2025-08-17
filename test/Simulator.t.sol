// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./Base.t.sol";
import {FixedPointMathLib as Math} from "solady/utils/FixedPointMathLib.sol";

contract SimulatorUnitTest is BaseTest {
    function test_eip712Domain() public {
        (bytes1 fields, string memory name, string memory version, uint256 chainId,
            address verifyingContract, bytes32 salt, uint256[] memory extensions) = simulator.eip712Domain();

        assertEq(uint8(fields), uint8(0x0f));
        assertEq(name, "Simulator");
        assertEq(version, "0.0.1");
        assertEq(chainId, block.chainid);
        assertEq(verifyingContract, address(simulator));
        assertEq(salt, bytes32(0));
        assertEq(extensions.length, 0);
    }

    function test_simulateCombinedGas_loop_PaymentError() public {
        DelegatedEOA memory d = _randomEIP7702DelegatedEOA();

        // No funds for payer; primary run uses prePayment=0 and succeeds, loop then fails.
        bytes memory execData = _thisTargetFunctionExecutionData(0, abi.encode("ok"));

        Orchestrator.Intent memory i;
        i.eoa = d.eoa;
        i.nonce = 0;
        i.executionData = execData;
        i.payer = address(0);
        i.paymentToken = address(paymentToken);
        i.paymentRecipient = address(0);
        i.prePaymentAmount = 0;
        i.prePaymentMaxAmount = 1e24; // large cap, avoid overflow in updates
        i.totalPaymentAmount = 0;
        i.totalPaymentMaxAmount = 1e24; // large cap, avoid overflow in updates
        i.combinedGas = 20_000;

        {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint128(_randomUniform()), bytes32(_randomUniform()));
            i.signature = abi.encodePacked(r, s, v);
        }

        // As soon as the loop adds payment for combinedGas, balance (0) is insufficient.
        vm.expectRevert(bytes4(keccak256("PaymentError()")));
        simulator.simulateCombinedGas(address(oc), true, 0, 1, 11_000, abi.encode(i));
    }

    function test_simulateV1Logs_verificationRun_bubbles_StateOverrideError() public {
        DelegatedEOA memory d = _randomEIP7702DelegatedEOA();

        // Fund payer generously so primary simulation passes.
        paymentToken.mint(d.eoa, type(uint128).max);

        bytes memory execData = _thisTargetFunctionExecutionData(0, abi.encode("ok"));

        Orchestrator.Intent memory i;
        i.eoa = d.eoa;
        i.nonce = 0;
        i.executionData = execData;
        i.payer = address(0);
        i.paymentToken = address(paymentToken);
        i.paymentRecipient = address(0);
        i.prePaymentAmount = 0;
        i.prePaymentMaxAmount = 1e24; // large cap, avoid overflow in updates
        i.totalPaymentAmount = 0;
        i.totalPaymentMaxAmount = 1e24; // large cap, avoid overflow in updates
        i.combinedGas = 20_000;

        {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint128(_randomUniform()), bytes32(_randomUniform()));
            i.signature = abi.encodePacked(r, s, v);
        }

        // Do NOT set tx.origin balance to max; verification run should revert with StateOverrideError.
        vm.expectRevert(bytes4(keccak256("StateOverrideError()")));
        simulator.simulateV1Logs(address(oc), true, 0, 1, 11_000, 0, abi.encode(i));

        // Now set tx.origin balance to max and ensure verification run succeeds
        uint256 snapshot = vm.snapshotState();
        vm.deal(_ORIGIN_ADDRESS, type(uint192).max);
        uint256 feePrecision = 0;
        uint256 feePerGas = 1;
        (uint256 gUsed, uint256 combinedGas) = simulator.simulateV1Logs(
            address(oc), true, uint8(feePrecision), feePerGas, 11_000, 0, abi.encode(i)
        );
        assertGt(gUsed, 0);
        assertGt(combinedGas, 0);
        vm.revertToStateAndDelete(snapshot);
    }
    function test_simulateGasUsed_success() public {
        DelegatedEOA memory d = _randomEIP7702DelegatedEOA();

        // Ensure there is no pre-payment to avoid funding requirements for this test.
        bytes memory execData = _thisTargetFunctionExecutionData(0, abi.encode("ok"));

        Orchestrator.Intent memory i;
        i.eoa = d.eoa;
        i.nonce = 0;
        i.executionData = execData;
        i.payer = address(0);
        i.paymentToken = address(paymentToken);
        i.paymentRecipient = address(0);
        i.prePaymentAmount = 0;
        i.prePaymentMaxAmount = 0;
        i.totalPaymentAmount = 0;
        i.totalPaymentMaxAmount = 0;
        i.combinedGas = 20_000;

        // Junk signature is fine; simulate path sets isValid = true.
        {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint128(_randomUniform()), bytes32(_randomUniform()));
            i.signature = abi.encodePacked(r, s, v);
        }

        // Use max combinedGas override to allow verification/code paths to run with ample gas.
        uint256 gUsed = simulator.simulateGasUsed(address(oc), true, abi.encode(i));
        assertGt(gUsed, 0);
    }

    function test_simulateGasUsed_bubbles_PaymentError() public {
        DelegatedEOA memory d = _randomEIP7702DelegatedEOA();

        bytes memory execData = _thisTargetFunctionExecutionData(0, abi.encode("ok"));

        Orchestrator.Intent memory i;
        i.eoa = d.eoa;
        i.nonce = 0;
        i.executionData = execData;
        i.payer = address(0);
        i.paymentToken = address(paymentToken);
        i.paymentRecipient = address(0);
        // Request some pre-payment but do not fund the payer.
        i.prePaymentAmount = 1;
        i.prePaymentMaxAmount = 1;
        i.totalPaymentAmount = 1;
        i.totalPaymentMaxAmount = 1;
        i.combinedGas = 20_000;

        {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint128(_randomUniform()), bytes32(_randomUniform()));
            i.signature = abi.encodePacked(r, s, v);
        }

        vm.expectRevert(bytes4(keccak256("PaymentError()")));
        simulator.simulateGasUsed(address(oc), false, abi.encode(i));
    }

    function test_simulateCombinedGas_primaryRunFailure_bubbles() public {
        DelegatedEOA memory d = _randomEIP7702DelegatedEOA();

        bytes memory execData = _thisTargetFunctionExecutionData(0, abi.encode("ok"));

        Orchestrator.Intent memory i;
        i.eoa = d.eoa;
        i.nonce = 0;
        i.executionData = execData;
        i.payer = address(0);
        i.paymentToken = address(paymentToken);
        i.paymentRecipient = address(0);
        // Underfunded: pre-payment required but payer has zero balance.
        i.prePaymentAmount = 1;
        i.prePaymentMaxAmount = 1;
        i.totalPaymentAmount = 1;
        i.totalPaymentMaxAmount = 1;
        i.combinedGas = 20_000;

        {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint128(_randomUniform()), bytes32(_randomUniform()));
            i.signature = abi.encodePacked(r, s, v);
        }

        vm.expectRevert(bytes4(keccak256("PaymentError()")));
        simulator.simulateCombinedGas(address(oc), true, 0, 1, 11_000, abi.encode(i));
    }
}


