# Staging Full Deployment with Dependencies
deploy-staging-full :; forge script script/staging/FullStagingDeploy.s.sol:FullStagingDeploy --sender ${ETH_FROM} --broadcast --verify --multi

# Staging Deployments
deploy-mainnet-staging-controller :; ENV=staging forge script script/Deploy.s.sol:DeployMainnetController --sender ${ETH_FROM} --broadcast --verify
deploy-base-staging-controller :; CHAIN=base ENV=staging forge script script/Deploy.s.sol:DeployForeignController --sender ${ETH_FROM} --broadcast --verify

# Production Deployments
deploy-mainnet-production-full       :; ENV=production forge script script/Deploy.s.sol:DeployMainnetFull --sender ${ETH_FROM} --broadcast --verify
deploy-mainnet-production-controller :; ENV=production forge script script/Deploy.s.sol:DeployMainnetController --sender ${ETH_FROM} --broadcast --verify

deploy-arbitrum-one-production-full       :; CHAIN=arbitrum_one ENV=production forge script script/Deploy.s.sol:DeployForeignFull --sender ${ETH_FROM} --broadcast --verify
deploy-arbitrum-one-production-controller :; CHAIN=arbitrum_one ENV=production forge script script/Deploy.s.sol:DeployForeignController --sender ${ETH_FROM} --broadcast --verify

deploy-base-production-full       :; CHAIN=base ENV=production forge script script/Deploy.s.sol:DeployForeignFull --sender ${ETH_FROM} --broadcast --verify
deploy-base-production-controller :; CHAIN=base ENV=production forge script script/Deploy.s.sol:DeployForeignController --sender ${ETH_FROM} --broadcast --verify

deploy-unichain-production-full       :; CHAIN=unichain ENV=production forge script script/Deploy.s.sol:DeployForeignFull --sender ${ETH_FROM} --broadcast --verify
deploy-unichain-production-controller :; CHAIN=unichain ENV=production forge script script/Deploy.s.sol:DeployForeignController --sender ${ETH_FROM} --broadcast --verify

deploy-avalanche-production-full       :; CHAIN=avalanche ENV=production forge script script/Deploy.s.sol:DeployForeignFull --sender ${ETH_FROM} --broadcast --verify
deploy-avalanche-production-controller :; CHAIN=avalanche ENV=production forge script script/Deploy.s.sol:DeployForeignController --sender ${ETH_FROM} --broadcast --verify

deploy-optimism-production-full       :; CHAIN=optimism ENV=production forge script script/Deploy.s.sol:DeployForeignFull --sender ${ETH_FROM} --broadcast --verify
deploy-optimism-production-controller :; CHAIN=optimism ENV=production forge script script/Deploy.s.sol:DeployForeignController --sender ${ETH_FROM} --broadcast --verify
