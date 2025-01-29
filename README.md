# Hamza Token

## Enviorment Set up 
Intall foundry if haven't

Create a .env with PRIVATE_KEY =0x...

## Testing
To run tests using Foundry, execute the following command:

```bash
forge test --fork-url sepolia -vvv
```

The forking process ensures proper referencing of the Hats contract deployed on-chain.

---

## Deployment

### Important Notes
- Update the following variables in the scripts `HatsDeployment.s.sol` and `DeployHamzaVault.s.sol`:
  - `OWNER_ONE`
  - `OWNER_TWO`
  - `adminAddress2`

### Deploying Contracts
To deploy the contracts on the network, add the `--broadcast` flag to the script command:

```bash
forge script -vvv ./scripts/DeployHamzaVault.s.sol:DeployHamzaVault \
  --rpc-url sepolia \
  --sender 0x000 \
  --broadcast
```

### Running the Script Without Deployment
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

2. Add the deployed address from `DeployBaalSummoner` to `DeployHamzaVault.s.sol` by updating the `BALL_SUMMONER` variable.
