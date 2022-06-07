// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {BaseStrategy} from "@badger-finance/BaseStrategy.sol";
import {IERC20Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";


import {IStrategy} from "../../interfaces/badger/IStrategy.sol";
import {ISett15} from "../../interfaces/badger/ISett15.sol";


/// @dev A autocompounding strategy denominated in the underlying
/// NOTE: Unused code, but you can build on top of it
contract AutoCompoundingStrategyUnderlying is BaseStrategy {
    // address public want; // Inherited from BaseStrategy
    // uint256 public constant MAX_BPS = 10_000; // Inherited from BaseStrategy
    uint256 public constant ONE_ETH = 1e18;
    
    address public reward; // Token we farm
    ISett15 public emittingVault; // Sett we will use for gaining tokens
    address public claimTree; // Tree that the emitting strategy is using, which we'll claim from

    address constant BADGER = 0x3472A5A71965499acd81997a54BBA8D852C6E53d;
    /// @dev Initialize the Strategy with security settings as well as tokens
    /// @notice Proxies will set any non constant variable you declare as default value
    /// @dev add any extra changeable variable at end of initializer as shown
    function initialize(address _vault, address[3] memory _wantConfig) public initializer {
        __BaseStrategy_init(_vault);
        /// @dev Add config here
        want = _wantConfig[0];
        reward = _wantConfig[1];

        ISett15 _depositVault = ISett15(_wantConfig[2]);

        emittingVault = _depositVault;

        claimTree = _depositVault.badgerTree();
        
        // If you need to set new values that are not constants, set them like so
        // stakingContract = 0x79ba8b76F61Db3e7D994f7E384ba8f7870A043b7;

        // If you need to do one-off approvals do them here like so
        IERC20Upgradeable(want).safeApprove(
            address(_depositVault),
            type(uint256).max
        );
    }
    
    /// @dev Return the name of the strategy
    function getName() external pure override returns (string memory) {
        return "AutoCompoundingStrategy";
    }

    /// @dev Return a list of protected tokens
    /// @notice It's very important all tokens that are meant to be in the strategy to be marked as protected
    /// @notice this provides security guarantees to the depositors they can't be sweeped away
    function getProtectedTokens() public view virtual override returns (address[] memory) {
        address[] memory protectedTokens = new address[](3);
        protectedTokens[0] = want;
        protectedTokens[1] = address(emittingVault);
        protectedTokens[2] = reward;
        return protectedTokens;
    }

    /// @dev Deposit `_amount` of want, investing it to earn yield
    function _deposit(uint256 _amount) internal override {
        // Add code here to invest `_amount` of want to earn yield
        emittingVault.deposit(_amount);
    }

    /// @dev Withdraw all funds, this is used for migrations, most of the time for emergency reasons
    function _withdrawAll() internal override {
        // Withdraw everything
        emittingVault.withdrawAll();
    }

    /// @dev Withdraw `_amount` of want, so that it can be sent to the vault / depositor
    /// @notice just unlock the funds and return the amount you could unlock
    function _withdrawSome(uint256 _amountOfUnderlying) internal override returns (uint256) {
        // Given conversion rate, withdraw what needs to be withdrawn

        // Let ppfs = p
        // withdrawal fee = f
        // If s shares => s * p * (1 - w) underlying
        // Then x underlying => x / (p * (1 - w)) shares to withdraw

        uint256 shares = emittingVault.balanceOf(address(this));

        uint256 pricePerFullShare = emittingVault.getPricePerFullShare();

        uint256 withdrawalFee = emittingVault.withdrawalFee();

        uint256 sharesToWithdraw = _amountOfUnderlying.mul(ONE_ETH).mul(MAX_BPS).div(pricePerFullShare).div(MAX_BPS.sub(withdrawalFee));

        emittingVault.withdraw(sharesToWithdraw);

        return _amountOfUnderlying;
    }


    /// @dev Does this function require `tend` to be called?
    function _isTendable() internal override pure returns (bool) {
        return false; // Change to true if the strategy should be tended
    }

    function _harvest() internal override returns (TokenAmount[] memory harvested) {
        /// NOTE: The caller must also claimReward on behalf of the strategy for this to work

        address cachedReward = reward;
        address cachedWant = want;

        uint256 balanceOfReward = IERC20Upgradeable(cachedReward).balanceOf(address(this));

        // Nothing harvested, we have 2 tokens, return both 0s
        harvested = new TokenAmount[](2);
        harvested[0] = TokenAmount(cachedWant, 0);
        harvested[1] = TokenAmount(cachedReward, 0);

        if(balanceOfReward == 0) {
            return harvested; // Early 0 return
        }

        /// The strategy can then process the tokens and auto-compound them
        uint256 initialbalanceOfWant = balanceOfWant();

        // TODO: Sell reward for want here
        //  Idea of how to find optimal swap here: https://github.com/GalloDaSballo/strategy-ftm-solidex-DCA-templatized/blob/af10111d0b5c0acb167ced7999960b6c0fbc138d/contracts/StrategyGenericSolidexDCA.sol#L373

        uint256 difference = IERC20Upgradeable(cachedWant).balanceOf(address(this)).sub(initialbalanceOfWant);

        harvested[0] = TokenAmount(cachedWant, difference);

        // keep this to get paid!
        _reportToVault(difference);

        // May as well re-invest
        _deposit(difference);

        return harvested;
    }


    // Example tend is a no-op which returns the values, could also just revert
    function _tend() internal override returns (TokenAmount[] memory tended){
        // Nothing tended as we always auto-sell the tokens
        address cachedWant = want;

        uint256 availableWant = IERC20Upgradeable(cachedWant).balanceOf(address(this));

        if(availableWant > 0){
            _deposit(availableWant);
        }

        tended = new TokenAmount[](2);
        tended[0] = TokenAmount(cachedWant, availableWant);
        tended[1] = TokenAmount(reward, 0); 
        return tended;
    }


    /// @dev Return the balance (in want) that the strategy has invested somewhere
    function balanceOfPool() public view override returns (uint256) {
        uint256 shares = emittingVault.balanceOf(address(this));

        uint256 pricePerFullShare = emittingVault.getPricePerFullShare();

        uint256 withdrawalFee = emittingVault.withdrawalFee();

        // NOTE: Has to account for withdrawalFee
        // shares * pricePerFullShare * (1 - withdrawal fee)
        // Works even if fee is 0, as we are dividing 10_000 / 10_000
        return shares.mul(pricePerFullShare).mul(MAX_BPS.sub(withdrawalFee)).div(MAX_BPS).div(ONE_ETH);
    }

    /// @dev Return the balance of rewards that the strategy has accrued
    /// @notice Used for offChain APY and Harvest Health monitoring
    function balanceOfRewards() external view override returns (TokenAmount[] memory rewards) {
        // Rewards are 0
        rewards = new TokenAmount[](2);
        rewards[0] = TokenAmount(want, 0);
        rewards[1] = TokenAmount(BADGER, 0); 
        return rewards;
    }
}
