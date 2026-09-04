package deployments

import "fmt"

// ErrDeploymentNotFound reports an unknown deployment selection.
type ErrDeploymentNotFound struct {
	ChainID      uint64
	DeploymentID string
}

func (e *ErrDeploymentNotFound) Error() string {
	return fmt.Sprintf("deployment %q on chain %d was not found", e.DeploymentID, e.ChainID)
}

// ErrDeploymentDisabled reports a chain that is explicitly unavailable.
type ErrDeploymentDisabled struct {
	ChainID uint64
	Reason  string
}

func (e *ErrDeploymentDisabled) Error() string {
	return fmt.Sprintf("chain %d is disabled: %s", e.ChainID, e.Reason)
}

// ValidationError identifies an invalid embedded deployment artifact.
type ValidationError struct {
	Path string
	Err  error
}

func (e *ValidationError) Error() string {
	return fmt.Sprintf("invalid deployment artifact %q: %v", e.Path, e.Err)
}

func (e *ValidationError) Unwrap() error {
	return e.Err
}
