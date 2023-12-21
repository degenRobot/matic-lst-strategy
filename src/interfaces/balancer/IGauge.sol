// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;
pragma experimental ABIEncoderV2;

interface IGauge {
    function deposit(uint256 _value) external;
    function withdraw(uint256 _value) external;
    function balanceOf(address _user) external view returns(uint256);
    function claim_rewards() external;
}