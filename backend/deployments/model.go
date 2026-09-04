package deployments

import "github.com/ethereum/go-ethereum/common"

// Environment identifies the operational class of a reviewed deployment.
type Environment string

const (
	EnvironmentLocal      Environment = "local"
	EnvironmentTestnet    Environment = "testnet"
	EnvironmentProduction Environment = "production"
)

// BytecodeHashes contains the reviewed runtime bytecode identities needed at
// indexer startup. Task 3 only validates their shape; it performs no RPC calls.
type BytecodeHashes struct {
	LaunchFactory    common.Hash
	BondingCurveV1   common.Hash
	UniswapV2Factory common.Hash
	WETH             common.Hash
}

// Deployment is the runtime subset of a reviewed deployment manifest.
type Deployment struct {
	ChainID             uint64
	DeploymentID        string
	Name                string
	Environment         Environment
	Factory             common.Address
	StartBlock          uint64
	EngineVersion       uint16
	CurveImplementation common.Address
	UniV2Factory        common.Address
	WETH                common.Address
	PairInitCodeHash    common.Hash
	LPBurnAddress       common.Address
	BytecodeHashes      BytecodeHashes
	DeployTransaction   common.Hash
	ExplorerBase        string
}
