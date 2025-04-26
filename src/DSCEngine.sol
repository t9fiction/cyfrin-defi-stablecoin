// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDSCEngine} from "./interfaces/IDSCEngine.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title DSCEngine
 * @author Sohail Ishaque
 * @notice Core engine contract for managing the collateralized PKR stablecoin system.
 * @dev Handles the business logic for collateral deposits, redemptions, debt positions, and stability mechanisms.
 */

/////////////////////
/// Custom Errors ///
/////////////////////
library DSCEngine__Errors {
    error AmountMustBeGreaterThanZero();
    error TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error CollateralTokenAddressNotProvided();
    error DSCTokenAddressNotProvided();
    error CollateralTokenNotAllowed();
}

contract DSCEngine is ReentrancyGuard, IDSCEngine {
    //////////////////////
    /// State Variable ///
    //////////////////////
    mapping(address token => address priceFeed) private s_priceFeeds;
    DecentralizedStableCoin private immutable i_dscToken;

    /////////////////
    /// Modifiers ///
    /////////////////

    modifier moreThenZero(uint256 _amount) {
        if (_amount <= 0) {
            revert DSCEngine__Errors.AmountMustBeGreaterThanZero();
        }
        _;
    }

    modifier isAllowedCollateralToken(address _tokenCollateralAddress) {
        if (_tokenCollateralAddress == address(0)) {
            revert DSCEngine__Errors.CollateralTokenNotAllowed();
        }
        _;
    }

    /////////////////
    /// Functions ///
    /////////////////

    constructor(
        address[] memory _tokenAddresses,
        address[] memory _priceFeedAddresses,
        address _dscAddress
    ) {
        if (_tokenAddresses.length != _priceFeedAddresses.length) {
            revert DSCEngine__Errors
                .TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        if (_tokenAddresses.length == 0) {
            revert DSCEngine__Errors.CollateralTokenAddressNotProvided();
        }
        if (_dscAddress == address(0)) {
            revert DSCEngine__Errors.DSCTokenAddressNotProvided();
        }

        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            s_priceFeeds[_tokenAddresses[i]] = _priceFeedAddresses[i];
        }

        i_dscToken = DecentralizedStableCoin(_dscAddress);
    }

    //////////////////////////

    function depositCollateral(
        address _tokenCollateralAddress,
        uint256 _amountCollateral
    )
        external
        moreThenZero(_amountCollateral)
        isAllowedCollateralToken(_tokenCollateralAddress)
        nonReentrant
    {}

    //////////////////////////
    /// External Functions ///
    //////////////////////////
}
