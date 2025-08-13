from __future__ import annotations

import wake.ir as ir
from rich import print
from wake.printers import Printer, printer

# Contains programatic checks of rate limiteds in the ForeignController and MainnetController
# contracts. The script uses `wake`,[0] which can be installed for example with:
#   > uv tool install eth-wake
#   > pipx install eth-wake
#   > pip install eth-wake
# Printers are scripts that you can run over the AST of the codebase. To execute this script,
# run:
#   > wake --config printers/wake.toml print rate-limits
# A zero exit-code indicates the below spec is satisfied.
# If the `printers/wake.toml` config file ever goes out of sync, you can regenerate it by running
#   > wake up config
# (This will read Foundry remappings and create a new `wake.toml` file which can then be moved to
# /printers.)
# [0] https://github.com/Ackee-Blockchain/wake

# --- SPEC ---
D_FOREIGN_CONTROLLER = {
    "LIMIT_4626_DEPOSIT": {
        "exists": {
            "setSupplyQueueMorpho(address,Id[])",
            "updateWithdrawQueueMorpho(address,uint256[])",
            "reallocateMorpho(address,struct MarketAllocation[])",
        },
        "down": {
            "depositERC4626(address,uint256)",
        },
        "up": {
            "withdrawERC4626(address,uint256)",
            "redeemERC4626(address,uint256)",
        }
    },
    "LIMIT_4626_WITHDRAW": {
        "exists": set(),
        "down": {
            "withdrawERC4626(address,uint256)",
            "redeemERC4626(address,uint256)",
        },
        "up": set(),
    },
    "LIMIT_AAVE_DEPOSIT": {
        "exists": set(),
        "down": {
            "depositAave(address,uint256)",
        },
        "up": {
            "withdrawAave(address,uint256)",
        }
    },
    "LIMIT_AAVE_WITHDRAW": {
        "exists": set(),
        "down": {
            "withdrawAave(address,uint256)",
        },
        "up": set(),
    },
    "LIMIT_LAYERZERO_TRANSFER": {
        "exists": set(),
        "down": {
            "transferTokenLayerZero(address,uint256,uint32)",
        },
        "up": set(),
    },
    "LIMIT_PSM_DEPOSIT": {
        "exists": set(),
        "down": {
            "depositPSM(address,uint256)",
        },
        "up": set(),
    },
    "LIMIT_PSM_WITHDRAW": {
        "exists": set(),
        "down": {
            "withdrawPSM(address,uint256)",
        },
        "up": set(),
    },
    "LIMIT_USDC_TO_CCTP": {
        "exists": set(),
        "down": {
            "transferUSDCToCCTP(uint256,uint32)",
        },
        "up": set(),
    },
    "LIMIT_USDC_TO_DOMAIN": {
        "exists": set(),
        "down": {
            "transferUSDCToCCTP(uint256,uint32)",
        },
        "up": set(),
    },
}
D_MAINNET_CONTROLLER = {
    "LIMIT_4626_DEPOSIT": {
        "exists": set(),
        "down": {
            "depositERC4626(address,uint256)",
        },
        "up": {
            "withdrawERC4626(address,uint256)",
            "redeemERC4626(address,uint256)",
        }
    },
    "LIMIT_4626_WITHDRAW": {
        "exists": set(),
        "down": {
            "withdrawERC4626(address,uint256)",
            "redeemERC4626(address,uint256)",
        },
        "up": set(),
    },
    "LIMIT_7540_DEPOSIT": {
        "exists": {
            "claimDepositERC7540(address)",
            "cancelCentrifugeDepositRequest(address)",
            "claimCentrifugeCancelDepositRequest(address)",
        },
        "down": {
            "requestDepositERC7540(address,uint256)",
        },
        "up": set(),
    },
    "LIMIT_7540_REDEEM": {
        "exists": {
            "claimRedeemERC7540(address)",
            "cancelCentrifugeRedeemRequest(address)",
            "claimCentrifugeCancelRedeemRequest(address)",
        },
        "down": {
            "requestRedeemERC7540(address,uint256)",
        },
        "up": set(),
    },
    "LIMIT_AAVE_DEPOSIT": {
        "exists": set(),
        "down": {
            "depositAave(address,uint256)",
        },
        "up": {
            "withdrawAave(address,uint256)",
        }
    },
    "LIMIT_AAVE_WITHDRAW": {
        "exists": set(),
        "down": {
            "withdrawAave(address,uint256)",
        },
        "up": set(),
    },
    "LIMIT_ASSET_TRANSFER": {
        "exists": set(),
        "down": {
            "transferAsset(address,address,uint256)",
        },
        "up": set(),
    },
    "LIMIT_CURVE_DEPOSIT": {
        "exists": set(),
        "down": {
            "addLiquidityCurve(address,uint256[],uint256)"
        },
        "up": set(),
    },
    "LIMIT_CURVE_SWAP": {
        "exists": set(),
        "down": {
            "swapCurve(address,uint256,uint256,uint256,uint256)",
            "addLiquidityCurve(address,uint256[],uint256)",
        },
        "up": set(),
    },
    "LIMIT_CURVE_WITHDRAW": {
        "exists": set(),
        "down": {
            "removeLiquidityCurve(address,uint256,uint256[])",
        },
        "up": set(),
    },
    "LIMIT_LAYERZERO_TRANSFER": {
        "exists": set(),
        "down": {
            "transferTokenLayerZero(address,uint256,uint32)",
        },
        "up": set(),
    },
    "LIMIT_MAPLE_REDEEM": {
        "exists": {
            "cancelMapleRedemption(address,uint256)",
        },
        "down": {
            "requestMapleRedemption(address,uint256)",
        },
        "up": set(),
    },
    "LIMIT_FARM_DEPOSIT": {
        "exists": set(),
        "down": {
            "depositToFarm(address,uint256)",
        },
        "up": set(),
    },
    "LIMIT_FARM_WITHDRAW": {
        "exists": set(),
        "down": {
            "withdrawFromFarm(address,uint256)",
        },
        "up": set(),
    },
    "LIMIT_SUPERSTATE_REDEEM": {
        "exists": set(),
        "down": {
            "redeemSuperstate(uint256)",
        },
        "up": set(),
    },
    "LIMIT_SUPERSTATE_SUBSCRIBE": {
        "exists": set(),
        "down": {
            "subscribeSuperstate(uint256)",
        },
        "up": set(),
    },
    "LIMIT_SUSDE_COOLDOWN": {
        "exists": set(),
        "down": {
            "cooldownAssetsSUSDe(uint256)",
            "cooldownSharesSUSDe(uint256)",
        },
        "up": set(),
    },
    "LIMIT_USDC_TO_CCTP": {
        "exists": set(),
        "down": {
            "transferUSDCToCCTP(uint256,uint32)",
        },
        "up": set(),
    },
    "LIMIT_USDC_TO_DOMAIN": {
        "exists": set(),
        "down": {
            "transferUSDCToCCTP(uint256,uint32)",
        },
        "up": set(),
    },
    "LIMIT_USDE_BURN": {
        "exists": set(),
        "down": {
            "prepareUSDeBurn(uint256)",
        },
        "up": set(),
    },
    "LIMIT_USDE_MINT": {
        "exists": set(),
        "down": {
            "prepareUSDeMint(uint256)",
        },
        "up": set(),
    },
    "LIMIT_USDS_MINT": {
        "exists": set(),
        "down": {
            "mintUSDS(uint256)",
        },
        "up": {
            "burnUSDS(uint256)",
        },
    },
    "LIMIT_USDS_TO_USDC": {
        "exists": set(),
        "down": {
            "swapUSDSToUSDC(uint256)",
        },
        "up": {
            "swapUSDCToUSDS(uint256)"
        },
    },
}

