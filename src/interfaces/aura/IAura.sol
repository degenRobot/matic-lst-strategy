// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;
pragma experimental ABIEncoderV2;

interface IAura {
    function deposit(uint256 _pid, uint256 _amount, bool _stake) external;
    function depositAll(uint256 _pid, bool _stake) external;
    function withdraw(uint256 _pid, uint256 _amount, bool _stake) external;
    function claimRewards(uint256 _pid, address gauge) external;
}

interface IBaseRewardPool {
    function balanceOf(address _user) external view returns (uint256);
    function getReward(address _user, bool _claimExtras) external;
    function withdrawAndUnwrap(uint256 amount, bool claim) external;
}