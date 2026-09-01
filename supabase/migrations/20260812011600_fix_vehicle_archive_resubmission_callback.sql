create or replace function app_private.execute_vehicle_archive_workflow_callback(
  p_business_id uuid,
  p_status text,
  p_actor text,
  p_comment text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_catalog.set_config('app.workflow_engine', 'on', true);

  update public.vehicle_archive
  set audit_status = case p_status
        when 'running' then 'pending'
        when 'approved' then 'approved'
        when 'rejected' then 'rejected'
        when 'withdrawn' then 'pending'
        when 'cancelled' then 'pending'
        else audit_status
      end,
      audit_time = case
        when p_status in ('approved', 'rejected') then pg_catalog.now()
        else null
      end,
      audit_by = case
        when p_status in ('approved', 'rejected') then p_actor
        else null
      end,
      audit_remark = case
        when p_status in ('approved', 'rejected', 'cancelled')
          then nullif(pg_catalog.btrim(coalesce(p_comment, '')), '')
        else null
      end
  where id = p_business_id;

  if not found then
    raise exception '车辆档案不存在或已被删除';
  end if;
end;
$$;

create or replace function app_private.trg_require_workflow_for_vehicle_review()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (
    new.audit_status is distinct from old.audit_status
    or new.audit_by is distinct from old.audit_by
    or new.audit_time is distinct from old.audit_time
    or new.audit_remark is distinct from old.audit_remark
  ) and coalesce(
    pg_catalog.current_setting('app.workflow_engine', true),
    ''
  ) <> 'on' then
    raise exception '车辆档案审核状态与审核信息必须通过审批中心流转';
  end if;

  return new;
end;
$$;;
