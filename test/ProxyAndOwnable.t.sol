// SPDX-License-Identifier: UNLINCESED
pragma solidity ^0.8.16;

import { Test } from "@forge-std/Test.sol";
import { Vault } from "src/src-default/Vault.sol";
import { Token } from "src/src-default/Token.sol";
import { LZEndpointMock } from "@layerZeroOmnichain/mocks/LZEndpointMock.sol";
import { WETH9 } from "test/WETH9.sol";
import { PoolToken } from "test/PoolToken.sol";
import { Proxy } from "test/Proxy.sol";
import { ILinkedList } from "src/src-default/interfaces/ILinkedList.sol";
import { IVault } from "src/src-default/interfaces/IVault.sol";
import { VaultUpgrade } from "test/VaultUpgrade.sol";

contract VaultTest is Test {
    Vault vault;
    VaultUpgrade vaultUpgrade;
    Proxy proxy;
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

    event LogNode(ILinkedList.Node);

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
        bytes memory data_;
        proxy = new Proxy(address(vault), ownerVault, data_);
    }

    function testProxyCall() external {
        // Give a user LP tokens to interact
        vm.startPrank(lucy);
        uint256 balance = _userGetLPTokens(lucy);

        //Approve and transfer tokens to the vault
        _approveTokens(balance, address(proxy));

        // Test call
        ILinkedList.Node memory newNode_ = ILinkedList.Node({
            nextId: 0,
            endTime: block.timestamp + 52 weeks,
            share: 10,
            currentTotalWeight: 0,
            owner: address(lucy),
            depositedLPTokens: 5
        });
        vm.expectEmit(true, true, true, true);
        emit LogNode(newNode_);
        
        IVault(address(proxy)).deposit(5, 1);
        //(bool success,) = address(proxy).call(abi.encodeWithSignature("deposit(uint256,uint256)", 5, 1));
        //require(success); // using SafeERC20 for IERC20
        vm.stopPrank();
    }

    function testUpgradeVault() external {
        // Try upgrading with another user, make sure it fails
        vaultUpgrade = new VaultUpgrade(address(LPToken));
        vm.startPrank(lucy);
        vm.expectRevert();
        (bool success,) = address(proxy).call(abi.encodeWithSignature("upgradeTo(address)", address(vaultUpgrade)));
        vm.stopPrank();
        // Try upgrading with the owner
        vm.startPrank(ownerVault);
        (success,) = address(proxy).call(abi.encodeWithSignature("upgradeTo(address)", address(vaultUpgrade)));
        require(success);
        vm.stopPrank();

        bytes memory data;
        (success, data) = address(proxy).call(abi.encodeWithSignature("claimRewards(uint256)", 20));
        require(success);
        uint256 output = abi.decode(data, (uint256));
        assertEq(output, 40);
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

    function _approveTokens(uint256 amount_, address aprrover_) internal {
        Token(address(LPToken)).approve(aprrover_, amount_);
        //(bool success,) = LPToken.call(abi.encodeWithSignature("approve(address,uint256)", aprrover_, amount_));
        //require(success);
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
