create or replace function app_private.hr_guard_candidate_history_immutable()
returns trigger language plpgsql set search_path = '' as $function$
begin
  if coalesce(current_setting('app.hr_recruitment_erasure', true), '') <> 'on' then
    raise exception '候选人阶段历史为不可变审计记录' using errcode = '42501';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end
$function$;

create trigger hr_candidate_stage_history_immutable
before update or delete on public.hr_candidate_stage_history
for each row execute function app_private.hr_guard_candidate_history_immutable();

revoke all on function app_private.hr_guard_candidate_history_immutable()
from public, anon, authenticated;

create or replace function public.hr_delete_recruitment_record_secure(
  p_kind text,
  p_id uuid
)
returns void language plpgsql security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if p_kind not in ('requisition', 'candidate') then
    raise exception '仅招聘需求和未进入流程的候选人允许删除';
  end if;
  if not app_private.can_execute_business_action('HrRecruitment', 'Hr:Recruitment:Delete', null, false) then
    raise exception '当前账号没有删除招聘记录的权限' using errcode = '42501';
  end if;

  if p_kind = 'requisition' then
    delete from public.hr_recruitment_requisition requisition
    where requisition.id = p_id
      and requisition.status in ('draft', 'rejected')
      and (app_private.is_platform_super() or requisition.tenant_id = v_tenant_id)
      and not exists (
        select 1 from public.hr_candidate candidate where candidate.requisition_id = requisition.id
      );
    if not found then
      raise exception '仅没有候选人的草稿或已驳回招聘需求可以删除';
    end if;
    return;
  end if;

  if not exists (
    select 1 from public.hr_candidate candidate
    where candidate.id = p_id and candidate.stage = 'new'
      and (app_private.is_platform_super() or candidate.tenant_id = v_tenant_id)
      and not exists (
        select 1 from public.hr_recruitment_interview interview where interview.candidate_id = candidate.id
      )
      and not exists (
        select 1 from public.hr_recruitment_offer offer where offer.candidate_id = candidate.id
      )
      and not exists (
        select 1 from public.hr_recruitment_handoff handoff where handoff.candidate_id = candidate.id
      )
  ) then
    raise exception '仅未进入筛选且没有后续业务记录的候选人可以删除';
  end if;
  perform pg_catalog.set_config('app.hr_recruitment_erasure', 'on', true);
  delete from public.hr_candidate_stage_history where candidate_id = p_id;
  delete from public.hr_candidate where id = p_id;
end
$function$;

revoke all on function public.hr_delete_recruitment_record_secure(text, uuid)
from public, anon;
grant execute on function public.hr_delete_recruitment_record_secure(text, uuid)
to authenticated, service_role;

create or replace function public.hr_transition_recruitment_offer_secure(
  p_offer_id uuid,
  p_action text,
  p_comment text default null
)
returns void language plpgsql security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_offer public.hr_recruitment_offer;
  v_candidate public.hr_candidate;
  v_requisition public.hr_recruitment_requisition;
  v_permission text;
  v_next_status text;
  v_handoff_id uuid;
