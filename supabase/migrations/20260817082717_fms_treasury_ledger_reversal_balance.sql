begin;

-- A reversal is an additional opposite ledger movement. The original movement
-- remains part of the historical balance even after its lifecycle status is
-- marked as reversed, so both entries must participate in balance calculation.
create or replace view public.fms_fund_account_summary
with (security_invoker = true)
as
select
  a.*,
  coalesce(l.inflow_amount, 0)::numeric(18, 2) as inflow_amount,
  coalesce(l.outflow_amount, 0)::numeric(18, 2) as outflow_amount,
  (a.opening_balance + coalesce(l.inflow_amount, 0) - coalesce(l.outflow_amount, 0))::numeric(18, 2)
    as current_balance,
  (a.opening_balance + coalesce(l.inflow_amount, 0) - coalesce(l.outflow_amount, 0)
    - a.frozen_balance)::numeric(18, 2) as available_balance,
  coalesce(l.entry_count, 0)::integer as ledger_entry_count,
  greatest(a.balance_as_of, l.last_entry_date) as latest_balance_date
from public.fms_fund_account a
left join lateral (
  select
    sum(case when e.direction = 'inflow' then e.amount else 0 end) as inflow_amount,
    sum(case when e.direction = 'outflow' then e.amount else 0 end) as outflow_amount,
    count(*) as entry_count,
    max(e.entry_date) as last_entry_date
  from public.fms_fund_ledger_entry e
  where e.fund_account_id = a.id
) l on true;

commit;

;
