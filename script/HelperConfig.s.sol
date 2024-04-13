// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.22;

// imports
import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wETHUsdpriceFeed;
        address wBTCUsdpriceFeed;
        address wETH;
        address wBTC;
        uint256 deployerKey;
    }
    uint8 public constant DECIMAL = 8;
    int256 public constant ETH_USD__PRICE = 2000e8;
    int256 public constant BTC_USD__PRICE = 1000e8;
    uint256 public DEFAULT_ANVIL_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    NetworkConfig public ActiveNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            ActiveNetworkConfig = getSepoliaETHConfig();
        } else {
            ActiveNetworkConfig = getOrCreateAnviEthConfig();
        }
    }

    function getSepoliaETHConfig() public view returns (NetworkConfig memory) {
        return
            NetworkConfig({
                wETHUsdpriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306, // ETH / USD
                wBTCUsdpriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
                wETH: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
                wBTC: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
                deployerKey: vm.envUint("PRIVATE_KEY")
            });
    }

    function getOrCreateAnviEthConfig()
        public
        returns (NetworkConfig memory AnvilNetworkConfig)
    {
        if (ActiveNetworkConfig.wETH != address(0)) {
            return ActiveNetworkConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator ETHUsdpriceFeed = new MockV3Aggregator(
            DECIMAL,
            ETH_USD__PRICE
        );
        ERC20Mock wETHMock = new ERC20Mock("WETH", "WETH", msg.sender, 1000e8);

        MockV3Aggregator BTCUsdpriceFeed = new MockV3Aggregator(
            DECIMAL,
            BTC_USD__PRICE
        );
        ERC20Mock wBTCMock = new ERC20Mock("WBTC", "WBTC", msg.sender, 1000e8);
        vm.stopBroadcast();
        AnvilNetworkConfig = NetworkConfig({
            wETHUsdpriceFeed: address(ETHUsdpriceFeed),
            wBTCUsdpriceFeed: address(BTCUsdpriceFeed),
            wETH: address(wETHMock),
            wBTC: address(wBTCMock),
            deployerKey: DEFAULT_ANVIL_KEY
        });
    }
}
