// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

interface IProxyAdmin {
  function upgrade(address strat_proxy, address new_strat_logic) external;
  function owner() external view returns (address);
}