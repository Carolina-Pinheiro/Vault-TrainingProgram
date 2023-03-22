// SPDX-License-Identifier: UNLINCESED
pragma solidity ^0.8.16;

import { Test } from "@forge-std/Test.sol";
import { VaultV2 } from "src/src-default/VaultV2.sol";
import { Token } from "src/src-default/Token.sol";
import { LZEndpointMock } from "@layerZeroOmnichain/mocks/LZEndpointMock.sol";
import { WETH9 } from "test/WETH9.sol";
import { PoolToken } from "test/PoolToken.sol";
import { ILinkedList } from "src/src-default/interfaces/ILinkedList.sol";

contract VaultFuzzTestPublic is Test {
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
        vault1.addConnectedChains(uint16(2));
        vault2.setTrustedRemoteAddress(1, abi.encodePacked(address(vault1)));
        vault2.addConnectedChains(uint16(1));
        lzEndpoint1.setDestLzEndpoint(address(vault2), address(lzEndpoint2));
        lzEndpoint2.setDestLzEndpoint(address(vault1), address(lzEndpoint1));
        vm.stopPrank();
        vm.label(address(vault1), "Vault-Chain1");
        vm.label(address(vault2), "Vault-Chain2");
        vm.deal(ownerVault, 50 ether);
        vm.deal(address(vault1), 50 ether);
        vm.deal(address(vault2), 50 ether);
    }

    // Needed so the test contract itself can receive ether
    // when withdrawing
    receive() external payable {}

    function testFuzz_deposit(uint256 amount_) public {
        //Note: for now all lockup periods will be 1 year
        amount_ = bound(amount_,1, 5000);
        vm.startPrank(lucy);
        uint256 balance = _userGetLPTokens(lucy);

        //Approve  tokens to the vault
        _approveTokens(balance, address(vault1));

        // Pass some time so block.timestamp is more realistical
        vm.warp(block.timestamp + 52 weeks);

        // User makes two spaced out deposits in vault 1
        vault1.deposit{ value: 0.5 ether }(amount_, 1);
    }

    // -------------------------------------------------
    // HELPER FUNCTIONS
    // ------------------------------------------------------


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
        vm.deal(phoebe, 10*256 ether);
        vm.deal(lucy, 10*256 ether);
        vm.deal(julien, 10*256 ether);
        vm.deal(dacus, 10*256 ether);

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