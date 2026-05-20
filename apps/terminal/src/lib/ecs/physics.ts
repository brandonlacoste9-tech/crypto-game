/**
 * Aether-War Physics Engine — ECS State Machine
 * 
 * MUD-inspired Entity-Component-System architecture.
 * Manages sectors, resource generation, decay, and tick processing.
 * Runs client-side as a simulation of the on-chain state.
 */

// ── Types ────────────────────────────────────────────────────────────────────

export interface Sector {
  id: number;
  owner: string | null;    // Swarm account address (or null)
  energyRate: number;      // Energy per tick
  computeRate: number;     // Compute per tick
  dataRate: number;        // Data per tick
  lastClaimed: number;     // Tick number
  level: number;           // 1-10
  x: number;               // 2D map position
  y: number;
  active: boolean;
}

export interface SwarmState {
  id: number;
  account: string;
  name: string;
  energy: number;
  compute: number;
  data: number;
  sectors: number[];
  scoutLevel: number;
  builderLevel: number;
  closerLevel: number;
  treasurerLevel: number;
}

export interface WorldState {
  tick: number;
  sectors: Sector[];
  swarms: SwarmState[];
  energySupply: number;
  computeSupply: number;
  dataSupply: number;
}

// ── Constants ────────────────────────────────────────────────────────────────

const SECTOR_COUNT = 100;
const BASE_ENERGY = 10;
const BASE_COMPUTE = 1;
const BASE_DATA = 0.1;
const DECAY_RATE = 0.01; // 1% per tick
const CLAIM_COST_COMPUTE = 5;
const UPGRADE_COST_MULTIPLIER = 10;

// ── Engine ───────────────────────────────────────────────────────────────────

let world: WorldState = {
  tick: 0,
  sectors: [],
  swarms: [],
  energySupply: 0,
  computeSupply: 0,
  dataSupply: 0,
};

export function getWorld(): WorldState {
  return world;
}

export function initWorld(): WorldState {
  // Generate 100 sectors in a 10x10 grid
  const sectors: Sector[] = [];
  for (let i = 0; i < SECTOR_COUNT; i++) {
    sectors.push({
      id: i + 1,
      owner: i < 10 ? `swarm_${i + 1}` : null, // First 10 pre-claimed for demo
      energyRate: BASE_ENERGY + (i % 5) * 1,
      computeRate: BASE_COMPUTE + (i % 3) * 0.5,
      dataRate: BASE_DATA + (i % 10) * 0.05,
      lastClaimed: 0,
      level: 1,
      x: (i % 10) * 10 + 5,
      y: Math.floor(i / 10) * 10 + 5,
      active: true,
    });
  }

  // Initialize 10 demo swarms
  const swarms: SwarmState[] = [];
  for (let i = 1; i <= 10; i++) {
    swarms.push({
      id: i,
      account: `0x${i.toString(16).padStart(40, "0")}`,
      name: `Swarm ${i}`,
      energy: 100 + Math.random() * 50,
      compute: 10 + Math.random() * 5,
      data: Math.random() * 2,
      sectors: [],
      scoutLevel: 1,
      builderLevel: 1,
      closerLevel: 1,
      treasurerLevel: 1,
    });
  }

  world = { tick: 0, sectors, swarms, energySupply: 0, computeSupply: 0, dataSupply: 0 };
  return world;
}

export function processTick(): WorldState {
  world.tick++;

  // Generate resources for claimed sectors
  for (const sector of world.sectors) {
    if (!sector.owner || !sector.active) continue;

    const ticksSinceLastClaim = world.tick - sector.lastClaimed;
    const energyGen = sector.energyRate * ticksSinceLastClaim * sector.level;
    const computeGen = sector.computeRate * ticksSinceLastClaim * sector.level;
    const dataGen = sector.dataRate * ticksSinceLastClaim * sector.level;

    // Add to the owning swarm
    const swarm = world.swarms.find(s => s.account === sector.owner);
    if (swarm) {
      swarm.energy += energyGen;
      swarm.compute += computeGen;
      swarm.data += dataGen;
    }

    world.energySupply += energyGen;
    world.computeSupply += computeGen;
    world.dataSupply += dataGen;
    sector.lastClaimed = world.tick;
  }

  // Apply decay to all swarms
  for (const swarm of world.swarms) {
    swarm.energy *= (1 - DECAY_RATE);
    swarm.compute *= (1 - DECAY_RATE * 0.5);
  }

  return world;
}

export function claimSector(sectorId: number, swarmAccount: string): Sector | null {
  const sector = world.sectors.find(s => s.id === sectorId);
  if (!sector || sector.owner) return null;

  const swarm = world.swarms.find(s => s.account === swarmAccount);
  if (!swarm || swarm.compute < CLAIM_COST_COMPUTE) return null;

  swarm.compute -= CLAIM_COST_COMPUTE;
  sector.owner = swarmAccount;
  sector.lastClaimed = world.tick;

  return sector;
}

export function upgradeSector(sectorId: number, swarmAccount: string): Sector | null {
  const sector = world.sectors.find(s => s.id === sectorId);
  if (!sector || sector.owner !== swarmAccount || sector.level >= 10) return null;

  const swarm = world.swarms.find(s => s.account === swarmAccount);
  const upgradeCost = sector.level * UPGRADE_COST_MULTIPLIER;
  if (!swarm || swarm.compute < upgradeCost) return null;

  swarm.compute -= upgradeCost;
  sector.level++;
  sector.energyRate = BASE_ENERGY * sector.level;
  sector.computeRate = BASE_COMPUTE * sector.level;
  sector.dataRate = BASE_DATA * sector.level;

  return sector;
}

export function getSwarmStats(account: string): SwarmState | null {
  return world.swarms.find(s => s.account === account) || null;
}

export function getSectorMap(): { x: number; y: number; id: number; owner: string | null; level: number }[] {
  return world.sectors.map(s => ({ x: s.x, y: s.y, id: s.id, owner: s.owner, level: s.level }));
}
