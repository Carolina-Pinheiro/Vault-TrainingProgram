// SPDX-License-Identifier: UNLINCESED
pragma solidity ^0.8.16;

import { Test } from "@forge-std/Test.sol";
import { VaultV2 } from "src/src-default/VaultV2.sol";
import { Token } from "src/src-default/Token.sol";
import { LZEndpointMock } from "@layerZeroOmnichain/mocks/LZEndpointMock.sol";
import { WETH9 } from "test/WETH9.sol";
import { PoolToken } from "test/PoolToken.sol";
import { ILinkedList } from "src/src-default/interfaces/ILinkedList.sol";
import { IVault } from "src/src-default/interfaces/IVault.sol";

contract VaultTestV2 is Test {
    VaultV2 vault1;
    VaultV2 vault2;
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

    LZEndpointMock lzEndpoint1; // chainId=1
    LZEndpointMock lzEndpoint2; // chainId=2
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
    error NotTrustedChainOrAddressError();

    function setUp() external {
        // Set-up the vault contract
        vm.label(ownerVault, "OwnerVault");
        vm.label(lucy, "Lucy");
        vm.label(phoebe, "Phoebe");
        vm.label(julien, "Julien");
        vm.label(dacus, "Dacus");
        lzEndpoint1 = new LZEndpointMock(1); // chainId=1
        lzEndpoint2 = new LZEndpointMock(2); // chainId=2
        rewardToken = new Token(address(lzEndpoint1), address(vault1));
        LPToken = _setUpUniswap();
        vm.startPrank(ownerVault);
        vault1 = new VaultV2(LPToken, address(lzEndpoint1));
        vault2 = new VaultV2(LPToken, address(lzEndpoint2));
        vault1.setTrustedRemoteAddress(2, abi.encodePacked(address(vault2)));
        vault1.addConnectedChains(uint16(2), address(vault2));
        vault2.setTrustedRemoteAddress(1, abi.encodePacked(address(vault1)));
        vault2.addConnectedChains(uint16(1), address(vault1));
        lzEndpoint1.setDestLzEndpoint(address(vault2), address(lzEndpoint2));
        lzEndpoint2.setDestLzEndpoint(address(vault1), address(lzEndpoint1));
        vm.stopPrank();
        vm.label(address(vault1), "Vault-Chain1");
        vm.label(address(vault2), "Vault-Chain2");
        vm.deal(ownerVault, 50 ether);
        vm.deal(address(vault1), 50 ether);
        vm.deal(address(vault2), 50 ether);
    }

    function testChangeVariablesBetweenChains() external {
        // send from v1 to v2
        vm.startPrank(lucy);
        uint256 balance = _userGetLPTokens(lucy);

        //Approve  tokens to the vault
        _approveTokens(balance, address(vault1));
        vm.warp(block.timestamp + 52 weeks);
        vault1.deposit{ value: 1 ether }(10, 6);

        vm.warp(block.timestamp + 1 weeks);
        vault1.deposit{ value: 1 ether }(50, 1);

        uint256 weightVault1 = vault1.getTotalWeightLocked();
        uint256 lastMintTimeVault1 = vault1.getLastMintTime();
        vm.stopPrank();

        vm.prank(ownerVault);
        vault1.updateTotalWeight{ value: 10 ether }(2, lastMintTimeVault1, weightVault1);

        uint256 weightVault2 = vault2.getTotalWeightLocked();
        uint256 lastMintTimeVault2 = vault2.getLastMintTime();

        assertEq(weightVault1, weightVault2);
        assertEq(lastMintTimeVault1, lastMintTimeVault2);
    }

    function testAutomaticUpdateBetweenChains() external {
        vm.startPrank(lucy);
        uint256 balance = _userGetLPTokens(lucy);

        //Approve  tokens to the vault
        _approveTokens(balance, address(vault1));

        // Pass some time so block.timestamp is more realistical
        vm.warp(block.timestamp + 52 weeks);

        // User makes two spaced out deposits in vault 1
        vault1.deposit{ value: 1 ether }(10, 6);
        vm.warp(block.timestamp + 1 weeks);
        vault1.deposit{ value: 1 ether }(50, 1);
        vm.stopPrank();

        // Get weight and lastminttime in one vault
        uint256 weightVault1 = vault1.getTotalWeightLocked();
        uint256 lastMintTimeVault1 = vault1.getLastMintTime();

        // Get weight and lastminttime in the other vault
        uint256 weightVault2 = vault2.getTotalWeightLocked();
        uint256 lastMintTimeVault2 = vault2.getLastMintTime();

        // Assert they are equal
        assertEq(weightVault1, weightVault2);
        assertEq(lastMintTimeVault1, lastMintTimeVault2);
    }

    function testSharedVariablesAcrossChains() external {
        // send from v1 to v2
        vm.startPrank(lucy);
        uint256 balance = _userGetLPTokens(lucy);

        //Approve  tokens to the vault
        _approveTokens(balance, address(vault1));
        vm.stopPrank();

        vm.startPrank(phoebe);
        balance = _userGetLPTokens(phoebe);

        //Approve  tokens to the vault
        _approveTokens(balance, address(vault2));
        vm.stopPrank();

        vm.warp(block.timestamp + 52 weeks);
        vm.prank(lucy);
        vault1.deposit(10, 6);

        vm.prank(phoebe);
        vault2.deposit(10, 6);

        vm.warp(block.timestamp + 1 weeks);
        vm.prank(lucy);
        uint256 rewardsClaimedLucy = vault1.claimRewards(0);
        vm.prank(phoebe);
        uint256 rewardsClaimedPhoebe = vault2.claimRewards(0);

        uint256 expectedRewards = (REWARDS_PER_SECOND * 1 weeks) / 2;

        assertEq(expectedRewards, rewardsClaimedLucy);
        assertEq(expectedRewards, rewardsClaimedPhoebe);
        assertEq(rewardsClaimedLucy, rewardsClaimedPhoebe);

        vm.warp(block.timestamp + 26 weeks);
        //uint256[] memory deps;
        //vm.prank(phoebe); // she shouldn't be able to withdraw since she has not assets in vault1
        //vault1.withdraw(deps);
    }

    function _testReceiveInfoFromTrustedSource() external {
        // Create a vault whose chain is not trusted and address is not trusted
        LZEndpointMock lzEndpoint3 = new LZEndpointMock(3); // chainId=3
        LZEndpointMock lzEndpoint4 = new LZEndpointMock(4); // chainId=3
        vm.startPrank(ownerVault);
        VaultV2 vault3 = new VaultV2(LPToken, address(lzEndpoint3));
        VaultV2 vault4 = new VaultV2(LPToken, address(lzEndpoint4));
        vault4.setTrustedRemoteAddress(3, abi.encodePacked(address(vault3)));
        vault4.addConnectedChains(uint16(3), address(vault3));
        vault3.setTrustedRemoteAddress(4, abi.encodePacked(address(vault4)));
        lzEndpoint3.setDestLzEndpoint(address(vault4), address(lzEndpoint4));
        lzEndpoint4.setDestLzEndpoint(address(vault3), address(lzEndpoint3));

        vault3.addConnectedChains(uint16(2), address(vault1)); // no correct chain id nor address

        vm.expectRevert(NotTrustedChainOrAddressError.selector);
        vault4.updateTotalWeight{ value: 1 ether }(3, 10, 10);
        vm.stopPrank();

        // Create a vault whose chain is trusted but address is not
        vm.startPrank(ownerVault);
        vault3.setTrustedRemoteAddress(4, abi.encodePacked(address(vault4)));
        vault3.addConnectedChains(uint16(4), address(vault4));
        vault4.setTrustedRemoteAddress(3, abi.encodePacked(address(vault3)));
        vault4.addConnectedChains(uint16(3), address(julien)); // chain is trusted, address no

        vm.expectRevert(NotTrustedChainOrAddressError.selector);
        vault3.updateTotalWeight{ value: 1 ether }(4, 10, 10);
        vm.stopPrank();

        // Create a vault whose address is trusted but the chain is different
        vm.startPrank(ownerVault);
        vault3.setTrustedRemoteAddress(4, abi.encodePacked(address(vault4)));
        vault3.addConnectedChains(uint16(4), address(vault4));
        vault4.setTrustedRemoteAddress(3, abi.encodePacked(address(vault3)));
        vault4.addConnectedChains(uint16(2), address(vault3));

        vm.expectRevert(NotTrustedChainOrAddressError.selector);
        vault3.updateTotalWeight{ value: 1 ether }(4, 10, 10);
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

    function _approveTokens(uint256 amount_, address to_) internal {
        (bool success,) = LPToken.call(abi.encodeWithSignature("approve(address,uint256)", to_, amount_));
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