def name(function_definition: ir.FunctionDefinition) -> str:
    return function_definition.canonical_name.split(".")[-1]

class RateLimitsPrinter(Printer):

    d_for = {}
    d_main = {}
    d_main_manual = {}

    @printer.command(name="rate-limits")
    def cli(self) -> None:
        pass

    def visit_contract_definition(self, contr: ir.ContractDefinition):
        if contr.name == "ForeignController":
            d_res = self.d_for
        elif contr.name == "MainnetController":
            d_res = self.d_main
        else:
            return

        print("Handling", contr.name)

        for var_decl in contr.declared_variables:
            if not var_decl.name.startswith("LIMIT"):
                continue
            for ref in var_decl.references:
                function_enclosing = None; modifier_called = None
                functions_called = []
                parent = ref.parent
                while parent is not None:
                    if isinstance(parent, ir.ModifierInvocation):
                        modifier_called = parent
                    if isinstance(parent, ir.FunctionCall):
                        functions_called.append(parent.function_called)
                    if isinstance(parent, ir.FunctionDefinition):
                        function_enclosing = parent
                        break
                    parent = parent.parent

                assert function_enclosing is not None, "Function enclosing should not be None"
                assert modifier_called is not None or len(functions_called) > 0, \
                    "Either modifier_called or function_called should not be None"
                # d_res[var_decl.name] = (function_enclosing, modifier_called, function_called)

                if var_decl.name not in d_res:
                    d_res[var_decl.name] = {"exists": set(), "down": set(), "up": set()}

                if modifier_called is not None:
                    # print(var_decl.name, "modifier_called")
                    if modifier_called.modifier_name.name == "rateLimited":
                        d_res[var_decl.name]["down"].add(name(function_enclosing))
                    elif modifier_called.modifier_name.name == "rateLimitedAsset":
                        d_res[var_decl.name]["down"].add(name(function_enclosing))
                    elif modifier_called.modifier_name.name == "rateLimitExists":
                        d_res[var_decl.name]["exists"].add(name(function_enclosing))
                    else:
                        raise ValueError(f"Unknown modifier called: {modifier_called.modifier_name.name}")
                elif len(functions_called) > 0:
                    # print(var_decl.name, "functions_called")
                    if "triggerRateLimitDecrease" in map(lambda x: x.name, functions_called):
                        d_res[var_decl.name]["down"].add(name(function_enclosing))
                    elif "triggerRateLimitIncrease" in map(lambda x: x.name, functions_called):
                        d_res[var_decl.name]["up"].add(name(function_enclosing))
                    elif "_rateLimited" in map(lambda x: x.name, functions_called):
                        d_res[var_decl.name]["down"].add(name(function_enclosing))
                    elif "_rateLimitedAsset" in map(lambda x: x.name, functions_called):
                        d_res[var_decl.name]["down"].add(name(function_enclosing))
                    elif "_cancelRateLimit" in map(lambda x: x.name, functions_called):
                        d_res[var_decl.name]["up"].add(name(function_enclosing))
                    elif "_rateLimitExists" in map(lambda x: x.name, functions_called):
                        d_res[var_decl.name]["exists"].add(name(function_enclosing))
                    elif "addLiquidity" in map(lambda x: x.name, functions_called):
                        d_res[var_decl.name]["down"].add(name(function_enclosing))
                    elif "swap" in map(lambda x: x.name, functions_called):
                        d_res[var_decl.name]["down"].add(name(function_enclosing))
                    elif "removeLiquidity" in map(lambda x: x.name, functions_called):
                        d_res[var_decl.name]["down"].add(name(function_enclosing))
                    elif "transferUSDCToCCTP" in map(lambda x: x.name, functions_called):
                        d_res[var_decl.name]["down"].add(name(function_enclosing))
                    elif "transferswapUSDSToUSDC" in map(lambda x: x.name, functions_called):
                        d_res[var_decl.name]["down"].add(name(function_enclosing))
                    elif "swapUSDSToUSDC" in map(lambda x: x.name, functions_called):
                        d_res[var_decl.name]["down"].add(name(function_enclosing))
                    elif "swapUSDCToUSDS" in map(lambda x: x.name, functions_called):
                        d_res[var_decl.name]["up"].add(name(function_enclosing))
                    else:
                        raise ValueError(f"Unknown function called in chain: {', '.join(map(lambda x: x.name, functions_called))}")
                else:
                    raise ValueError("Either modifier_called or functions_called should not be empty")




    def print(self) -> None:
        assert set(self.d_for.keys()) == set(D_FOREIGN_CONTROLLER.keys())
        for key in self.d_for:
            for k in ["exists", "down", "up"]:
                assert self.d_for[key][k] == D_FOREIGN_CONTROLLER[key][k], \
                    f"Mismatch in Foreign {key}.{k}: {self.d_for[key][k]} != {D_FOREIGN_CONTROLLER[key][k]}"

        assert set(self.d_main.keys()) == set(D_MAINNET_CONTROLLER.keys())
        for key in self.d_main:
            for k in ["exists", "down", "up"]:
                assert self.d_main[key][k] == D_MAINNET_CONTROLLER[key][k], \
                    f"Mismatch in Main {key}.{k}: {self.d_main[key][k]} != {D_MAINNET_CONTROLLER[key][k]}"




