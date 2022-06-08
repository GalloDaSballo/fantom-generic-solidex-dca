"""
  Test to verify that undoing the BadgerRewards Integration allows to unblock operations
  As well as verify storage integrity
"""
import brownie
from brownie import (
    TheVault,
    TheVaultWithoutTree,
    AdminUpgradeabilityProxy,
    accounts,
    ERC20Upgradeable,
    interface
)
import pytest

VAULT_PROXY = "0x5dA75c76565B69A5cDC5F2195E31362CEA00CD14"

PROXY_ADMIN = "0x20dce41acca85e8222d6861aa6d23b6c941777bf"

## Account with funds stuck due to integration
USER = "0xB943cdb5622E7Bb26D3E462dB68Ee71D8868C940"

## Accounts ##
@pytest.fixture
def proxy_admin():
  return interface.IProxyAdmin(PROXY_ADMIN)

@pytest.fixture
def vault():
    return TheVault.at(VAULT_PROXY)


@pytest.fixture
def gov(vault):
  return accounts.at(vault.governance(), force=True)

@pytest.fixture
def user():
  return accounts.at(USER, force=True)

@pytest.fixture
def want(vault):
    return ERC20Upgradeable.at(vault.token())

## Forces reset before each test
@pytest.fixture(autouse=True)
def isolation(fn_isolation):
    pass


def test_check_upgrade_works(vault, proxy_admin, want, user, gov):
  new_logic = TheVaultWithoutTree.deploy({"from": gov})

  ## Proof we gotta upgrade
  with brownie.reverts():
    vault.withdrawAll({"from": user})

  ## Technically we could test for one slot missing
  ## But checking most is not a bad idea so let's do that

  prev_strategy = vault.strategy()
  prev_guardian = vault.guardian()
  prev_treasury = vault.treasury()

  prev_badgerTree = vault.badgerTree()

    
  prev_lifeTimeEarned = vault.lifeTimeEarned()
  prev_lastHarvestedAt = vault.lastHarvestedAt()
  prev_lastHarvestAmount = vault.lastHarvestAmount()
  prev_assetsAtLastHarvest = vault.assetsAtLastHarvest()

  prev_performanceFeeGovernance = vault.performanceFeeGovernance()
  prev_performanceFeeStrategist = vault.performanceFeeStrategist()
  prev_withdrawalFee = vault.withdrawalFee()
  prev_managementFee = vault.managementFee()

  prev_maxPerformanceFee = vault.maxPerformanceFee()
  prev_maxWithdrawalFee = vault.maxWithdrawalFee()
  prev_maxManagementFee = vault.maxManagementFee()

  prev_toEarnBps = vault.toEarnBps()

  
  ## Balance of Underlying
  initial_bal = want.balanceOf(user)
  initial_shares = vault.balanceOf(user)
  assert initial_shares > 0

  proxy_admin.upgrade(vault, new_logic, {"from": accounts.at(proxy_admin.owner(), force=True)})

  vault.withdrawAll({"from": user})

  assert want.balanceOf(user) > initial_bal
  assert vault.balanceOf(user) == 0

  ## Verify Slot are fine

  assert prev_strategy == vault.strategy()
  assert prev_guardian == vault.guardian()
  assert prev_treasury == vault.treasury()

  assert prev_badgerTree == vault.badgerTree()

    
  assert prev_lifeTimeEarned == vault.lifeTimeEarned()
  assert prev_lastHarvestedAt == vault.lastHarvestedAt()
  assert prev_lastHarvestAmount == vault.lastHarvestAmount()
  assert prev_assetsAtLastHarvest == vault.assetsAtLastHarvest()

  assert prev_performanceFeeGovernance == vault.performanceFeeGovernance()
  assert prev_performanceFeeStrategist == vault.performanceFeeStrategist()
  assert prev_withdrawalFee == vault.withdrawalFee()
  assert prev_managementFee == vault.managementFee()

  assert prev_maxPerformanceFee == vault.maxPerformanceFee()
  assert prev_maxWithdrawalFee == vault.maxWithdrawalFee()
  assert prev_maxManagementFee == vault.maxManagementFee()

  assert prev_toEarnBps == vault.toEarnBps()







