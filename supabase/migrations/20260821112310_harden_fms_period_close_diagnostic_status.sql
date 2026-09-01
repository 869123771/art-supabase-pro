-- Treat diagnostic result and control level as protected close-diagnostic fields.

create or replace function app_private.fms_period_close_check_to_secure_json(
  p_check jsonb,p_owner_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_access jsonb:=app_private.field_access_map('fms.period_close',p_owner_id);
  v_data jsonb:=coalesce(p_check,'{}'::jsonb)-'tenant_id';
begin
  v_data:=app_private.apply_jsonb_amount_access(
    v_data,array['issue_count']::text[],coalesce(v_access->>'closeDiagnostics','hidden')
  );
  v_data:=app_private.apply_jsonb_text_access(
    v_data,array['status','is_blocking','summary','detail']::text[],
    coalesce(v_access->>'closeDiagnostics','hidden')
  );
  return v_data||jsonb_build_object(
    'field_access',v_access,
    'is_record_owner',p_owner_id=app_private.current_app_user_id()
  );
end;
$$;

;
