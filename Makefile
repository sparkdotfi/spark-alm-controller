# Targets
.PHONY: install build test deploy

# Install Dependencies
install :
	forge install openzeppelin/openzeppelin-contracts@dbb6104ce834628e473d2173bbc9d47f81a9eec3 --no-commit
	forge install makerdao/usds@1e91268374d2796abcbb1af2b75473b2af488265 --no-commit
	forge install makerdao/dss-allocator@226584d3b179d98025497815adb4ea585ea0102d --no-commit
	forge install makerdao/dss-test@f2a2b2bbea71921103c5b7cf3cb1d241b957bec7 --no-commit
	forge install morpho-org/metamorpho@f5faa9c21b1396c291b471a6a5ad9407d23486a9 --no-commit

# Staging Full Deployment with Dependencies
deploy-staging-full :; forge script script/staging/FullStagingDeploy.s.sol:FullStagingDeploy --sender ${ETH_FROM} --broadcast --verify

# Staging Deployments
deploy-mainnet-staging-controller :; ENV=staging forge script script/Deploy.s.sol:DeployMainnetController --sender ${ETH_FROM} --broadcast --verify

deploy-base-staging-controller :; CHAIN=base ENV=staging forge script script/Deploy.s.sol:DeployForeignController --sender ${ETH_FROM} --broadcast --verify

# Production Deployments
deploy-mainnet-production-full       :; ENV=production forge script script/Deploy.s.sol:DeployMainnetFull --sender ${ETH_FROM} --broadcast --verify
deploy-mainnet-production-controller :; ENV=production forge script script/Deploy.s.sol:DeployMainnetController --sender ${ETH_FROM} --broadcast --verify

deploy-base-production-full       :; CHAIN=base ENV=production forge script script/Deploy.s.sol:DeployForeignFull --sender ${ETH_FROM} --broadcast --verify
deploy-base-production-controller :; CHAIN=base ENV=production forge script script/Deploy.s.sol:DeployForeignController --sender ${ETH_FROM} --broadcast --verify
