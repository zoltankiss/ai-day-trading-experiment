PHASE: TRADE (8:45 CT, 15 min after the 8:30 CT open).

1. Read today's journal plan from the research run (if it's missing, do a compressed
   version of the research yourself first).
2. `get_portfolio` for buying power, `get_equity_positions` and `get_equity_orders` for
   what's held and what's pending.
3. Re-check quotes for the plan's names; skip anything that gapped far past its entry or
   whose story broke overnight.
4. Execute: exits first, then entries, within settled buying power. Review → place.
5. Before you finish, re-check the orders: for every buy that filled, place its GTC stop
   sell now. For buys still working, book a `check` run (ops/requests) 30–60 min out to
   place the stop once filled — or re-price/cancel per the plan.
6. Record every order in the journal and update `kb/positions.md`.
