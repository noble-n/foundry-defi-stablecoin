//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import { console } from "forge-std/console.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";


contract Handler is Test {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    
    uint256 public timesMintIsCalled;
    address[] public usersWithCollateral;
    MockV3Aggregator public ethUsdPriceFeed;
    MockV3Aggregator public btcUsdPriceFeed;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

   constructor(DSCEngine _dSCEngine, DecentralizedStableCoin _dsc) {
        dsce = _dSCEngine;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = collateralTokens[0];
        wbtc = collateralTokens[1];

        ethUsdPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(weth)));
        btcUsdPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(wbtc)));
    }

    //redeem collateral

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        usersWithCollateral.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dsce.getCollateralBalanceOfUser(address(collateral), msg.sender);
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }

        vm.startPrank(msg.sender);
        dsce.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    function mintDsc(uint256 amount, uint256 addressSeed) public {

        if (usersWithCollateral.length == 0) {
            return;
        }
        address sender = usersWithCollateral[addressSeed % usersWithCollateral.length];
        
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = dsce.getAccountInformation(sender);
        
        int256 maxDscToMint = (int256(totalCollateralValueInUsd) / 2) - int256(totalDscMinted);
        
        if (maxDscToMint <= 0) {
            return;
        }
        amount = bound(amount, 1, uint256(maxDscToMint));
        
        vm.startPrank(sender);
        dsce.mintDsc(amount);
        vm.stopPrank();
        timesMintIsCalled++;
        
    }

    // function updateCollateralPrice(uint256 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    //     //btcUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    //helper functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return ERC20Mock(weth);
        } else {
            return ERC20Mock(wbtc);
        }
    }
}