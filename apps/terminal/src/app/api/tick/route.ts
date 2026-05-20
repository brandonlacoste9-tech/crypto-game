import { NextResponse } from "next/server";
import { initWorld, getWorld, processTick } from "@/lib/ecs/physics";
import { runSwarmPipeline } from "@/lib/agents/swarm";

let initialized = false;

export async function GET() {
  if (!initialized) {
    initWorld();
    initialized = true;
  }

  const world = getWorld();
  
  // Run the swarm pipeline for swarm #1 (or all if specified)
  const reports = await runSwarmPipeline(1);
  
  return NextResponse.json({
    tick: world.tick,
    world: {
      sectors: world.sectors.length,
      swarms: world.swarms.length,
      energySupply: world.energySupply.toFixed(1),
      computeSupply: world.computeSupply.toFixed(1),
      dataSupply: world.dataSupply.toFixed(2),
    },
    reports,
  });
}
