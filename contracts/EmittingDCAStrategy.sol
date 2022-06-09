// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {BaseStrategy} from "@badger-finance/BaseStrategy.sol";
import {FantomSwapper} from "./lib/FantomSwapper.sol";
import {IERC20Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import {IRewardsManager} from "../interfaces/badger/IRewardsManager.sol";
import {IUniswapRouterV2} from "../interfaces/uniswap/IUniswapRouterV2.sol";
import {ILpDepositor, Amounts} from "../interfaces/solidex/ILpDepositor.sol";
import {IBaseV1Router01} from "../interfaces/solidly/IBaseV1Router01.sol";
import {ICurveRouter} from "../interfaces/curve/ICurveRouter.sol";
import {IBaseV1Pair} from "../interfaces/solidly/IBaseV1Pair.sol";
import {route} from "../interfaces/solidly/IBaseV1Router01.sol";


/// @dev A DCA Emitting Strategy that claims tokens, sells them for reward and emits reward to the tree
contract EmittingDCAStrategy is BaseStrategy, FantomSwapper {
    // address public want; // Inherited from BaseStrategy
    IERC20Upgradeable public reward; // Token we autocompound into

    // Solidex
    ILpDepositor public constant lpDepositor =
        ILpDepositor(0x26E1A0d851CF28E697870e1b7F053B605C8b060F);

    /// @dev Initialize the Strategy with security settings as well as tokens
    /// @notice Proxies will set any non constant variable you declare as default value
    /// @dev add any extra changeable variable at end of initializer as shown
    function initialize(address _vault, address[2] memory _wantConfig) public initializer {
        __BaseStrategy_init(_vault);
        address _want = _wantConfig[0]; // Cache to not read from storage below

        want = _want;
        reward = IERC20Upgradeable(_wantConfig[1]);

        IERC20Upgradeable(_want).safeApprove(address(lpDepositor), type(uint256).max);

        FantomSwapper__Initialize();
    }

    /// @dev Return the name of the strategy
    function getName() external pure override returns (string memory) {
        return "SolidexEmittingStrat";
    }

    /// @dev Return a list of protected tokens
    /// @notice It's very important all tokens that are meant to be in the strategy to be marked as protected
    /// @notice this provides security guarantees to the depositors they can't be sweeped away
    function getProtectedTokens() public view virtual override returns (address[] memory) {
        address[] memory protectedTokens = new address[](2);
        protectedTokens[0] = want;
        protectedTokens[1] = address(reward);
        return protectedTokens;
    }

    /// @dev Deposit `_amount` of want, investing it to earn yield
    function _deposit(uint256 _amount) internal override {
        lpDepositor.deposit(want, _amount);
    }

    /// @dev Withdraw all funds, this is used for migrations, most of the time for emergency reasons
    function _withdrawAll() internal override {
        lpDepositor.withdraw(want, balanceOfPool());
    }

    /// @dev Withdraw `_amount` of want, so that it can be sent to the vault / depositor
    /// @notice just unlock the funds and return the amount you could unlock
    function _withdrawSome(uint256 _amount) internal override returns (uint256) {
        lpDepositor.withdraw(want, _amount);
        return _amount;
    }


    /// @dev Does this function require `tend` to be called?
    function _isTendable() internal override pure returns (bool) {
        return false; // Change to true if the strategy should be tended
    }

    function _harvest() internal override returns (TokenAmount[] memory harvested) {
        // Any time you use Storage var more than once, just cache and read from memory
        IERC20Upgradeable cachedReward = reward;
        address cachedWant = want;

        // 1. Claim rewards
        address[] memory pools = new address[](1);
        pools[0] = cachedWant;
        lpDepositor.getReward(pools);

        // 2. Swap all SOLID for wFTM
        uint256 solidBalance = SOLID.balanceOf(address(this));
        if (solidBalance > 0) {
            _doOptimalSwap(address(SOLID), address(wFTM), solidBalance);
        }

        // 3. Swap all SEX for wFTM
        uint256 sexBalance = SEX.balanceOf(address(this));
        if (sexBalance > 0) {
            _doOptimalSwap(address(SEX), address(wFTM), sexBalance);
        }

        // 4. Swap all wFTM for Reward
        uint256 wFTMBalance = wFTM.balanceOf(address(this));
        if (wFTMBalance > 0 && reward != wFTM) {
            _doOptimalSwap(address(wFTM), address(cachedReward), wFTMBalance);
        }

        uint256 totalReward = cachedReward.balanceOf(address(this));


        harvested = new TokenAmount[](2);
        harvested[0] = TokenAmount(cachedWant, 0);
        harvested[1] = TokenAmount(address(cachedReward), totalReward);

        // keep this to get paid!
        _reportToVault(0); // Keep at 0 as the strat emits
        
        // Use this if your strategy doesn't sell the extra tokens
        // This will take fees and send the token to the badgerTree
        _processExtraToken(address(cachedReward), totalReward); // Emit the token here

        return harvested;
    }


    // Example tend is a no-op which returns the values, could also just revert
    function _tend() internal override returns (TokenAmount[] memory tended){
        // Nothing tended
        tended = new TokenAmount[](2);
        tended[0] = TokenAmount(want, 0);
        tended[1] = TokenAmount(address(reward), 0); 
        return tended;
    }

    /// @dev Return the balance (in want) that the strategy has invested somewhere
    function balanceOfPool() public view override returns (uint256) {
        return lpDepositor.userBalances(
            address(this),
            want
        );
    }

    /// @dev Return the balance of rewards that the strategy has accrued
    /// @notice Used for offChain APY and Harvest Health monitoring
    function balanceOfRewards() external view override returns (TokenAmount[] memory rewards) {
        address[] memory pools = new address[](1);
        pools[0] = want;

        Amounts[] memory pending = lpDepositor.pendingRewards(address(this), pools);

        // Rewards are 0
        rewards = new TokenAmount[](2);
        rewards[0] = TokenAmount(address(SOLID), pending[0].solid);
        rewards[1] = TokenAmount(address(SEX), pending[0].sex); 
        return rewards;
    }
}
