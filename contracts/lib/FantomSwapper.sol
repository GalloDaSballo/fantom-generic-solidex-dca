// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {IERC20Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import {SafeERC20Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";



import {IUniswapRouterV2} from "../../interfaces/uniswap/IUniswapRouterV2.sol";
import {IBaseV1Router01} from "../../interfaces/solidly/IBaseV1Router01.sol";
import {ICurveRouter} from "../../interfaces/curve/ICurveRouter.sol";
import {IBaseV1Pair} from "../../interfaces/solidly/IBaseV1Pair.sol";
import {route} from "../../interfaces/solidly/IBaseV1Router01.sol";

contract FantomSwapper {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // ===== Token Registry =====

    IERC20Upgradeable public constant SOLID =
        IERC20Upgradeable(0x888EF71766ca594DED1F0FA3AE64eD2941740A20);
    IERC20Upgradeable public constant SEX =
        IERC20Upgradeable(0xD31Fcd1f7Ba190dBc75354046F6024A9b86014d7);
    IERC20Upgradeable public constant wFTM =
        IERC20Upgradeable(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);
      // Solidly Doesn't revert on failure
    IBaseV1Router01 public constant SOLIDLY_ROUTER = IBaseV1Router01(0xa38cd27185a464914D3046f0AB9d43356B34829D);

    // Spookyswap, reverts on failure
    IUniswapRouterV2 public constant SPOOKY_ROUTER = IUniswapRouterV2(0xF491e7B69E4244ad4002BC14e878a34207E38c29); // Spookyswap

    // Curve / Doesn't revert on failure
    ICurveRouter public constant CURVE_ROUTER = ICurveRouter(0x74E25054e98fd3FCd4bbB13A962B43E49098586f); // Curve quote and swaps
  function FantomSwapper__Initialize() internal {
    SOLID.safeApprove(address(SOLIDLY_ROUTER), type(uint256).max);
    SOLID.safeApprove(address(SPOOKY_ROUTER), type(uint256).max);
    SOLID.safeApprove(address(CURVE_ROUTER), type(uint256).max);

    SEX.safeApprove(address(SOLIDLY_ROUTER), type(uint256).max);
    SEX.safeApprove(address(SPOOKY_ROUTER), type(uint256).max);
    SEX.safeApprove(address(CURVE_ROUTER), type(uint256).max);

    // Extra approve is for wFTM as we need a liquid token for certain swaps
    wFTM.safeApprove(address(SOLIDLY_ROUTER), type(uint256).max);
    wFTM.safeApprove(address(SPOOKY_ROUTER), type(uint256).max);
    wFTM.safeApprove(address(CURVE_ROUTER), type(uint256).max);
  }

  function _doOptimalSwap(address tokenIn, address tokenOut, uint256 amountIn) internal returns (uint256) {
      // Check Solidly
      (uint256 solidlyQuote, bool stable) = IBaseV1Router01(SOLIDLY_ROUTER).getAmountOut(amountIn, tokenIn, tokenOut);

      // Check Curve
      (, uint256 curveQuote) = ICurveRouter(CURVE_ROUTER).get_best_rate(tokenIn, tokenOut, amountIn);

      uint256 spookyQuote; // 0 by default

      // Check Spooky (Can Revert)
      address[] memory path = new address[](2);
      path[0] = address(tokenIn);
      path[1] = address(tokenOut);


      // NOTE: Ganache sometimes will randomly revert over this line, no clue why, you may need to comment this out for testing on forknet
    //   try SPOOKY_ROUTER.getAmountsOut(amountIn, path) returns (uint256[] memory spookyAmounts) {
    //       spookyQuote = spookyAmounts[spookyAmounts.length - 1]; // Last one is the outToken
    //   } catch (bytes memory) {
    //       // We ignore as it means it's zero
    //   }
      
      // On average, we expect Solidly and Curve to offer better slippage
      // Spooky will be the default case
      // Because we got quotes, we add them as min, but they are not guarantees we'll actually not get rekt
      if(solidlyQuote > spookyQuote) {
          // Either SOLID or curve
          if(curveQuote > solidlyQuote) {
              // Curve swap here
              return CURVE_ROUTER.exchange_with_best_rate(tokenIn, tokenOut, amountIn, curveQuote);
          } else {
              // Solid swap here
              route[] memory _route = new route[](1);
              _route[0] = route(tokenIn, tokenOut, stable);
              uint256[] memory amounts = SOLIDLY_ROUTER.swapExactTokensForTokens(amountIn, solidlyQuote, _route, address(this), now);
              return amounts[amounts.length - 1];
          }

      } else if (curveQuote > spookyQuote) {
          // Curve Swap here
          return CURVE_ROUTER.exchange_with_best_rate(tokenIn, tokenOut, amountIn, curveQuote);
      } else {
          // Spooky swap here
          uint256[] memory amounts = SPOOKY_ROUTER.swapExactTokensForTokens(
              amountIn,
              spookyQuote, // This is not a guarantee of anything beside the quote we already got, if we got frontrun we're already rekt here
              path,
              address(this),
              now
          ); // Btw, if you're frontrunning us on this contract, email me at alex@badger.finance we have actual money for you to make

          return amounts[amounts.length - 1];
      }
  }
}