// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title IntentMarket
 * @notice ERC-7521-compatible RFQ (Request for Quote) system for agent-to-agent
 *         resource trading. Swarm agents broadcast intents; solvers execute matches.
 * @dev Phase 1+5 — Settlement Layer intent coordination.
 */
contract IntentMarket is ReentrancyGuard {
    // ── Types ─────────────────────────────────────────────────────────────────
    
    enum IntentStatus { Open, PartiallyFilled, Filled, Cancelled, Expired }
    enum IntentType { Buy, Sell }
    
    struct Intent {
        uint256 id;
        address creator;        // Swarm account that created this intent
        IntentType intentType;
        address tokenIn;        // Token being offered (sell) or wanted (buy)
        address tokenOut;       // Token being received (buy) or wanted (sell)
        uint256 amountIn;
        uint256 amountOut;
        uint256 minFill;        // Minimum fill amount to prevent dust
        uint256 deadline;       // Block timestamp after which intent expires
        IntentStatus status;
        bytes extraData;        // For future extensions (solver hints, routes)
    }
    
    struct Quote {
        uint256 intentId;
        address solver;         // Counterparty swarm account
        uint256 fillAmount;
        uint256 receiveAmount;
        bool accepted;
    }
    
    // ── State ─────────────────────────────────────────────────────────────────
    
    uint256 private _intentCounter;
    mapping(uint256 => Intent) public intents;
    mapping(uint256 => Quote[]) public quotes;
    
    address public physicsEngine;
    
    // ── Events ────────────────────────────────────────────────────────────────
    
    event IntentCreated(uint256 indexed id, address creator, IntentType intentType, uint256 amountIn, uint256 amountOut);
    event IntentCancelled(uint256 indexed id);
    event IntentFilled(uint256 indexed id, address solver, uint256 fillAmount, uint256 receiveAmount);
    event QuoteSubmitted(uint256 indexed intentId, address solver, uint256 fillAmount);
    event IntentExpired(uint256 indexed id);
    
    // ── Modifiers ─────────────────────────────────────────────────────────────
    
    modifier onlyPhysicsEngine() {
        require(msg.sender == physicsEngine, "Only Physics Engine");
        _;
    }
    
    modifier intentActive(uint256 intentId) {
        Intent storage intent = intents[intentId];
        require(intent.status == IntentStatus.Open || intent.status == IntentStatus.PartiallyFilled, "Intent not active");
        require(block.timestamp <= intent.deadline, "Intent expired");
        _;
    }
    
    // ── Constructor ───────────────────────────────────────────────────────────
    
    constructor(address _physicsEngine) {
        physicsEngine = _physicsEngine;
    }
    
    // ── Intent Creation ──────────────────────────────────────────────────────
    
    /**
     * @notice Create a new trading intent. Called by swarm agents via their account.
     * @param intentType Buy or Sell
     * @param tokenIn Token being offered/wanted
     * @param tokenOut Token being received/wanted
     * @param amountIn Amount of tokenIn
     * @param amountOut Desired amount of tokenOut
     * @param deadline Seconds from now until intent expires
     */
    function createIntent(
        IntentType intentType,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 deadline
    ) external returns (uint256 intentId) {
        require(amountIn > 0, "Zero amount");
        require(amountIn >= amountOut / 100, "Spam prevention"); // min 1% out/in ratio
        require(deadline <= 7 days, "Max 7 day deadline");
        
        intentId = ++_intentCounter;
        
        intents[intentId] = Intent({
            id: intentId,
            creator: msg.sender,
            intentType: intentType,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            amountOut: amountOut,
            minFill: amountIn / 100, // 1% minimum fill
            deadline: block.timestamp + deadline,
            status: IntentStatus.Open,
            extraData: ""
        });
        
        emit IntentCreated(intentId, msg.sender, intentType, amountIn, amountOut);
    }
    
    // ── Quote Submission ─────────────────────────────────────────────────────
    
    /**
     * @notice A solver submits a quote against an open intent
     */
    function submitQuote(
        uint256 intentId,
        uint256 fillAmount,
        uint256 receiveAmount
    ) external intentActive(intentId) {
        Intent storage intent = intents[intentId];
        require(fillAmount >= intent.minFill, "Below minimum fill");
        require(fillAmount <= intent.amountIn, "Exceeds intent amount");
        
        // If buying: solver sends tokenOut, receives tokenIn
        // If selling: solver sends tokenIn, receives tokenOut
        uint256 remainingAmount = _getRemainingAmount(intentId);
        require(fillAmount <= remainingAmount, "Exceeds remaining");
        
        quotes[intentId].push(Quote({
            intentId: intentId,
            solver: msg.sender,
            fillAmount: fillAmount,
            receiveAmount: receiveAmount,
            accepted: false
        }));
        
        emit QuoteSubmitted(intentId, msg.sender, fillAmount);
    }
    
    // ── Intent Execution ─────────────────────────────────────────────────────
    
    /**
     * @notice Accept a quote and execute the trade atomically
     */
    function acceptQuote(uint256 intentId, uint256 quoteIndex) external nonReentrant intentActive(intentId) {
        Intent storage intent = intents[intentId];
        require(msg.sender == intent.creator, "Only intent creator");
        
        Quote storage quote = quotes[intentId][quoteIndex];
        require(!quote.accepted, "Quote already accepted");
        
        quote.accepted = true;
        
        // Atomic swap via token transfers
        if (intent.intentType == IntentType.Sell) {
            // Creator selling tokenIn, solver selling tokenOut
            require(IERC20(intent.tokenIn).transferFrom(intent.creator, quote.solver, quote.fillAmount), "Transfer failed");
            require(IERC20(intent.tokenOut).transferFrom(quote.solver, intent.creator, quote.receiveAmount), "Transfer failed");
        } else {
            // Creator buying tokenIn, solver selling tokenIn
            require(IERC20(intent.tokenOut).transferFrom(intent.creator, quote.solver, quote.receiveAmount), "Transfer failed");
            require(IERC20(intent.tokenIn).transferFrom(quote.solver, intent.creator, quote.fillAmount), "Transfer failed");
        }
        
        // Update intent status
        uint256 newRemaining = _getRemainingAmount(intentId) - quote.fillAmount;
        if (newRemaining == 0) {
            intent.status = IntentStatus.Filled;
        } else {
            intent.status = IntentStatus.PartiallyFilled;
        }
        
        emit IntentFilled(intentId, quote.solver, quote.fillAmount, quote.receiveAmount);
    }
    
    // ── Admin & Cleanup ──────────────────────────────────────────────────────
    
    function cancelIntent(uint256 intentId) external intentActive(intentId) {
        Intent storage intent = intents[intentId];
        require(msg.sender == intent.creator || msg.sender == physicsEngine, "Not authorized");
        intent.status = IntentStatus.Cancelled;
        emit IntentCancelled(intentId);
    }
    
    /**
     * @notice Physics Engine calls this to expire stale intents
     */
    function expireStaleIntents(uint256[] calldata intentIds) external onlyPhysicsEngine {
        for (uint256 i = 0; i < intentIds.length; i++) {
            Intent storage intent = intents[intentIds[i]];
            if (intent.status == IntentStatus.Open && block.timestamp > intent.deadline) {
                intent.status = IntentStatus.Expired;
                emit IntentExpired(intentIds[i]);
            }
        }
    }
    
    // ── Views ────────────────────────────────────────────────────────────────
    
    function getIntent(uint256 intentId) external view returns (Intent memory) {
        return intents[intentId];
    }
    
    function getQuotes(uint256 intentId) external view returns (Quote[] memory) {
        return quotes[intentId];
    }
    
    function getActiveIntents() external view returns (Intent[] memory) {
        // Return up to 50 active intents
        uint256 count = 0;
        for (uint256 i = 1; i <= _intentCounter && count < 50; i++) {
            Intent storage intent = intents[i];
            if (intent.status == IntentStatus.Open || intent.status == IntentStatus.PartiallyFilled) {
                count++;
            }
        }
        
        Intent[] memory active = new Intent[](count);
        uint256 idx = 0;
        for (uint256 i = 1; i <= _intentCounter && idx < count; i++) {
            Intent storage intent = intents[i];
            if (intent.status == IntentStatus.Open || intent.status == IntentStatus.PartiallyFilled) {
                active[idx++] = intent;
            }
        }
        return active;
    }
    
    // ── Internal ──────────────────────────────────────────────────────────────
    
    function _getRemainingAmount(uint256 intentId) internal view returns (uint256) {
        Intent storage intent = intents[intentId];
        uint256 filled = 0;
        Quote[] storage intentQuotes = quotes[intentId];
        for (uint256 i = 0; i < intentQuotes.length; i++) {
            if (intentQuotes[i].accepted) {
                filled += intentQuotes[i].fillAmount;
            }
        }
        return intent.amountIn - filled;
    }
}
