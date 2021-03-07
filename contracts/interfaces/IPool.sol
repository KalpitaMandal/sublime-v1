// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.0;

interface IPool {

    
    function getLoanStatus() external view returns (uint256);

    function depositCollateral(uint256 _amount, bool _transferFromSavingsAccount) external payable;

    function addCollateralInMarginCall(
        address _lender,
        uint256 _amount,
        bool _isDirect
    ) external payable;

    function withdrawBorrowedAmount() external;

    function beforeTransfer(
        address _from,
        address _to,
        uint256 _amount
    ) external ;

    function setPoolToken(address _poolToken) external;
}
