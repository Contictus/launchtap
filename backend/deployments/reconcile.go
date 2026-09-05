package deployments

import "fmt"

// Resolve selects an exact deployment and applies startup-only configuration
// rules. API and indexer entrypoints should use this method.
func (r *Registry) Resolve(chainID uint64, deploymentID string, indexerConfirmations *uint64) (Deployment, error) {
	deployment, err := r.Lookup(chainID, deploymentID)
	if err != nil {
		return Deployment{}, err
	}
	if err := ReconcileConfig(chainID, indexerConfirmations, deployment); err != nil {
		return Deployment{}, err
	}
	return deployment, nil
}

// ReconcileConfig enforces startup rules that depend on a resolved manifest.
// Config parsing remains pure and does not call this function.
func ReconcileConfig(chainID uint64, indexerConfirmations *uint64, deployment Deployment) error {
	if chainID != deployment.ChainID {
		return fmt.Errorf("configured chain id %d does not match deployment chain id %d", chainID, deployment.ChainID)
	}
	if indexerConfirmations != nil && deployment.Environment != EnvironmentLocal {
		return fmt.Errorf("indexer confirmations override is not allowed for %s deployments", deployment.Environment)
	}
	return nil
}
