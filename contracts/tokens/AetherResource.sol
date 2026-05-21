// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title AetherResource
 * @notice Base ERC-20 for the three Aether-War resources: Energy, Compute, Data.
 *         Gas-optimized with permit support, decay mechanics, and capped supply.
 * @dev Phase 1 — Settlement Layer token standard.
 */
contract AetherResource is ERC20, ERC20Permit, Ownable {
    // ── State ─────────────────────────────────────────────────────────────────
    
    /// @notice Physics Engine address — only this contract can mint/burn resources
    address public physicsEngine;
    
    /// @notice Maximum total supply for this resource
    uint256 public immutable maxSupply;
    
    /// @notice Decay rate per epoch (basis points, 100 = 1%)
    uint16 public decayRateBPS;
    
    /// @notice Last epoch timestamp for decay calculation
    uint256 public lastDecayEpoch;
    
    /// @notice Epoch duration in seconds
    uint256 public constant EPOCH_DURATION = 1 hours;
    
    // ── Events ────────────────────────────────────────────────────────────────
    
    event PhysicsEngineUpdated(address indexed newEngine);
    event DecayApplied(uint256 epoch, uint256 amountBurned);
    event ResourceMinted(address indexed to, uint256 amount);
    event ResourceBurned(address indexed from, uint256 amount);
    
    // ── Constructor ───────────────────────────────────────────────────────────
    
    constructor(
        string memory name,
        string memory symbol,
        uint256 _maxSupply,
        uint16 _decayRateBPS,
        address _physicsEngine
    ) ERC20(name, symbol) ERC20Permit(name) Ownable(msg.sender) {
        require(_decayRateBPS <= 10000, "Decay rate must be <= 100%");
        maxSupply = _maxSupply;
        decayRateBPS = _decayRateBPS;
        physicsEngine = _physicsEngine;
        lastDecayEpoch = block.timestamp;
    }
    
    // ── Modifiers ─────────────────────────────────────────────────────────────
    
    modifier onlyPhysicsEngine() {
        require(msg.sender == physicsEngine, "Only Physics Engine");
        _;
    }
    
    // ── Admin ─────────────────────────────────────────────────────────────────
    
    function setPhysicsEngine(address _engine) external onlyOwner {
        require(_engine != address(0), "Zero address");
        physicsEngine = _engine;
        emit PhysicsEngineUpdated(_engine);
    }
    
    function setDecayRate(uint16 _rateBPS) external onlyOwner {
        require(_rateBPS <= 10000, "Max 100%");
        decayRateBPS = _rateBPS;
    }
    
    // ── Minting (Physics Engine only) ─────────────────────────────────────────
    
    function mint(address to, uint256 amount) external onlyPhysicsEngine {
        require(totalSupply() + amount <= maxSupply, "Exceeds max supply");
        _mint(to, amount);
        emit ResourceMinted(to, amount);
    }
    
    function burn(address from, uint256 amount) external onlyPhysicsEngine {
        _burn(from, amount);
        emit ResourceBurned(from, amount);
    }
    
    // ── Decay Logic ───────────────────────────────────────────────────────────
    
    /**
     * @notice Apply decay to all non-vault holders. Called by Physics Engine each epoch.
     *         Decays a percentage of each holder's balance.
     */
    function applyDecay() external onlyPhysicsEngine returns (uint256 burned) {
        uint256 epochs = (block.timestamp - lastDecayEpoch) / EPOCH_DURATION;
        if (epochs == 0) return 0;
        
        lastDecayEpoch = block.timestamp;
        
        // Decay is applied per-account by the Physics Engine via burn()
        // This contract tracks the epoch for coordination
        emit DecayApplied(lastDecayEpoch, 0);
        return epochs;
    }
    
    /**
     * @notice Calculate the decay amount for a given balance
     */
    function calculateDecay(uint256 balance) public view returns (uint256) {
        return (balance * decayRateBPS) / 10000;
    }
}
