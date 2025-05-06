// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wethUSDCPriceFeed;
        address wbtcUSDCPriceFeed;
        address wethToken;
        address wbtcToken;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else if (block.chainid == 31337) {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        } else {
            revert("Unsupported network");
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            wethUSDCPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcUSDCPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            wethToken: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtcToken: 0x29f2D40B0605204364af54EC677bD022dA425d03,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.wethUSDCPriceFeed != address(0)) {
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator ethUsdcPriceFeed = new MockV3Aggregator(8, 2000e8);
        MockV3Aggregator wbtcUsdcPriceFeed = new MockV3Aggregator(8, 1000e8);
        ERC20Mock wethMock = new ERC20Mock("Wrapped Ether", "WETH", msg.sender, 200000);
        ERC20Mock wbtcMock = new ERC20Mock("Wrapped Bitcoin", "WBTC", msg.sender, 50000);
        activeNetworkConfig = NetworkConfig({
            wethUSDCPriceFeed: address(ethUsdcPriceFeed),
            wbtcUSDCPriceFeed: address(wbtcUsdcPriceFeed),
            wethToken: address(wethMock),
            wbtcToken: address(wbtcMock),
            deployerKey: vm.envUint("ANVIL_PRIVATE_KEY")
        });
        vm.stopBroadcast();
        return activeNetworkConfig;
    }
}
