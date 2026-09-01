-- Enterprise employee listening and engagement foundation.
-- Privacy boundary: participation is identifiable for delivery, but anonymous
-- responses never persist employee_id, participant_id, create_by or update_by.

create table public.hr_experience_survey (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  survey_code text not null,
  survey_name text not null,
  survey_type text not null,
  cadence text not null default 'one_time',
  audience_type text not null default 'all_active',
  audience_organization_id uuid,
  minimum_group_size integer not null default 5,
  start_date date not null,
  end_date date not null,
  status text not null default 'draft',
  description text,
  launched_at timestamptz,
  closed_at timestamptz,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_experience_survey_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_experience_survey_organization_fkey
    foreign key (tenant_id, audience_organization_id)
    references public.sys_organization(tenant_id, id) on delete restrict,
  constraint hr_experience_survey_id_tenant_unique unique (id, tenant_id),
  constraint hr_experience_survey_code_unique unique (tenant_id, survey_code),
  constraint hr_experience_survey_code_not_blank check (btrim(survey_code) <> ''),
  constraint hr_experience_survey_name_not_blank check (btrim(survey_name) <> ''),
  constraint hr_experience_survey_type_check check (
    survey_type in ('pulse', 'engagement', 'lifecycle', 'wellbeing', 'change', 'ad_hoc')
  ),
  constraint hr_experience_survey_cadence_check check (
    cadence in ('one_time', 'weekly', 'monthly', 'quarterly', 'annual')
  ),
  constraint hr_experience_survey_audience_check check (
    (audience_type = 'all_active' and audience_organization_id is null)
    or (audience_type = 'organization' and audience_organization_id is not null)
  ),
  constraint hr_experience_survey_privacy_threshold_check check (
    minimum_group_size between 5 and 50
  ),
  constraint hr_experience_survey_dates_check check (end_date >= start_date),
  constraint hr_experience_survey_status_check check (
    status in ('draft', 'scheduled', 'open', 'closed', 'cancelled')
  )
);

create index hr_experience_survey_tenant_status_dates_idx
  on public.hr_experience_survey(tenant_id, status, start_date, end_date);
create index hr_experience_survey_organization_fk_idx
  on public.hr_experience_survey(tenant_id, audience_organization_id)
  where audience_organization_id is not null;

create table public.hr_experience_question (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  survey_id uuid not null,
  dimension text not null,
  question_text text not null,
  answer_type text not null default 'rating_5',
  required boolean not null default true,
  enabled boolean not null default true,
  sort integer not null default 0,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_experience_question_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_experience_question_survey_fkey foreign key (survey_id, tenant_id)
    references public.hr_experience_survey(id, tenant_id) on delete cascade,
  constraint hr_experience_question_id_tenant_unique unique (id, tenant_id),
  constraint hr_experience_question_text_not_blank check (btrim(question_text) <> ''),
  constraint hr_experience_question_dimension_check check (
    dimension in ('engagement', 'leadership', 'recognition', 'workload',
      'growth', 'wellbeing', 'inclusion', 'collaboration', 'change', 'other')
  ),
  constraint hr_experience_question_answer_type_check check (
    answer_type in ('rating_5', 'enps_11', 'open_text')
  )
);

create index hr_experience_question_survey_sort_idx
  on public.hr_experience_question(survey_id, tenant_id, enabled, sort);

