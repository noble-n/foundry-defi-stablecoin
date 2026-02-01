 //SPDX-License-Identifier: MIT

// //Invariants
// //1. Total DSC supply should be less than total collateral value
// //2. Getter view functions should never revert

 pragma solidity ^0.8.18;

// import {Test} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {DSCEngine} from "../../src/DSCEngine.sol";
// import {DeployDSC} from "../../script/DeployDSC.s.sol";
// import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
// import {HelperConfig} from "../../script/HelperConfig.s.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// contract OpenInvariantTest is StdInvariant {
//     DeployDSC deployer;
//     DSCEngine dsce;
//     DecentralizedStableCoin dsc;
//     HelperConfig config;
//     address weth;
//     address wbtc;

//     function setUp() external{
//         deployer = new DeployDSC();
//         (dsc, dsce, config) = deployer.run();
//         ( , , weth, wbtc, ) = config.activeNetworkConfig();
//         targetContract(address(dsce));
//     }

//     function invariant_protocolMustHaveMoreCollateralThanDSCSupply() public view {
//         uint256 totalSupply = dsc.totalSupply();
//         uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
//         uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsce));

//         uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited);
//         uint256 wbtcValue = dsce.getUsdValue(wbtc, totalWbtcDeposited);

//         uint256 totalCollateralValue = wethValue + wbtcValue;
//         assert(totalCollateralValue >= totalSupply);
//     }
// }