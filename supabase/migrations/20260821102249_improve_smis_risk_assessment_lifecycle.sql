-- SMIS 风险评估第二批：评估版本原子创建、历史快照和草稿期保护。

alter table public.smis_risk_assessment_item
  add column hazard_name_snapshot text,
  add column hazard_description_snapshot text,
  add column accident_type_snapshot text,
  add column possible_consequence_snapshot text,
  add column existing_controls_snapshot text;

update public.smis_risk_assessment_item item_row
set hazard_name_snapshot = source_row.hazard_name,
    hazard_description_snapshot = source_row.hazard_description,
    accident_type_snapshot = source_row.accident_type,
    possible_consequence_snapshot = source_row.possible_consequence,
    existing_controls_snapshot = source_row.existing_controls
from public.smis_hazard_source source_row
where source_row.id = item_row.hazard_source_id
  and source_row.tenant_id = item_row.tenant_id;

alter table public.smis_risk_assessment_item
  alter column hazard_name_snapshot set not null;

comment on column public.smis_risk_assessment_item.hazard_name_snapshot
  is '评估发生时的危险源名称快照，避免主档后续修改污染历史评估';
comment on column public.smis_risk_assessment_item.hazard_description_snapshot
  is '评估发生时的危险源描述快照';
comment on column public.smis_risk_assessment_item.accident_type_snapshot
  is '评估发生时的事故类型快照';
comment on column public.smis_risk_assessment_item.possible_consequence_snapshot
  is '评估发生时的可能后果快照';
comment on column public.smis_risk_assessment_item.existing_controls_snapshot
  is '评估发生时的既有措施快照';

create or replace function app_private.validate_smis_assessment_item_source()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source public.smis_hazard_source%rowtype;
begin
  select source_row.*
    into v_source
  from public.smis_risk_assessment assessment_row
  join public.smis_hazard_source source_row
    on source_row.risk_point_id = assessment_row.risk_point_id
   and source_row.tenant_id = assessment_row.tenant_id
  where assessment_row.id = new.assessment_id
    and source_row.id = new.hazard_source_id
    and assessment_row.tenant_id = new.tenant_id;

  if not found then
    raise exception '危险源不属于本次评估的风险点' using errcode = '23514';
  end if;

  new.hazard_name_snapshot := v_source.hazard_name;
  new.hazard_description_snapshot := v_source.hazard_description;
  new.accident_type_snapshot := v_source.accident_type;
  new.possible_consequence_snapshot := v_source.possible_consequence;
  new.existing_controls_snapshot := v_source.existing_controls;
  return new;
end;
$$;

create or replace function app_private.guard_smis_risk_assessment_metadata()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status <> 'draft' then
    raise exception '只有草稿评估可以修改评估信息' using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke all on function app_private.guard_smis_risk_assessment_metadata()
  from public, anon, authenticated, service_role;

create trigger smis_risk_assessment_metadata_draft_guard
before update of assessor_user_id, assessment_date, assessment_summary
on public.smis_risk_assessment
for each row execute function app_private.guard_smis_risk_assessment_metadata();

revoke update (risk_point_id, assessor_user_id, version_no, assessment_date, assessment_summary)
  on public.smis_risk_assessment from authenticated;
grant update (assessor_user_id, assessment_date, assessment_summary)
  on public.smis_risk_assessment to authenticated;

alter policy smis_risk_assessment_delete
on public.smis_risk_assessment
using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisRiskPoint:Assess')
  and status = 'draft'
);

create or replace function public.smis_create_risk_assessment(
  p_risk_point_id uuid,
  p_assessment_date date default current_date,
  p_assessment_summary text default null
)
returns public.smis_risk_assessment
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_point public.smis_risk_point%rowtype;
  v_assessment public.smis_risk_assessment%rowtype;
  v_next_version integer;
