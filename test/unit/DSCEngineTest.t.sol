//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;

    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");


    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, , ) = config.activeNetworkConfig();

        // Fund USER with some WETH
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(LIQUIDATOR, STARTING_ERC20_BALANCE);

    }

    // Constructor tests
    address[] priceFeedAddresses;
    address[] tokenAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeedLength() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressAndPriceFeedAddressLengthMismatch.selector);
        new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(dsc)
        );
    }

    // Price tests

    function testGetUsdValue() public {
        // Arrange
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18; // 15 ETH * $2000/ETH
        // Act
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);

        // Assert
        assertEq(expectedUsd, actualUsd );
    }

    function testGetTokenAmountFromUsd() public {
        // Arrange
        uint256 usdAmount = 30000e18;
        uint256 expectedEth = 15e18; // $30,000 / $2000 per ETH

        // Act
        uint256 actualEth = dsce.getTokenAmountFromUsd(weth, usdAmount);

        // Assert
        assertEq(expectedEth, actualEth);
    }

    // Deposit Collateral tests

    function testRevertIfCollateralIsZero() public{
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnApprovedCollateral() public {
        ERC20Mock unApprovedToken = new ERC20Mock("unapproved", "UNAPP", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowed.selector);
        dsce.depositCollateral(address(unApprovedToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositCollateral(){
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    //Health Factor Tests

    function testHealthFactorIsInfiniteWithoutMintingDsc() public depositCollateral(){
        uint256 healthFactor = dsce.getHealthFactor(USER);
        assertEq(healthFactor, type(uint256).max);
    }

    // DSC tests
    function testRevertsIfMintAmountCausesHealthFactorToBeTooLow() public depositCollateral(){
        uint256 mintAmount = 11000e18;

        vm.startPrank(USER);
        vm.expectRevert();
        dsce.mintDsc(mintAmount);
        vm.stopPrank();
    }

    function testCanMintDscAndGetAccountInfo() public depositCollateral(){
        uint256 mintAmount = 5000e18;

        vm.startPrank(USER);
        dsce.mintDsc(mintAmount);
        vm.stopPrank();

        (uint256 totalDscMinted, ) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, mintAmount);
    }

    function testCanBurnDscAndGetAccountInfo() public depositCollateral(){
        uint256 mintAmount = 5000e18;
        uint256 burnAmount = 100e18;

        vm.startPrank(USER);
        dsce.mintDsc(mintAmount);
        dsc.approve(address(dsce), burnAmount);
        dsce.burnDsc(burnAmount);
        vm.stopPrank();

        (uint256 totalDscMinted, ) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, mintAmount - burnAmount);
    }


    //Liquidate tests

     modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.mintDsc(5000e18);
        vm.stopPrank();
        _;
    }
    function testRevertsIfHealthFactorIsAboveMinimumDuringLiquidation() public depositCollateral(){
        uint256 mintAmount = 5000e18;

        vm.startPrank(USER);
        dsce.mintDsc(mintAmount);
        vm.stopPrank();
        uint256 debtToCover = 100e18;
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dsce.liquidate(weth, USER, debtToCover);
    }

    function testRevertsIfDebtToCoverIsZero() public depositedCollateralAndMintedDsc {
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.liquidate(weth, USER, 0);
    }

    function testCanLiquidateIfHealthFactorIsBelowMinimum() public depositCollateral() {
        uint256 mintAmount = 5000e18;

        vm.startPrank(USER);
        dsce.mintDsc(mintAmount);
        vm.stopPrank();

        // Simulate price drop - ETH price drops from $2000 to $900
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(900e8); // $900 per ETH
        // New health factor: (10 ETH * $900 * 0.5) / $5,000 = 0.9 (below threshold!)

        uint256 debtToCover = 100e18; // Cover 100 DSC of debt

        
        // Mint DSC to liquidator so they can pay off the debt
        vm.startPrank(address(dsce)); // Only DSCEngine can mint
        dsc.mint(LIQUIDATOR, debtToCover);
        vm.stopPrank();

        // Liquidator approves and liquidates
        vm.startPrank(LIQUIDATOR);
        dsc.approve(address(dsce), debtToCover);
        dsce.liquidate(weth, USER, debtToCover);
        vm.stopPrank();

        // Verify liquidation worked
        (uint256 totalDscMinted, ) = dsce.getAccountInformation(USER);
        
        // User should have less debt now
        assertLt(totalDscMinted, mintAmount);
        
        // User's health factor should be improved (or position fully liquidated)
        uint256 healthFactorAfter = dsce.getHealthFactor(USER);
        assertGt(healthFactorAfter, 0);
    }

    function testLiquidatorReceivesCollateralWithBonus() public depositedCollateralAndMintedDsc {
        // Crash the price
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(900e8);
        
        uint256 debtToCover = 100e18; // $100
        
        // Calculate expected collateral with 10% bonus
        // debtToCover in ETH: $100 / $900 = 0.111... ETH
        // With 10% bonus: 0.111... * 1.1 = 0.122... ETH
        uint256 expectedCollateral = dsce.getTokenAmountFromUsd(weth, debtToCover);
        uint256 bonusCollateral = (expectedCollateral * 10) / 100;
        uint256 totalExpectedCollateral = expectedCollateral + bonusCollateral;
        
        // Setup liquidator
        vm.prank(address(dsce));
        dsc.mint(LIQUIDATOR, debtToCover);
        
        uint256 liquidatorCollateralBefore = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        
        vm.startPrank(LIQUIDATOR);
        dsc.approve(address(dsce), debtToCover);
        dsce.liquidate(weth, USER, debtToCover);
        vm.stopPrank();
        
        uint256 liquidatorCollateralAfter = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        assertEq(liquidatorCollateralAfter - liquidatorCollateralBefore, totalExpectedCollateral);
    }

    function testRevertsIfHealthFactorNotImproved() public depositedCollateralAndMintedDsc {
        // Crash the price severely
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(500e8); // $500 per ETH
        
        // Try to liquidate a tiny amount that won't improve health factor enough
        uint256 debtToCover = 1; // Extremely small amount
        
        vm.prank(address(dsce));
        dsc.mint(LIQUIDATOR, debtToCover);
        
        vm.startPrank(LIQUIDATOR);
        dsc.approve(address(dsce), debtToCover);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        dsce.liquidate(weth, USER, debtToCover);
        vm.stopPrank();
    }

    function testRevertsIfLiquidatorHealthFactorBreaks() public depositedCollateralAndMintedDsc {
        // Crash the price
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(900e8);
        
        // Give liquidator a risky position
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, 4000e18); // Almost maxed out
        vm.stopPrank();
        
        uint256 debtToCover = 10000e18; // Large liquidation
        
        vm.prank(address(dsce));
        dsc.mint(LIQUIDATOR, debtToCover);
        
        vm.startPrank(LIQUIDATOR);
        dsc.approve(address(dsce), debtToCover);
        
        // This should revert because liquidator's health factor breaks
        vm.expectRevert();
        dsce.liquidate(weth, USER, debtToCover);
        vm.stopPrank();
    }

        function testCannotLiquidateSelf() public depositedCollateralAndMintedDsc {
        // Arrange: Make user's position unhealthy
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(900e8); // Price crash: $2000 → $900
        
        uint256 debtToCover = 100e18;
        
        // Arrange: Give USER the DSC needed for liquidation
        vm.prank(address(dsce));
        dsc.mint(USER, debtToCover);
        
        // Act & Assert: USER attempts self-liquidation
        vm.startPrank(USER);
        dsc.approve(address(dsce), debtToCover);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowed.selector);
        dsce.liquidate(weth, USER, debtToCover);
        vm.stopPrank();
    }

    //  function testLiquidationEmitsEvents() public depositedCollateralAndMintedDsc {
    //     // Crash the price
    //     MockV3Aggregator(ethUsdPriceFeed).updateAnswer(900e8);
        
    //     uint256 debtToCover = 100e18;
        
    //     vm.prank(address(dsce));
    //     dsc.mint(LIQUIDATOR, debtToCover);
        
    //     vm.startPrank(LIQUIDATOR);
    //     dsc.approve(address(dsce), debtToCover);
        
    //     // You would check for emitted events here if you have them defined
    //     // vm.expectEmit(true, true, true, true);
    //     // emit Liquidated(USER, LIQUIDATOR, weth, debtToCover, ...);
        
    //     dsce.liquidate(weth, USER, debtToCover);
    //     vm.stopPrank();
    // }


}