from brownie import *
from helpers.constants import MaxUint256

## TODO: Make test fail by default so dev has to fix

def test_are_you_trying(deployer, user, reward, reward_whale, badgerTree, vault, strategy, want, governance):
    """
    Verifies that you set up the Strategy properly
    """
    # Setup
    startingBalance = want.balanceOf(deployer)

    depositAmount = startingBalance // 2
    assert startingBalance >= depositAmount
    assert startingBalance >= 0
    # End Setup

    # Deposit
    assert want.balanceOf(vault) == 0

    want.approve(vault, MaxUint256, {"from": deployer})
    vault.depositFor(user, depositAmount, {"from": deployer})

    available = vault.available()
    assert available > 0

    vault.earn({"from": governance})

    chain.sleep(10000 * 13)  # Mine so we get some interest

    ## TEST 1: Does the want get used in any way?
    assert want.balanceOf(vault) == depositAmount - available

    # Did the strategy do something with the asset?
    # assert want.balanceOf(strategy) < available

    # Use this if it should invest all
    # assert want.balanceOf(strategy) == 0 ## Most staking invest all, change to above if needed

    # Change to this if the strat is supposed to hodl and do nothing
    assert strategy.balanceOfWant() == depositAmount * vault.toEarnBps() // vault.MAX_BPS()

    ## Simulate earning by sending a deposit of rewards[0]
    reward.transfer(strategy, 10e18, {"from": reward_whale}) ## TODO: Remove

    harvest = strategy.harvest({"from": governance})

    ## TEST 2: Does the strategy emit anything?
    event = harvest.events["TreeDistribution"]
    assert event["token"] == reward.address ## Add token you emit
    assert event["amount"] > 0 ## We want it to emit something

    ## Test 3: Verify the badgerTree shows rewards for the Depositor
    current_epoch = badgerTree.currentEpoch()
    assert badgerTree.rewards(current_epoch, vault, reward) > 0

    ## Accrue so we get total points
    badgerTree.accrueUser(current_epoch, vault, user)

    ## Tracking is somewhat correct
    assert badgerTree.getBalanceAtEpoch(current_epoch, vault, user)[0] > 0

    ## And total points are non-zero
    assert badgerTree.points(current_epoch, vault, user) > 0

    ## Wait for end of epoch
    chain.sleep(badgerTree.SECONDS_PER_EPOCH() + 1)
    chain.mine()
    badgerTree.startNextEpoch({"from": user})

    user_reward_balance_prev = reward.balanceOf(user)

    ## Have user claim
    badgerTree.claimReward(current_epoch, vault, reward, user)

    ## They receive 100% of rewards (only depositor)
    assert reward.balanceOf(user) - user_reward_balance_prev == event["amount"]


