create or replace function public.hr_transition_lifecycle_case_secure(
  p_id uuid,
  p_action text,
  p_comment text default null,
  p_effective_date date default null
)
returns void language plpgsql security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_case public.hr_lifecycle_case;
  v_open_blocking integer;
  v_open_required integer;
  v_permission text := case when p_action = 'complete'
    then 'Hr:Lifecycle:CompleteCase' else 'Hr:Lifecycle:Start' end;
begin
  if p_action not in ('start', 'ready', 'complete', 'cancel') then
    raise exception '不支持的事项动作';
  end if;
  if not app_private.can_execute_business_action('HrLifecycle', v_permission, null, false) then
    raise exception '当前账号没有推进生命周期事项的权限' using errcode = '42501';
  end if;
  select * into v_case from public.hr_lifecycle_case c
  where c.id = p_id and (app_private.is_platform_super() or c.tenant_id = v_tenant_id)
  for update;
  if not found then raise exception '生命周期事项不存在或无权操作'; end if;

  perform set_config('app.workflow_engine', 'on', true);
  if p_action = 'start' then
    if v_case.execution_status <> 'planning' or v_case.status not in ('approved', 'effective') then
      raise exception '只有审批通过且待规划的事项可以启动';
    end if;
    if not exists (
      select 1 from public.hr_lifecycle_task t where t.lifecycle_case_id = v_case.id
    ) then raise exception '事项至少需要一项执行任务'; end if;
    update public.hr_lifecycle_case
    set execution_status = 'in_progress', started_at = now()
    where id = v_case.id;
    return;
  end if;
  if p_action = 'ready' then
    if v_case.execution_status <> 'in_progress' then
      raise exception '只有执行中的事项可以校验就绪';
    end if;
    select count(*) into v_open_blocking from public.hr_lifecycle_task t
    where t.lifecycle_case_id = v_case.id and t.blocking
      and t.status in ('pending', 'processing');
    if v_open_blocking > 0 then
      raise exception '仍有 % 项阻断任务未完成', v_open_blocking;
    end if;
    update public.hr_lifecycle_case
    set execution_status = 'ready', ready_at = now()
    where id = v_case.id;
    return;
  end if;
  if p_action = 'complete' then
    if v_case.execution_status <> 'ready' then raise exception '只有已就绪事项可以办结'; end if;
    select count(*) into v_open_required from public.hr_lifecycle_task t
    where t.lifecycle_case_id = v_case.id and t.required
      and t.status in ('pending', 'processing');
    if v_open_required > 0 then raise exception '仍有 % 项必办任务未完成', v_open_required; end if;
    update public.hr_lifecycle_case
    set status = 'effective', execution_status = 'completed',
      actual_effective_date = coalesce(p_effective_date, planned_effective_date),
      completed_at = now(), completed_by = auth.uid()::text,
      remark = coalesce(nullif(btrim(p_comment), ''), remark)
    where id = v_case.id;
    return;
  end if;
  if v_case.execution_status in ('completed', 'cancelled') then
    raise exception '已结束事项不能取消';
  end if;
  if nullif(btrim(p_comment), '') is null then raise exception '取消事项必须填写原因'; end if;
  update public.hr_lifecycle_case
  set status = 'cancelled', execution_status = 'cancelled',
    cancelled_at = now(), cancellation_reason = btrim(p_comment)
  where id = v_case.id;
  update public.hr_lifecycle_task set status = 'cancelled'
  where lifecycle_case_id = v_case.id and status in ('pending', 'processing');
end
$function$;

revoke all on function public.hr_transition_lifecycle_case_secure(uuid,text,text,date)
  from public, anon, authenticated;
grant execute on function public.hr_transition_lifecycle_case_secure(uuid,text,text,date)
  to authenticated, service_role;

;
