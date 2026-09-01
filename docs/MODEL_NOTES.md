# Model Notes

## Binary information environment

The asset settles at either `Low = 90` or `High = 110`. The baseline prior assigns each state probability one half. A customer is informed with probability `alpha`; otherwise the order is liquidity-motivated. Informed customers buy in the high state and sell in the low state, while noise customers choose either direction with equal probability.

This implies

```text
P(Buy | High) = (1 + alpha) / 2
P(Buy | Low)  = (1 - alpha) / 2
```

The market maker observes order direction but not the hidden state or trader type. A customer buy therefore moves the posterior toward the high state, and a sell moves it toward the low state.

## Competitive quote convention

The quote is conditional on the event that it is accepted:

```text
ask = E[V | customer buys]
bid = E[V | customer sells]
```

At the symmetric prior,

```text
spread = (High - Low) * alpha
```

With values 90 and 110 and `alpha = 0.20`, the quote is `98 / 102`. Away from the symmetric prior, the bid and ask remain conditional expectations, but the linear spread formula does not carry over unchanged.

## Information boundaries

The simulator separates three roles.

### Scenario generator

It knows the terminal state, trader type, current information regime, and future random draws.

### Strategy

It knows its prior or posterior, the assumed model, current inventory where relevant, and previously observed customer-side order directions. It never receives the terminal state, trader identity, or future flow.

### Evaluator

After an episode, it may use hidden state to compute terminal wealth, fair-value error, and P&L attribution between informed and noise flow.

The event sequence is fixed as

```text
belief -> quote -> trade -> accounting -> observe side -> posterior update
```

Updating before quoting would leak the information carried by the current execution. The resulting graph might look better, but the experiment would no longer answer the stated question.

## Strategy variants

### Static

The fair-value belief never changes. The strategy still uses the chosen information parameter to produce a bid and ask, but it ignores the history of order directions.

### Bayesian

The strategy knows an assumed `alpha` and updates the probability of the high state after every order.

### Joint Bayesian

The strategy places prior mass on a finite grid of possible `alpha` values and maintains a joint posterior over `(state, alpha)`. This introduces a genuine identification problem: a run of buys may indicate a high state, a strongly informed customer population, or both.

### Rolling joint Bayesian

The joint posterior is rebuilt from the latest `w` observations. Old orders fall out of the window. The rule can respond to a regime change, though it gives up information and depends on a tuning choice that the full-history posterior does not require.

## Why inventory uses a second environment

In the information model, one customer order executes at every step. Quote width does not affect participation. That setup isolates adverse selection, but it cannot support a causal claim that changing prices reduced inventory or lost volume.

The inventory environment therefore introduces a public midprice following a Gaussian random walk. The market maker centres its quote at

```text
reservation price = mid - inventory_skew * inventory
```

and fill probability decays exponentially with distance from the public mid. This makes quote placement affect both trade value and trade frequency.

The split is not a claim that information and inventory are independent in actual markets. It is a decision to avoid combining mechanisms until their separate effects can be checked.

## Assumptions

- binary terminal value;
- symmetric prior in the baseline experiments;
- perfectly informed informed customers;
- balanced and independent noise flow;
- independent trader types;
- one-unit orders;
- sequential arrivals;
- no strategic order splitting, waiting, or demand shading;
- perfect classification of customer buy and sell direction;
- instantaneous belief and quote updates;
- no fees, rebates, tick size, latency, queueing, or competition;
- no cross-asset hedge;
- a known model family and finite alpha grid;
- one deterministic low-to-high regime jump in the non-stationary experiment;
- independent Monte Carlo episodes.

## Interpretation-sensitive limitations

### Exogenous execution can reward implausibly wide quotes

A market maker that overestimates `alpha` quotes too widely but loses no orders in the information environment. Parts of the misspecification P&L surface therefore reflect the execution assumption rather than a robust economic opportunity. Fair-value error and informed-flow loss are cleaner diagnostics there.

### Alpha and state are only weakly separated

Order imbalance identifies a combination of state and signal strength. With one binary terminal value and a short tape, the joint filter often shrinks its alpha estimate toward the centre of the candidate grid. More observations help, but the ambiguity is structural rather than merely computational.

### Rolling adaptation is a heuristic

The regime experiment contains one abrupt, deterministic change. A short window reacts quickly but produces a noisier posterior; a long window is stable and slow. The reported best window is tied to the jump size, horizon, grid, and adaptation criterion used in the experiment.

### The fill curve is imposed

The inventory model uses an exponential execution rule because it produces a transparent spread-volume trade-off. Its parameters are not estimated from exchange data. The apparent optimal half-spread is therefore a property of the chosen toy market.

### There is no strategic equilibrium

Informed customers do not alter their behaviour when quotes widen, and competing market makers do not undercut unattractive prices. These omissions are most consequential precisely where the simple model seems easiest to exploit.

### Information and inventory are not unified

A richer market maker would learn from order flow, skew for inventory, affect who chooses to trade, and possibly hedge elsewhere. This project isolates those mechanisms rather than claiming to solve the feedback loop.

## Sensible extensions

The most informative next changes would be noisy private signals, variable trade sizes, quote-sensitive informed demand, and a latent Markov information regime. Multiple market makers or a continuous fundamental could follow once those mechanisms are understood. A full order book, reinforcement learning, and live-data backtesting would add substantial implementation surface without first resolving the assumptions that currently drive the main results.
