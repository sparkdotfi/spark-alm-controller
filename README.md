# 🌳 Grove ALM Controller

![Foundry CI](https://github.com/grove-labs/grove-alm-controller/actions/workflows/ci.yml/badge.svg)
[![Foundry][foundry-badge]][foundry]
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://github.com/grove-labs/grove-alm-controller/blob/master/LICENSE)
![Ethereum](https://img.shields.io/badge/Ethereum-3C3C3D?style=flat&logo=ethereum&logoColor=white)

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg

## 📝 Overview

This repo contains the onchain components of the Grove Liquidity Layer. The following contracts are contained in this repository:

- `ALMProxy`: The proxy contract that holds custody of all funds. This contract routes calls to external contracts according to logic within a specified `controller` contract. This pattern was used to allow for future iterations in logic, as a new controller can be onboarded and can route calls through the proxy with new logic. This contract is stateless except for the ACL logic contained within the inherited OpenZeppelin `AccessControl` contract.
- `MainnetController`: This controller contract is intended to be used on the Ethereum mainnet.
- `RateLimits`: This contract is used to enforce and update rate limits on logic in the `MainnetController` contract. This contract is stateful and is used to store the rate limit data.

## ⚖️ Licensing

This repository is a fork of the sparkdotfi/spark-alm-controller. All code in this repository is licensed under the GNU Affero General Public License v3.0 (AGPL-3.0), which requires that modifications to the code must be made available under the same license. See the [LICENSE](LICENSE) file for more details.
