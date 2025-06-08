                                                       MEV-Resistant DEX on zkSync Era

A decentralized exchange (DEX) designed to mitigate Miner Extractable Value (MEV) attacks, such as front-running and sandwich attacks, using commit-reveal schemes, time-delayed order queues, batch execution, and fair price matching. Built with UUPS upgradeability for zkSync Era, this DEX leverages Layer 2 scalability, Chainlink oracles, and Foundry for robust testing.

Features


MEV Protection: Commit-reveal hides order details, time-delay queues prevent reordering, and batch execution neutralizes sandwich attacks.



Fair Price Matching: Volume-weighted average price (VWAP) ensures equitable execution, validated by Chainlink oracles.



UUPS Upgradeability: Supports seamless upgrades via OpenZeppelin’s UUPS proxy pattern.



zkSync Optimization: Low gas costs and fast block times (~1s) enhance scalability and user experience.



Partial Fills & Cancellation: Orders support partial execution and user-initiated cancellation.



Foundry Testing: Comprehensive tests simulate MEV attacks (front-running, sandwich) and verify upgrades.

Architecture

The DEX uses a limit-order model for a single ERC20 token pair (e.g., WETH/DAI). Key components:





Commit-Reveal Scheme: Users submit hashed orders, revealing details after a delay (~4s on zkSync).



Time-Delay Queue: Orders are executable after 4 blocks to reduce validator control.



Batch Execution: Processes up to 10 orders at a uniform clearing price.



Chainlink Oracles: Validates clearing prices within ±5% of market rates.



UUPS Proxy: Enables upgrades without state loss.

Prerequisites





Node.js: v16 or higher



Foundry: Latest version (curl -L https://foundry.paradigm.xyz | bash)



zkSync CLI: npm install -g @matterlabs/zksync-cli



Wallet: Funded with zkSync Sepolia testnet ETH (use faucet)



Dependencies:





OpenZeppelin Contracts Upgradeable


Chainlink Contracts

Tests include:
Commit-reveal functionality
Front-running attack prevention
Sandwich attack neutralization
UUPS proxy upgrades


Usage





Commit an Order:





Generate a commitment: keccak256(abi.encode(amount, price, isBuy, nonce)).



Call commitOrder(commitment).



Reveal Order:





After ~4 blocks (~4s on zkSync), call revealOrder(orderId, amount, price, isBuy, nonce).



Approve tokens for transfer (e.g., WETH for buy, DAI for sell).



Execute Batch:





Call executeBatch(orderIds) with an array of order IDs.



Orders are matched at VWAP, validated by Chainlink.



Cancel Order:





Call cancelOrder(orderId) to cancel unfilled orders and refund tokens.



Upgrade Contract:





Deploy a new implementation.



Call upgradeTo(newImplementation) as the owner.

zkSync Considerations





Block Time: ~1s, so DELAY_BLOCKS = 4 ensures ~4s delay.



Gas Costs: zkSync’s low fees amplify batch processing benefits.



Chainlink: Use zkSync-supported price feeds (check Chainlink’s zkSync docs).



Account Abstraction: Future iterations may leverage zkSync’s native AA for gasless UX.