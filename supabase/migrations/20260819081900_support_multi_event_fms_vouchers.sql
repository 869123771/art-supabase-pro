
alter table public.fms_voucher
  add column if not exists source_event_code text;

update public.fms_voucher v
set source_event_code = e.event_code
from public.fms_posting_event e
where e.voucher_id = v.id
  and v.source_event_code is null;

drop index if exists public.fms_voucher_source_uidx;

create unique index fms_voucher_source_event_uidx
  on public.fms_voucher(account_set_id, source_type, source_id, coalesce(source_event_code, ''))
  where source_id is not null;

drop index if exists public.fms_voucher_source_lookup_idx;

create index fms_voucher_source_lookup_idx
  on public.fms_voucher(tenant_id, source_type, source_id, source_event_code);

do $migration$
declare
  v_save_definition text;
  v_process_definition text;
begin
  select pg_get_functiondef('public.save_fms_voucher(jsonb)'::regprocedure)
  into v_save_definition;

  if position(
    'voucher_date, fiscal_year, period_no, status, source_type, source_id, source_no,' ||
    E'\n      summary, attachments'
    in v_save_definition
  ) = 0 then
    raise exception 'save_fms_voucher insert columns did not match expected definition';
  end if;

  v_save_definition := replace(
    v_save_definition,
    'voucher_date, fiscal_year, period_no, status, source_type, source_id, source_no,' ||
      E'\n      summary, attachments',
    'voucher_date, fiscal_year, period_no, status, source_type, source_id, source_no,' ||
      E'\n      source_event_code, summary, attachments'
  );

  if position(
    'nullif(p_payload ->> ''sourceId'', '''')::uuid, nullif(btrim(p_payload ->> ''sourceNo''), ''''),' ||
    E'\n      btrim(p_payload ->> ''summary'')'
    in v_save_definition
  ) = 0 then
    raise exception 'save_fms_voucher insert values did not match expected definition';
  end if;

  v_save_definition := replace(
    v_save_definition,
    'nullif(p_payload ->> ''sourceId'', '''')::uuid, nullif(btrim(p_payload ->> ''sourceNo''), ''''),' ||
      E'\n      btrim(p_payload ->> ''summary'')',
    'nullif(p_payload ->> ''sourceId'', '''')::uuid, nullif(btrim(p_payload ->> ''sourceNo''), ''''),' ||
      E'\n      nullif(btrim(p_payload ->> ''sourceEventCode''), ''''), btrim(p_payload ->> ''summary'')'
  );

  if position(
    'source_no = nullif(btrim(p_payload ->> ''sourceNo''), ''''),' ||
    E'\n      summary = btrim(p_payload ->> ''summary'')'
    in v_save_definition
  ) = 0 then
    raise exception 'save_fms_voucher update values did not match expected definition';
  end if;

  v_save_definition := replace(
    v_save_definition,
    'source_no = nullif(btrim(p_payload ->> ''sourceNo''), ''''),' ||
      E'\n      summary = btrim(p_payload ->> ''summary'')',
    'source_no = nullif(btrim(p_payload ->> ''sourceNo''), ''''),' ||
      E'\n      source_event_code = nullif(btrim(p_payload ->> ''sourceEventCode''), ''''),' ||
      E'\n      summary = btrim(p_payload ->> ''summary'')'
  );

  execute v_save_definition;

  select pg_get_functiondef('app_private.process_fms_posting_event(uuid,boolean)'::regprocedure)
  into v_process_definition;

  if position(
    '''sourceId'', v_event.source_id,' ||
    E'\n      ''sourceNo'', v_event.source_no,'
    in v_process_definition
  ) = 0 then
    raise exception 'process_fms_posting_event voucher payload did not match expected definition';
  end if;

  v_process_definition := replace(
    v_process_definition,
    '''sourceId'', v_event.source_id,' ||
      E'\n      ''sourceNo'', v_event.source_no,',
    '''sourceId'', v_event.source_id,' ||
      E'\n      ''sourceNo'', v_event.source_no,' ||
      E'\n      ''sourceEventCode'', v_event.event_code,'
  );

  execute v_process_definition;
end
$migration$;

comment on column public.fms_voucher.source_event_code is
  'Lifecycle event code that distinguishes multiple accounting vouchers generated from the same business object.';
;
