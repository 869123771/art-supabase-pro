create or replace function app_private.trg_require_customer_statement_items()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'pending_review' and old.status <> 'pending_review'
     and not exists (
       select 1
       from public.tms_customer_statement_item i
       where i.statement_id = new.id
     ) then
    raise exception '空对账单不能提交审核';
  end if;
  return new;
end;
$$;

revoke all on function app_private.trg_require_customer_statement_items() from public;

drop trigger if exists tms_customer_statement_require_items on public.tms_customer_statement;
create trigger tms_customer_statement_require_items
before update of status on public.tms_customer_statement
for each row execute function app_private.trg_require_customer_statement_items();

create or replace view public.tms_customer_statement_summary
with (security_invoker = true)
as
select
  s.id,
  s.tenant_id,
  s.statement_no,
  s.customer_id,
  s.customer_name_snapshot as customer_name,
  s.period_start,
  s.period_end,
  s.status,
  count(i.id)::integer as waybill_count,
  coalesce(sum(i.line_amount), 0)::numeric(14, 2) as statement_amount,
  s.settled_amount,
  case
    when s.status = 'voided' then 0
    else greatest(coalesce(sum(i.line_amount), 0) - s.settled_amount, 0)
  end::numeric(14, 2) as outstanding_amount,
  s.submitted_at,
  s.submitted_by,
  s.reviewed_at,
  s.reviewed_by,
  s.review_remark,
  s.voided_at,
  s.voided_by,
  s.void_reason,
  s.remark,
  s.create_by,
  s.create_time,
  s.update_by,
  s.update_time
from public.tms_customer_statement s
left join public.tms_customer_statement_item i on i.statement_id = s.id
group by s.id;

grant select on table public.tms_customer_statement_summary to authenticated, service_role;

;
