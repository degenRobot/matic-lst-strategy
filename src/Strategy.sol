// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Import interfaces for many popular DeFi projects, or add your own!
//import "../interfaces/<protocol>/<Interface>.sol";

// AAVE Interfaces
import {IAToken} from "./interfaces/aave/IAToken.sol";
import {IVariableDebtToken} from "./interfaces/aave/IVariableDebtToken.sol";
import {IPool} from "./interfaces/aave/IPool.sol";
import {IAaveOracle} from "./interfaces/aave/IAaveOracle.sol";
import {IPoolAddressesProvider} from "./interfaces/aave/IPoolAddressesProvider.sol";
import {IRouter} from "./interfaces/quickswap/IRouter.sol";
import {ExactInputSingleParams} from "./interfaces/quickswap/IRouter.sol";

// Balancer Interfaces & Structs
import {IBalancerV2} from "./interfaces/balancer/IBalancerV2.sol";
import {SingleSwap} from "./interfaces/balancer/IBalancerV2.sol";
import {FundManagement} from "./interfaces/balancer/IBalancerV2.sol";
import {JoinPoolRequest} from "./interfaces/balancer/IBalancerV2.sol";
import {ExitPoolRequest} from "./interfaces/balancer/IBalancerV2.sol";
import {BatchSwapStep} from "./interfaces/balancer/IBalancerV2.sol";

import {IAura} from "./interfaces/aura/IAura.sol";
import {IBaseRewardPool} from "./interfaces/aura/IAura.sol";

/**
 * The `TokenizedStrategy` variable can be used to retrieve the strategies
 * specific storage data your contract.
 *
 *       i.e. uint256 totalAssets = TokenizedStrategy.totalAssets()
 *
 * This can not be used for write functions. Any TokenizedStrategy
 * variables that need to be updated post deployment will need to
 * come from an external call from the strategies specific `management`.
 */

// NOTE: To implement permissioned functions you can use the onlyManagement, onlyEmergencyAuthorized and onlyKeepers modifiers

