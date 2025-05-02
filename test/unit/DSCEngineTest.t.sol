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
    address weth;

    address public USER1 = makeAddr("user1");
    uint256 public constant AMOUNT_COLLATERAL = 10e18; // 10 ETH (18 decimals)

    function setUp() public {
        // Set up the test environment
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdcPriceFeed,, weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER1, 10e18); // Mint 10 ETH to USER1
    }

    function test_SetUpWorks() public {
        // Verify that the contracts were deployed successfully
        assertTrue(address(dsc) != address(0), "DecentralizedStableCoin address is zero");
        assertTrue(address(engine) != address(0), "DSCEngine address is zero");
    }

    function testGetUSDCValue() public {
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
}
