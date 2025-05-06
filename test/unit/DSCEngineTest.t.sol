// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine, DSCEngine__Errors} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";
import {console} from "forge-std/console.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address ethUsdcPriceFeed;
    address wbtcUSDCPriceFeed;
    address weth;
    address wbtc;

    address public USER1 = makeAddr("user1");
    address public USER2 = makeAddr("user2");
    address public liquidator = makeAddr("liquidator");
    address public liquidatedUser = makeAddr("liquidatedUser");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_TO_MINT = 500e18; // 500 DSC
    uint256 public constant MIN_HEALTH_FACTOR = 1e18; // Assuming MIN_HEALTH_FACTOR from DSCEngine
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant DSC_AMOUNT_TO_MINT = 500 ether;
    uint256 public constant DSC_TO_BURN = 250 ether;
    uint256 public constant COLLATERAL_AMOUNT_TO_REDEEM = 5 ether;

    function setUp() public {
        // Set up the test environment
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdcPriceFeed, wbtcUSDCPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER1, 10e18); // Mint 10 ETH to USER1
        ERC20Mock(weth).mint(USER2, 10e18); // Mint WETH for USER2
    }

    modifier depositCollateral() {
        vm.startPrank(USER1);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier depositCollateralAndMintDsc() {
        vm.startPrank(USER1);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }

    modifier mintDsc() {
        vm.startPrank(USER1);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        engine.mintDSC(AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }

    modifier liquidated() {
        // First, USER1 deposits collateral and mints DSC
        vm.startPrank(USER1);
        ERC20Mock(weth).mint(USER1, AMOUNT_COLLATERAL);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();

        // Drop ETH price to make USER1's position unhealthy
        int256 ethUsdUpdatedPrice = 18e8; // $18 per ETH
        MockV3Aggregator(ethUsdcPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        // Check that USER1's health factor is below MIN_HEALTH_FACTOR
        uint256 userHealthFactor = engine.getHealthFactor(USER1);
        assert(userHealthFactor < MIN_HEALTH_FACTOR);

        // Setup liquidator with sufficient collateral and mint DSC through engine
        uint256 collateralToCover = 10 ether; // Increased to 10 ETH
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(engine), collateralToCover);
        engine.depositCollateral(weth, collateralToCover);
        uint256 debtToCover = 90e18; // Liquidate 90 DSC
        engine.mintDSC(debtToCover);
        dsc.approve(address(engine), debtToCover);
        engine.liquidate(weth, USER1, debtToCover);
        vm.stopPrank();

        _;
    }

    // Set up an unhealthy position for liquidation tests
    function setUpUserForLiquidation(address user, uint256 collateralAmount, uint256 dscToMint) internal {
        // Give the user some collateral
        ERC20Mock(weth).mint(user, collateralAmount);

        // User deposits collateral and mints DSC
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), collateralAmount);
        engine.depositCollateral(weth, collateralAmount);
        engine.mintDSC(dscToMint);
        vm.stopPrank();
    }

    // Manipulate the price to make a position unhealthy
    function setPriceToCreateUnhealthyPosition() internal {
        // Get the MockV3Aggregator and set a new lower price
        MockV3Aggregator(ethUsdcPriceFeed).updateAnswer(1000e8); // Price drops by 50%
    }

    ///////////////////////
    // Constructor Tests //
    ///////////////////////
    address[] public tokensAddresses;
    address[] public priceFeedsAddresses;
    uint8[] public tokenDecimals = new uint8[](1);

    function testGetTokenAmountFromUSD() public view {
        uint256 usdAmount = 100 ether; // 100 USD (18 decimals)
        uint256 expectedTokenAmount = 0.05 ether; // 0.05 ETH (18 decimals)

        uint256 actualWETHTokenAmount = engine.getTokenAmountFromUSD(weth, usdAmount);

        assertEq(actualWETHTokenAmount, expectedTokenAmount, "Token amount for 100 USD should be 0.05 ETH");
    }

    function testRevertsIfTokenLengthDontMatchPriceFeedLength() public {
        tokensAddresses.push(weth);
        priceFeedsAddresses.push(ethUsdcPriceFeed);
        priceFeedsAddresses.push(wbtcUSDCPriceFeed);
        tokenDecimals[0] = 18; // WETH decimals

        vm.expectRevert(DSCEngine__Errors.TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokensAddresses, priceFeedsAddresses, address(dsc), tokenDecimals);
    }

    ///////////////////////
    // Price Tests //
    ///////////////////////

    function testGetUSDValue() public view {
        uint256 amount = 1e18; // 1 ETH (18 decimals)
        uint256 expectedUsdValue = 2000e18; // Since mock feed returns 2000e8 and we convert it to 18 decimals

        uint256 actualUsdValue = engine.getUSDValue(weth, amount);

        assertEq(actualUsdValue, expectedUsdValue, "USD value for 1 ETH should be 2000 USD");
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER1);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine__Errors.AmountMustBeGreaterThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("Random Token", "RND", USER1, AMOUNT_COLLATERAL);
        vm.startPrank(USER1);
        vm.expectRevert(DSCEngine__Errors.CollateralTokenNotAllowed.selector);
        engine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDepostCollateralAndGetAccountInfo() public depositCollateral {
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = engine.getAccountInformation(USER1);
        uint256 expectedDepositAmount = engine.getTokenAmountFromUSD(weth, collateralValueInUSD);
        assertEq(totalDSCMinted, 0);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount, "Collateral value in USD should be 20000 USD");
    }

    //////////////////////////////////
    // depositCollateralAndMintDSC Tests //
    //////////////////////////////////

    function testDepositCollateralAndMintDSC() public {
        vm.startPrank(USER1);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();

        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = engine.getAccountInformation(USER1);
        assertEq(totalDSCMinted, AMOUNT_TO_MINT);
        assertEq(collateralValueInUSD, 20000e18); // 10 ETH at $2000 = $20,000
        assertEq(dsc.balanceOf(USER1), AMOUNT_TO_MINT);
    }

    function testRevertsIfDepositCollateralAndMintDSCBreaksHealthFactor() public {
        // Try to mint too much DSC for the collateral amount
        uint256 tooMuchDsc = 19000e18; // This will break the health factor (95% of collateral value)

        vm.startPrank(USER1);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine__Errors.BreaksHealthFactor.selector, 526315789473684210));
        engine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, tooMuchDsc);
        vm.stopPrank();
    }

    ///////////////////
    // mintDSC Tests //
    ///////////////////

    function testMintDSC() public depositCollateral {
        vm.startPrank(USER1);
        engine.mintDSC(AMOUNT_TO_MINT);
        vm.stopPrank();

        (uint256 totalDSCMinted,) = engine.getAccountInformation(USER1);
        assertEq(totalDSCMinted, AMOUNT_TO_MINT);
        assertEq(dsc.balanceOf(USER1), AMOUNT_TO_MINT);
    }

    function testRevertsIfMintAmountIsZero() public depositCollateral {
        vm.startPrank(USER1);
        vm.expectRevert(DSCEngine__Errors.AmountMustBeGreaterThanZero.selector);
        engine.mintDSC(0);
        vm.stopPrank();
    }

    function testRevertsIfMintBreaksHealthFactor() public depositCollateral {
        // Try to mint too much DSC for the collateral amount
        uint256 tooMuchDsc = 19000e18; // This will break the health factor (95% of collateral value)

        vm.startPrank(USER1);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine__Errors.BreaksHealthFactor.selector, 526315789473684210));
        engine.mintDSC(tooMuchDsc);
        vm.stopPrank();
    }

    //////////////////////////
    // redeemCollateral Tests //
    //////////////////////////

    function testRedeemCollateral() public depositCollateral {
        // Debug: Check collateral balance and tokens
        uint256 collateralBalance = engine.getCollateralBalance(USER1, weth);
        console.log("Collateral balance for USER1 and WETH:", collateralBalance);
        assertEq(collateralBalance, AMOUNT_COLLATERAL, "Collateral balance should match deposited amount");
        address[] memory collateralTokens = engine.getCollateralTokens();
        console.log("Collateral tokens:");
        for (uint256 i = 0; i < collateralTokens.length; i++) {
            console.logAddress(collateralTokens[i]);
        }
        uint256 collateralValue = engine.getAccountCollateralValue(USER1);
        console.log("Collateral value in USD:", collateralValue);
        assertEq(collateralValue, 20000e18, "Collateral value should be 20000 USD");

        vm.startPrank(USER1);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = engine.getAccountInformation(USER1);
        assertEq(totalDSCMinted, 0);
        assertEq(collateralValueInUSD, 0);
        assertEq(ERC20Mock(weth).balanceOf(USER1), AMOUNT_COLLATERAL);
    }

    function testRevertsIfRedeemAmountIsZero() public depositCollateral {
        vm.startPrank(USER1);
        vm.expectRevert(DSCEngine__Errors.AmountMustBeGreaterThanZero.selector);
        engine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsIfRedeemBreaksHealthFactor() public mintDsc {
        // Try to redeem too much collateral, which would break the health factor
        vm.startPrank(USER1);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine__Errors.BreaksHealthFactor.selector, 0));
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    ///////////////////
    // burnDSC Tests //
    ///////////////////

    function testBurnDSC() public {
        vm.startPrank(USER1);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        dsc.approve(address(engine), AMOUNT_TO_MINT);
        engine.burnDSC(AMOUNT_TO_MINT);
        vm.stopPrank();

        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = engine.getAccountInformation(USER1);
        assertEq(totalDSCMinted, 0);
        assertEq(dsc.balanceOf(USER1), 0);
    }

    function testRevertsIfBurnAmountIsZero() public mintDsc {
        vm.startPrank(USER1);
        vm.expectRevert(DSCEngine__Errors.AmountMustBeGreaterThanZero.selector);
        engine.burnDSC(0);
        vm.stopPrank();
    }

    function testRevertsIfBurnAmountExceedsBalance() public mintDsc {
        vm.startPrank(USER1);
        dsc.approve(address(engine), AMOUNT_TO_MINT + 1);
        vm.expectRevert(); // This will revert with a transfer error due to insufficient balance
        engine.burnDSC(AMOUNT_TO_MINT + 1);
        vm.stopPrank();
    }

    ////////////////////////////////////
    // redeemCollateralForDSC Tests //
    ////////////////////////////////////

    function testRedeemCollateralForDSC() public depositCollateral {
        vm.startPrank(USER1);
        engine.mintDSC(DSC_AMOUNT_TO_MINT);
        dsc.approve(address(engine), DSC_TO_BURN);
        engine.redeemCollateralForDSC(weth, COLLATERAL_AMOUNT_TO_REDEEM, DSC_TO_BURN);
        vm.stopPrank();

        (uint256 dscMinted, uint256 collateralValue) = engine.getAccountInformation(USER1);
        assertEq(dscMinted, DSC_AMOUNT_TO_MINT - DSC_TO_BURN);
        assertEq(collateralValue, 10000e18);
        assertEq(ERC20Mock(weth).balanceOf(USER1), COLLATERAL_AMOUNT_TO_REDEEM);
    }

    //////////////////////
    // liquidate Tests //
    //////////////////////

    function testCannotLiquidateHealthyPosition() public depositCollateralAndMintDsc {
        address liquidator = makeAddr("liquidator");

        ERC20Mock(weth).mint(liquidator, 10 ether);

        // Attempt liquidation
        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(engine), 10 ether);
        engine.depositCollateralAndMintDSC(weth, 10 ether, 100e18);
        dsc.approve(address(engine), 100e18);

        vm.expectRevert(DSCEngine__Errors.HealthFactorNotUnderThreshold.selector);
        engine.liquidate(weth, liquidatedUser, 100e18);
        vm.stopPrank();
    }

    function testOriginalUserShouldBeLiquidated() public liquidated {
        (uint256 dscMinted, uint256 collateralValue) = engine.getAccountInformation(USER1);
        assertEq(dscMinted, AMOUNT_TO_MINT - 90e18, "USER1's DSC minted should be reduced by 90 DSC");
        assertEq(collateralValue, 81e18, "USER1's collateral value should be 4.5 ETH at $18");
    }

    function testLiquidate() public liquidated {
        // After liquidation:

        // 1. USER1's DSC debt should be reduced by 90 DSC
        (uint256 dscMinted, uint256 collateralValue) = engine.getAccountInformation(USER1);
        assertEq(dscMinted, AMOUNT_TO_MINT - 90e18, "USER1's DSC minted should be reduced by 90 DSC");

        // 2. Check that USER1 still has some collateral value left
        assertEq(collateralValue, 81e18, "USER1 should have 4.5 ETH worth $81 at $18");

        // 3. Calculate how much collateral the liquidator should have received
        uint256 ethPriceInUsd = 18e8; // Current ETH price in USD
        uint256 collateralToSeize = (90e18 * 1e18) / (ethPriceInUsd * 1e10); // 90 DSC
        console.log("collateralToSeize:", collateralToSeize);
        //
        uint256 bonusCollateral = (collateralToSeize * 10) / 100;
        uint256 totalCollateralToLiquidator = collateralToSeize + bonusCollateral;

        // 4. Check that liquidator received the expected amount of collateral
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(liquidator);
        assertEq(liquidatorWethBalance, totalCollateralToLiquidator, "Liquidator should receive 5.5 ETH");
        // 5. Check that the liquidator's DSC balance is reduced by the amount they used to cover the debt
        uint256 liquidatorDscBalance = dsc.balanceOf(liquidator);
        console.log("liquidatorDscBalance:", liquidatorDscBalance);
        (uint256 dscMintedLiquidator, uint256 collateralValueLiquidator) = engine.getAccountInformation(liquidator);
        console.log("dscMintedLiquidator:", dscMintedLiquidator);
        console.log("collateralValueLiquidator:", collateralValueLiquidator);

        // 5. USER1's health factor should be improved
        uint256 userHealthFactor = engine.getHealthFactor(liquidator);
        require(userHealthFactor >= MIN_HEALTH_FACTOR, "Health factor should be at least 1e18 after liquidation");
    }

    // function testRevertsIfHealthFactorNotImproved() public {
    //     // Create a user with an unhealthy position
    //     uint256 liquidatedCollateral = 1 ether;
    //     uint256 liquidatedDscMinted = 1000e18;
    //     setUpUserForLiquidation(liquidatedUser, liquidatedCollateral, liquidatedDscMinted);

    //     // Price drops, making the position unhealthy
    //     setPriceToCreateUnhealthyPosition();

    //     // Prepare the liquidator
    //     uint256 debtToCover = 100e18;
    //     uint256 liquidatorCollateral = 10 ether;

    //     // Liquidator deposits collateral and mints DSC
    //     vm.startPrank(liquidator);
    //     ERC20Mock(weth).mint(liquidator, liquidatorCollateral);
    //     ERC20Mock(weth).approve(address(engine), liquidatorCollateral);
    //     engine.depositCollateral(weth, liquidatorCollateral);
    //     engine.mintDSC(debtToCover); // Mint 100 DSC through DSCEngine
    //     dsc.approve(address(engine), debtToCover);

    //     // Expect liquidation to revert due to insufficient health factor improvement
    //     vm.expectRevert(DSCEngine__Errors.HealthFactorNotImproved.selector);
    //     engine.liquidate(weth, liquidatedUser, debtToCover);
    //     vm.stopPrank();
    // }

    ///////////////////////////////
    // Test Health Factor Calculations //
    ///////////////////////////////

    function testHealthFactorCalculation() public {
        // We'll test the internal _healthFactor function through the public interface
        vm.startPrank(USER1);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        engine.mintDSC(5000e18); // $5000 DSC with $20000 collateral (health factor should be 2)
        vm.stopPrank();

        // The health factor should be above MIN_HEALTH_FACTOR
        (uint256 dscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER1);
        assertEq(dscMinted, 5000e18);
        assertEq(collateralValueInUsd, 20000e18);

        // Calculate expected health factor: ($20000 * 50) / ($5000 * 100) = 2
        MockV3Aggregator(ethUsdcPriceFeed).updateAnswer(500e8); // Drop ETH price to $500

        // Recalculate collateral value
        (, uint256 newCollateralValue) = engine.getAccountInformation(USER1);
        assertEq(newCollateralValue, 5000e18); // $5000 collateral with $5000 DSC (health factor should be 0.5)

        // Drop price further to make it very unhealthy
        MockV3Aggregator(ethUsdcPriceFeed).updateAnswer(250e8); // Drop ETH price to $250

        // Attempting to redeem collateral should fail now
        vm.startPrank(USER1);
        vm.expectRevert(); // Should revert due to health factor being broken
        engine.redeemCollateral(weth, 1e18);
        vm.stopPrank();

        // Reset price
        MockV3Aggregator(ethUsdcPriceFeed).updateAnswer(2000e8);
    }

    //////////////////////////////////
    // getAccountCollateralValue Tests //
    //////////////////////////////////

    function testGetAccountCollateralValue() public {
        // Deposit multiple types of collateral
        vm.startPrank(USER1);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL); // 10 ETH at $2000 = $20,000

        // Mint some WBTC and deposit as collateral
        ERC20Mock(wbtc).mint(USER1, 1e8); // 1 BTC
        ERC20Mock(wbtc).approve(address(engine), 1e8);
        engine.depositCollateral(wbtc, 1e8); // 1 BTC at $1000 (mock price) = $1,000
        vm.stopPrank();

        // Get account collateral value
        uint256 collateralValue = engine.getAccountCollateralValue(USER1);

        // Value should be $20,000 (ETH) + $1,000 (BTC) = $21,000
        assertEq(collateralValue, 21000e18);
    }

    ///////////////////////////////////
    // Test Miscellaneous View Functions //
    ///////////////////////////////////

    function testGetCollateralBalanceReturnsZeroForNonDepositor() public view {
        uint256 balance = engine.getCollateralBalance(USER1, weth);
        assertEq(balance, 0, "Balance should be 0 for user with no deposits");
    }

    function testGetCollateralBalanceReturnsCorrectAmountAfterDeposit() public {
        vm.startPrank(USER1);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        uint256 balance = engine.getCollateralBalance(USER1, weth);
        assertEq(balance, AMOUNT_COLLATERAL, "Balance should match deposited amount");
    }

    function testGetCollateralBalanceReturnsZeroForDifferentToken() public {
        vm.startPrank(USER1);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        uint256 balance = engine.getCollateralBalance(USER1, wbtc);
        assertEq(balance, 0, "Balance should be 0 for token not deposited");
    }

    function testGetCollateralBalanceForDifferentUser() public {
        vm.startPrank(USER1);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        vm.startPrank(USER2);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        uint256 balanceUser1 = engine.getCollateralBalance(USER1, weth);
        uint256 balanceUser2 = engine.getCollateralBalance(USER2, weth);
        assertEq(balanceUser1, AMOUNT_COLLATERAL, "USER1 balance should match deposited amount");
        assertEq(balanceUser2, AMOUNT_COLLATERAL, "USER2 balance should match deposited amount");
    }

    function testGetCollateralTokensReturnsCorrectTokens() public view {
        address[] memory tokens = engine.getCollateralTokens();
        assertEq(tokens.length, 2, "Should return 2 collateral tokens");
        assertEq(tokens[0], weth, "First token should be WETH");
        assertEq(tokens[1], wbtc, "Second token should be WBTC");
    }

    function testGetCollateralTokensArrayLength() public view {
        address[] memory tokens = engine.getCollateralTokens();
        assertEq(tokens.length, 2, "Collateral tokens array should have length 2");
    }

    // New tests for getUSDValue and getTokenAmountFromUSD
    function testGetUSDValueForWETH() public view {
        uint256 amount = 1e18; // 1 WETH (18 decimals)
        uint256 expectedUsdValue = 2000e18; // $2,000 (18 decimals)
        uint256 actualUsdValue = engine.getUSDValue(weth, amount);
        assertEq(actualUsdValue, expectedUsdValue, "USD value for 1 WETH should be 2000 USD");
    }

    function testGetUSDValueForWBTC() public view {
        uint256 amount = 1e8; // 1 WBTC (8 decimals)
        uint256 expectedUsdValue = 1000e18; // $1,000 (18 decimals)
        uint256 actualUsdValue = engine.getUSDValue(wbtc, amount);
        assertEq(actualUsdValue, expectedUsdValue, "USD value for 1 WBTC should be 1000 USD");
    }

    function testGetUSDValueForZeroAmount() public view {
        uint256 amount = 0;
        uint256 expectedUsdValue = 0;
        uint256 actualUsdValue = engine.getUSDValue(weth, amount);
        assertEq(actualUsdValue, expectedUsdValue, "USD value for 0 amount should be 0");
    }

    function testGetTokenAmountFromUSDForWETH() public view {
        uint256 usdAmount = 2000e18; // 2,000 USD (18 decimals)
        uint256 expectedTokenAmount = 1e18; // 1 WETH (18 decimals)
        uint256 actualTokenAmount = engine.getTokenAmountFromUSD(weth, usdAmount);
        assertEq(actualTokenAmount, expectedTokenAmount, "Token amount for 2000 USD should be 1 WETH");
    }

    function testGetTokenAmountFromUSDForWBTC() public view {
        uint256 usdAmount = 1000e18; // 1,000 USD (18 decimals)
        uint256 expectedTokenAmount = 1e8; // 1 WBTC (8 decimals)
        uint256 actualTokenAmount = engine.getTokenAmountFromUSD(wbtc, usdAmount);
        assertEq(actualTokenAmount, expectedTokenAmount, "Token amount for 1000 USD should be 1 WBTC");
    }

    function testGetTokenAmountFromUSDForZeroUSD() public view {
        uint256 usdAmount = 0;
        uint256 expectedTokenAmount = 0;
        uint256 actualTokenAmount = engine.getTokenAmountFromUSD(weth, usdAmount);
        assertEq(actualTokenAmount, expectedTokenAmount, "Token amount for 0 USD should be 0");
    }

    ///////////////////////////////////
    // Test DecentralizedStableCoin Functions //
    ///////////////////////////////////

    function testDscMintAndBurn() public {
        // Deposit collateral and mint DSC
        vm.startPrank(USER1);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);

        // Verify DSC was minted
        assertEq(dsc.balanceOf(USER1), AMOUNT_TO_MINT);

        // Test DSC burn function
        dsc.approve(address(engine), AMOUNT_TO_MINT);
        engine.burnDSC(AMOUNT_TO_MINT);

        // Verify DSC was burned
        assertEq(dsc.balanceOf(USER1), 0);
        vm.stopPrank();
    }

    function testDscCannotMintToZeroAddress() public {
        // Try to mint directly using DSC (not through engine)
        vm.expectRevert();
        dsc.mint(address(0), 100);
    }

    function testDscCannotBurnMoreThanBalance() public {
        // Mint some DSC first via engine
        vm.startPrank(USER1);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, 100);

        // Try to burn more than balance
        vm.expectRevert();
        dsc.burn(200);
        vm.stopPrank();
    }

    function testDscCannotBurnZeroAmount() public {
        // Mint some DSC first via engine
        vm.startPrank(USER1);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, 100);

        // Try to burn zero amount
        vm.expectRevert();
        dsc.burn(0);
        vm.stopPrank();
    }
}