contract Strategy is BaseStrategy {
    using SafeERC20 for ERC20;

    constructor(
        address _asset,
        address _assetOut, // what we swap for via bal when converting to asset
        address _aToken,
        bool _swapViaQuick,
        string memory _name
    ) BaseStrategy(_asset, _name) {

        aToken = IAToken(_aToken);
        swapViaQuick = _swapViaQuick;
        assetOut = ERC20(_assetOut);
        _setInterfaces();
        _approveContracts();

    }


    function _setInterfaces() internal {
        // Tokens
        wMatic = ERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
        stMatic = ERC20(0x3A58a54C066FdC0f2D55FC9C89F0415C92eBf3C4);
        farmToken = IERC20(0x9a71012B13CA4d3D0Cdc72A177DF3ef03b0E76A3);
        auraToken = IERC20(0x1509706a6c66CA549ff0cB464de88231DDBe213B);

        // AAVE Contracts
        IPoolAddressesProvider provider = IPoolAddressesProvider(0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb);
        pool = IPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);
        oracle = IAaveOracle(provider.getPriceOracle());


        debtToken = IVariableDebtToken(0x4a1c3aD6Ed28a636ee1751C69071f6be75DEb8B8);  

        // Balancer Contracts
        lpToken = 0xf0ad209e2e969EAAA8C882aac71f02D8a047d5c2;
        balancer = IBalancerV2(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

        // Farm Contracts
        aura = IAura(0x98Ef32edd24e2c92525E59afc4475C1242a30184);
        baseRewardPool = IBaseRewardPool(0xB97341e9DA2eA5654a0E198184F88eef630E9a63);

        // Quickswap Router (used to swap USDC.e to USDC)
        router = IRouter(0xf5b509bB0909a69B1c207E495f687a596C168E12);


    }

    function _approveContracts() internal {
        asset.approve(address(pool), type(uint256).max);   
        wMatic.approve(address(pool), type(uint256).max);

        assetOut.approve(address(router), type(uint256).max);
        
        wMatic.approve(address(balancer), type(uint256).max);
        stMatic.approve(address(balancer), type(uint256).max);
        farmToken.approve(address(balancer), type(uint256).max);
        
        // to deposit into Aura 
        address boosterLite = 0x98Ef32edd24e2c92525E59afc4475C1242a30184;
        ERC20(lpToken).approve(boosterLite, type(uint256).max);
        ERC20(lpToken).approve(address(balancer), type(uint256).max);

    }


    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    ERC20 public wMatic;
    ERC20 public stMatic;
    ERC20 public assetOut;
    IERC20 public farmToken;
    IERC20 public auraToken;

    // If need to swap via quick i.e. if we need to swap USDC.e to USDC
    bool public swapViaQuick;

    uint256 public collatUpper = 6700;
    uint256 public collatTarget = 6000;
    uint256 public collatLower = 5300;
    uint256 public collatLimit = 7500;

    // this is used to adj amount of wMatic swapped to better align weights to pool weights 
    uint256 public swapPercentAdj = 10150; // 101.5%
    uint256 public slippageAdjSwap = 9950; // 99.5%    
    uint256 public slippageAdjPool = 9950; // 99.5%
    uint256 public basisPrecision = 10000;

    // max Amount of wMatic to be deployed any give time assets deployed (to avoid slippage)
    uint256 public maxDeploy = type(uint256).max; 

    IPool public pool;
    IAToken public aToken;
    IVariableDebtToken public debtToken;

    IAaveOracle public oracle;

    IBalancerV2 public balancer;
    address public lpToken;
    IAura public aura;
    IBaseRewardPool public baseRewardPool;

    uint256 public pid = 5;

    bytes32 public poolId = 0xf0ad209e2e969eaaa8c882aac71f02d8a047d5c2000200000000000000000b49;
    //bytes32 public farmPoolId = 0xf0ad209e2e969eaaa8c882aac71f02d8a047d5c2000200000000000000000b49;

    IRouter public router;

    function setCollatTargets(uint256 _collatLow, uint256 _collatTarget, uint256 _collatHigh) external onlyManagement {
        require(_collatLow < _collatTarget);
        require(_collatTarget < _collatHigh);
        require(_collatHigh < collatLimit);

        collatLower = _collatLow;
        collatTarget = _collatTarget;
        collatUpper = _collatHigh;

    }

    function setSlippageConfig(uint256 _slippageSwap, uint256 _slippagePool) external onlyManagement {
        require(_slippageSwap < basisPrecision);
        require(_slippagePool < basisPrecision);

        slippageAdjSwap = _slippageSwap;
        slippageAdjPool = _slippagePool;

    }

    function setMaxDeploy(uint256 _maxDeploy) external onlyManagement {
        maxDeploy = _maxDeploy;
    }

    // Placeholder to potentially withdraw AURA to multi-sig & bridge then swap (as no LP on Polygon to swap)
    function withdrawAura(address _recipient) external onlyManagement {
        auraToken.transfer(_recipient, auraToken.balanceOf(address(this)));
    }

    /**
     * @dev Should deploy up to '_amount' of 'asset' in the yield source.
     *
     * This function is called at the end of a {deposit} or {mint}
     * call. Meaning that unless a whitelist is implemented it will
     * be entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * @param _amount The amount of 'asset' that the strategy should attempt
     * to deposit in the yield source.
     */
    function _deployFunds(uint256 _amount) internal override {

        // Provide collateral to aave 
        _lendWant(_amount);

        // Calculate how much wMatic to borrow 
        uint256 oPrice = getOraclePrice();
        uint256 _borrowAmt = (_amount * collatTarget / basisPrecision) * 1e18 / oPrice;

        (uint256 _wMaticWeight, uint256 _lpValue) = getLpData();

        if (_borrowAmt > maxDeploy) {
            _borrowAmt = maxDeploy;
        }  
        _borrow(_borrowAmt);

        // Swap wMatic for stMatic and enter pool 
        uint256 _swapAmt = (_borrowAmt * (basisPrecision - _wMaticWeight) / swapPercentAdj) * 1e18 / (1e18 * ( 1 + _borrowAmt / _lpValue) );
        _swapToStMatic(_swapAmt);
        _joinPool();
        _depositToGauge();
    }

    function balanceLend() public view returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    function balanceDebtInShort() public view returns (uint256) {
        // Each debtToken is pegged 1:1 with the short token
        return debtToken.balanceOf(address(this));
    }

    function balanceDebt() public view returns (uint256) {
        uint256 oPrice = getOraclePrice();
        return (balanceDebtInShort() * oPrice / 1e18);
    }

    // balance of any wMatic / stMatic not deployed 
    function balanceShort() public view returns(uint256) {
        uint256 oPrice = getOraclePrice();
        uint256 oPriceLst = getOraclePriceLst();
        
        uint256 bal = wMatic.balanceOf(address(this));
        bal += stMatic.balanceOf(address(this)) * oPriceLst / basisPrecision;

        return bal * oPrice / 1e18;

    }

    // Calculate value of LP in asset
    function balanceLp() public view returns (uint256) {

        (address[] memory tokens, uint256[] memory balances,) = balancer.getPoolTokens(poolId);

        uint256 _oPrice = getOraclePrice();
        uint256 _oPriceLst = getOraclePriceLst();
        uint256 gaugeTokens = baseRewardPool.balanceOf(address(this));
        uint256 gaugeSupply = IERC20(lpToken).totalSupply();


        // we get the total value in the LP pool priced in wMatic 
        uint256 _totalValue;

        if (tokens[0] == address(wMatic)) {
            _totalValue += balances[0];
            _totalValue += balances[1] * _oPriceLst / basisPrecision;
        } else {
            _totalValue += balances[1];
            _totalValue += balances[0] * _oPriceLst / basisPrecision;
        }

        // calculate strategies value of LP tokens in asset price
        return ((gaugeTokens * _totalValue / gaugeSupply) * _oPrice / 1e18);


    }

    function balanceDeployed() public view returns (uint256) {
        return balanceLend() - balanceDebt() + balanceLp() + balanceShort();
    }

    function calcCollateralRatio() public view returns (uint256) {
        return (balanceDebt() * basisPrecision / balanceLend());
    }

    function _lendWant(uint256 amount) internal {
        pool.supply(address(asset), amount, address(this), 0);
    }

    function _redeemWant(uint256 _redeemAmount) internal {

        // We run this check in case some dust is left & cannot redeem full amount 
        uint256 _bal = balanceLend();
        uint256 _debt = balanceDebt();

        uint256 _maxRedeem = _bal - (_debt * basisPrecision / collatLimit);

        if (_redeemAmount > _maxRedeem) {
            _redeemAmount = _maxRedeem;
        }

        if (_redeemAmount == 0) return;
        pool.withdraw(address(asset), _redeemAmount, address(this));
    }

    function _borrow(uint256 borrowAmount) internal {
        pool.borrow(address(wMatic), borrowAmount, 2, 0, address(this));
    }

    function _repayDebt() internal {
        uint256 _bal = wMatic.balanceOf(address(this));
        if (_bal == 0) return;

        uint256 _debt = balanceDebtInShort();
        if (_bal < _debt) {
            pool.repay(address(wMatic), _bal, 2, address(this));
        } else {
            pool.repay(address(wMatic), _debt, 2, address(this));
        }
    }


    // used to determine how much wMatic to borrow
    function getOraclePrice() public view returns (uint256) {
        uint256 shortOPrice = oracle.getAssetPrice(address(wMatic));
        uint256 wantOPrice = oracle.getAssetPrice(address(asset));
        return
            shortOPrice*(10**(asset.decimals() + (18) - (wMatic.decimals())))/(
                wantOPrice
            );
    }

    // used to compare price of LST to wMatic to determine min Out on Swap 
    function getOraclePriceLst() public view returns (uint256) {
        uint256 wMaticPrice = oracle.getAssetPrice(address(wMatic));
        uint256 stMaticPrice = oracle.getAssetPrice(address(stMatic));
        return stMaticPrice*(basisPrecision)/wMaticPrice;
    }

    function getLpData() public view returns (uint256 _wMaticWeight, uint256 _totalValue) {
        (address[] memory tokens, uint256[] memory balances,) = balancer.getPoolTokens(poolId);

        uint256 _oPrice = getOraclePriceLst();
        if (tokens[0] == address(wMatic)) {
            _totalValue += balances[0];
            _totalValue += balances[1] * _oPrice / basisPrecision;
            _wMaticWeight = balances[0] * basisPrecision / _totalValue;
        } else {
            _totalValue += balances[1];
            _totalValue += balances[0] * _oPrice / basisPrecision;
            _wMaticWeight = balances[1] * basisPrecision / _totalValue;
        }
        

    }

    function getPoolWMaticWeight() public view returns (uint256 _wMaticWeight) {
        (address[] memory tokens, uint256[] memory balances,) = balancer.getPoolTokens(poolId);

        uint256 _oPrice = getOraclePriceLst();
        uint256 _totalValue;
        if (tokens[0] == address(wMatic)) {
            _totalValue += balances[0];
            _totalValue += balances[1] * _oPrice / basisPrecision;
            _wMaticWeight = balances[0] * basisPrecision / _totalValue;
        } else {
            _totalValue += balances[1];
            _totalValue += balances[0] * _oPrice / basisPrecision;
            _wMaticWeight = balances[1] * basisPrecision / _totalValue;
        }
        


    }

    function _joinPool() internal {

        // Also assuming JoinPoolRequest struct is defined appropriately
        // Explicitly declare arrays as memory arrays
        address[] memory assets = new address[](2);
        uint256[] memory amtsIn = new uint256[](2);

        // Initialize the arrays
        assets[0] = address(wMatic);
        assets[1] = address(stMatic);
        amtsIn[0] = wMatic.balanceOf(address(this));
        amtsIn[1] = stMatic.balanceOf(address(this));

        uint256 bptOut;
        uint256 gaugeSupply = IERC20(lpToken).totalSupply();
        (address[] memory tokens, uint256[] memory balances,) = balancer.getPoolTokens(poolId);

        if (tokens[0] == address(stMatic)) {
            bptOut = (amtsIn[1] * gaugeSupply / balances[0]) * slippageAdjPool / basisPrecision;
        } else {
            bptOut = (amtsIn[1] * gaugeSupply / balances[1]) * slippageAdjPool / basisPrecision;
        }

        bytes memory userData = abi.encode(IBalancerV2.JoinKind.ALL_TOKENS_IN_FOR_EXACT_BPT_OUT, bptOut);


        // Create the JoinPoolRequest struct in memory
        JoinPoolRequest memory request = JoinPoolRequest({
            assets: assets,
            maxAmountsIn: amtsIn,
            userData: userData,
            fromInternalBalance: false
        });
        balancer.joinPool(poolId, address(this), address(this), request);
    }

    function _depositToGauge() internal {
        aura.deposit(pid, IERC20(lpToken).balanceOf(address(this)),true);
    }

    function _withdrawFromGauge(uint256 _amount) internal {
        baseRewardPool.withdrawAndUnwrap(_amount, false);
    }

    function _exitPool(uint256 _amountOut) internal {


        // Also assuming ExitPoolRequest struct is defined appropriately
        // Explicitly declare arrays as memory arrays
        uint256[] memory amtsOut = new uint256[](2);

        (address[] memory assets, uint256[] memory balances,) = balancer.getPoolTokens(poolId);

        amtsOut[0] = (balances[0] * _amountOut / IERC20(lpToken).totalSupply()) * slippageAdjPool / basisPrecision;
        amtsOut[1] = (balances[1] * _amountOut / IERC20(lpToken).totalSupply()) * slippageAdjPool / basisPrecision;

        bytes memory userData = abi.encode(1, _amountOut);

        // Create the ExitPoolRequest struct in memory
        ExitPoolRequest memory request = ExitPoolRequest({
            assets: assets,
            minAmountsOut: amtsOut,
            userData: userData,
            toInternalBalance: false
        });
        balancer.exitPool(poolId, address(this), payable(address(this)), request);
    }

    function _swapToStMatic(uint256 _amountIn) internal {

        uint256 oPrice = getOraclePriceLst();
        uint256 _minOut = (_amountIn * basisPrecision / oPrice) * slippageAdjSwap / basisPrecision;

        SingleSwap memory singleSwap = SingleSwap({
            poolId: poolId,
            kind: 0,
            assetIn: address(wMatic),
            assetOut: address(stMatic),
            amount: _amountIn,
            userData: abi.encode(0)
        });

        FundManagement memory funds = FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        balancer.swap(singleSwap, funds, _minOut, block.timestamp);
    }

    function _swapToWMatic(uint256 _amountIn) internal {
        uint256 oPrice = getOraclePriceLst();
        uint256 _minOut = (_amountIn * basisPrecision / oPrice) * slippageAdjSwap / basisPrecision;

        SingleSwap memory singleSwap = SingleSwap({
            poolId: poolId,
            kind: 0,
            assetIn: address(stMatic),
            assetOut: address(wMatic),
            amount: _amountIn,
            userData: abi.encode(0)
        });

        FundManagement memory funds = FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        balancer.swap(singleSwap, funds, _minOut, block.timestamp);

    }

    function _swapMaticToUSDC() internal {
        uint256 _amountIn = wMatic.balanceOf(address(this));

        SingleSwap memory singleSwap = SingleSwap({
            poolId: 0x0297e37f1873d2dab4487aa67cd56b58e2f27875000100000000000000000002,
            kind: 0,
            assetIn: address(wMatic),
            assetOut: address(assetOut),
            amount: _amountIn,
            userData: abi.encode(0)
        });

        FundManagement memory funds = FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        balancer.swap(singleSwap, funds, 0, block.timestamp);

        if (swapViaQuick) {
            _swapUSDCetoUSDC();
        }
        
    }

    function _swapRewardsToAsset() internal {
        uint256 _amountIn = farmToken.balanceOf(address(this));

        SingleSwap memory singleSwap = SingleSwap({
            poolId: 0x0297e37f1873d2dab4487aa67cd56b58e2f27875000100000000000000000002,
            kind: 0,
            assetIn: address(farmToken),
            assetOut: address(assetOut),
            amount: _amountIn,
            userData: abi.encode(0)
        });

        FundManagement memory funds = FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        balancer.swap(singleSwap, funds, 0, block.timestamp);

        if (swapViaQuick) {
            _swapUSDCetoUSDC();
        }
    }

    function _swapUSDCetoUSDC() internal {

        uint256 _amount = assetOut.balanceOf(address(this));
        // asssuming 1 for 1 USDCe to USDC 
        uint256 amountOut = _amount;

        ExactInputSingleParams memory input;
        input.amountIn = _amount;
        input.tokenIn = address(assetOut);
        input.tokenOut = address(asset);
        input.recipient = address(this);
        input.deadline = block.timestamp;
        input.amountOutMinimum = amountOut*(slippageAdjSwap)/(basisPrecision);
        router.exactInputSingle(input);

    }

    function _swapRewardsToWMatic() internal {
        uint256 _amountIn = farmToken.balanceOf(address(this));

        SingleSwap memory singleSwap = SingleSwap({
            poolId: 0x0297e37f1873d2dab4487aa67cd56b58e2f27875000100000000000000000002,
            kind: 0,
            assetIn: address(farmToken),
            assetOut: address(wMatic),
            amount: _amountIn,
            userData: abi.encode(0)
        });

        FundManagement memory funds = FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        balancer.swap(singleSwap, funds, 0, block.timestamp);

    }


    /**
     * @dev Will attempt to free the '_amount' of 'asset'.
     *
     * The amount of 'asset' that is already loose has already
     * been accounted for.
     *
     * This function is called during {withdraw} and {redeem} calls.
     * Meaning that unless a whitelist is implemented it will be
     * entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * Should not rely on asset.balanceOf(address(this)) calls other than
     * for diff accounting purposes.
     *
     * Any difference between `_amount` and what is actually freed will be
     * counted as a loss and passed on to the withdrawer. This means
     * care should be taken in times of illiquidity. It may be better to revert
     * if withdraws are simply illiquid so not to realize incorrect losses.
     *
     * @param _amount, The amount of 'asset' to be freed.
     */
    function _freeFunds(uint256 _amount) internal override {

        uint256 _percentWithdrawn = _amount * basisPrecision / balanceDeployed();
        uint256 _gaugeTokensOut = baseRewardPool.balanceOf(address(this)) * _percentWithdrawn / basisPrecision;
        uint256 _redeemAmt = balanceLend() * _percentWithdrawn / basisPrecision;

        _withdrawFromGauge(_gaugeTokensOut);
        _exitPool(_gaugeTokensOut);
        _swapToWMatic(stMatic.balanceOf(address(this)));
        _repayDebt();    

        // Swap Any Excess back to Want ??? 
        if (wMatic.balanceOf(address(this)) > 0) {
            _swapMaticToUSDC();
        }

        _redeemWant(_redeemAmt);

    }


    function rebalanceCollateral() external onlyKeepers {
        uint256 cRatio = calcCollateralRatio();
        if (cRatio >= collatUpper) {
            _rebalanceCollateralHigh();
        } else {
            _rebalanceCollateralLow();
        }
    }

    // If Collateral Ratio goes above collat high redeem some assets from LP pool & repay debt 
    function _rebalanceCollateralHigh() internal {
        uint256 cRatio = calcCollateralRatio();
        require(cRatio >= collatUpper);
        uint256 percentAdj = (cRatio - collatTarget) * basisPrecision / cRatio;
        uint256 _gaugeTokensOut = baseRewardPool.balanceOf(address(this)) * percentAdj / basisPrecision;
        _withdrawFromGauge(_gaugeTokensOut);
        _exitPool(_gaugeTokensOut);
        _swapToWMatic(stMatic.balanceOf(address(this)));
        _repayDebt();    
    }

    // If Collateral Ratio goes below collat low borrow some assets & deploy to LP Pool 
    function _rebalanceCollateralLow() internal {

        uint256 cRatio = calcCollateralRatio();
        require(cRatio <= collatLower);

        uint256 oPrice = getOraclePrice();
        uint256 _amount = balanceLend();
        uint256 _borrowAmt = (_amount * (collatTarget - cRatio) / basisPrecision) * 1e18 / oPrice;

        if (_borrowAmt > maxDeploy) {
            _borrowAmt = maxDeploy;
        }  
        _borrow(_borrowAmt);

        (uint256 _wMaticWeight, uint256 _lpValue) = getLpData();
        // Swap wMatic for stMatic and enter pool 
        uint256 _swapAmt = (_borrowAmt * (basisPrecision - _wMaticWeight) / swapPercentAdj) * 1e18 / (1e18 * ( 1 + _borrowAmt / _lpValue) );
        _swapToStMatic(_swapAmt);
        _joinPool();
        _depositToGauge();
    }

    /**
     * @dev Internal function to harvest all rewards, redeploy any idle
     * funds and return an accurate accounting of all funds currently
     * held by the Strategy.
     *
     * This should do any needed harvesting, rewards selling, accrual,
     * redepositing etc. to get the most accurate view of current assets.
     *
     * NOTE: All applicable assets including loose assets should be
     * accounted for in this function.
     *
     * Care should be taken when relying on oracles or swap values rather
     * than actual amounts as all Strategy profit/loss accounting will
     * be done based on this returned value.
     *
     * This can still be called post a shutdown, a strategist can check
     * `TokenizedStrategy.isShutdown()` to decide if funds should be
     * redeployed or simply realize any profits/losses.
     *
     * @return _totalAssets A trusted and accurate account for the total
     * amount of 'asset' the strategy currently holds including idle funds.
     */
    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {

        baseRewardPool.getReward(address(this), true);

        // TO DO -- decide how we handle AURA Rewards? (i.e. boost or sell)


        // Depending on current state we either swap rewards to wMatic & repay debt or accumulate more of strategies core asset
        if (balanceDebt() > balanceLp()) {
            _swapRewardsToWMatic();
            _repayDebt();
        } else {
            _swapRewardsToAsset();
        }

        _totalAssets = asset.balanceOf(address(this)) + balanceDeployed();
    }

    /*//////////////////////////////////////////////////////////////
                    OPTIONAL TO OVERRIDE BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Optional function for strategist to override that can
     *  be called in between reports.
     *
     * If '_tend' is used tendTrigger() will also need to be overridden.
     *
     * This call can only be called by a permissioned role so may be
     * through protected relays.
     *
     * This can be used to harvest and compound rewards, deposit idle funds,
     * perform needed position maintenance or anything else that doesn't need
     * a full report for.
     *
     *   EX: A strategy that can not deposit funds without getting
     *       sandwiched can use the tend when a certain threshold
     *       of idle to totalAssets has been reached.
     *
     * The TokenizedStrategy contract will do all needed debt and idle updates
     * after this has finished and will have no effect on PPS of the strategy
     * till report() is called.
     *
     * @param _totalIdle The current amount of idle funds that are available to deploy.
     *
    */
    function _tend(uint256 _totalIdle) internal override {
        
        uint256 cRatio = calcCollateralRatio();
        if (cRatio >= collatUpper) {
            _rebalanceCollateralHigh();
        } else {
            _rebalanceCollateralLow();
        }        
    }
    

    /**
     * @dev Optional trigger to override if tend() will be used by the strategy.
     * This must be implemented if the strategy hopes to invoke _tend().
     *
     * @return . Should return true if tend() should be called by keeper or false if not.
     *
    */
    function _tendTrigger() internal view override returns (bool) {
        if (balanceLend() == 0) return false;

        if (calcCollateralRatio() >= collatUpper) {
            return true;
        } 
        if (calcCollateralRatio() <= collatLower) {
            return true;
        }
        return false;
    }
    

    /**
     * @notice Gets the max amount of `asset` that an address can deposit.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overridden by strategists.
     *
     * This function will be called before any deposit or mints to enforce
     * any limits desired by the strategist. This can be used for either a
     * traditional deposit limit or for implementing a whitelist etc.
     *
     *   EX:
     *      if(isAllowed[_owner]) return super.availableDepositLimit(_owner);
     *
     * This does not need to take into account any conversion rates
     * from shares to assets. But should know that any non max uint256
     * amounts may be converted to shares. So it is recommended to keep
     * custom amounts low enough as not to cause overflow when multiplied
     * by `totalSupply`.
     *
     * @param . The address that is depositing into the strategy.
     * @return . The available amount the `_owner` can deposit in terms of `asset`
     *
    function availableDepositLimit(
        address _owner
    ) public view override returns (uint256) {
        TODO: If desired Implement deposit limit logic and any needed state variables .
        
        EX:    
            uint256 totalAssets = TokenizedStrategy.totalAssets();
            return totalAssets >= depositLimit ? 0 : depositLimit - totalAssets;
    }
    */

    /**
     * @notice Gets the max amount of `asset` that can be withdrawn.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overridden by strategists.
     *
     * This function will be called before any withdraw or redeem to enforce
     * any limits desired by the strategist. This can be used for illiquid
     * or sandwichable strategies. It should never be lower than `totalIdle`.
     *
     *   EX:
     *       return TokenIzedStrategy.totalIdle();
     *
     * This does not need to take into account the `_owner`'s share balance
     * or conversion rates from shares to assets.
     *
     * @param . The address that is withdrawing from the strategy.
     * @return . The available amount that can be withdrawn in terms of `asset`
     *
    function availableWithdrawLimit(
        address _owner
    ) public view override returns (uint256) {
        TODO: If desired Implement withdraw limit logic and any needed state variables.
        
        EX:    
            return TokenizedStrategy.totalIdle();
    }
    */

    /**
     * @dev Optional function for a strategist to override that will
     * allow management to manually withdraw deployed funds from the
     * yield source if a strategy is shutdown.
     *
     * This should attempt to free `_amount`, noting that `_amount` may
     * be more than is currently deployed.
     *
     * NOTE: This will not realize any profits or losses. A separate
     * {report} will be needed in order to record any profit/loss. If
     * a report may need to be called after a shutdown it is important
     * to check if the strategy is shutdown during {_harvestAndReport}
     * so that it does not simply re-deploy all funds that had been freed.
     *
     * EX:
     *   if(freeAsset > 0 && !TokenizedStrategy.isShutdown()) {
     *       depositFunds...
     *    }
     *
     * @param _amount The amount of asset to attempt to free.
     *
    function _emergencyWithdraw(uint256 _amount) internal override {
        TODO: If desired implement simple logic to free deployed funds.

        EX:
            _amount = min(_amount, aToken.balanceOf(address(this)));
            _freeFunds(_amount);
    }

    */
}
