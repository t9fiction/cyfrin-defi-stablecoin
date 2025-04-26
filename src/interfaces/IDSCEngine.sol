// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IDSCEngine
 * @author Sohail Ishaque
 * @notice Interface for DSCEngine core functions
 */
interface IDSCEngine {
    function depositCollateralAndMintPKR() external;
    function depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral) external;
    function redeemCollateralForPKR() external;
    function redeemCollateral() external;
    function mintPKR() external;
    function burnPKR() external;
    function liquidate() external;
    function getHealthFactor() external view;
}
