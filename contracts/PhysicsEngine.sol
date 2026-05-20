// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../tokens/AetherResource.sol";
import "../intents/IntentMarket.sol";

/**
 * @title PhysicsEngine
 * @notice The L3 ECS-like state machine. Manages resource generation, decay,
 *         claims, sector ownership, and tick processing.
 * @dev Phase 2 — The "world tick" that drives all game mechanics.
 */
contract PhysicsEngine is AccessControl, ReentrancyGuard {
    // ── Roles ─────────────────────────────────────────────────────────────────
    
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    
    // ── Constants ─────────────────────────────────────────────────────────────
    
    uint256 public constant TICK_INTERVAL = 1 hours;
    uint256 public constant MAX_SECTORS = 1000;
    uint256 public constant BASE_ENERGY_RATE = 10 ether;     // Per sector per tick
    uint256 public constant BASE_COMPUTE_RATE = 1 ether;
    uint256 public constant BASE_DATA_RATE = 0.1 ether;
    
    // ── Sector State ──────────────────────────────────────────────────────────
    
    struct Sector {
        uint256 id;
        address owner;          // Swarm account that owns this sector
        uint256 energyRate;     // Energy generated per tick
        uint256 computeRate;    // Compute generated per tick
        uint256 dataRate;       // Data generated per tick
        uint256 lastClaimed;    // Last tick this sector was claimed
        uint8 level;            // Upgrade level (1-10)
        bool active;
    }
    
    mapping(uint256 => Sector) public sectors;
    uint256 public sectorCount;
    
    // ── Resource Tokens ───────────────────────────────────────────────────────
    
    AetherResource public immutable energy;
    AetherResource public immutable compute;
    AetherResource public immutable data;
    
    // ── Intent Market ─────────────────────────────────────────────────────────
    
    IntentMarket public immutable intentMarket;
    
    // ── Tick Tracking ─────────────────────────────────────────────────────────
    
    uint256 public lastTickTimestamp;
    uint256 public tickCount;
    
    // ── Events ────────────────────────────────────────────────────────────────
    
    event SectorClaimed(uint256 indexed sectorId, address indexed owner);
    event SectorUpgraded(uint256 indexed sectorId, uint8 newLevel);
    event TickProcessed(uint256 tickNumber, uint256 sectorsClaimed);
    event ResourcesGenerated(uint256 indexed sectorId, uint256 energy, uint256 compute, uint256 data);
    
    // ── Constructor ───────────────────────────────────────────────────────────
    
    constructor(
        address _energy,
        address _compute,
        address _data,
        address _intentMarket
    ) {
        energy = AetherResource(_energy);
        compute = AetherResource(_compute);
        data = AetherResource(_data);
        intentMarket = IntentMarket(_intentMarket);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(KEEPER_ROLE, msg.sender);
        
        lastTickTimestamp = block.timestamp;
        sectorCount = 100; // Pre-generate 100 sectors
        
        // Initialize sectors
        for (uint256 i = 1; i <= 100; i++) {
            sectors[i] = Sector({
                id: i,
                owner: address(0),
                energyRate: BASE_ENERGY_RATE + (i % 5) * 1 ether,
                computeRate: BASE_COMPUTE_RATE + (i % 3) * 0.5 ether,
                dataRate: BASE_DATA_RATE + (i % 10) * 0.05 ether,
                lastClaimed: 0,
                level: 1,
                active: true
            });
        }
    }
    
    // ── Sector Management ─────────────────────────────────────────────────────
    
    /**
     * @notice Claim an unowned sector for a swarm account
     */
    function claimSector(uint256 sectorId, address swarmAccount) external nonReentrant {
        Sector storage sector = sectors[sectorId];
        require(sector.active, "Sector not active");
        require(sector.owner == address(0), "Sector already claimed");
        require(swarmAccount != address(0), "Zero address");
        
        // Burn compute as claim cost
        compute.burn(msg.sender, 5 ether);
        
        sector.owner = swarmAccount;
        sector.lastClaimed = block.timestamp;
        
        emit SectorClaimed(sectorId, swarmAccount);
    }
    
    /**
     * @notice Abandon a sector (releases it for others)
     */
    function abandonSector(uint256 sectorId) external {
        Sector storage sector = sectors[sectorId];
        require(sector.owner == msg.sender, "Not owner");
        sector.owner = address(0);
        sector.level = 1;
    }
    
    /**
     * @notice Upgrade a sector — increases resource generation rates
     */
    function upgradeSector(uint256 sectorId) external {
        Sector storage sector = sectors[sectorId];
        require(sector.owner == msg.sender, "Not owner");
        require(sector.level < 10, "Max level");
        
        uint256 upgradeCost = sector.level * 10 ether; // 10, 20, 30... compute
        compute.burn(msg.sender, upgradeCost);
        
        sector.level++;
        sector.energyRate = BASE_ENERGY_RATE * sector.level;
        sector.computeRate = BASE_COMPUTE_RATE * sector.level;
        sector.dataRate = BASE_DATA_RATE * sector.level;
        
        emit SectorUpgraded(sectorId, sector.level);
    }
    
    // ── Tick Processing ───────────────────────────────────────────────────────
    
    /**
     * @notice Process the world tick. Called by keepers each hour.
     *         Generates resources for all claimed sectors, applies decay.
     */
    function processTick() external onlyRole(KEEPER_ROLE) nonReentrant {
        require(block.timestamp >= lastTickTimestamp + TICK_INTERVAL, "Too early");
        
        uint256 sectorsProcessed = 0;
        
        for (uint256 i = 1; i <= sectorCount; i++) {
            Sector storage sector = sectors[i];
            if (sector.owner == address(0)) continue;
            
            // Calculate resources generated since last claim
            uint256 ticks = (block.timestamp - lastTickTimestamp) / TICK_INTERVAL;
            if (ticks == 0) ticks = 1;
            
            uint256 energyGen = sector.energyRate * ticks;
            uint256 computeGen = sector.computeRate * ticks;
            uint256 dataGen = sector.dataRate * ticks;
            
            // Mint resources to sector owner
            if (energyGen > 0) {
                try energy.mint(sector.owner, energyGen) {} catch {}
            }
            if (computeGen > 0) {
                try compute.mint(sector.owner, computeGen) {} catch {}
            }
            if (dataGen > 0) {
                try data.mint(sector.owner, dataGen) {} catch {}
            }
            
            sector.lastClaimed = block.timestamp;
            sectorsProcessed++;
            
            emit ResourcesGenerated(i, energyGen, computeGen, dataGen);
        }
        
        // Apply decay to all resource holders
        energy.applyDecay();
        compute.applyDecay();
        data.applyDecay();
        
        lastTickTimestamp = block.timestamp;
        tickCount++;
        
        emit TickProcessed(tickCount, sectorsProcessed);
    }
    
    // ── Queries ───────────────────────────────────────────────────────────────
    
    function getSector(uint256 sectorId) external view returns (Sector memory) {
        return sectors[sectorId];
    }
    
    function getSectorYield(uint256 sectorId) external view returns (uint256 energyYield, uint256 computeYield, uint256 dataYield) {
        Sector storage sector = sectors[sectorId];
        return (sector.energyRate, sector.computeRate, sector.dataRate);
    }
    
    function getActiveSectors() external view returns (Sector[] memory) {
        uint256 count = 0;
        for (uint256 i = 1; i <= sectorCount; i++) {
            if (sectors[i].active) count++;
        }
        
        Sector[] memory active = new Sector[](count);
        uint256 idx = 0;
        for (uint256 i = 1; i <= sectorCount; i++) {
            if (sectors[i].active) {
                active[idx++] = sectors[i];
            }
        }
        return active;
    }
    
    function getWorldState() external view returns (
        uint256 _tickCount,
        uint256 _lastTick,
        uint256 _sectorCount,
        uint256 _energySupply,
        uint256 _computeSupply,
        uint256 _dataSupply
    ) {
        return (
            tickCount,
            lastTickTimestamp,
            sectorCount,
            energy.totalSupply(),
            compute.totalSupply(),
            data.totalSupply()
        );
    }
}