create table public.hr_experience_participant (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  survey_id uuid not null,
  employee_id uuid not null,
  organization_snapshot_id uuid not null,
  status text not null default 'invited',
  assigned_on date not null default current_date,
  completed_on date,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_experience_participant_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_experience_participant_survey_fkey foreign key (survey_id, tenant_id)
    references public.hr_experience_survey(id, tenant_id) on delete cascade,
  constraint hr_experience_participant_employee_fkey foreign key (employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_experience_participant_organization_fkey
    foreign key (tenant_id, organization_snapshot_id)
    references public.sys_organization(tenant_id, id) on delete restrict,
  constraint hr_experience_participant_unique unique (survey_id, employee_id),
  constraint hr_experience_participant_status_check check (
    status in ('invited', 'completed', 'declined')
  ),
  constraint hr_experience_participant_completion_check check (
    (status = 'completed' and completed_on is not null)
    or (status <> 'completed' and completed_on is null)
  )
);

create index hr_experience_participant_employee_status_idx
  on public.hr_experience_participant(tenant_id, employee_id, status, assigned_on desc);
create index hr_experience_participant_survey_status_idx
  on public.hr_experience_participant(survey_id, tenant_id, status);
create index hr_experience_participant_employee_fk_idx
  on public.hr_experience_participant(employee_id, tenant_id);
create index hr_experience_participant_organization_fk_idx
  on public.hr_experience_participant(tenant_id, organization_snapshot_id);

-- Deliberately excludes employee_id, participant_id and actor audit fields.
create table public.hr_experience_response (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  survey_id uuid not null,
  cohort_organization_id uuid not null,
  submitted_at timestamptz not null default now(),
  constraint hr_experience_response_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_experience_response_survey_fkey foreign key (survey_id, tenant_id)
    references public.hr_experience_survey(id, tenant_id) on delete cascade,
  constraint hr_experience_response_organization_fkey
    foreign key (tenant_id, cohort_organization_id)
    references public.sys_organization(tenant_id, id) on delete restrict,
  constraint hr_experience_response_id_tenant_unique unique (id, tenant_id)
);

create index hr_experience_response_survey_time_idx
  on public.hr_experience_response(survey_id, tenant_id, submitted_at desc);
create index hr_experience_response_cohort_idx
  on public.hr_experience_response(tenant_id, survey_id, cohort_organization_id);

-- Answers inherit anonymity from hr_experience_response and carry no actor columns.
create table public.hr_experience_answer (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  response_id uuid not null,
  question_id uuid not null,
  numeric_score numeric(8,3),
  text_answer text,
  create_time timestamptz not null default now(),
  constraint hr_experience_answer_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_experience_answer_response_fkey foreign key (response_id, tenant_id)
    references public.hr_experience_response(id, tenant_id) on delete cascade,
  constraint hr_experience_answer_question_fkey foreign key (question_id, tenant_id)
    references public.hr_experience_question(id, tenant_id) on delete restrict,
  constraint hr_experience_answer_unique unique (response_id, question_id),
  constraint hr_experience_answer_shape_check check (
    (numeric_score is not null and text_answer is null)
    or (numeric_score is null and nullif(btrim(text_answer), '') is not null)
  ),
  constraint hr_experience_answer_text_length_check check (
    text_answer is null or char_length(text_answer) <= 2000
  )
);

create index hr_experience_answer_response_fk_idx
  on public.hr_experience_answer(response_id, tenant_id);
create index hr_experience_answer_question_fk_idx
  on public.hr_experience_answer(question_id, tenant_id);

create table public.hr_experience_action (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  survey_id uuid not null,
  organization_id uuid,
  dimension text not null,
  title text not null,
  owner_employee_id uuid not null,
  due_date date not null,
  status text not null default 'planned',
  success_measure text not null,
  progress_note text,
  result_summary text,
  started_at timestamptz,
  completed_at timestamptz,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_experience_action_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_experience_action_survey_fkey foreign key (survey_id, tenant_id)
    references public.hr_experience_survey(id, tenant_id) on delete restrict,
  constraint hr_experience_action_organization_fkey
    foreign key (tenant_id, organization_id)
    references public.sys_organization(tenant_id, id) on delete restrict,
  constraint hr_experience_action_owner_fkey foreign key (owner_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_experience_action_id_tenant_unique unique (id, tenant_id),
  constraint hr_experience_action_title_not_blank check (btrim(title) <> ''),
  constraint hr_experience_action_measure_not_blank check (btrim(success_measure) <> ''),
  constraint hr_experience_action_dimension_check check (
    dimension in ('engagement', 'leadership', 'recognition', 'workload',
      'growth', 'wellbeing', 'inclusion', 'collaboration', 'change', 'other')
  ),
  constraint hr_experience_action_status_check check (
    status in ('planned', 'in_progress', 'completed', 'cancelled')
  ),
  constraint hr_experience_action_completion_check check (
    (status = 'completed' and completed_at is not null
      and nullif(btrim(result_summary), '') is not null)
    or status <> 'completed'
  )
);

create index hr_experience_action_survey_status_idx
  on public.hr_experience_action(survey_id, tenant_id, status, due_date);
create index hr_experience_action_owner_fk_idx
  on public.hr_experience_action(owner_employee_id, tenant_id);
create index hr_experience_action_organization_fk_idx
  on public.hr_experience_action(tenant_id, organization_id)
  where organization_id is not null;
create index hr_experience_action_open_due_idx
  on public.hr_experience_action(tenant_id, due_date, owner_employee_id)
  where status in ('planned', 'in_progress');

create table public.hr_experience_event (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  entity_type text not null,
  entity_id uuid not null,
  event_type text not null,
  from_status text,
  to_status text,
  summary text not null,
  payload jsonb not null default '{}'::jsonb,
  actor_user_id uuid,
  actor_name text,
  create_time timestamptz not null default now(),
  constraint hr_experience_event_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_experience_event_actor_fkey foreign key (actor_user_id)
    references public.sys_user(id) on delete set null,
  constraint hr_experience_event_entity_type_check check (
    entity_type in ('survey', 'action')
  ),
  constraint hr_experience_event_type_not_blank check (btrim(event_type) <> ''),
  constraint hr_experience_event_summary_not_blank check (btrim(summary) <> ''),
  constraint hr_experience_event_payload_object check (jsonb_typeof(payload) = 'object')
);

create index hr_experience_event_entity_time_idx
  on public.hr_experience_event(tenant_id, entity_type, entity_id, create_time desc);
create index hr_experience_event_actor_fk_idx
  on public.hr_experience_event(actor_user_id)
  where actor_user_id is not null;

create trigger hr_experience_survey_create_audit
before insert on public.hr_experience_survey for each row
execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_experience_survey_update_audit
before update on public.hr_experience_survey for each row
execute function public.trg_set_update_time_and_by();
create trigger hr_experience_question_create_audit
before insert on public.hr_experience_question for each row
execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_experience_question_update_audit
before update on public.hr_experience_question for each row
execute function public.trg_set_update_time_and_by();
create trigger hr_experience_participant_create_audit
before insert on public.hr_experience_participant for each row
execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_experience_participant_update_audit
before update on public.hr_experience_participant for each row
execute function public.trg_set_update_time_and_by();
create trigger hr_experience_action_create_audit
before insert on public.hr_experience_action for each row
execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_experience_action_update_audit
before update on public.hr_experience_action for each row
execute function public.trg_set_update_time_and_by();

alter table public.hr_experience_survey enable row level security;
alter table public.hr_experience_question enable row level security;
alter table public.hr_experience_participant enable row level security;
alter table public.hr_experience_response enable row level security;
alter table public.hr_experience_answer enable row level security;
alter table public.hr_experience_action enable row level security;
alter table public.hr_experience_event enable row level security;

create policy hr_experience_survey_direct_deny on public.hr_experience_survey
  for all using (false) with check (false);
create policy hr_experience_question_direct_deny on public.hr_experience_question
  for all using (false) with check (false);
create policy hr_experience_participant_direct_deny on public.hr_experience_participant
  for all using (false) with check (false);
create policy hr_experience_response_direct_deny on public.hr_experience_response
  for all using (false) with check (false);
create policy hr_experience_answer_direct_deny on public.hr_experience_answer
  for all using (false) with check (false);
create policy hr_experience_action_direct_deny on public.hr_experience_action
  for all using (false) with check (false);
create policy hr_experience_event_direct_deny on public.hr_experience_event
  for all using (false) with check (false);

revoke all on public.hr_experience_survey, public.hr_experience_question,
  public.hr_experience_participant, public.hr_experience_response,
  public.hr_experience_answer, public.hr_experience_action,
  public.hr_experience_event from public, anon, authenticated;
grant all on public.hr_experience_survey, public.hr_experience_question,
  public.hr_experience_participant, public.hr_experience_response,
  public.hr_experience_answer, public.hr_experience_action,
  public.hr_experience_event to service_role;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), type_seed(type_name, type_code, sort) as (
  values
    ('员工体验调查类型', 'hrExperienceSurveyType', 142),
    ('员工体验调查频率', 'hrExperienceCadence', 143),
    ('员工体验调查状态', 'hrExperienceSurveyStatus', 144),
    ('员工体验题目维度', 'hrExperienceDimension', 145),
    ('员工体验答案类型', 'hrExperienceAnswerType', 146),
    ('员工体验参与状态', 'hrExperienceParticipantStatus', 147),
    ('员工体验行动状态', 'hrExperienceActionStatus', 148),
    ('员工体验受众类型', 'hrExperienceAudienceType', 149)
)
insert into public.sys_dict_type(
  id, name, code, status, remark, tenant_id, create_by, update_by,
  parent_id, node_type, sort
)
select gen_random_uuid(), seed.type_name, seed.type_code, '1',
  '企业 HR 员工体验与敬业度字典', platform_tenant.id,
  '624944977@qq.com', '624944977@qq.com',
  (select id from public.sys_dict_type where code = 'hrManage' limit 1),
  'dictionary', seed.sort
from type_seed seed cross join platform_tenant
on conflict (code) do update set name = excluded.name, status = excluded.status,
  update_by = excluded.update_by, update_time = now(), remark = excluded.remark,
  sort = excluded.sort;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), dictionary_seed(type_code, value, label, sort, tag_type) as (
  values
    ('hrExperienceSurveyType','pulse','脉搏调查',1,'primary'),
    ('hrExperienceSurveyType','engagement','敬业度调查',2,'success'),
    ('hrExperienceSurveyType','lifecycle','员工旅程调查',3,'warning'),
    ('hrExperienceSurveyType','wellbeing','身心健康调查',4,'success'),
    ('hrExperienceSurveyType','change','变革反馈',5,'warning'),
    ('hrExperienceSurveyType','ad_hoc','专题调研',6,'info'),
    ('hrExperienceCadence','one_time','单次',1,'info'),
    ('hrExperienceCadence','weekly','每周',2,'primary'),
    ('hrExperienceCadence','monthly','每月',3,'primary'),
    ('hrExperienceCadence','quarterly','每季度',4,'success'),
    ('hrExperienceCadence','annual','每年',5,'warning'),
    ('hrExperienceSurveyStatus','draft','草稿',1,'info'),
    ('hrExperienceSurveyStatus','scheduled','待开放',2,'warning'),
    ('hrExperienceSurveyStatus','open','收集中',3,'success'),
    ('hrExperienceSurveyStatus','closed','已关闭',4,'primary'),
    ('hrExperienceSurveyStatus','cancelled','已取消',5,'danger'),
    ('hrExperienceDimension','engagement','敬业度',1,'primary'),
    ('hrExperienceDimension','leadership','领导力',2,'warning'),
    ('hrExperienceDimension','recognition','认可激励',3,'success'),
    ('hrExperienceDimension','workload','工作负荷',4,'warning'),
    ('hrExperienceDimension','growth','成长发展',5,'primary'),
    ('hrExperienceDimension','wellbeing','身心健康',6,'success'),
    ('hrExperienceDimension','inclusion','包容归属',7,'primary'),
    ('hrExperienceDimension','collaboration','协作体验',8,'info'),
    ('hrExperienceDimension','change','变革体验',9,'warning'),
    ('hrExperienceDimension','other','其他',10,'info'),
    ('hrExperienceAnswerType','rating_5','五分量表',1,'primary'),
    ('hrExperienceAnswerType','enps_11','eNPS 十一分量表',2,'success'),
    ('hrExperienceAnswerType','open_text','开放文本',3,'warning'),
    ('hrExperienceParticipantStatus','invited','待填写',1,'warning'),
    ('hrExperienceParticipantStatus','completed','已完成',2,'success'),
    ('hrExperienceParticipantStatus','declined','已放弃',3,'info'),
    ('hrExperienceActionStatus','planned','待开始',1,'info'),
    ('hrExperienceActionStatus','in_progress','进行中',2,'warning'),
    ('hrExperienceActionStatus','completed','已完成',3,'success'),
    ('hrExperienceActionStatus','cancelled','已取消',4,'danger'),
    ('hrExperienceAudienceType','all_active','全部在职员工',1,'primary'),
    ('hrExperienceAudienceType','organization','指定组织及下级',2,'success')
)
insert into public.sys_dictionary(
  id, type_id, code, status, create_by, update_by, remark,
  value, label, tenant_id, tag_type, sort
)
select gen_random_uuid(), dictionary_type.id, seed.type_code || '_' || seed.value,
  '1', '624944977@qq.com', '624944977@qq.com',
  '企业 HR 员工体验与敬业度字典项', seed.value, seed.label,
  platform_tenant.id, seed.tag_type, seed.sort
