// SPDX-License-Identifier: MIT
pragma solidity 0.7.0;

interface ISavingsAccount {
    //events
    event Deposited(
        address user,
        uint256 amount,
        address asset,
        address strategy
    );
    event StrategySwitched(
        address user,
        address currentStrategy,
        address newStrategy
    );
    event Withdrawn(
        address user,
        uint256 amountReceived,
        address token,
        address strategy
    );
    event WithdrawnAll(address user, uint256 tokenReceived, address asset);
    event Approved(address token, address from, address to, uint256 amount);
    event Transfer(
        address token,
        address strategy,
        address from,
        address to,
        uint256 amount
    );

    function deposit(
        uint256 amount,
        address asset,
        address strategy,
        address user
    ) external payable returns (uint256 sharesReceived);

    function depositFrom(
        uint256 amount,
        address asset,
        address strategy,
        address from,
        address to
    ) external payable returns (uint256 sharesReceived);

    /**
     * @dev Used to switch saving strategy of an asset
     * @param currentStrategy initial strategy of asset
     * @param newStrategy new strategy to invest
     * @param asset address of the asset
     * @param amount amount of **liquidity shares** to be reinvested
     */
    function switchStrategy(
        address currentStrategy,
        address newStrategy,
        address asset,
        uint256 amount
    ) external;

    /**
     * @dev Used to withdraw asset from Saving Account
     * @param withdrawTo address to which asset should be sent
     * @param amount amount of liquidity shares to withdraw
     * @param asset address of the asset to be withdrawn
     * @param strategy strategy from where asset has to withdrawn(ex:- compound,Aave etc)
     * @param withdrawShares boolean indicating to withdraw in liquidity share or underlying token
     */
    function withdraw(
        address payable withdrawTo,
        uint256 amount,
        address asset,
        address strategy,
        bool withdrawShares
    ) external returns (uint256);

    function withdrawAll(address _asset)
        external
        returns (uint256 tokenReceived);

    function approve(
        address token,
        address to,
        uint256 amount
    ) external;

    function transfer(
        address token,
        address to,
        address investedTo,
        uint256 amount
    ) external returns (uint256);

    function transferFrom(
        address token,
        address from,
        address to,
        address investedTo,
        uint256 amount
    ) external returns (uint256);
}
