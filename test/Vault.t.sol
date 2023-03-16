// SPDX-License-Identifier: UNLINCESED
pragma solidity ^0.8.16;

import { Test } from "@forge-std/Test.sol";
import { Vault } from "src/src-default/Vault.sol";
import { Token } from "src/src-default/Token.sol";
import { LZEndpointMock } from "@layerZeroOmnichain/mocks/LZEndpointMock.sol";
import { WETH9 } from "test/WETH9.sol";
import { PoolToken } from "test/PoolToken.sol";
import { ILinkedList } from "src/src-default/interfaces/ILinkedList.sol";

contract VaultTest is Test {
    Vault vault;
    address public ownerVault = vm.addr(11);
    address public lucy = vm.addr(12);
    address public phoebe = vm.addr(13);
    address public julien = vm.addr(14);

    //
    // Constants
    //
    uint256 public constant UNISWAP_INITIAL_TOKEN_RESERVE = 1_000_000_000 ether;
    uint256 public constant UNISWAP_INITIAL_WETH_RESERVE = 1_000_000_000 ether;

    //
    // Uniswap V2 contracts
    //
    address public factory;
    address public router;
    address public pair;

    //
    // Tokens
    //
    Token public rewardToken;
    WETH9 public weth;
    PoolToken public poolToken;
    address LPToken;
    //
    // Pool
    //
    address public pool;

    LZEndpointMock lzEndpoint;
    uint256 REWARDS_PER_SECOND = 317;

    event LogAddress(address);
    event LogUint(uint256);
    event LogUintPair(uint256, uint256);
    event LogNode(ILinkedList.Node);

    function setUp() external {
        // Set-up the vault contract
        vm.label(ownerVault, "OwnerVault");
        vm.label(lucy, "Lucy");
        vm.label(phoebe, "Phoebe");
        vm.label(julien, "Julien");
        rewardToken = new Token(address(lzEndpoint), address(vault));
        LPToken = _setUpUniswap();
        vm.prank(ownerVault);
        vault = new Vault(LPToken);
    }

    function testSingleDeposit() external {
        vm.startPrank(lucy);
        uint256 balance = _userGetLPTokens(lucy);

        //Approve and transfer tokens to the vault
        (bool success,) = LPToken.call(abi.encodeWithSignature("approve(address,uint256)", address(vault), balance));
        require(success);

        vault.deposit(1, 6);
        vm.stopPrank();
    }

    function testRewardsMultiplier() external {
        // Give the user ETH
        vm.deal(lucy, 10 ether);

        vm.startPrank(lucy);
        uint256 balance = _userGetLPTokens(lucy);

        //Approve and transfer tokens to the vault
        (bool success,) = LPToken.call(abi.encodeWithSignature("approve(address,uint256)", address(vault), balance));
        require(success);

        // Test the 4 tiers
        uint8[4] memory rewardsTiers = [6, 1, 2, 4]; // 6 months, 1 year, 2 years, 4 years
        uint8[4] memory expectedRewardsMultiplier = [1, 2, 4, 8];
        uint256 rewardsMultiplier;
        vm.startPrank(lucy);
        for (uint256 i = 0; i < 4; i++) {
            vault.deposit(1, rewardsTiers[i]);
            (, rewardsMultiplier,,,) = vault.depositList(lucy, i);
            assertEq(rewardsMultiplier, expectedRewardsMultiplier[i]);
        }

        //Test with an incorrect lock up period
        vm.expectRevert();
        vault.deposit(1, 3);

        vm.stopPrank();
    }

    function _testProxy() external {
        //TODO
    }

    function testUniswapSetup() external {
        // Give the user ETH
        vm.deal(phoebe, 10 ether);

        // User gets LP Tokens after depositing tokens to the pair
        vm.startPrank(phoebe);
        uint256 balance = _userGetLPTokens(phoebe);

        //Approve and transfer tokens to the vault
        (bool success,) = LPToken.call(abi.encodeWithSignature("approve(address,uint256)", address(vault), balance));
        require(success);

        vm.stopPrank();

        // Try depositing, if the deposit is successful it's because the vault was able to transfer the tokens to itself
        vm.startPrank(address(vault));
        // Transfer the tokens to the contract
        (success,) = LPToken.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", phoebe, address(vault), balance)
        );
        require(success);
        vm.stopPrank();
    }

    function testRewardsAcrueing() external {
        uint256 startTime = block.timestamp;
        vm.startPrank(lucy);
        uint256 balance = _userGetLPTokens(lucy);

        //Approve and transfer tokens to the vault
        (bool success,) = LPToken.call(abi.encodeWithSignature("approve(address,uint256)", address(vault), balance));
        require(success);

        vault.deposit(100, 6);
        vm.stopPrank();

        vm.warp(startTime + 13 weeks); // 3 months
        vm.startPrank(julien);
        balance = _userGetLPTokens(julien);
        //Approve and transfer tokens to the vault
        (success,) = LPToken.call(abi.encodeWithSignature("approve(address,uint256)", address(vault), balance));
        require(success);
        vault.deposit(100, 6);
        vm.stopPrank();

        vm.warp(startTime + 27 weeks); // Lucy has expired - she will get the total awards for the first 3 months and half of the rewards for the next 3 months
        uint256 expectedRewards = (REWARDS_PER_SECOND * 13 weeks) + (REWARDS_PER_SECOND * 13 weeks) / 2;
        vm.startPrank(lucy);
        uint256 rewardsToClaim = vault.claimRewards(0);
        assertEq(rewardsToClaim, expectedRewards);
        vm.stopPrank();

        vm.warp(startTime + 53 weeks);
        vm.startPrank(julien); // at this point Julien will have half of the rewards for the initial 3 month period + all the rewards for the other 3 month period
        rewardsToClaim = vault.claimRewards(0);
        assertEq(rewardsToClaim, expectedRewards);
        vm.stopPrank();
    }

    function testVariousDeposits() external {
        vm.startPrank(phoebe);
        uint256 balance = _userGetLPTokens(phoebe);

        //Approve and transfer tokens to the vault
        (bool success,) = LPToken.call(abi.encodeWithSignature("approve(address,uint256)", address(vault), balance));
        require(success);

        vault.deposit(20, 1);
        vault.deposit(30, 2);
        vault.deposit(40, 4);
        vault.deposit(10, 6);
    }

    function _setUpUniswap() internal returns (address) {
        // Setup token contracts
        weth = new WETH9();
        vm.label(address(weth), "WETH");

        vm.startPrank(lucy);
        poolToken = new PoolToken();

        // Give tokens to all the actors/contracts
        poolToken.mint(address(this), UNISWAP_INITIAL_TOKEN_RESERVE);
        poolToken.mint(phoebe, 10 ether);
        poolToken.mint(lucy, 10 ether);
        poolToken.mint(julien, 10 ether);
        vm.stopPrank();

        // Give ether to all the actors
        vm.deal(phoebe, 10 ether);
        vm.deal(lucy, 10 ether);
        vm.deal(julien, 10 ether);

        // Setup Uniswap V2 contracts
        factory = deployCode("UniswapV2Factory.sol", abi.encode(address(0)));
        router = deployCode("UniswapV2Router02.sol", abi.encode(address(factory), address(weth)));
        vm.label(factory, "Factory");
        vm.label(router, "Router");

        // Create pair WETH <-> poolToken and add liquidity
        poolToken.approve(router, UNISWAP_INITIAL_TOKEN_RESERVE);

        (bool success,) = router.call{ value: UNISWAP_INITIAL_WETH_RESERVE }(
            abi.encodeWithSignature(
                "addLiquidityETH(address,uint256,uint256,uint256,address,uint256)",
                address(poolToken),
                UNISWAP_INITIAL_TOKEN_RESERVE,
                0,
                0,
                lucy, //deployer
                block.timestamp * 2
            )
        );
        require(success);

        // Get the pair to interact with
        (, bytes memory data) =
            factory.call(abi.encodeWithSignature("getPair(address,address)", address(poolToken), address(weth)));
        pair = abi.decode(data, (address));
        vm.label(pair, "Pair-LPTokens");

        return pair;
    }

    // Function used to give LPTokens to a user, must be preeced with startPrank
    function _userGetLPTokens(address user) internal returns (uint256) {
        // Wrap the ETH
        weth.deposit{ value: 5 ether }();

        // Use Pool to have LP tokens
        poolToken.approve(address(router), 5 ether);
        weth.approve(address(router), 5 ether);
        (bool success,) = router.call(
            abi.encodeWithSignature(
                "addLiquidity(address,address,uint256,uint256,uint256,uint256,address,uint256)",
                address(poolToken),
                address(weth),
                5 ether,
                5 ether,
                5 ether,
                5 ether,
                user, //recipient
                block.timestamp * 2
            )
        );
        require(success);

        // Make sure that the user received liquidty tokens
        bytes memory data;
        (success, data) = LPToken.call(abi.encodeWithSignature("balanceOf(address)", user));
        require(success);
        uint256 balance = abi.decode(data, (uint256));
        assertGt(balance, 0);

        return balance;
    }
}
