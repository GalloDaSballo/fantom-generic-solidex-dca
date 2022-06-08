import time

from brownie import (
    accounts,
    network,
    EmittingStrategy,
    TheVault,
    AdminUpgradeabilityProxy,
    interface,
)

from _setup.config import (
    REWARD,
    WANT, 
    REGISTRY,

    PERFORMANCE_FEE_GOVERNANCE,
    PERFORMANCE_FEE_STRATEGIST,
    WITHDRAWAL_FEE,
    MANAGEMENT_FEE,
)

from helpers.constants import AddressZero

import click
from rich.console import Console

console = Console()

sleep_between_tx = 1


def main():
    """
    FOR STRATEGISTS AND GOVERNANCE
    Deploys a Controller, a TheVault and your strategy under upgradable proxies and wires them up.
    Note that it sets your deployer account as the governance for the three contracts so that
    the setup and production tests are simpler and more efficient. The rest of the permissioned actors
    are set based on the latest entries from the Badger Registry.
    """

    # Get deployer account from local keystore
    dev = connect_account()

    # Get actors from registry
    registry = interface.IBadgerRegistry(REGISTRY)

    strategist = registry.get("governance")
    badgerTree = "0xB9F9ac0aC2E21108c7335cD8751779522fC63979" ## BadgerRewards b0.1
    guardian = registry.get("guardian")
    keeper = registry.get("keeper")
    proxyAdmin = registry.get("proxyAdminTimelock")

    name = "wFTM/WETH to wBTC DCA Vault" ## In vaults 1.5 it's the full name
    symbol = "bwFTM/WETH->wBTC" ## e.g The full symbol (remember to add symbol from want)

    assert strategist != AddressZero
    assert guardian != AddressZero
    assert keeper != AddressZero
    assert proxyAdmin != AddressZero
    assert name != "Name Prefix Here"
    assert symbol != "bveSymbolHere"

    # Deploy Vault
    vault = TheVault.at("0x5dA75c76565B69A5cDC5F2195E31362CEA00CD14")
    
    # Deploy Strategy
    strategy = deploy_strategy(
        vault,
        proxyAdmin,
        dev
    )

    dev_setup = vault.setStrategy(strategy, {"from": dev})
    console.print("[green]Strategy was set was deployed at: [/green]", dev_setup)
    


def deploy_vault(governance, keeper, guardian, strategist, badgerTree, proxyAdmin, name, symbol, dev):
    args = [
        WANT,
        governance,
        keeper,
        guardian,
        governance,
        strategist,
        badgerTree,
        name,
        symbol,
        [
            PERFORMANCE_FEE_GOVERNANCE,
            PERFORMANCE_FEE_STRATEGIST,
            WITHDRAWAL_FEE,
            MANAGEMENT_FEE,
        ],
    ]

    print("Vault Arguments: ", args)

    vault_logic = TheVault.at("0xf3F6666949c5a0324d6575242e68c6Ca1097C38f")

    vault_proxy = AdminUpgradeabilityProxy.deploy(
        vault_logic,
        proxyAdmin,
        vault_logic.initialize.encode_input(*args),
        {"from": dev, "publish_source": True}
    )
    time.sleep(sleep_between_tx)

    ## We delete from deploy and then fetch again so we can interact
    AdminUpgradeabilityProxy.remove(vault_proxy)
    vault_proxy = TheVault.at(vault_proxy.address)

    console.print("[green]Vault was deployed at: [/green]", vault_proxy.address)

    return vault_proxy


def deploy_strategy(
     vault, proxyAdmin, dev
):

    args = [
        vault,
        [WANT, REWARD]
    ]

    print("Strategy Arguments: ", args)

    strat_logic = EmittingStrategy.at("0x4055D395361E73530D43c9D4F18b0668fe4B5b91")
    time.sleep(sleep_between_tx)

    strat_proxy = AdminUpgradeabilityProxy.deploy(
        strat_logic,
        proxyAdmin,
        strat_logic.initialize.encode_input(*args),
        {"from": dev}
    )
    time.sleep(sleep_between_tx)

    ## We delete from deploy and then fetch again so we can interact
    AdminUpgradeabilityProxy.remove(strat_proxy)
    strat_proxy = EmittingStrategy.at(strat_proxy.address)

    console.print("[green]Strategy was deployed at: [/green]", strat_proxy.address)

    return strat_proxy



def connect_account():
    click.echo(f"You are using the '{network.show_active()}' network")
    dev = accounts.load(click.prompt("Account", type=click.Choice(accounts.load())))
    click.echo(f"You are using: 'dev' [{dev.address}]")
    return dev
