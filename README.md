# Matic LST Strategy

This strategy utilised Yearns V3 Tokenized Strategy Mix to generate yield via AAVE & Aura (via Balancer LP Pools)

The strategy deposits collateral into AAVE to borrow MATIC which is deployed to Balancer Pool containing WMatic & stMatic (CLP is utilised here) LP Tokens are then deposited into Aura to generate BAL & AURA Rewards

![AAVE-AURA-LST](https://github.com/degenRobot/matic-lst-strategy/assets/86513395/75e5dea2-643e-431f-bf79-af2b8bffea04)

The current iteration of the code is developed to handle USDC however the code can be extended to handle other collateral types i.e. WETH & WBTC in addition to being extended to other networks such as Arbitrum and Optimism (which contain AAVE & relevant LST pools on Balancer / AURA) 
