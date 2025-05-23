// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDSCEngine} from "./interfaces/IDSCEngine.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

interface IERC20Decimals {
    function decimals() external view returns (uint8);
}

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
    error TransferFailed();
    error MintFailed();
    error BreaksHealthFactor(uint256 healthFactor);
    error RedeemFailed();
    error HealthFactorNotUnderThreshold();
    error HealthFactorNotImproved();
    error InputAmountExceedsBalance();
}

contract DSCEngine is ReentrancyGuard, IDSCEngine {
    //////////////////////
    /// State Variable ///
    //////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountOfDscMinted) private s_DscMinted;
    mapping(address => bool) private s_isCollateralTokenAllowed;
    mapping(address token => uint8 decimals) private s_tokenDecimals; // New mapping for token decimals
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dscToken;

    /////////////////
    ///  Events   ///
    /////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);
    event CollateralLiquidated(address indexed user, address indexed liquidator, address indexed token, uint256 amount);
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
        if (!s_isCollateralTokenAllowed[_tokenCollateralAddress]) {
            revert DSCEngine__Errors.CollateralTokenNotAllowed();
        }
        _;
    }

    constructor(
        address[] memory _tokenAddresses,
        address[] memory _priceFeedAddresses,
        address _dscAddress,
        uint8[] memory _tokenDecimals
    ) {
        if (_tokenAddresses.length != _priceFeedAddresses.length || _tokenAddresses.length != _tokenDecimals.length) {
            revert DSCEngine__Errors.TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        if (_tokenAddresses.length == 0) {
            revert DSCEngine__Errors.CollateralTokenAddressNotProvided();
        }
        if (_dscAddress == address(0)) {
            revert DSCEngine__Errors.DSCTokenAddressNotProvided();
        }

        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            s_priceFeeds[_tokenAddresses[i]] = _priceFeedAddresses[i];
            s_tokenDecimals[_tokenAddresses[i]] = _tokenDecimals[i]; // Store decimals
            s_collateralTokens.push(_tokenAddresses[i]);
            s_isCollateralTokenAllowed[_tokenAddresses[i]] = true;
        }

        i_dscToken = DecentralizedStableCoin(_dscAddress);
    }

    //////////////////////////
    /// External Functions ///
    //////////////////////////

    function depositCollateralAndMintDSC(
        address _tokenCollateralAddress,
        uint256 _amountCollateral,
        uint256 _amountDscToMint
    ) external {
        depositCollateral(_tokenCollateralAddress, _amountCollateral);
        mintDSC(_amountDscToMint);
    }

    function depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral)
        public
        moreThenZero(_amountCollateral)
        isAllowedCollateralToken(_tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][_tokenCollateralAddress] += _amountCollateral;
        emit CollateralDeposited(msg.sender, _tokenCollateralAddress, _amountCollateral);
        bool success = IERC20(_tokenCollateralAddress).transferFrom(msg.sender, address(this), _amountCollateral);
        if (!success) {
            revert DSCEngine__Errors.TransferFailed();
        }
    }

    function mintDSC(uint256 _amountDscToMint) public moreThenZero(_amountDscToMint) nonReentrant {
        s_DscMinted[msg.sender] += _amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool success = i_dscToken.mint(msg.sender, _amountDscToMint);
        if (!success) {
            revert DSCEngine__Errors.MintFailed();
        }
    }

    function burnDSC(uint256 _amountDscToBurn) public moreThenZero(_amountDscToBurn) {
        _burnDSC(msg.sender, msg.sender, _amountDscToBurn);
        // Revert if health factor is broken, callet his after transfer and not before
        // _revertIfHealthFactorIsBroken(msg.sender);
    }

    // In order for RedeemCollateral to work
    // 1. Health factor must be over 1 after collateral pulled
    function redeemCollateral(address _tokenCollateralAddress, uint256 _amountCollateral)
        public
        moreThenZero(_amountCollateral)
        isAllowedCollateralToken(_tokenCollateralAddress)
        nonReentrant
    {
        _redeemCollateral(_tokenCollateralAddress, msg.sender, msg.sender, _amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function redeemCollateralForDSC(
        address _tokenCollateralAddress,
        uint256 _amountCollateral,
        uint256 _amountDSCToBurn
    ) external {
        burnDSC(_amountDSCToBurn);
        redeemCollateral(_tokenCollateralAddress, _amountCollateral);
        // RedeemCollateral already checks health factor
    }

    // Liquidation for some non healthy collateralized user
    function liquidate(address _tokenCollateral, address _user, uint256 _debtToCover)
        external
        moreThenZero(_debtToCover)
        nonReentrant
    {
        uint256 _startingUserHealthFactor = _healthFactor(_user);
        // 1. Check if the user is undercollateralized
        if (_startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__Errors.HealthFactorNotUnderThreshold();
        }

        uint256 _amountCollateralToSeize = getTokenAmountFromUSD(_tokenCollateral, _debtToCover);
        uint256 _bonusCollateral = (_amountCollateralToSeize * LIQUIDATION_BONUS) / 100;
        uint256 _totalCollateralToRedeem = _amountCollateralToSeize + _bonusCollateral;
        _redeemCollateral(_tokenCollateral, msg.sender, _user, _totalCollateralToRedeem);
        // 3. Burn the user's DSC
        _burnDSC(_user, msg.sender, _debtToCover);
        // 4. Check the user's health factor after liquidation
        uint256 _endingUserHealthFactor = _healthFactor(msg.sender);
        if (_endingUserHealthFactor <= _startingUserHealthFactor) {
            revert DSCEngine__Errors.HealthFactorNotImproved();
        }
        // 5. Emit the Liquidation event
        _revertIfHealthFactorIsBroken(msg.sender);
        emit CollateralLiquidated(_user, msg.sender, _tokenCollateral, _totalCollateralToRedeem);
    }

    /////////////////////////////////////////
    /// Internal & Private view Functions ///
    /////////////////////////////////////////

    function _burnDSC(address _onBehalfOf, address _dscFrom, uint256 _amountDscToBurn) private {
        s_DscMinted[_onBehalfOf] -= _amountDscToBurn;
        bool success = i_dscToken.transferFrom(_dscFrom, address(this), _amountDscToBurn);
        if (!success) {
            revert DSCEngine__Errors.TransferFailed();
        }
        i_dscToken.burn(_amountDscToBurn);
    }

    function _redeemCollateral(address _tokenCollateralAddress, address _to, address _from, uint256 _amountCollateral)
        private
    {
        if (s_collateralDeposited[_from][_tokenCollateralAddress] < _amountCollateral) {
            revert DSCEngine__Errors.InputAmountExceedsBalance();
        }
        s_collateralDeposited[_from][_tokenCollateralAddress] -= _amountCollateral;
        emit CollateralRedeemed(_from, _to, _tokenCollateralAddress, _amountCollateral);
        bool success = IERC20(_tokenCollateralAddress).transfer(_to, _amountCollateral);
        if (!success) {
            revert DSCEngine__Errors.RedeemFailed();
        }
    }

    function _healthFactor(address _user) private view returns (uint256) {
        (uint256 _totalDSCMinted, uint256 _collateralValueInUSD) = _getAccountInformation(_user);
        if (_totalDSCMinted == 0) {
            return type(uint256).max;
        }
        uint256 _collateralAdjustedForThreshold = (_collateralValueInUSD * LIQUIDATION_THRESHOLD) / 100;

        return (_collateralAdjustedForThreshold * 1e18) / _totalDSCMinted;
    }

    function _revertIfHealthFactorIsBroken(address _user) internal view {
        // Check health factor, Do they have enough collateral?
        // Revert if health factor is broken

        uint256 _userHealthFactor = _healthFactor(_user);
        if (_userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__Errors.BreaksHealthFactor(_userHealthFactor);
        }
    }

    function _getAccountInformation(address _user)
        private
        view
        returns (uint256 _totalDSCMinted, uint256 _collateralValueInUSD)
    {
        _totalDSCMinted = s_DscMinted[_user];
        _collateralValueInUSD = getAccountCollateralValue(_user);
    }

    function getAccountCollateralValue(address _user) public view returns (uint256 _totalCollateralValue) {
        // Loop through each token and get the value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address _token = s_collateralTokens[i];
            uint256 _amount = s_collateralDeposited[_user][_token];
            if (_amount > 0) {
                _totalCollateralValue += getUSDValue(_token, _amount);
            }
        }
    }

    function getUSDValue(address _token, uint256 _amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        uint8 decimals = s_tokenDecimals[_token];
        uint256 normalizedAmount = _amount * (10 ** (18 - decimals));
        uint256 priceInUSDWithPrecision = (uint256(price) * ADDITIONAL_FEED_PRECISION * normalizedAmount) / 1e18;
        return priceInUSDWithPrecision;
    }

    function getTokenAmountFromUSD(address _tokenCollateral, uint256 _usdAmountInWei) public view returns (uint256) {
        // Convert the price to USD
        // Assuming the price is in 8 decimal format, we need to convert it to 18 decimal format
        // 1e10(ADDITIONAL_FEED_PRECISION) is used to convert the price to 18 decimal format

        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_tokenCollateral]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        uint8 decimals = s_tokenDecimals[_tokenCollateral];
        uint256 normalizedPrice = uint256(price) * (10 ** (18 - decimals));
        return (_usdAmountInWei * 1e18) / (normalizedPrice * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountInformation(address _user) external view returns (uint256, uint256) {
        (uint256 _totalDSCMinted, uint256 _collateralValueInUSD) = _getAccountInformation(_user);
        return (_totalDSCMinted, _collateralValueInUSD);
    }

    function getCollateralBalance(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getHealthFactor(address _user) external view returns (uint256) {
        return _healthFactor(_user);
    }
}
