## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```


# Deploy ParimutuelBets

## Deployment

```sh
forge create ./src/ParimutuelBets.sol:ParimutuelBets --rpc-url $BASE_SEPOLIA_RPC_URL --account deployer --broadcast --verify
```

## Verification

```sh
forge verify-contract --etherscan-api-key $ETHERSCAN_API_KEY --rpc-url $BASE_SEPOLIA_RPC_URL $BET_CONTRACT ./src/ParimutuelBets.sol:ParimutuelBets
```

## Interact with Contract

```sh
# Get total bets count
cast call $BET_CONTRACT "getTotalBetsCount()" --rpc-url $BASE_SEPOLIA_RPC_URL

# Get bet details
cast call $BET_CONTRACT "bets(uint256)" <BET_ID> --rpc-url $BASE_SEPOLIA_RPC_URL
```