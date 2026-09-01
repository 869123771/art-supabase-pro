-- Preserve protected source references and attachments on permitted header-only edits.

create or replace function public.save_fms_voucher_secure(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := nullif(p_payload ->> 'id', '')::uuid;
  v_existing public.fms_voucher%rowtype;
  v_saved public.fms_voucher%rowtype;
  v_period public.fms_accounting_period%rowtype;
  v_access jsonb;
  v_amount_editable boolean := true;
  v_date date;
  v_actor text := coalesce(auth.jwt() ->> 'email', auth.uid()::text, 'unknown');
  v_permission text := case when v_id is null
    then 'FinanceVoucherCenter:Add'
    else 'FinanceVoucherCenter:Edit'
  end;
begin
  if not app_private.can_execute_business_action(
    'FinanceVoucherCenter', v_permission, null, false
  ) then
    raise exception 'Missing voucher write permission' using errcode = '42501';
  end if;

  if v_id is not null then
    select * into v_existing
    from public.fms_voucher voucher_row
    where voucher_row.id = v_id
      and voucher_row.tenant_id = app_private.current_user_tenant_id()
    for update;
    if not found then
      raise exception 'Voucher not found' using errcode = 'P0002';
    end if;
    v_access := app_private.field_access_map('fms.voucher', v_existing.created_by_user_id);
    v_amount_editable := coalesce(v_access ->> 'voucherAmounts', 'hidden') = 'edit';

    if not v_amount_editable
       and app_private.fms_voucher_financial_lines_input(p_payload -> 'lines')
         is distinct from app_private.fms_voucher_financial_lines_payload(v_id) then
      raise exception 'Voucher amounts are not editable' using errcode = '42501';
    end if;

    if coalesce(v_access ->> 'sourceReferences', 'hidden') <> 'edit' then
      p_payload := p_payload || jsonb_build_object(
        'sourceId', v_existing.source_id,
        'sourceNo', v_existing.source_no,
        'sourceEventCode', v_existing.source_event_code
      );
    end if;

    if coalesce(v_access ->> 'voucherAttachments', 'hidden') <> 'edit' then
      p_payload := p_payload || jsonb_build_object('attachments', v_existing.attachments);
    end if;

    if not v_amount_editable then
      if nullif(p_payload ->> 'accountSetId', '')::uuid is distinct from v_existing.account_set_id then
        raise exception 'Voucher account set cannot be changed' using errcode = '42501';
      end if;
      if v_existing.status not in ('draft', 'rejected') then
        raise exception 'Only draft or rejected vouchers are editable' using errcode = '23514';
      end if;
      v_date := coalesce(nullif(p_payload ->> 'voucherDate', '')::date, v_existing.voucher_date);
      select * into v_period
      from public.fms_accounting_period period_row
      where period_row.account_set_id = v_existing.account_set_id
        and v_date between period_row.start_date and period_row.end_date;
      if not found then
        raise exception 'Voucher date has no accounting period' using errcode = '23503';
      end if;

      update public.fms_voucher
      set accounting_period_id = v_period.id,
          voucher_type = coalesce(nullif(p_payload ->> 'voucherType', ''), voucher_type),
          voucher_date = v_date,
          fiscal_year = v_period.fiscal_year,
          period_no = v_period.period_no,
          source_type = coalesce(nullif(p_payload ->> 'sourceType', ''), source_type),
          source_id = nullif(p_payload ->> 'sourceId', '')::uuid,
          source_no = nullif(btrim(p_payload ->> 'sourceNo'), ''),
          source_event_code = nullif(btrim(p_payload ->> 'sourceEventCode'), ''),
          summary = btrim(p_payload ->> 'summary'),
          attachments = coalesce(p_payload -> 'attachments', attachments)
      where id = v_id
      returning * into v_saved;

      insert into public.fms_voucher_action(
        tenant_id, account_set_id, voucher_id, action, from_status, to_status,
        actor, snapshot
      ) values (
        v_saved.tenant_id, v_saved.account_set_id, v_saved.id, 'save',
        v_saved.status, v_saved.status, v_actor,
        jsonb_build_object(
          'version', v_saved.version,
          'lineCount', v_saved.line_count,
          'totalDebit', v_saved.total_debit,
          'totalCredit', v_saved.total_credit
        )
      );
      return app_private.fms_voucher_to_secure_json(
        app_private.fms_voucher_raw_json(v_saved.id, false),
        v_saved.created_by_user_id
      );
    end if;
  end if;

  v_saved := public.save_fms_voucher(p_payload);
  return app_private.fms_voucher_to_secure_json(
    app_private.fms_voucher_raw_json(v_saved.id, false),
    v_saved.created_by_user_id
  );
end;
$$;

;
