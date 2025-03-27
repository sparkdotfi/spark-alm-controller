# Staging Full Deployment with Dependencies
deploy-staging-full :; forge script script/staging/FullStagingDeploy.s.sol:FullStagingDeploy --sender ${ETH_FROM} --broadcast --verify

# Staging Deployments
deploy-mainnet-staging-controller :; ENV=staging forge script script/Deploy.s.sol:DeployMainnetController --sender ${ETH_FROM} --broadcast --verify

# Production Deployments
deploy-mainnet-production-full       :; ENV=production forge script script/Deploy.s.sol:DeployMainnetFull --sender ${ETH_FROM} --broadcast --verify
deploy-mainnet-production-controller :; ENV=production forge script script/Deploy.s.sol:DeployMainnetController --sender ${ETH_FROM} --broadcast --verify
