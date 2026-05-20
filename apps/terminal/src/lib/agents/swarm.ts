/**
 * Aether-War Agentic Loop — LLM-powered swarm agents
 * 
 * Each agent reads on-chain state, reasons via LLM, and generates intents.
 * Scout → Builder → Closer → Treasurer pipeline.
 */

import { getWorld, processTick } from "../ecs/physics";

// ── Agent Types ──────────────────────────────────────────────────────────────

export interface AgentReport {
  agent: "scout" | "builder" | "closer" | "treasurer";
  swarmId: number;
  tick: number;
  reasoning: string;
  action: string;
  confidence: number;
}

export interface Intent {
  id: string;
  swarmId: number;
  type: "buy" | "sell";
  resourceIn: "energy" | "compute" | "data";
  resourceOut: "energy" | "compute" | "data";
  amountIn: number;
  amountOut: number;
  creator: string;
  status: "open" | "filled" | "cancelled";
}

// ── Scout Agent ──────────────────────────────────────────────────────────────

export async function scoutAnalyze(swarmId: number): Promise<AgentReport> {
  const world = getWorld();
  const swarm = world.swarms.find(s => s.id === swarmId);
  if (!swarm) throw new Error(`Swarm ${swarmId} not found`);

  // Scan for undervalued sectors (unowned, high yield, near swarm)
  const unownedSectors = world.sectors.filter(s => !s.owner && s.active);
  const bestSector = unownedSectors.reduce((best, s) => 
    (s.energyRate + s.computeRate * 10 + s.dataRate * 100) > 
    (best?.energyRate || 0) + (best?.computeRate || 0) * 10 + (best?.dataRate || 0) * 100 ? s : best, 
    unownedSectors[0]
  );

  const reasoning = bestSector 
    ? `Sector ${bestSector.id} at (${bestSector.x},${bestSector.y}) — yield E:${bestSector.energyRate} C:${bestSector.computeRate} D:${bestSector.dataRate}. Unclaimed. Recommend claim.`
    : `No unowned sectors available. Recommend monitoring for abandoned sectors.`;

  return {
    agent: "scout",
    swarmId,
    tick: world.tick,
    reasoning,
    action: bestSector ? `claim_sector_${bestSector.id}` : "wait",
    confidence: bestSector ? 85 : 40,
  };
}

// ── Builder Agent ────────────────────────────────────────────────────────────

export async function builderAnalyze(swarmId: number): Promise<AgentReport> {
  const world = getWorld();
  const swarm = world.swarms.find(s => s.id === swarmId);
  if (!swarm) throw new Error(`Swarm ${swarmId} not found`);

  // Find owned sectors that can be upgraded
  const ownedSectors = world.sectors.filter(s => s.owner === swarm.account);
  
  // Find the sector with the lowest level that's upgradeable
  const upgradeCandidate = ownedSectors
    .filter(s => s.level < 10)
    .sort((a, b) => a.level - b.level)[0];

  const upgradeCost = upgradeCandidate ? upgradeCandidate.level * 10 : 0;
  const canAfford = swarm.compute >= upgradeCost;

  const reasoning = upgradeCandidate
    ? `Sector ${upgradeCandidate.id} at level ${upgradeCandidate.level}. Upgrade cost: ${upgradeCost} Compute. ${canAfford ? 'AFFORDABLE — upgrading.' : 'Cannot afford — accumulating Compute.'}`
    : `No upgradeable sectors owned. Owning ${ownedSectors.length} sectors.`;

  return {
    agent: "builder",
    swarmId,
    tick: world.tick,
    reasoning,
    action: canAfford && upgradeCandidate ? `upgrade_sector_${upgradeCandidate.id}` : "accumulate",
    confidence: canAfford ? 90 : 50,
  };
}

// ── Closer Agent ─────────────────────────────────────────────────────────────

export async function closerAnalyze(swarmId: number): Promise<AgentReport> {
  const world = getWorld();
  const swarm = world.swarms.find(s => s.id === swarmId);
  if (!swarm) throw new Error(`Swarm ${swarmId} not found`);

  // Check if we need to trade: if low on Energy but high on Compute, create sell intent
  const needEnergy = swarm.energy < 50;
  const excessCompute = swarm.compute > 20;
  const excessData = swarm.data > 3;

  let reasoning = `Portfolio: E:${swarm.energy.toFixed(1)} C:${swarm.compute.toFixed(1)} D:${swarm.data.toFixed(2)}. `;
  let action = "hold";

  if (needEnergy && excessCompute) {
    reasoning += `Low Energy, excess Compute. Creating SELL intent: 5 Compute for 50 Energy.`;
    action = `sell_compute_for_energy`;
  } else if (needEnergy && excessData) {
    reasoning += `Low Energy, excess Data. Creating SELL intent: 0.5 Data for 75 Energy.`;
    action = `sell_data_for_energy`;
  } else if (!needEnergy && swarm.compute < 5) {
    reasoning += `Low Compute, sufficient Energy. Creating BUY intent.`;
    action = `buy_compute_with_energy`;
  } else {
    reasoning += `Balanced. Holding.`;
  }

  return {
    agent: "closer",
    swarmId,
    tick: world.tick,
    reasoning,
    action,
    confidence: action === "hold" ? 60 : 78,
  };
}

// ── Treasurer Agent ──────────────────────────────────────────────────────────

export async function treasurerAnalyze(swarmId: number): Promise<AgentReport> {
  const world = getWorld();
  const swarm = world.swarms.find(s => s.id === swarmId);
  if (!swarm) throw new Error(`Swarm ${swarmId} not found`);

  const totalValue = swarm.energy + swarm.compute * 10 + swarm.data * 100;
  const decayRisk = swarm.energy > 200 ? `High Energy decay risk — consider spending or trading.` : `Decay manageable.`;
  
  const ownedCount = world.sectors.filter(s => s.owner === swarm.account).length;
  const diversification = ownedCount < 2 ? `Undiversified — recommend claiming more sectors.` : `Sector diversification: ${ownedCount} sectors.`;

  return {
    agent: "treasurer",
    swarmId,
    tick: world.tick,
    reasoning: `Vault: ${totalValue.toFixed(0)} total value. ${decayRisk} ${diversification}`,
    action: totalValue > 500 ? "rebalance" : "accumulate",
    confidence: 75,
  };
}

// ── Full Swarm Pipeline ─────────────────────────────────────────────────────

export async function runSwarmPipeline(swarmId: number): Promise<AgentReport[]> {
  const world = getWorld();
  processTick(); // Advance the world first

  const reports: AgentReport[] = [];

  // Scout → Builder → Closer → Treasurer
  reports.push(await scoutAnalyze(swarmId));
  reports.push(await builderAnalyze(swarmId));
  reports.push(await closerAnalyze(swarmId));
  reports.push(await treasurerAnalyze(swarmId));

  return reports;
}
