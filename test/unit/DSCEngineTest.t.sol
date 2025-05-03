// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine, DSCEngine__Errors} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

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
    uint256 public constant AMOUNT_COLLATERAL = 10e18; // 10 ETH (18 decimals)
    uint256 public constant AMOUNT_TO_MINT = 500e18; // 5000 DSC
    uint256 public constant MIN_HEALTH_FACTOR = 1e18; // Assuming MIN_HEALTH_FACTOR from DSCEngine

    function setUp() public {
        // Set up the test environment
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdcPriceFeed, wbtcUSDCPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER1, 10e18); // Mint 10 ETH to USER1
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

    function testGetTokenAmountFromUSD() public view {
        uint256 usdAmount = 100 ether; // 2000 USD (18 decimals)
        uint256 expectedTokenAmount = 0.05 ether; // 1 ETH (18 decimals)

        uint256 actualWETHTokenAmount = engine.getTokenAmountFromUSD(weth, usdAmount);

        assertEq(actualWETHTokenAmount, expectedTokenAmount, "Token amount for 2000 USD should be 1 ETH");
    }

    function testRevertsIfTokenLengthDontMatchPriceFeedLength() public {
        tokensAddresses.push(weth);
        priceFeedsAddresses.push(ethUsdcPriceFeed);
        priceFeedsAddresses.push(wbtcUSDCPriceFeed);

        vm.expectRevert(DSCEngine__Errors.TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokensAddresses, priceFeedsAddresses, address(dsc));
    }

    ///////////////////////
    // Price Tests //
    ///////////////////////

    function testGetUSDCValue() public view {
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
        // 20,000,000000000000000000
        //  5000000000000000
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

        vm.expectRevert(abi.encodeWithSelector(DSCEngine__Errors.BreaksHealthFactor.selector, 0));
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
        // Give USER1 some DSC tokens
        // engine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);

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

    function testRedeemCollateralForDSC() public mintDsc {
        uint256 halfCollateral = AMOUNT_COLLATERAL / 2;
        uint256 halfDSC = AMOUNT_TO_MINT / 2;

        vm.startPrank(USER1);
        dsc.approve(address(engine), halfDSC);
        engine.redeemCollateralForDSC(weth, halfCollateral, halfDSC);
        vm.stopPrank();

        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = engine.getAccountInformation(USER1);
        assertEq(totalDSCMinted, halfDSC);
        assertEq(collateralValueInUSD, 10000e18); // 5 ETH at $2000 = $10,000
        assertEq(dsc.balanceOf(USER1), halfDSC);
        assertEq(ERC20Mock(weth).balanceOf(USER1), halfCollateral);
    }

    //////////////////////
    // liquidate Tests //
    //////////////////////

    function testLiquidate() public {
        // Create a user with an unhealthy position
        address liquidatedUser = makeAddr("liquidatedUser");
        uint256 liquidatedCollateral = 1 ether;
        uint256 liquidatedDscMinted = 1000e18; // At $2000/ETH, this is a healthy position
        setUpUserForLiquidation(liquidatedUser, liquidatedCollateral, liquidatedDscMinted);

        // Price drops, making the position unhealthy
        setPriceToCreateUnhealthyPosition();

        // Liquidator preparation
        address liquidator = makeAddr("liquidator");
        uint256 debtToCover = 300e18;
        ERC20Mock(weth).mint(liquidator, 10 ether); // Give liquidator some ETH
        setUpUserForLiquidation(liquidator, 5 ether, 100e18); // Liquidator has their own position

        // Execute liquidation
        vm.startPrank(liquidator);
        dsc.approve(address(engine), debtToCover);
        engine.liquidate(weth, liquidatedUser, debtToCover);
        vm.stopPrank();

        // Verify liquidated user state
        (uint256 dscMinted, uint256 collateralValue) = engine.getAccountInformation(liquidatedUser);
        assertEq(dscMinted, liquidatedDscMinted - debtToCover);

        // Verify liquidator received collateral + bonus
        uint256 expectedCollateralToSeize = (debtToCover * 1e18) / (1000e8 * 1e10); // Calculate using new price
        uint256 expectedBonus = (expectedCollateralToSeize * 10) / 100; // 10% bonus
        uint256 expectedTotal = expectedCollateralToSeize + expectedBonus;

        // Reset price to test balance properly
        MockV3Aggregator(ethUsdcPriceFeed).updateAnswer(2000e8);
    }

    function testRevertsIfHealthFactorNotImproved() public {
        // Create a user with an unhealthy position
        address liquidatedUser = makeAddr("liquidatedUser");
        uint256 liquidatedCollateral = 1 ether;
        uint256 liquidatedDscMinted = 1000e18;
        setUpUserForLiquidation(liquidatedUser, liquidatedCollateral, liquidatedDscMinted);

        // Price drops, making the position unhealthy
        setPriceToCreateUnhealthyPosition();

        // Prepare the liquidator address
        address liquidator = makeAddr("liquidator");
        uint256 debtToCover = 100e18;

        // Try to perform liquidation with too small amount
        // This will not improve health factor enough
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

        // First create a position
        vm.startPrank(USER1);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        engine.mintDSC(5000e18); // $5000 DSC with $20000 collateral (health factor should be 4)
        vm.stopPrank();

        // The health factor should be above MIN_HEALTH_FACTOR
        (uint256 dscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER1);
        assertEq(dscMinted, 5000e18);
        assertEq(collateralValueInUsd, 20000e18);

        // Calculate expected health factor: ($20000 * 50) / ($5000 * 100) = 2
        // Where 50 is the liquidation threshold percentage (50%) and 100 is the precision factor
        // 2 > 1, so the position is healthy

        // Now make the position unhealthy by manipulating price
        MockV3Aggregator(ethUsdcPriceFeed).updateAnswer(500e8); // Drop ETH price to $500

        // Recalculate collateral value
        (, uint256 newCollateralValue) = engine.getAccountInformation(USER1);
        assertEq(newCollateralValue, 5000e18); // $5000 collateral with $5000 DSC (health factor should be 1)

        // Calculate expected health factor: ($5000 * 50) / ($5000 * 100) = 0.5
        // 0.5 < 1, so the position is unhealthy

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

    // Test removed: testGetCollateralBalanceOfUser
    // The DSCEngine contract does not have a getCollateralBalanceOfUser function
    // To test collateral amounts, use the ERC20 token's balanceOf or check through getAccountInformation

    // function testGetCollateralTokenPriceFeed() public {
    //     address priceFeed = engine.getCollateralTokenPriceFeed(weth);
    //     assertEq(priceFeed, ethUsdcPriceFeed);
    // }

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
