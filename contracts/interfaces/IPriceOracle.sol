// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.0;

interface IPriceOracle {
    function getLatestPrice(address num, address den)
        external
        view
        returns (uint256, uint256);
    function doesFeedExist(address btoken, address ctoken) external view returns(bool);
}