from dictionary_seed seed
join public.sys_dict_type dictionary_type on dictionary_type.code = seed.type_code
cross join platform_tenant
where not exists (
  select 1 from public.sys_dictionary existing
  where existing.type_id = dictionary_type.id and existing.value = seed.value
);

insert into public.sys_menu(
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
) values (
  'c0de0000-0000-4000-8000-000000000209'::uuid,
  'c0de0000-0000-4000-8000-000000000200'::uuid,
  'HrEmployeeExperience', 'employee-experience', '/hr/operations/employee-experience',
  jsonb_build_object('title', '员工体验与敬业度', 'icon', 'ri:survey-line',
    'is_hide', false, 'is_enable', true, 'roles', jsonb_build_array()),
  9, 'menu', 'hr', '624944977@qq.com', '624944977@qq.com'
)
on conflict (id) do update set parent_id = excluded.parent_id, name = excluded.name,
  path = excluded.path, component = excluded.component, meta = excluded.meta,
  sort = excluded.sort, type = excluded.type, app_code = excluded.app_code,
  update_by = excluded.update_by, update_time = now();

insert into public.sys_menu(
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
)
select seed.id, 'c0de0000-0000-4000-8000-000000000209'::uuid, seed.name, '', '',
  jsonb_build_object('title', seed.title, 'icon', '', 'is_hide', true,
    'is_enable', true, 'roles', jsonb_build_array()),
  seed.sort, 'button', 'hr', '624944977@qq.com', '624944977@qq.com'
