# Hamza Token

## Enviorment Set up 
Intall foundry if haven't

Create a .env with PRIVATE_KEY =0x...

## Testing
To run tests using Foundry, execute the following command:

```bash
forge test --fork-url sepolia -vvv
```

The forking ensures proper referencing of the Hats contract deployed on-chain.

---

## Deployment

### Important Notes
- Update ownerTwo in `config.json` to not be your address
- Adjust any other params in `config.json` and they will update globally across deployments and tests 
- If making a new test inherit the `DeploymentSetup.t.sol` to make it work form deployment 

### Deploying Contracts
To deploy the contracts on the network, add the `--broadcast` flag to the script command:

```bash
forge script -vvv ./scripts/DeployHamzaVault.s.sol:DeployHamzaVault \
  --rpc-url sepolia \
  --sender 0x000 \
  --broadcast
```

### Running the Script Without Live Deployment
You can run the deployment script without actually deploying the contract using the following command:

```bash
forge script -vvv ./scripts/DeployHamzaVault.s.sol:DeployHamzaVault \
  --rpc-url sepolia \
  --sender 0x...
```

### Deploying on Non-Sepolia Networks
1. Run the `DeployBaalSummoner.s.sol` script on the chain of your choice:

   ```bash
   forge script -vvv ./scripts/DeployBaalSummoner.s.sol:DeployCustomBaalSummoner \
    --rpc-url <RPC-URL> \    
    --sender 0x... \
    --broadcast
   ```

2. Add the deployed address from `DeployBaalSummoner` to `DeploymentSetup.t.sol` by updating the `BALL_SUMMONER` variable.

## Configuration (`config.json`)
The `config.json` file contains key settings for deployment and testing. Below is an explnation of each param:

- **mode**: Determines the deployment environment.
  - `Test`: Used for testing.
  - `Deploy`: Used for live deployments with logging enabled.

- **owners**:
  - `ownerTwo`: The secondary owner address.

- **baal**:
  - `sharesName`: Name of the governance share tokens.
  - `sharesSymbol`: Symbol for the governance shares.
  - `pauseSharesOnInit`: Whether to pause share transfers at the beginning.
  - `pauseLootOnInit`: Whether to pause loot (non-voting) token transfers initially.
  - `safeSharesToMint`: Initial governance shares allocated to the safe.
  - `userLootAmount`: Number of loot tokens deploying user receives.
  - `vaultLootAmount`: Number of loot tokens allocated to the vault.

- **governanceToken**:
  - `name`: Name of the governance token.
  - `symbol`: Symbol for the governance token.

- **governanceVault**:
  - `vestingPeriod`: Time (in days) for governance token vesting.

- **governor**:
  - `timelockDelay`: Delay (in blocks or time) before execution of governance proposals.

- **systemSettings**:
  - `feeBPS`: Fee basis points (0 means no fee).

- **escrow**:
  - `autoRelease`: Whether the escrow automatically releases funds upon conditions being met.

The `config.json` file is used to ensure consistent deployment settings across tests and live deployments. Adjust these parameters before running any scripts.

---


