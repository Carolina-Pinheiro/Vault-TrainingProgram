// SPDX-License-Identifier: UNLINCESED
pragma solidity ^0.8.16;

import { Test } from "@forge-std/Test.sol";
import { Vault } from "src/src-default/Vault.sol";
import { Token } from "src/src-default/Token.sol";
import { LZEndpointMock } from "@layerZeroOmnichain/mocks/LZEndpointMock.sol";
import { WETH9 } from "test/WETH9.sol";
import { PoolToken } from "test/PoolToken.sol";
import { ILinkedList } from "src/src-default/interfaces/ILinkedList.sol";
import { IVault } from "src/src-default/interfaces/IVault.sol";

contract VaultTest is Test {
    Vault vault;
    address public ownerVault = vm.addr(11);
    address public lucy = vm.addr(12);
    address public phoebe = vm.addr(13);
    address public julien = vm.addr(14);
    address public dacus = vm.addr(15);

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

    //-----------------------------------------------------------------------
    //------------------------------LOGS-------------------------------------
    //-----------------------------------------------------------------------
    event LogUint(uint256);
    event LogRewardsTokenMinted(address, uint256);
    event LogNode(ILinkedList.Node);
    event LogDepositExpired(address, uint256); // Owner and deposit id
    event LogWithdrawHasNotExpired(uint256);
    event LogUintArray(uint256[]);
    event LogWithdraw(address, uint256);
    event LogAddress(address);
    event LogUintPair(uint256, uint256);

    //-----------------------------------------------------------------------
    //------------------------------ERRORS-----------------------------------
    //-----------------------------------------------------------------------
    error NoRewardsToClaimError();
    error TransferOfLPTokensWasNotPossibleError();
    error NotEnoughAmountOfTokensDepositedError();
    error WrongLockUpPeriodError();

    function setUp() external {
        // Set-up the vault contract
        vm.label(ownerVault, "OwnerVault");
        vm.label(lucy, "Lucy");
        vm.label(phoebe, "Phoebe");
        vm.label(julien, "Julien");
        vm.label(dacus, "Dacus");
        rewardToken = new Token(address(lzEndpoint), address(vault));
        LPToken = _setUpUniswap();
        vm.prank(ownerVault);
        vault = new Vault(LPToken);
    }

    function testSingleDeposit() external {
        vm.startPrank(lucy);
        uint256 balance = _userGetLPTokens(lucy);

        //Approve  tokens to the vault
        _approveTokens(balance);

        vault.deposit(1, 6);
        vm.stopPrank();
    }

    function testRewardsMultiplier() external {
        vm.startPrank(lucy);
        uint256 balance = _userGetLPTokens(lucy);

        //Approve and transfer tokens to the vault
        _approveTokens(balance);

        // Test the 4 tiers
        vault.deposit(1, 6);
        vault.deposit(1, 1);
        vault.deposit(1, 2);
        vault.deposit(1, 4);
        vm.stopPrank();

        vm.startPrank(address(vault));
        ILinkedList.Node memory node6Months = vault.getDeposit(vault.ownersDepositId(lucy, 0));
        ILinkedList.Node memory node1Year = vault.getDeposit(vault.ownersDepositId(lucy, 1));
        ILinkedList.Node memory node2Years = vault.getDeposit(vault.ownersDepositId(lucy, 2));
        ILinkedList.Node memory node4Years = vault.getDeposit(vault.ownersDepositId(lucy, 3));
        vm.stopPrank();

        assertEq(node6Months.share, 1); // 6 months
        assertEq(node1Year.share, 2); // 1 year
        assertEq(node2Years.share, 4); // 2 years
        assertEq(node4Years.share, 8); // 4 years

        //Test with an incorrect lock up period
        vm.startPrank(lucy);
        vm.expectRevert(WrongLockUpPeriodError.selector);
        vault.deposit(1, 3);
        vm.stopPrank();
    }

    function _testProxy() external {
        //TODO
    }

    function testUniswapSetup() external {
        // User gets LP Tokens after depositing tokens to the pair
        vm.startPrank(phoebe);
        uint256 balance = _userGetLPTokens(phoebe);

        //Approve  tokens to the vault
        _approveTokens(balance);

        vm.stopPrank();

        // Try depositing, if the deposit is successful it's because the vault was able to transfer the tokens to itself
        vm.startPrank(address(vault));
        // Transfer the tokens to the contract
        (bool success,) = LPToken.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", phoebe, address(vault), balance)
        );
        require(success);
        vm.stopPrank();
    }

    function testRewardsAcrueing() external {
        uint256 startTime = block.timestamp;
        vm.startPrank(lucy);
        uint256 balance = _userGetLPTokens(lucy);

        //Approve tokens to the vault
        _approveTokens(balance);

        vault.deposit(100, 6);
        vm.stopPrank();

        vm.warp(startTime + 13 weeks); // 3 months
        vm.startPrank(julien);
        balance = _userGetLPTokens(julien);
        //Approve tokens to the vault
        _approveTokens(balance);
        vault.deposit(100, 6);
        vm.stopPrank();

        vm.warp(startTime + 27 weeks); // Lucy has expired - she will get the total awards for the first 3 months and half of the rewards for the next 3 months
        uint256 expectedRewards = (REWARDS_PER_SECOND * 13 weeks) + (REWARDS_PER_SECOND * 13 weeks) / 2;
        vm.startPrank(lucy);
        vm.expectEmit(true, true, true, true);
        emit LogRewardsTokenMinted(lucy, expectedRewards);
        uint256 rewardsToClaim = vault.claimRewards(0);
        assertEq(rewardsToClaim, expectedRewards);
        vm.stopPrank();

        vm.warp(startTime + 53 weeks);
        vm.startPrank(julien); // at this point Julien will have half of the rewards for the initial 3 month period + all the rewards for the other 3 month period
        vm.expectEmit(true, true, true, true);
        emit LogRewardsTokenMinted(julien, expectedRewards);
        rewardsToClaim = vault.claimRewards(0);
        assertEq(rewardsToClaim, expectedRewards);
        vm.stopPrank();
    }

    function testVariousDeposits() external {
        vm.startPrank(phoebe);
        uint256 balance = _userGetLPTokens(phoebe);

        //Approve tokens to the vault
        _approveTokens(balance);

        vault.deposit(20, 1);
        vault.deposit(30, 2);
        vault.deposit(40, 4);
        vault.deposit(10, 6);
    }

    function testWithdraw() external {
        // Deposit
        vm.startPrank(lucy);
        uint256 balance = _userGetLPTokens(lucy);

        //Approve tokens to the vault
        _approveTokens(balance);
        vault.deposit(5, 6);
        vm.stopPrank();

        // 25 out of 26 weeks go by, deposit has not expired
        vm.warp(block.timestamp + 25 weeks);

        vm.startPrank(lucy);
        uint256[] memory depositsToWithdraw = new uint256[](1);
        depositsToWithdraw[0] = vault.ownersDepositId(lucy, 0);
        vm.expectEmit(true, true, true, true);
        emit LogWithdrawHasNotExpired(1);
        vault.withdraw(depositsToWithdraw);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 weeks); // enough time has expired
        vm.startPrank(lucy);

        (bool success, bytes memory data) = LPToken.call(abi.encodeWithSignature("balanceOf(address)", lucy));
        uint256 balanceBefore = abi.decode(data, (uint256));
        vault.withdraw(depositsToWithdraw);
        (success, data) = LPToken.call(abi.encodeWithSignature("balanceOf(address)", lucy));
        uint256 balanceAfter = abi.decode(data, (uint256));
        vm.stopPrank();
        assertGt(balanceAfter, balanceBefore);

        vm.startPrank(lucy);
        vault.deposit(5, 6);
        vault.deposit(10, 1);
        vm.stopPrank();

        vm.warp(block.timestamp + 53 weeks);
        vm.startPrank(lucy);
        uint256[] memory deps; // empty array
        vm.expectEmit(true, true, true, true);
        emit LogWithdraw(lucy, 15);
        vault.withdraw(deps);
        vm.stopPrank();
    }

    function testScenario1() external {
        vm.startPrank(lucy);
        uint256 balance = _userGetLPTokens(lucy);

        //Approve  tokens to the vault
        _approveTokens(balance);
        vm.stopPrank();

        vm.startPrank(julien);
        balance = _userGetLPTokens(julien);

        //Approve tokens to the vault
        _approveTokens(balance);
        vm.stopPrank();

        // Both depositors lock 5 LPs for 6 months
        vm.prank(lucy);
        vault.deposit(5, 6);

        vm.prank(julien);
        vault.deposit(5, 6);

        vm.warp(block.timestamp + 27 weeks); // 6 months and one week go by~
        uint256 expectedRewards = (REWARDS_PER_SECOND * 26 weeks) / 2; // each user is expected to get half of the available rewards

        vm.prank(julien);
        uint256 rewardsClaimed = vault.claimRewards(0); // claim all rewards
        assertEq(rewardsClaimed, expectedRewards);

        vm.prank(lucy);
        rewardsClaimed = vault.claimRewards(0); // claim all rewards
        assertEq(rewardsClaimed, expectedRewards);
    }

    function testScenario2() external {
        vm.startPrank(lucy);
        uint256 balance = _userGetLPTokens(lucy);

        //Approve  tokens to the vault
        _approveTokens(balance);
        vm.stopPrank();

        vm.startPrank(julien);
        balance = _userGetLPTokens(julien);

        //Approve tokens to the vault
        _approveTokens(balance);
        vm.stopPrank();

        // Both depositors lock 5 LPs for 6 months
        vm.prank(lucy);
        vault.deposit(5, 6);

        vm.prank(julien);
        vault.deposit(5, 1);

        vm.warp(block.timestamp + 53 weeks); // 1 year and 1 week go by, all deposits have expired
        uint256 expectedRewardsLucy = (REWARDS_PER_SECOND * 26 weeks) / 3; // Lucy gets 1/3 of the rewards available for the 6 mo period
        uint256 expectedRewardsJulien = (2 * (REWARDS_PER_SECOND * 26 weeks)) / 3 + (REWARDS_PER_SECOND * 26 weeks); // Julien gets 2/3 of the rewards available for the 6 mo period + totality for the other 6mo

        vm.prank(julien);
        uint256 rewardsClaimed = vault.claimRewards(0); // claim all rewards
        assertEq(rewardsClaimed, expectedRewardsJulien);

        vm.prank(lucy);
        rewardsClaimed = vault.claimRewards(0); // claim all rewards
        assertEq(rewardsClaimed, expectedRewardsLucy);
    }

    function testScenario3() external {
        // Depositors get LPTokens
        vm.startPrank(lucy);
        uint256 balance = _userGetLPTokens(lucy);
        //Approve tokens to the vault
        _approveTokens(balance);
        vm.stopPrank();

        vm.startPrank(julien);
        balance = _userGetLPTokens(julien);
        //Approve tokens to the vault
        _approveTokens(balance);
        vm.stopPrank();

        vm.startPrank(phoebe);
        balance = _userGetLPTokens(phoebe);
        //Approve  tokens to the vault
        _approveTokens(balance);
        vm.stopPrank();

        // Transfers
        vm.prank(lucy);
        vault.deposit(5, 6);
        vm.prank(julien);
        vault.deposit(5, 1);
        vm.prank(phoebe);
        vault.deposit(5, 2);

        // 2 years and 1 week goes by -> all deposits expired
        vm.warp(block.timestamp + 105 weeks);

        // Lucy gets 1/7 of the rewards for the 6 mo period
        uint256 expectedRewardsLucy = (REWARDS_PER_SECOND * 26 weeks) / 7;
        // Julien gets 2/7 of the rewards for the 6 mo period + 1/3 for the second 6mo
        uint256 expectedRewardsJulien = (2 * (REWARDS_PER_SECOND * 26 weeks)) / 7 + (REWARDS_PER_SECOND * 26 weeks) / 3;
        // Phoebe gets 4/7 of the rewards for the 6 mo period + 2/3 for the second 6mo + totality for 1 year
        uint256 expectedRewardsPhoebe = (4 * (REWARDS_PER_SECOND * 26 weeks)) / 7
            + (2 * (REWARDS_PER_SECOND * 26 weeks)) / 3 + (REWARDS_PER_SECOND * 52 weeks);

        // Claim rewards and assert
        vm.prank(lucy);
        uint256 rewardsClaimed = vault.claimRewards(0); // claim all rewards
        assertEq(rewardsClaimed, expectedRewardsLucy);

        vm.prank(julien);
        rewardsClaimed = vault.claimRewards(0); // claim all rewards
        assertEq(rewardsClaimed, expectedRewardsJulien);

        vm.prank(phoebe);
        rewardsClaimed = vault.claimRewards(0); // claim all rewards
        assertEq(rewardsClaimed, expectedRewardsPhoebe);
    }

    function testScenario4() external {
        // Depositors get LPTokens
        vm.startPrank(lucy);
        uint256 balance = _userGetLPTokens(lucy);
        //Approve tokens to the vault
        _approveTokens(balance);
        vm.stopPrank();

        vm.startPrank(julien);
        balance = _userGetLPTokens(julien);
        //Approve  tokens to the vault
        _approveTokens(balance);
        vm.stopPrank();

        vm.startPrank(phoebe);
        balance = _userGetLPTokens(phoebe);
        //Approve tokens to the vault
        _approveTokens(balance);
        vm.stopPrank();

        vm.startPrank(dacus);
        balance = _userGetLPTokens(dacus);
        //Approve  tokens to the vault
        _approveTokens(balance);
        vm.stopPrank();

        // Transfers
        vm.prank(lucy);
        vault.deposit(5, 6);
        vm.prank(julien);
        vault.deposit(5, 1);
        vm.prank(phoebe);
        vault.deposit(5, 2);
        vm.prank(dacus);
        vault.deposit(5, 4);

        // 4 years (208 weeks)  and 1 week goes by -> all deposits expired
        vm.warp(block.timestamp + 209 weeks);

        // Lucy gets 1/15 of the rewards for the 6 mo period
        uint256 expectedRewardsLucy = (REWARDS_PER_SECOND * 26 weeks) / 15;
        // Julien gets 2/15 of the rewards for the 6 mo period + 1/7 for the second 6mo
        uint256 expectedRewardsJulien = (2 * (REWARDS_PER_SECOND * 26 weeks)) / 15 + (REWARDS_PER_SECOND * 26 weeks) / 7;
        // Phoebe gets 4/15 of the rewards for the 6 mo period + 2/7 for the second 6mo + 1/3 for 1 year
        uint256 expectedRewardsPhoebe = (4 * (REWARDS_PER_SECOND * 26 weeks)) / 15
            + (2 * (REWARDS_PER_SECOND * 26 weeks)) / 7 + (REWARDS_PER_SECOND * 52 weeks) / 3;
        // Dacus gets 8/15 of the rewards for the 6 mo period + 4/7 for the second 6mo + 2/3 for 1 year + totality for 2 years
        uint256 expectedRewardsDacus = (8 * (REWARDS_PER_SECOND * 26 weeks)) / 15
            + (4 * (REWARDS_PER_SECOND * 26 weeks)) / 7 + (2 * (REWARDS_PER_SECOND * 52 weeks)) / 3
            + (REWARDS_PER_SECOND * 104 weeks);

        // Claim rewards and assert
        vm.prank(lucy);
        uint256 rewardsClaimed = vault.claimRewards(0); // claim all rewards
        assertEq(rewardsClaimed, expectedRewardsLucy);

        vm.prank(julien);
        rewardsClaimed = vault.claimRewards(0); // claim all rewards
        assertEq(rewardsClaimed, expectedRewardsJulien);

        vm.prank(phoebe);
        rewardsClaimed = vault.claimRewards(0); // claim all rewards
        assertEq(rewardsClaimed, expectedRewardsPhoebe);

        vm.prank(dacus);
        rewardsClaimed = vault.claimRewards(0); // claim all rewards
        assertEq(rewardsClaimed, expectedRewardsDacus);
    }

    function testScenario5() external {
        // Depositors get LPTokens
        vm.startPrank(lucy);
        uint256 balance = _userGetLPTokens(lucy);
        //Approve  tokens to the vault
        _approveTokens(balance);
        vm.stopPrank();

        vm.startPrank(julien);
        balance = _userGetLPTokens(julien);
        //Approve  tokens to the vault
        _approveTokens(balance);
        vm.stopPrank();

        // Transfers
        vm.prank(lucy);
        vault.deposit(5, 6);
        vm.warp(block.timestamp + 13 weeks); // 3 months go by
        vm.prank(julien);
        vault.deposit(5, 6);

        // 6 months goes by -> all deposits expired
        vm.warp(block.timestamp + 27 weeks);

        // Both Lucy & Julien get totality of rewards for 3 mo + half for 3 mo
        uint256 expectedRewards = (REWARDS_PER_SECOND * 13 weeks) / 2 + (REWARDS_PER_SECOND * 13 weeks);

        // Claim rewards and assert
        vm.prank(lucy);
        uint256 rewardsClaimed = vault.claimRewards(0); // claim all rewards
        assertEq(rewardsClaimed, expectedRewards);

        vm.prank(julien);
        rewardsClaimed = vault.claimRewards(0); // claim all rewards
        assertEq(rewardsClaimed, expectedRewards);
    }

    function testScenario6() external {
        // Depositors get LPTokens
        vm.startPrank(lucy);
        uint256 balance = _userGetLPTokens(lucy);
        //Approve  tokens to the vault
        _approveTokens(balance);
        vm.stopPrank();

        vm.startPrank(julien);
        balance = _userGetLPTokens(julien);
        //Approve tokens to the vault
        _approveTokens(balance);
        vm.stopPrank();

        // Transfers
        vm.prank(lucy);
        vault.deposit(5, 6);
        vm.warp(block.timestamp + 13 weeks); // 3 months go by
        vm.prank(julien);
        vault.deposit(5, 1);

        // 2 years goes by -> all deposits expired
        vm.warp(block.timestamp + 104 weeks);

        // Lucy gets totality of rewards for 3 mo + 1/3 for 3 mo
        uint256 expectedRewardsLucy = (REWARDS_PER_SECOND * 13 weeks) + (REWARDS_PER_SECOND * 13 weeks) / 3;
        // Julien gets totality of rewards for 9 mo + 2/3 for 3 mo
        uint256 expectedRewardsJulien = (REWARDS_PER_SECOND * 39 weeks) + (2 * (REWARDS_PER_SECOND * 13 weeks)) / 3;

        // Claim rewards and assert
        vm.prank(lucy);
        uint256 rewardsClaimed = vault.claimRewards(0); // claim all rewards
        assertEq(rewardsClaimed, expectedRewardsLucy);

        vm.prank(julien);
        rewardsClaimed = vault.claimRewards(0); // claim all rewards
        assertEq(rewardsClaimed, expectedRewardsJulien);
    }

    function testScenario7() external {
        // Depositors get LPTokens
        vm.startPrank(lucy);
        uint256 balance = _userGetLPTokens(lucy);
        //Approve tokens to the vault
        _approveTokens(balance);
        vm.stopPrank();

        vm.startPrank(julien);
        balance = _userGetLPTokens(julien);
        //Approve  tokens to the vault
        _approveTokens(balance);
        vm.stopPrank();

        vm.startPrank(phoebe);
        balance = _userGetLPTokens(phoebe);
        //Approve tokens to the vault
        _approveTokens(balance);
        vm.stopPrank();

        // Transfers
        vm.prank(lucy);
        vault.deposit(5, 6);
        vm.warp(block.timestamp + 13 weeks); // 3 months go by

        vm.prank(julien);
        vault.deposit(5, 1);
        vm.warp(block.timestamp + 39 weeks); // 9 months go by

        vm.prank(phoebe);
        vault.deposit(5, 1);

        // 2 years and 1 week goes by -> all deposits expired
        vm.warp(block.timestamp + 105 weeks);

        // Lucy gets totaly of the rewards for a 3 mo period + 1/3 for another 3 mo period
        uint256 expectedRewardsLucy = (REWARDS_PER_SECOND * 13 weeks) + ((REWARDS_PER_SECOND * 13 weeks)) / 3;
        // Julien gets 2/3 of the rewards for a 3 mo period + totality  for  6mo + half for 3 mo
        uint256 expectedRewardsJulien = (2 * (REWARDS_PER_SECOND * 13 weeks)) / 3 + (REWARDS_PER_SECOND * 26 weeks)
            + (REWARDS_PER_SECOND * 13 weeks) / 2;
        // Phoebe gets half of the rewards for a 3 mo period + totality for 9 mo
        uint256 expectedRewardsPhoebe = (REWARDS_PER_SECOND * 13 weeks) / 2 + (REWARDS_PER_SECOND * 39 weeks);

        // Claim rewards and assert
        vm.prank(lucy);
        uint256 rewardsClaimed = vault.claimRewards(0); // claim all rewards
        assertEq(rewardsClaimed, expectedRewardsLucy);

        vm.prank(julien);
        rewardsClaimed = vault.claimRewards(0); // claim all rewards
        assertEq(rewardsClaimed, expectedRewardsJulien);

        vm.prank(phoebe);
        rewardsClaimed = vault.claimRewards(0); // claim all rewards
        assertEq(rewardsClaimed, expectedRewardsPhoebe);
    }

    function testInvalidTransferLPTokens() external {
        vm.startPrank(lucy);
        _userGetLPTokens(lucy);

        // Tokens are not being approved, so deposit should fail
        vm.expectRevert(TransferOfLPTokensWasNotPossibleError.selector);
        vault.deposit(5, 1);
        vm.stopPrank();
    }

    function testNoRewardsToClaim() external {
        vm.startPrank(lucy);
        uint256 balance = _userGetLPTokens(lucy);

        //Approve and transfer tokens to the vault
        _approveTokens(balance);

        // Deposit
        vault.deposit(5, 1);

        vm.warp(block.timestamp + 51 weeks); // not enough time has passed

        vm.expectRevert(NoRewardsToClaimError.selector);
        vault.claimRewards(0);

        vm.stopPrank();
    }

    function testZeroDeposit() external {
        vm.startPrank(lucy);
        _userGetLPTokens(lucy);

        // Deposit
        vm.expectRevert(NotEnoughAmountOfTokensDepositedError.selector);
        vault.deposit(0, 1);
        vm.stopPrank();
    }

    function testWithdrawScenarios() external {
        vm.startPrank(lucy);
        uint256 balance = _userGetLPTokens(lucy);

        //Approve and transfer tokens to the vault
        _approveTokens(balance);

        // Deposit
        vault.deposit(5, 1);

        vm.warp(block.timestamp + 51 weeks); // not enough time has passed
        uint256[] memory depositsToWithdraw = new uint256[](0);
        vault.withdraw(depositsToWithdraw);

        vm.stopPrank();
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
        poolToken.mint(dacus, 10 ether);
        vm.stopPrank();

        // Give ether to all the actors
        vm.deal(phoebe, 10 ether);
        vm.deal(lucy, 10 ether);
        vm.deal(julien, 10 ether);
        vm.deal(dacus, 10 ether);

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

    function _approveTokens(uint256 amount_) internal {
        (bool success,) = LPToken.call(abi.encodeWithSignature("approve(address,uint256)", address(vault), amount_));
        require(success);
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