from (values
  ('c0de0000-0000-4000-8209-000000000001'::uuid, 'Hr:Experience:View', '查看员工体验工作台', 1),
  ('c0de0000-0000-4000-8209-000000000002'::uuid, 'Hr:Experience:Survey:Manage', '管理员工体验调查', 2),
  ('c0de0000-0000-4000-8209-000000000003'::uuid, 'Hr:Experience:Question:Manage', '管理调查题目', 3),
  ('c0de0000-0000-4000-8209-000000000004'::uuid, 'Hr:Experience:Launch', '发布和关闭调查', 4),
  ('c0de0000-0000-4000-8209-000000000005'::uuid, 'Hr:Experience:Respond', '填写员工体验调查', 5),
  ('c0de0000-0000-4000-8209-000000000006'::uuid, 'Hr:Experience:Insights:View', '查看匿名聚合洞察', 6),
  ('c0de0000-0000-4000-8209-000000000007'::uuid, 'Hr:Experience:Comments:View', '查看匿名开放反馈', 7),
  ('c0de0000-0000-4000-8209-000000000008'::uuid, 'Hr:Experience:Action:Manage', '管理员工体验行动', 8),
  ('c0de0000-0000-4000-8209-000000000009'::uuid, 'Hr:Experience:Action:Close', '验收员工体验行动', 9)
) seed(id, name, title, sort)
on conflict (id) do update set parent_id = excluded.parent_id, name = excluded.name,
  meta = excluded.meta, sort = excluded.sort, type = excluded.type,
  app_code = excluded.app_code, update_by = excluded.update_by, update_time = now();

