alter table public.hr_succession_candidate
  drop constraint hr_succession_candidate_plan_fkey,
  add constraint hr_succession_candidate_plan_fkey
    foreign key (plan_id, tenant_id)
    references public.hr_succession_plan(id, tenant_id) on delete restrict;

alter table public.hr_succession_development_action
  drop constraint hr_succession_action_candidate_fkey,
  add constraint hr_succession_action_candidate_fkey
    foreign key (candidate_id, tenant_id)
    references public.hr_succession_candidate(id, tenant_id) on delete restrict;

create or replace function public.hr_delete_succession_record_secure(p_kind text, p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_permission text;
begin
  v_permission := case p_kind
    when 'plan' then 'Hr:Succession:Plan:Delete'
    when 'candidate' then 'Hr:Succession:Candidate:Delete'
    when 'action' then 'Hr:Succession:Action:Delete'
    else null
  end;
  if v_permission is null then raise exception '不支持的继任记录类型'; end if;
  if not app_private.can_execute_business_action('HrSuccession', v_permission, null, false) then
    raise exception 'Missing succession delete permission' using errcode = '42501';
  end if;

  if p_kind = 'plan' then
    if exists (
      select 1 from public.hr_succession_candidate candidate_row
      where candidate_row.plan_id = p_id
        and (app_private.is_platform_super() or candidate_row.tenant_id = v_tenant_id)
    ) then
      raise exception '该计划已有候选人记录，请先逐项处理候选人，继任历史不会级联删除';
    end if;
    delete from public.hr_succession_plan
    where id = p_id and status = 'draft'
      and (app_private.is_platform_super() or tenant_id = v_tenant_id);
  elsif p_kind = 'candidate' then
    if exists (
      select 1 from public.hr_succession_development_action action_row
      where action_row.candidate_id = p_id
        and (app_private.is_platform_super() or action_row.tenant_id = v_tenant_id)
    ) then
      raise exception '该候选人已有发展行动，请先逐项处理行动，人才发展历史不会级联删除';
    end if;
    delete from public.hr_succession_candidate
    where id = p_id and status = 'nominated'
      and (app_private.is_platform_super() or tenant_id = v_tenant_id);
  else
    delete from public.hr_succession_development_action
    where id = p_id and status = 'planned'
      and (app_private.is_platform_super() or tenant_id = v_tenant_id);
  end if;
  if not found then
    raise exception '仅草稿计划、待评审候选人或计划中行动可删除';
  end if;
end;
$function$;

revoke all on function public.hr_delete_succession_record_secure(text, uuid) from public, anon;
grant execute on function public.hr_delete_succession_record_secure(text, uuid)
  to authenticated, service_role;

;
