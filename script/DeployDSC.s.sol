// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    uint8[] public tokenDecimals;

    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (
            address wethUSDCPriceFeed,
            address wbtcUSDCPriceFeed,
            address wethToken,
            address wbtcToken,
            uint256 deployerKey
        ) = config.activeNetworkConfig();

        tokenAddresses = [wethToken, wbtcToken];
        priceFeedAddresses = [wethUSDCPriceFeed, wbtcUSDCPriceFeed];
        tokenDecimals = [18, 8];

        vm.startBroadcast(deployerKey);

        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        DSCEngine engine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc), tokenDecimals);
        dsc.transferOwnership(address(engine));

        vm.stopBroadcast();

        return (dsc, engine, config);
    }
}
