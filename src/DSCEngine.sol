// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDSCEngine} from "./interfaces/IDSCEngine.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

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
}

contract DSCEngine is ReentrancyGuard, IDSCEngine {
    //////////////////////
    /// State Variable ///
    //////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    // Mapping of collateral token addresses to their corresponding price feed addresses
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountOfDscMinted) private s_DscMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dscToken;

    /////////////////
    ///  Events   ///
    /////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

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

    constructor(address[] memory _tokenAddresses, address[] memory _priceFeedAddresses, address _dscAddress) {
        if (_tokenAddresses.length != _priceFeedAddresses.length) {
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
            s_collateralTokens.push(_tokenAddresses[i]);
        }

        i_dscToken = DecentralizedStableCoin(_dscAddress);
    }

    //////////////////////////
    /// External Functions ///
    //////////////////////////

    function depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral)
        external
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

    function mintDSC(uint256 _amountDscToMint) external moreThenZero(_amountDscToMint) nonReentrant {
        s_DscMinted[msg.sender] += _amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool success = i_dscToken.mint(msg.sender, _amountDscToMint);
        if (!success) {
            revert DSCEngine__Errors.MintFailed();
        }
    }

    /////////////////////////////////////////
    /// Internal & Private view Functions ///
    /////////////////////////////////////////

    function _healthFactor(address _user) private view returns (uint256) {
        (uint256 _totalDSCMinted, uint256 _collateralValueInUSD) = _getAccountInformation(_user);
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

        // Convert the price to USD
        // Assuming the price is in 8 decimal format, we need to convert it to 18 decimal format
        // 1e10(ADDITIONAL_FEED_PRECISION) is used to convert the price to 18 decimal format
        // 1e8 is used to convert the amount to 18 decimal format
        uint256 priceInUSD = uint256(price) * ADDITIONAL_FEED_PRECISION;
        uint256 priceInUSDWithPrecision = (priceInUSD * _amount) / 1e8;
        return priceInUSDWithPrecision;
    }
}
