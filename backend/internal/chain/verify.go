package chain

import (
	"bytes"
	"context"
	"fmt"

	"github.com/Contictus/launchtap/backend/deployments"
	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
)

type CodeReader interface {
	CodeAt(context.Context, common.Address) ([]byte, error)
}

func VerifyDeploymentBytecode(ctx context.Context, reader CodeReader, deployment deployments.Deployment) error {
	checks := []struct {
		name     string
		address  common.Address
		expected common.Hash
	}{
		{"Factory", deployment.Factory, deployment.BytecodeHashes.LaunchFactory},
		{"CurveImplementation", deployment.CurveImplementation, deployment.BytecodeHashes.BondingCurveV1},
		{"WETH", deployment.WETH, deployment.BytecodeHashes.WETH},
		{"UniV2Factory", deployment.UniV2Factory, deployment.BytecodeHashes.UniswapV2Factory},
	}
	for _, check := range checks {
		code, err := reader.CodeAt(ctx, check.address)
		if err != nil {
			return fmt.Errorf("read %s bytecode at %s: %w", check.name, check.address.Hex(), err)
		}
		actual := crypto.Keccak256Hash(code)
		if len(code) == 0 || actual != check.expected {
			return fmt.Errorf("%w: %s at %s: got %s, want %s", ErrBytecodeMismatch, check.name, check.address.Hex(), actual.Hex(), check.expected.Hex())
		}
	}
	return nil
}

func PairAddress(factory, token, weth common.Address, initCodeHash common.Hash) common.Address {
	token0, token1 := token, weth
	if bytes.Compare(token0[:], token1[:]) > 0 {
		token0, token1 = token1, token0
	}
	salt := crypto.Keccak256Hash(token0[:], token1[:])
	hash := crypto.Keccak256([]byte{0xff}, factory[:], salt[:], initCodeHash[:])
	return common.BytesToAddress(hash[12:])
}

type ContractCaller interface {
	CallContract(context.Context, ethereum.CallMsg) ([]byte, error)
}

func VerifyPairAddress(ctx context.Context, caller ContractCaller, factory, token, weth common.Address, initCodeHash common.Hash) (common.Address, error) {
	expected := PairAddress(factory, token, weth, initCodeHash)
	selector := crypto.Keccak256([]byte("getPair(address,address)"))[:4]
	data := make([]byte, 4+64)
	copy(data, selector)
	copy(data[4+12:4+32], token[:])
	copy(data[4+32+12:], weth[:])
	result, err := caller.CallContract(ctx, ethereum.CallMsg{To: &factory, Data: data})
	if err != nil {
		return common.Address{}, fmt.Errorf("read pair address: %w", err)
	}
	if len(result) != 32 {
		return common.Address{}, fmt.Errorf("%w: getPair returned %d bytes", ErrPairMismatch, len(result))
	}
	for _, value := range result[:12] {
		if value != 0 {
			return common.Address{}, fmt.Errorf("%w: getPair returned a non-padded address", ErrPairMismatch)
		}
	}
	actual := common.BytesToAddress(result[12:])
	if actual != expected {
		return common.Address{}, fmt.Errorf("%w: got %s, want %s", ErrPairMismatch, actual.Hex(), expected.Hex())
	}
	return actual, nil
}