begin
  if auth.uid() is null then
    raise exception '请先登录后再创建风险评估' using errcode = '42501';
  end if;

  select point_row.*
    into v_point
  from public.smis_risk_point point_row
  where point_row.id = p_risk_point_id
    and (
      app_private.is_platform_super()
      or point_row.tenant_id = app_private.current_user_tenant_id()
    )
  for update;

  if not found then
    raise exception '风险点不存在或无权访问' using errcode = 'P0002';
  end if;
  if v_point.status <> 'active' then
    raise exception '只有启用状态的风险点可以创建评估';
  end if;
  if not app_private.can_execute_business_action(
    'SmisRiskPoint', 'SmisRiskPoint:Assess', null, false
  ) then
    raise exception '当前账号没有维护风险评估的权限' using errcode = '42501';
  end if;

  select coalesce(max(assessment_row.version_no), 0) + 1
    into v_next_version
  from public.smis_risk_assessment assessment_row
  where assessment_row.tenant_id = v_point.tenant_id
    and assessment_row.risk_point_id = v_point.id;

  insert into public.smis_risk_assessment (
    tenant_id,
    risk_point_id,
    assessor_user_id,
    version_no,
    assessment_date,
    assessment_summary,
    create_by
  ) values (
    v_point.tenant_id,
    v_point.id,
    app_private.current_app_user_id(),
    v_next_version,
    coalesce(p_assessment_date, current_date),
    nullif(btrim(p_assessment_summary), ''),
    coalesce(auth.jwt() ->> 'email', 'unknown')
  )
  returning * into v_assessment;

  return v_assessment;
end;
$$;

revoke all on function public.smis_create_risk_assessment(uuid, date, text)
  from public, anon;
grant execute on function public.smis_create_risk_assessment(uuid, date, text)
  to authenticated, service_role;

create or replace function public.smis_transition_risk_assessment(
  p_assessment_id uuid,
  p_action text,
  p_comment text default null
)
returns public.smis_risk_assessment
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_assessment public.smis_risk_assessment%rowtype;
  v_target_status text;
  v_permission text;
  v_actor_user_id uuid := app_private.current_app_user_id();
  v_max_score numeric(12, 2);
  v_max_level text;