-- Existing HR operations roles receive the page and threshold-protected insights.
insert into public.sys_role_menu(role_id, menu_id, tenant_id, permission, create_by, update_by)
select folder_grant.role_id, target.menu_id, role.tenant_id, '{}'::jsonb,
  '624944977@qq.com', '624944977@qq.com'
from public.sys_role_menu folder_grant
join public.sys_role role on role.id = folder_grant.role_id
cross join (values
  ('c0de0000-0000-4000-8000-000000000209'::uuid),
  ('c0de0000-0000-4000-8209-000000000001'::uuid),
  ('c0de0000-0000-4000-8209-000000000006'::uuid)
) target(menu_id)
where folder_grant.menu_id = 'c0de0000-0000-4000-8000-000000000200'::uuid
on conflict (role_id, menu_id) do nothing;

-- Existing employee-service roles receive only page access and the right to answer.
insert into public.sys_role_menu(role_id, menu_id, tenant_id, permission, create_by, update_by)
select service_grant.role_id, target.menu_id, role.tenant_id, '{}'::jsonb,
  '624944977@qq.com', '624944977@qq.com'
from public.sys_role_menu service_grant
join public.sys_role role on role.id = service_grant.role_id
cross join (values
  ('c0de0000-0000-4000-8000-000000000209'::uuid),
  ('c0de0000-0000-4000-8209-000000000001'::uuid),
  ('c0de0000-0000-4000-8209-000000000005'::uuid)
) target(menu_id)
where service_grant.menu_id = 'c0de0000-0000-4000-8000-000000000203'::uuid
on conflict (role_id, menu_id) do nothing;

;
