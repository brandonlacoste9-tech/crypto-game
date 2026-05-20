// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SwarmNFT
 * @notice ERC-721 representing a deployed Swarm. Each NFT is bound to an ERC-6551
 *         Token-Bound Account that holds the swarm's assets, agents, and vault.
 * @dev Phase 1 — Settlement Layer core ID primitive.
 */
contract SwarmNFT is ERC721, AccessControl, ReentrancyGuard {
    // ── Roles ─────────────────────────────────────────────────────────────────
    
    bytes32 public constant ARCHITECT_ROLE = keccak256("ARCHITECT_ROLE");
    bytes32 public constant TREASURER_ROLE = keccak256("TREASURER_ROLE");
    
    // ── State ─────────────────────────────────────────────────────────────────
    
    /// @notice ERC-6551 registry contract
    address public immutable tokenBoundRegistry;
    
    /// @notice ERC-6551 account implementation
    address public immutable accountImplementation;
    
    /// @notice Swarm ID counter
    uint256 private _swarmIdCounter;
    
    /// @notice Mapping from swarm ID to its token-bound account address
    mapping(uint256 => address) public swarmAccount;
    
    /// @notice Mapping from swarm ID to its architect (owner/commander)
    mapping(uint256 => address) public swarmArchitect;
    
    /// @notice Swarm metadata: name, strategy, active agents
    struct SwarmConfig {
        string name;
        uint8 scoutLevel;
        uint8 builderLevel;
        uint8 closerLevel;
        uint8 treasurerLevel;
        uint256 energyBalance;
        uint256 computeBalance;
        uint256 dataBalance;
    }
    
    mapping(uint256 => SwarmConfig) public swarmConfigs;
    
    // ── Events ────────────────────────────────────────────────────────────────
    
    event SwarmDeployed(uint256 indexed swarmId, address indexed architect, address account);
    event SwarmAccountCreated(uint256 indexed swarmId, address account);
    event TreasurerAuthorized(uint256 indexed swarmId, address treasurer);
    
    // ── Constructor ───────────────────────────────────────────────────────────
    
    constructor(
        address _tokenBoundRegistry,
        address _accountImplementation
    ) ERC721("Aether-War Swarm", "SWARM") {
        require(_tokenBoundRegistry != address(0), "Invalid registry");
        require(_accountImplementation != address(0), "Invalid implementation");
        
        tokenBoundRegistry = _tokenBoundRegistry;
        accountImplementation = _accountImplementation;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
    
    // ── Swarm Deployment ──────────────────────────────────────────────────────
    
    /**
     * @notice Deploy a new Swarm. Mints NFT, creates ERC-6551 account, assigns architect.
     * @param name Human-readable swarm identifier
     */
    function deploySwarm(string memory name) external returns (uint256 swarmId) {
        swarmId = ++_swarmIdCounter;
        
        // Mint the NFT
        _safeMint(msg.sender, swarmId);
        
        // Create ERC-6551 token-bound account
        bytes memory initData = abi.encodeWithSignature("initialize(address,uint256)", msg.sender, swarmId);
        
        address account = IERC6551Registry(tokenBoundRegistry).createAccount(
            accountImplementation,
            block.chainid,
            address(this),
            swarmId,
            0, // salt
            initData
        );
        
        swarmAccount[swarmId] = account;
        swarmArchitect[swarmId] = msg.sender;
        
        // Initialize swarm config
        swarmConfigs[swarmId] = SwarmConfig({
            name: name,
            scoutLevel: 1,
            builderLevel: 1,
            closerLevel: 1,
            treasurerLevel: 1,
            energyBalance: 100 ether,
            computeBalance: 10 ether,
            dataBalance: 0
        });
        
        // Grant architect role
        _grantRole(ARCHITECT_ROLE, msg.sender);
        
        emit SwarmDeployed(swarmId, msg.sender, account);
    }
    
    // ── Treasurer Authorization ──────────────────────────────────────────────
    
    /**
     * @notice Authorize a treasurer address to manage this swarm's vault
     * @param swarmId The swarm to authorize for
     * @param treasurer The treasurer agent address
     */
    function authorizeTreasurer(uint256 swarmId, address treasurer) external {
        require(msg.sender == swarmArchitect[swarmId], "Only Architect");
        require(treasurer != address(0), "Zero address");
        
        // Grant treasurer role to the address
        _grantRole(TREASURER_ROLE, treasurer);
        
        // Delegate authority on the ERC-6551 account
        ISwarmAccount(swarmAccount[swarmId]).setExecutor(treasurer, true);
        
        emit TreasurerAuthorized(swarmId, treasurer);
    }
    
    /**
     * @notice Revoke treasurer authorization
     */
    function revokeTreasurer(uint256 swarmId, address treasurer) external {
        require(msg.sender == swarmArchitect[swarmId], "Only Architect");
        _revokeRole(TREASURER_ROLE, treasurer);
        ISwarmAccount(swarmAccount[swarmId]).setExecutor(treasurer, false);
    }
    
    // ── Queries ───────────────────────────────────────────────────────────────
    
    function getSwarmAccount(uint256 swarmId) external view returns (address) {
        return swarmAccount[swarmId];
    }
    
    function getSwarmConfig(uint256 swarmId) external view returns (SwarmConfig memory) {
        return swarmConfigs[swarmId];
    }
    
    function totalSwarms() external view returns (uint256) {
        return _swarmIdCounter;
    }
    
    // ── Required overrides ────────────────────────────────────────────────────
    
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}

// ── Interfaces ──────────────────────────────────────────────────────────────

interface IERC6551Registry {
    function createAccount(
        address implementation,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId,
        uint256 salt,
        bytes calldata initData
    ) external returns (address);
}

interface ISwarmAccount {
    function initialize(address architect, uint256 swarmId) external;
    function setExecutor(address executor, bool authorized) external;
    function execute(address target, uint256 value, bytes calldata data) external returns (bytes memory);
}