begin
  if auth.uid() is null then
    raise exception '请先登录后再执行评估操作' using errcode = '42501';
  end if;

  select * into v_assessment
  from public.smis_risk_assessment assessment_row
  where assessment_row.id = p_assessment_id
    and (
      app_private.is_platform_super()
      or assessment_row.tenant_id = app_private.current_user_tenant_id()
    )
  for update;

  if not found then
    raise exception '风险评估不存在或无权访问' using errcode = 'P0002';
  end if;

  case p_action
    when 'submit' then
      v_target_status := 'submitted';
      v_permission := 'SmisRiskPoint:Assess';
      if v_assessment.status <> 'draft' then
        raise exception '只有草稿评估可以提交';
      end if;
      if not exists (
        select 1 from public.smis_risk_assessment_item item_row
        where item_row.assessment_id = p_assessment_id
      ) then
        raise exception '请至少完成一项危险源评估后再提交';
      end if;
      if exists (
        select 1
        from public.smis_risk_assessment_item item_row
        where item_row.assessment_id = p_assessment_id
          and not exists (
            select 1
            from public.smis_control_measure measure_row
            where measure_row.assessment_item_id = item_row.id
          )
      ) then
        raise exception '每项危险源评估至少需要一条管控措施后才能提交';
      end if;
    when 'activate' then
      v_target_status := 'effective';
      v_permission := 'SmisRiskPoint:ActivateAssessment';
      if v_assessment.status <> 'submitted' then
        raise exception '只有已提交评估可以生效';
      end if;
    when 'withdraw' then
      v_target_status := 'draft';
      v_permission := 'SmisRiskPoint:Assess';
      if v_assessment.status <> 'submitted' then
        raise exception '只有已提交评估可以撤回';
      end if;
    else
      raise exception '不支持的评估操作';
  end case;

  if not app_private.can_execute_business_action(
    'SmisRiskPoint', v_permission, null, false
  ) then
    raise exception '当前账号没有执行此评估操作的权限' using errcode = '42501';
  end if;

  select item_row.risk_score, item_row.risk_level
    into v_max_score, v_max_level
  from public.smis_risk_assessment_item item_row
  where item_row.assessment_id = p_assessment_id
  order by item_row.risk_score desc, item_row.id
  limit 1;

  if p_action = 'activate' then
    update public.smis_risk_assessment existing
    set status = 'superseded'
    where existing.tenant_id = v_assessment.tenant_id
      and existing.risk_point_id = v_assessment.risk_point_id
      and existing.status = 'effective'
      and existing.id <> v_assessment.id;
  end if;

  update public.smis_risk_assessment
  set status = v_target_status,
      submitted_at = case
        when p_action = 'submit' then now()
        when p_action = 'withdraw' then null
        else submitted_at
      end,
      effective_at = case when p_action = 'activate' then now() else effective_at end,
      reviewer_user_id = case when p_action = 'activate' then v_actor_user_id else reviewer_user_id end,
      review_comment = case when p_action = 'activate' then nullif(btrim(p_comment), '') else review_comment end,
      max_risk_score = v_max_score,
      max_risk_level = v_max_level
  where id = p_assessment_id
  returning * into v_assessment;

  if p_action = 'activate' then
    update public.smis_risk_point
    set current_risk_level = v_max_level
    where id = v_assessment.risk_point_id
      and tenant_id = v_assessment.tenant_id;
  end if;

  insert into public.smis_risk_assessment_event (
    tenant_id, assessment_id, from_status, to_status, action, comment,
    actor_user_id, create_by
  ) values (
    v_assessment.tenant_id, v_assessment.id,
    case
      when p_action = 'submit' then 'draft'
      when p_action = 'activate' then 'submitted'
      else 'submitted'
    end,
    v_target_status, p_action, nullif(btrim(p_comment), ''),
    v_actor_user_id, coalesce(auth.jwt() ->> 'email', 'unknown')
  );

  return v_assessment;
end;
$$;

revoke all on function public.smis_transition_risk_assessment(uuid, text, text)
  from public, anon;
grant execute on function public.smis_transition_risk_assessment(uuid, text, text)
  to authenticated, service_role;

-- 继续复用系统字典页面，注册评估状态、措施状态和标准 LEC 分值。
do $$
declare
  v_type_id uuid;