begin
  v_permission := case
    when p_action = 'submit' then 'Hr:Recruitment:Offer:Submit'
    when p_action in ('approve', 'reject') then 'Hr:Recruitment:Offer:Approve'
    when p_action in ('send', 'withdraw', 'expire') then 'Hr:Recruitment:Offer:Send'
    when p_action in ('accept', 'decline') then 'Hr:Recruitment:Offer:Respond'
    else null
  end;
  if v_permission is null then raise exception '不支持的 Offer 动作'; end if;
  if not app_private.can_execute_business_action('HrRecruitment', v_permission, null, false) then
    raise exception '当前账号没有执行该 Offer 动作的权限' using errcode = '42501';
  end if;
  select * into v_offer from public.hr_recruitment_offer
  where id = p_offer_id and (app_private.is_platform_super() or tenant_id = v_tenant_id)
  for update;
  if not found then raise exception 'Offer 不存在或无权操作'; end if;
  select * into v_candidate from public.hr_candidate where id = v_offer.candidate_id;
  select requisition.* into v_requisition
  from public.hr_recruitment_requisition requisition where requisition.id = v_candidate.requisition_id;
  if p_action in ('send', 'accept') and v_candidate.stage not in ('interview', 'offer') then
    raise exception '候选人当前阶段不允许发送或接受 Offer';
  end if;

  v_next_status := case
    when p_action = 'submit' and v_offer.status in ('draft', 'rejected') then 'pending_approval'
    when p_action = 'approve' and v_offer.status = 'pending_approval' then 'approved'
    when p_action = 'reject' and v_offer.status = 'pending_approval' then 'rejected'
    when p_action = 'send' and v_offer.status = 'approved' then 'sent'
    when p_action = 'accept' and v_offer.status = 'sent' then 'accepted'
    when p_action = 'decline' and v_offer.status = 'sent' then 'declined'
    when p_action = 'expire' and v_offer.status = 'sent' then 'expired'
    when p_action = 'withdraw' and v_offer.status in ('approved', 'sent') then 'withdrawn'
    else null
  end;
  if v_next_status is null then
    raise exception 'Offer 当前状态 % 不支持动作 %', v_offer.status, p_action;
  end if;
  if p_action in ('reject', 'decline', 'withdraw') and nullif(btrim(p_comment), '') is null then
    raise exception '该 Offer 动作必须填写原因';
  end if;

  update public.hr_recruitment_offer
  set status = v_next_status,
      approval_comment = case when p_action in ('approve', 'reject') then nullif(btrim(p_comment), '') else approval_comment end,
      approved_by = case when p_action = 'approve' then coalesce(app_private.current_user_email(), 'system') else approved_by end,
      approved_at = case when p_action = 'approve' then now() else approved_at end,
      sent_at = case when p_action = 'send' then now() else sent_at end,
      responded_at = case when p_action in ('accept', 'decline') then now() else responded_at end,
      response_note = case when p_action in ('accept', 'decline') then nullif(btrim(p_comment), '') else response_note end
  where id = v_offer.id;

  if p_action = 'send' and v_candidate.stage = 'interview' then
    perform app_private.hr_append_candidate_stage(v_candidate.id, 'offer', 'Offer 已发送');
  end if;
  if p_action = 'accept' then
    if v_candidate.stage = 'interview' then
      perform app_private.hr_append_candidate_stage(v_candidate.id, 'offer', '候选人已接受 Offer');
    end if;
    insert into public.hr_recruitment_handoff(
      tenant_id, candidate_id, offer_id, organization_id, position_id, planned_onboard_date, status
    ) values (
      v_offer.tenant_id, v_candidate.id, v_offer.id, v_requisition.organization_id,
      v_requisition.position_id, v_offer.proposed_onboard_date, 'pending'
    ) on conflict (tenant_id, candidate_id) do update set
      offer_id = excluded.offer_id,
      organization_id = excluded.organization_id,
      position_id = excluded.position_id,
      planned_onboard_date = excluded.planned_onboard_date,
      status = 'pending',
      completed_at = null
    where hr_recruitment_handoff.status <> 'completed'
    returning id into v_handoff_id;
    if v_handoff_id is null then raise exception '已完成入职交接的候选人不能重新接受 Offer'; end if;

    insert into public.hr_recruitment_onboarding_task(
      tenant_id, handoff_id, task_category, task_title, task_description, due_date
    )
    select v_offer.tenant_id, v_handoff_id, seed.category, seed.title, seed.description,
      v_offer.proposed_onboard_date + seed.day_offset
    from (values
      ('documentation', '收集并核验入职资料', '核验身份、学历、离职证明与录用所需资料。', -5),
      ('account', '准备系统账号与权限', '按岗位最小权限原则完成账号、组织和角色开通。', -2),
      ('equipment', '准备工位与工作设备', '确认电脑、工位、门禁及岗位必要设备。', -1),
      ('orientation', '安排首日引导与入职培训', '明确报到联系人、首日议程、制度学习与安全培训。', 0)
    ) seed(category, title, description, day_offset)
    where not exists (
      select 1 from public.hr_recruitment_onboarding_task task
      where task.handoff_id = v_handoff_id and task.task_title = seed.title
    );
  end if;
end
$function$;

revoke all on function public.hr_transition_recruitment_offer_secure(uuid, text, text)
from public, anon;
grant execute on function public.hr_transition_recruitment_offer_secure(uuid, text, text)
to authenticated, service_role;

;
