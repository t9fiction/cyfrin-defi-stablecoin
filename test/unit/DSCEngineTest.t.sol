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

    function testLiquidate() public {
        // Create a user with a healthy position initially
        uint256 liquidatedCollateral = 2 ether; // Health factor > 1 initially
        uint256 liquidatedDscMinted = 1100e18; // Increased to ensure health factor < 1 after price drop
        setUpUserForLiquidation(liquidatedUser, liquidatedCollateral, liquidatedDscMinted);

        // Price drops, making the position unhealthy
        setPriceToCreateUnhealthyPosition(); // ETH price to $1000, health factor ≈ 0.909

        // Liquidator preparation
        address liquidator = makeAddr("liquidator");
        uint256 debtToCover = 300e18;
        ERC20Mock(weth).mint(liquidator, 10 ether);

        // Set up liquidator's position with collateral and mint DSC
        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(engine), 5 ether);
        engine.depositCollateral(weth, 5 ether);
        engine.mintDSC(debtToCover); // Mint the required DSC for liquidation
        vm.stopPrank();

        // Execute liquidation
        vm.startPrank(liquidator);
        dsc.approve(address(engine), debtToCover);
        vm.expectEmit(true, true, true, true);
        emit DSCEngine.CollateralLiquidated(liquidatedUser, liquidator, weth, 0.33 ether);
        engine.liquidate(weth, liquidatedUser, debtToCover);
        vm.stopPrank();

        // Verify liquidated user state
        (uint256 dscMinted, uint256 collateralValue) = engine.getAccountInformation(liquidatedUser);
        assertEq(dscMinted, liquidatedDscMinted - debtToCover, "DSC minted should decrease by debt covered");
        assertEq(collateralValue, 1670e18, "Collateral value should reflect 1.67 ETH at $1000");

        // Verify liquidator received collateral + bonus
        uint256 expectedCollateralToSeize = (debtToCover * 1e18) / (1000e8 * 1e10); // 0.3 ETH
        uint256 expectedBonus = (expectedCollateralToSeize * 10) / 100; // 0.03 ETH
        uint256 expectedTotal = expectedCollateralToSeize + expectedBonus; // 0.33 ETH
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(liquidator);
        assertEq(liquidatorWethBalance, expectedTotal, "Liquidator should receive collateral plus bonus");
    }

    function testRevertsIfHealthFactorNotImproved() public {
        // Create a user with an unhealthy position
        uint256 liquidatedCollateral = 1 ether;
        uint256 liquidatedDscMinted = 1000e18;
        setUpUserForLiquidation(liquidatedUser, liquidatedCollateral, liquidatedDscMinted);

        // Price drops, making the position unhealthy
        setPriceToCreateUnhealthyPosition();

        // Prepare the liquidator address
        address liquidator = makeAddr("liquidator");
        uint256 debtToCover = 100e18;

        // Try to perform liquidation with too small amount
        vm.startPrank(liquidator);
        ERC20Mock(weth).mint(liquidator, 10 ether);
        dsc.mint(liquidator, debtToCover);
        dsc.approve(address(engine), debtToCover);

        vm.expectRevert(DSCEngine__Errors.HealthFactorNotImproved.selector);
        engine.liquidate(weth, liquidatedUser, debtToCover);
        vm.stopPrank();
    }

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