begin
  insert into public.sys_dict_type (name, code, status, create_by, remark, node_type, sort)
  values ('SMIS评估状态', 'smisAssessmentStatus', '1', '624944977@qq.com',
    '风险评估版本生命周期', 'dictionary', 613)
  on conflict do nothing;
  select id into v_type_id from public.sys_dict_type where code = 'smisAssessmentStatus' limit 1;
  insert into public.sys_dictionary
    (type_id, code, status, create_by, value, label, sort, tag_type)
  values
    (v_type_id, 'draft', '1', '624944977@qq.com', 'draft', '草稿', 1, 'info'),
    (v_type_id, 'submitted', '1', '624944977@qq.com', 'submitted', '已提交', 2, 'warning'),
    (v_type_id, 'effective', '1', '624944977@qq.com', 'effective', '已生效', 3, 'success'),
    (v_type_id, 'superseded', '1', '624944977@qq.com', 'superseded', '已被替代', 4, 'info')
  on conflict do nothing;

  insert into public.sys_dict_type (name, code, status, create_by, remark, node_type, sort)
  values ('SMIS管控措施状态', 'smisControlMeasureStatus', '1', '624944977@qq.com',
    '风险管控措施状态', 'dictionary', 614)
  on conflict do nothing;
  select id into v_type_id from public.sys_dict_type where code = 'smisControlMeasureStatus' limit 1;
  insert into public.sys_dictionary
    (type_id, code, status, create_by, value, label, sort, tag_type)
  values
    (v_type_id, 'draft', '1', '624944977@qq.com', 'draft', '草稿', 1, 'info'),
    (v_type_id, 'active', '1', '624944977@qq.com', 'active', '执行中', 2, 'success'),
    (v_type_id, 'suspended', '1', '624944977@qq.com', 'suspended', '已暂停', 3, 'warning'),
    (v_type_id, 'retired', '1', '624944977@qq.com', 'retired', '已退役', 4, 'info')
  on conflict do nothing;

  insert into public.sys_dict_type (name, code, status, create_by, remark, node_type, sort)
  values ('SMIS LEC可能性', 'smisLecLikelihood', '1', '624944977@qq.com',
    'LEC评估事故发生可能性L', 'dictionary', 615)
  on conflict do nothing;
  select id into v_type_id from public.sys_dict_type where code = 'smisLecLikelihood' limit 1;
  insert into public.sys_dictionary
    (type_id, code, status, create_by, value, label, sort)
  values
    (v_type_id, '10', '1', '624944977@qq.com', '10', '10 · 完全可以预料', 1),
    (v_type_id, '6', '1', '624944977@qq.com', '6', '6 · 相当可能', 2),
    (v_type_id, '3', '1', '624944977@qq.com', '3', '3 · 可能但不经常', 3),
    (v_type_id, '1', '1', '624944977@qq.com', '1', '1 · 可能性小', 4),
    (v_type_id, '0.5', '1', '624944977@qq.com', '0.5', '0.5 · 很不可能', 5),
    (v_type_id, '0.2', '1', '624944977@qq.com', '0.2', '0.2 · 极不可能', 6),
    (v_type_id, '0.1', '1', '624944977@qq.com', '0.1', '0.1 · 实际不可能', 7)
  on conflict do nothing;

  insert into public.sys_dict_type (name, code, status, create_by, remark, node_type, sort)
  values ('SMIS LEC暴露频次', 'smisLecExposure', '1', '624944977@qq.com',
    'LEC评估人员暴露频次E', 'dictionary', 616)
  on conflict do nothing;
  select id into v_type_id from public.sys_dict_type where code = 'smisLecExposure' limit 1;
  insert into public.sys_dictionary
    (type_id, code, status, create_by, value, label, sort)
  values
    (v_type_id, '10', '1', '624944977@qq.com', '10', '10 · 连续暴露', 1),
    (v_type_id, '6', '1', '624944977@qq.com', '6', '6 · 每天暴露', 2),
    (v_type_id, '3', '1', '624944977@qq.com', '3', '3 · 每周一次', 3),
    (v_type_id, '2', '1', '624944977@qq.com', '2', '2 · 每月一次', 4),
    (v_type_id, '1', '1', '624944977@qq.com', '1', '1 · 每年数次', 5),
    (v_type_id, '0.5', '1', '624944977@qq.com', '0.5', '0.5 · 非常罕见', 6)
  on conflict do nothing;

  insert into public.sys_dict_type (name, code, status, create_by, remark, node_type, sort)
  values ('SMIS LEC后果', 'smisLecConsequence', '1', '624944977@qq.com',
    'LEC评估事故后果C', 'dictionary', 617)
  on conflict do nothing;
  select id into v_type_id from public.sys_dict_type where code = 'smisLecConsequence' limit 1;
  insert into public.sys_dictionary
    (type_id, code, status, create_by, value, label, sort)
  values
    (v_type_id, '100', '1', '624944977@qq.com', '100', '100 · 10人以上死亡', 1),
    (v_type_id, '40', '1', '624944977@qq.com', '40', '40 · 3至9人死亡', 2),
    (v_type_id, '15', '1', '624944977@qq.com', '15', '15 · 1至2人死亡', 3),
    (v_type_id, '7', '1', '624944977@qq.com', '7', '7 · 严重伤害', 4),
    (v_type_id, '3', '1', '624944977@qq.com', '3', '3 · 致残伤害', 5),
    (v_type_id, '1', '1', '624944977@qq.com', '1', '1 · 轻微伤害', 6)
  on conflict do nothing;
end;
$$;

;
