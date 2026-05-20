import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log(`Deploying with: ${deployer.address}\n`);

  // 1. Deploy resource tokens
  const AetherResource = await ethers.getContractFactory("AetherResource");
  
  const energy = await AetherResource.deploy(
    "Aether Energy", "ENERGY",
    ethers.parseEther("1000000"), // 1M max supply
    100, // 1% decay per epoch
    deployer.address // Temporary physics engine placeholder
  );
  await energy.waitForDeployment();
  console.log(`Energy: ${await energy.getAddress()}`);

  const compute = await AetherResource.deploy(
    "Aether Compute", "COMPUTE",
    ethers.parseEther("100000"),
    50, // 0.5% decay
    deployer.address
  );
  await compute.waitForDeployment();
  console.log(`Compute: ${await compute.getAddress()}`);

  const data = await AetherResource.deploy(
    "Aether Data", "DATA",
    ethers.parseEther("10000"),
    25, // 0.25% decay
    deployer.address
  );
  await data.waitForDeployment();
  console.log(`Data: ${await data.getAddress()}`);

  // 2. Deploy Intent Market
  const IntentMarket = await ethers.getContractFactory("IntentMarket");
  const intentMarket = await IntentMarket.deploy(deployer.address);
  await intentMarket.waitForDeployment();
  console.log(`IntentMarket: ${await intentMarket.getAddress()}`);

  // 3. Deploy Physics Engine
  const PhysicsEngine = await ethers.getContractFactory("PhysicsEngine");
  const physics = await PhysicsEngine.deploy(
    await energy.getAddress(),
    await compute.getAddress(),
    await data.getAddress(),
    await intentMarket.getAddress()
  );
  await physics.waitForDeployment();
  console.log(`PhysicsEngine: ${await physics.getAddress()}`);

  // 4. Update Physics Engine addresses on tokens
  await energy.setPhysicsEngine(await physics.getAddress());
  await compute.setPhysicsEngine(await physics.getAddress());
  await data.setPhysicsEngine(await physics.getAddress());
  console.log("Physics Engine linked to tokens");

  // 5. Deploy ERC-6551 Registry Mock (simple)
  // For now, skip real ERC-6551 — use a simple account factory
  console.log("\n=== All contracts deployed ===");
  console.log(`Energy: ${await energy.getAddress()}`);
  console.log(`Compute: ${await compute.getAddress()}`);
  console.log(`Data: ${await data.getAddress()}`);
  console.log(`IntentMarket: ${await intentMarket.getAddress()}`);
  console.log(`PhysicsEngine: ${await physics.getAddress()}`);
  console.log(`Deployer: ${deployer.address}`);
}

main().catch(console.error);
