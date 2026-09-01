-- Keep period-close audit timestamps in the same protected field group as actor and reason.

create or replace function app_private.fms_period_close_run_to_secure_json(
  p_run jsonb,p_owner_id uuid,p_access jsonb default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_access jsonb:=coalesce(
    p_access,app_private.field_access_map('fms.period_close',p_owner_id)
  );
  v_data jsonb:=coalesce(p_run,'{}'::jsonb)-'tenant_id'-'created_by_user_id';
begin
  v_data:=app_private.apply_jsonb_amount_access(
    v_data,array['passed_count','warning_count','blocking_count']::text[],
    coalesce(v_access->>'closeDiagnostics','hidden')
  );
  v_data:=app_private.apply_jsonb_text_access(
    v_data,array['profit_loss_voucher_id','year_end_voucher_id']::text[],
    coalesce(v_access->>'voucherReferences','hidden')
  );
  v_data:=app_private.apply_jsonb_text_access(
    v_data,
    array['completed_at','completed_by','cancelled_at','cancelled_by','cancel_reason']::text[],
    coalesce(v_access->>'closeAudit','hidden')
  );
  return v_data||jsonb_build_object(
    'field_access',v_access,
    'is_record_owner',p_owner_id=app_private.current_app_user_id()
  );
end;
$$;

;
