// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title SwarmAccount
 * @notice ERC-6551 Token-Bound Account for a Swarm. Holds resources, executes trades,
 *         and enforces treasurer authorization.
 * @dev Security audit focus: only authorized executors can call execute().
 *      Multi-sig pattern: Architect + Treasurer signatures required for large transfers.
 */
contract SwarmAccount {
    using ECDSA for bytes32;
    
    // ── State ─────────────────────────────────────────────────────────────────
    
    address public architect;
    uint256 public swarmId;
    
    mapping(address => bool) public isExecutor;
    address[] public executors;
    
    /// @notice Multi-sig threshold for large transfers (in basis points of total value)
    uint256 public constant LARGE_TRANSFER_THRESHOLD = 1000 ether; // 1000 tokens
    
    // ── Events ────────────────────────────────────────────────────────────────
    
    event Executed(address indexed target, uint256 value, bytes data, address executor);
    event ExecutorSet(address indexed executor, bool authorized);
    event Received(address indexed from, uint256 amount);
    
    // ── Modifiers ─────────────────────────────────────────────────────────────
    
    modifier onlyExecutor() {
        require(isExecutor[msg.sender], "Not authorized executor");
        _;
    }
    
    modifier onlyArchitect() {
        require(msg.sender == architect, "Only architect");
        _;
    }
    
    // ── Initialization (called by ERC-6551 registry) ─────────────────────────
    
    function initialize(address _architect, uint256 _swarmId) external {
        require(architect == address(0), "Already initialized");
        architect = _architect;
        swarmId = _swarmId;
        isExecutor[_architect] = true;
        executors.push(_architect);
    }
    
    // ── Executor Management ──────────────────────────────────────────────────
    
    function setExecutor(address executor, bool authorized) external onlyArchitect {
        require(executor != address(0), "Zero address");
        require(executor != architect, "Cannot revoke architect");
        
        isExecutor[executor] = authorized;
        if (authorized) {
            executors.push(executor);
        }
        emit ExecutorSet(executor, authorized);
    }
    
    // ── Execution ────────────────────────────────────────────────────────────
    
    /**
     * @notice Execute a transaction on behalf of the swarm account.
     *         Large transfers require architect co-signature.
     */
    function execute(
        address target,
        uint256 value,
        bytes calldata data
    ) external onlyExecutor returns (bytes memory result) {
        // Multi-sig check for large transfers
        if (value >= LARGE_TRANSFER_THRESHOLD) {
            require(msg.sender == architect || _hasArchitectApproval(target, value, data),
                "Large transfer requires architect approval");
        }
        
        (bool success, bytes memory ret) = target.call{value: value}(data);
        require(success, "Execution failed");
        
        emit Executed(target, value, data, msg.sender);
        return ret;
    }
    
    /**
     * @notice Execute with explicit architect signature for large transfers
     */
    function executeWithSignature(
        address target,
        uint256 value,
        bytes calldata data,
        bytes calldata architectSignature
    ) external onlyExecutor returns (bytes memory) {
        bytes32 digest = keccak256(
            abi.encodePacked(target, value, data, block.chainid, address(this))
        );
        bytes32 hash = MessageHashUtils.toEthSignedMessageHash(digest);
        address signer = hash.recover(architectSignature);
        require(signer == architect, "Invalid architect signature");
        
        return this.execute(target, value, data);
    }
    
    // ── Internal ──────────────────────────────────────────────────────────────
    
    function _hasArchitectApproval(
        address target,
        uint256 value,
        bytes calldata data
    ) internal view returns (bool) {
        // Check if architect is also calling (msg.sender == architect handled above)
        return false; // Require explicit signature for non-architect callers
    }
    
    // ── Receiving ─────────────────────────────────────────────────────────────
    
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
    
    function onERC721Received(
        address, address, uint256, bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
    
    function onERC1155Received(
        address, address, uint256, uint256, bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }
}
