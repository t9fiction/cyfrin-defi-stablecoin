// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IDSCEngine
 * @author Sohail Ishaque
 * @notice Interface for DSCEngine core functions
 */
interface IDSCEngine {
    function depositCollateralAndMintDSC(address, uint256, uint256) external;
    function depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral) external;
    function redeemCollateralForDSC(address, uint256, uint256) external;
    function redeemCollateral(address, uint256) external;
    function mintDSC(uint256) external;
    function burnDSC(uint256) external;
    function liquidate(address, address, uint256) external;
    // function getHealthFactor() external view;
}
