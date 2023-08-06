// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {WorldIDBridge} from "./abstract/WorldIDBridge.sol";
import {FxBaseChildTunnel} from "fx-portal/contracts/tunnel/FxBaseChildTunnel.sol";
import {Ownable2Step} from "openzeppelin-contracts/access/Ownable2Step.sol";
import {SemaphoreTreeDepthValidator} from "./utils/SemaphoreTreeDepthValidator.sol";
import {SemaphoreVerifier} from "semaphore/base/SemaphoreVerifier.sol";
import {BytesUtils} from "./utils/BytesUtils.sol";

/// @title Polygon WorldID Bridge
/// @author Worldcoin
/// @notice A contract that manages the root history of the WorldID merkle root on Polygon PoS.
/// @dev This contract is deployed on Polygon PoS and is called by the StateBridge contract for each
///      new root insertion.
contract PolygonWorldID is WorldIDBridge, FxBaseChildTunnel, Ownable2Step {
    ///////////////////////////////////////////////////////////////////
    ///                           STORAGE                           ///
    ///////////////////////////////////////////////////////////////////

    /// @notice The selector of the `receiveRoot` function.
    /// @dev this selector is precomputed in the constructor to not have to recompute them for every
    /// call of the _processMesageFromRoot function
    bytes4 private receiveRootSelector;

    /// @notice The selector of the `receiveRootHistoryExpiry` function.
    /// @dev this selector is precomputed in the constructor to not have to recompute them for every
    /// call of the _processMesageFromRoot function
    bytes4 private receiveRootHistoryExpirySelector;

    ///////////////////////////////////////////////////////////////////
    ///                            ERRORS                           ///
    ///////////////////////////////////////////////////////////////////

    /// @notice Thrown when the message selector passed from FxRoot is invalid.
    error InvalidMessageSelector(bytes4 selector);

    /// @notice Thrown when an attempt is made to renounce ownership.
    error CannotRenounceOwnership();

    ///////////////////////////////////////////////////////////////////////////////
    ///                                CONSTRUCTION                             ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Initializes the contract's storage variables with the correct parameters
    ///
    /// @param _treeDepth The depth of the WorldID Identity Manager merkle tree.
    /// @param _fxChild The address of the FxChild tunnel - the contract that will receive messages on Polygon
    /// and Broadcasts them to FxPortal which bridges the messages to Ethereum
    constructor(uint8 _treeDepth, address _fxChild)
        FxBaseChildTunnel(_fxChild)
    {
        receiveRootSelector = bytes4(keccak256("receiveRoot(uint256,uint128)"));
        receiveRootHistoryExpirySelector = bytes4(keccak256("setRootHistoryExpiry(uint256)"));
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                               ROOT MIRRORING                            ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice An internal function used to receive messages from the StateBridge contract.
    /// @dev Calls `receiveRoot` upon receiving a message from the StateBridge contract via the
    ///      FxChildTunnel. Can revert if the message is not valid - decoding fails.
    ///      Can not work if Polygon's StateSync mechanism breaks and FxPortal does not receive the message
    ///      on the other end.
    ///
    /// @custom:param uint256 stateId An unused placeholder variable for `stateId`,
    /// required by the signature in fxChild.
    /// @param sender The sender of the message.
    /// @param message An ABI-encoded tuple of `(uint256 newRoot, uint128 supersedeTimestamp)` that
    ///        is used to call `receiveRoot`.
    ///
    /// @custom:reverts string If the sender is not valid.
    /// @custom:reverts EvmError If the provided `message` does not match the expected format.
    function _processMessageFromRoot(uint256, address sender, bytes memory message)
        internal
        override
        validateSender(sender)
    {
        bytes4 selector = bytes4(BytesUtils.substring(message, 0, 4));
        bytes memory payload = BytesUtils.substring(message, 4, message.length - 4);

        if (selector == receiveRootSelector) {
            (uint256 root, uint128 timestamp) = abi.decode(payload, (uint256, uint128));
            _receiveRoot(root, timestamp);
        } else if (selector == receiveRootHistoryExpirySelector) {
            uint256 rootHistoryExpiry = abi.decode(payload, (uint256));
            _setRootHistoryExpiry(rootHistoryExpiry);
        } else {
            revert InvalidMessageSelector(selector);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                              DATA MANAGEMENT                            ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Placeholder to satisfy WorldIDBridge inheritance
    /// @dev This function is not used on Polygon PoS because of FxPortal message passing architecture
    function setRootHistoryExpiry(uint256) public virtual override {
        revert("PolygonWorldID: Root history expiry should only be set via the state bridge");
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                             TUNNEL MANAGEMENT                           ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Sets the `fxRootTunnel` address if not already set.
    /// @dev This implementation replicates the logic from `FxBaseChildTunnel` due to the inability
    ///      to call `external` superclass methods when overriding them.
    ///
    /// @param _fxRootTunnel The address of the root (L1) tunnel contract.
    ///
    /// @custom:reverts string If the root tunnel has already been set.
    function setFxRootTunnel(address _fxRootTunnel) external virtual override onlyOwner {
        require(fxRootTunnel == address(0x0), "FxBaseChildTunnel: ROOT_TUNNEL_ALREADY_SET");
        fxRootTunnel = _fxRootTunnel;
    }

    ///////////////////////////////////////////////////////////////////
    ///                          OWNERSHIP                          ///
    ///////////////////////////////////////////////////////////////////
    /// @notice Ensures that ownership of WorldID implementations cannot be renounced.
    /// @dev This function is intentionally not `virtual` as we do not want it to be possible to
    ///      renounce ownership for any WorldID implementation.
    /// @dev This function is marked as `onlyOwner` to maintain the access restriction from the base
    ///      contract.
    function renounceOwnership() public view override onlyOwner {
        revert CannotRenounceOwnership();
    }
}
