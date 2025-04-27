// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IDSCEngine
 * @author Sohail Ishaque
 * @notice Interface for DSCEngine core functions
 */
interface IDSCEngine {
    // function depositCollateralAndMintDSC() external;
    function depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral) external;
    // function redeemCollateralForDSC() external;
    // function redeemCollateral() external;
    function mintDSC(uint256) external;
    // function burnDSC() external;
    // function liquidate() external;
    // function getHealthFactor() external view;
}
