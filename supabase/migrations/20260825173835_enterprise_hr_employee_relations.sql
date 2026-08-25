create table public.hr_employee_relation_case (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  case_no text not null,
  case_type text not null,
  title text not null,
  subject_employee_id uuid not null,
  reporter_employee_id uuid,
  anonymous_report boolean not null default false,
  source text not null default 'hr',
  severity text not null default 'medium',
  confidentiality_level text not null default 'restricted',
  status text not null default 'draft',
  owner_employee_id uuid,
  reported_at timestamptz,
  target_resolution_date date,
  triaged_at timestamptz,
  investigation_started_at timestamptz,
  resolved_at timestamptz,
  closed_at timestamptz,
  allegation_summary text not null,
  findings_summary text,
  outcome text,
  resolution_summary text,
  attachment_urls jsonb not null default '[]'::jsonb,
  external_reference text,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_employee_relation_case_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_employee_relation_case_id_tenant_unique unique (id, tenant_id),
  constraint hr_employee_relation_case_no_unique unique (tenant_id, case_no),
  constraint hr_employee_relation_case_subject_fkey
    foreign key (subject_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_employee_relation_case_reporter_fkey
    foreign key (reporter_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_employee_relation_case_owner_fkey
    foreign key (owner_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_employee_relation_case_no_not_blank
    check (nullif(btrim(case_no), '') is not null),
  constraint hr_employee_relation_case_title_not_blank
    check (nullif(btrim(title), '') is not null),
  constraint hr_employee_relation_case_allegation_not_blank
    check (nullif(btrim(allegation_summary), '') is not null),
  constraint hr_employee_relation_case_type_check check (
    case_type in ('grievance', 'misconduct', 'harassment', 'workplace_conflict',
      'accommodation', 'policy_violation', 'other')
  ),
  constraint hr_employee_relation_case_source_check check (
    source in ('employee_report', 'manager_report', 'hr', 'hotline', 'service_escalation', 'audit')
  ),
  constraint hr_employee_relation_case_severity_check check (
    severity in ('low', 'medium', 'high', 'critical')
  ),
  constraint hr_employee_relation_case_confidentiality_check check (
    confidentiality_level in ('standard', 'restricted', 'highly_restricted')
  ),
  constraint hr_employee_relation_case_status_check check (
    status in ('draft', 'reported', 'triaged', 'investigating', 'action_required',
      'resolved', 'closed', 'cancelled')
  ),
  constraint hr_employee_relation_case_outcome_check check (
    outcome is null or outcome in ('substantiated', 'unsubstantiated', 'inconclusive',
      'resolved_informally', 'withdrawn')
  ),
  constraint hr_employee_relation_case_anonymous_reporter_check check (
    not anonymous_report or reporter_employee_id is null
  ),
  constraint hr_employee_relation_case_attachment_urls_check check (
    jsonb_typeof(attachment_urls) = 'array'
  ),
  constraint hr_employee_relation_case_triage_check check (
    status in ('draft', 'reported', 'cancelled')
    or (owner_employee_id is not null and target_resolution_date is not null and triaged_at is not null)
  ),
  constraint hr_employee_relation_case_investigation_check check (
    status not in ('investigating', 'action_required', 'resolved', 'closed')
    or investigation_started_at is not null
  ),
  constraint hr_employee_relation_case_resolution_check check (
    status not in ('resolved', 'closed')
    or (outcome is not null and nullif(btrim(resolution_summary), '') is not null
      and resolved_at is not null)
  ),
  constraint hr_employee_relation_case_closed_check check (
    status <> 'closed' or closed_at is not null
  )
);

create table public.hr_employee_relation_action (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  case_id uuid not null,
  action_type text not null,
  title text not null,
  owner_employee_id uuid not null,
  due_date date not null,
  status text not null default 'planned',
  started_at timestamptz,
  completed_at timestamptz,
  completion_note text,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_employee_relation_action_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_employee_relation_action_id_tenant_unique unique (id, tenant_id),
  constraint hr_employee_relation_action_case_fkey foreign key (case_id, tenant_id)
    references public.hr_employee_relation_case(id, tenant_id) on delete cascade,
  constraint hr_employee_relation_action_owner_fkey foreign key (owner_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_employee_relation_action_title_not_blank
    check (nullif(btrim(title), '') is not null),
  constraint hr_employee_relation_action_type_check check (
    action_type in ('coaching', 'mediation', 'written_warning', 'investigation_follow_up',
      'policy_remediation', 'accommodation', 'disciplinary_recommendation', 'no_action')
  ),
  constraint hr_employee_relation_action_status_check check (
    status in ('planned', 'in_progress', 'completed', 'cancelled')
  ),
  constraint hr_employee_relation_action_started_check check (
    status not in ('in_progress', 'completed') or started_at is not null
  ),
  constraint hr_employee_relation_action_completed_check check (
    status <> 'completed'
    or (completed_at is not null and nullif(btrim(completion_note), '') is not null)
  )
);

create table public.hr_employee_relation_event (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  case_id uuid not null,
  event_type text not null,
  from_status text,
  to_status text,
  actor_employee_id uuid,
  comment text,
  event_data jsonb not null default '{}'::jsonb,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_employee_relation_event_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_employee_relation_event_case_fkey foreign key (case_id, tenant_id)
    references public.hr_employee_relation_case(id, tenant_id) on delete cascade,
  constraint hr_employee_relation_event_actor_fkey foreign key (actor_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint hr_employee_relation_event_type_check check (
    event_type in ('created', 'updated', 'reported', 'assigned', 'triaged',
      'investigation_started', 'action_required', 'resolved', 'closed', 'reopened',
      'cancelled', 'commented', 'action_created', 'action_updated', 'action_started',
      'action_completed', 'action_cancelled')
  )
);

create index hr_employee_relation_case_subject_fk_idx
  on public.hr_employee_relation_case(subject_employee_id, tenant_id);
create index hr_employee_relation_case_reporter_fk_idx
  on public.hr_employee_relation_case(reporter_employee_id, tenant_id)
  where reporter_employee_id is not null;
create index hr_employee_relation_case_owner_fk_idx
  on public.hr_employee_relation_case(owner_employee_id, tenant_id)
  where owner_employee_id is not null;
create index hr_employee_relation_case_queue_idx
  on public.hr_employee_relation_case(tenant_id, status, severity, update_time desc);
create index hr_employee_relation_case_due_idx
  on public.hr_employee_relation_case(tenant_id, target_resolution_date, severity)
  where status in ('reported', 'triaged', 'investigating', 'action_required');
create index hr_employee_relation_action_case_fk_idx
  on public.hr_employee_relation_action(case_id, tenant_id);
create index hr_employee_relation_action_owner_fk_idx
  on public.hr_employee_relation_action(owner_employee_id, tenant_id);
create index hr_employee_relation_action_due_idx
  on public.hr_employee_relation_action(tenant_id, due_date, status)
  where status in ('planned', 'in_progress');
create index hr_employee_relation_event_case_idx
  on public.hr_employee_relation_event(tenant_id, case_id, create_time desc);
create index hr_employee_relation_event_actor_fk_idx
  on public.hr_employee_relation_event(actor_employee_id, tenant_id)
  where actor_employee_id is not null;

create trigger hr_employee_relation_case_create_audit
before insert on public.hr_employee_relation_case for each row
execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_employee_relation_case_update_audit
before update on public.hr_employee_relation_case for each row
execute function public.trg_set_update_time_and_by();
create trigger hr_employee_relation_action_create_audit
before insert on public.hr_employee_relation_action for each row
execute function public.trg_set_create_time_and_by('true', 'true');
create trigger hr_employee_relation_action_update_audit
before update on public.hr_employee_relation_action for each row
execute function public.trg_set_update_time_and_by();
create trigger hr_employee_relation_event_create_audit
before insert on public.hr_employee_relation_event for each row
execute function public.trg_set_create_time_and_by('true', 'true');

alter table public.hr_employee_relation_case enable row level security;
alter table public.hr_employee_relation_action enable row level security;
alter table public.hr_employee_relation_event enable row level security;
create policy hr_employee_relation_case_deny_direct_access
  on public.hr_employee_relation_case for all to authenticated using (false) with check (false);
create policy hr_employee_relation_action_deny_direct_access
  on public.hr_employee_relation_action for all to authenticated using (false) with check (false);
create policy hr_employee_relation_event_deny_direct_access
  on public.hr_employee_relation_event for all to authenticated using (false) with check (false);

revoke all on table public.hr_employee_relation_case from public, anon, authenticated;
revoke all on table public.hr_employee_relation_action from public, anon, authenticated;
revoke all on table public.hr_employee_relation_event from public, anon, authenticated;
grant all on table public.hr_employee_relation_case to service_role;
grant all on table public.hr_employee_relation_action to service_role;
grant all on table public.hr_employee_relation_event to service_role;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), types(name, code, sort) as (values
  ('员工关系案件类型', 'hrEmployeeRelationCaseType', 123),
  ('员工关系案件状态', 'hrEmployeeRelationCaseStatus', 124),
  ('员工关系严重程度', 'hrEmployeeRelationSeverity', 125),
  ('员工关系保密等级', 'hrEmployeeRelationConfidentiality', 126),
  ('员工关系报告来源', 'hrEmployeeRelationSource', 127),
  ('员工关系案件结论', 'hrEmployeeRelationOutcome', 128),
  ('员工关系处置类型', 'hrEmployeeRelationActionType', 129),
  ('员工关系处置状态', 'hrEmployeeRelationActionStatus', 130),
  ('员工关系审计事件', 'hrEmployeeRelationEventType', 131)
)
insert into public.sys_dict_type(
  id, name, code, status, create_by, update_by, remark, tenant_id, parent_id, node_type, sort
)
select gen_random_uuid(), types.name, types.code, '1', '624944977@qq.com', '624944977@qq.com',
  '企业 HR 员工关系案件字典', platform_tenant.id,
  (select id from public.sys_dict_type where code = 'hrManage' limit 1),
  'dictionary', types.sort
from types cross join platform_tenant
on conflict (code) do update set name = excluded.name, status = excluded.status,
  update_by = excluded.update_by, update_time = now(), remark = excluded.remark,
  sort = excluded.sort;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), items(type_code, value, label, sort, tag_type) as (values
  ('hrEmployeeRelationCaseType','grievance','员工申诉',1,'warning'),
  ('hrEmployeeRelationCaseType','misconduct','不当行为',2,'danger'),
  ('hrEmployeeRelationCaseType','harassment','骚扰举报',3,'danger'),
  ('hrEmployeeRelationCaseType','workplace_conflict','职场冲突',4,'warning'),
  ('hrEmployeeRelationCaseType','accommodation','合理便利',5,'success'),
  ('hrEmployeeRelationCaseType','policy_violation','制度违规',6,'danger'),
  ('hrEmployeeRelationCaseType','other','其他案件',7,'info'),
  ('hrEmployeeRelationCaseStatus','draft','草稿',1,'info'),
  ('hrEmployeeRelationCaseStatus','reported','待受理',2,'warning'),
  ('hrEmployeeRelationCaseStatus','triaged','已分级',3,'primary'),
  ('hrEmployeeRelationCaseStatus','investigating','调查中',4,'primary'),
  ('hrEmployeeRelationCaseStatus','action_required','待完成处置',5,'warning'),
  ('hrEmployeeRelationCaseStatus','resolved','已解决',6,'success'),
  ('hrEmployeeRelationCaseStatus','closed','已结案',7,'info'),
  ('hrEmployeeRelationCaseStatus','cancelled','已取消',8,'info'),
  ('hrEmployeeRelationSeverity','low','低',1,'info'),
  ('hrEmployeeRelationSeverity','medium','中',2,'primary'),
  ('hrEmployeeRelationSeverity','high','高',3,'warning'),
  ('hrEmployeeRelationSeverity','critical','紧急',4,'danger'),
  ('hrEmployeeRelationConfidentiality','standard','标准',1,'info'),
  ('hrEmployeeRelationConfidentiality','restricted','受限',2,'warning'),
  ('hrEmployeeRelationConfidentiality','highly_restricted','高度保密',3,'danger'),
  ('hrEmployeeRelationSource','employee_report','员工报告',1,'primary'),
  ('hrEmployeeRelationSource','manager_report','管理者报告',2,'primary'),
  ('hrEmployeeRelationSource','hr','HR 发现',3,'success'),
  ('hrEmployeeRelationSource','hotline','合规热线',4,'warning'),
  ('hrEmployeeRelationSource','service_escalation','服务工单升级',5,'warning'),
  ('hrEmployeeRelationSource','audit','审计发现',6,'danger'),
  ('hrEmployeeRelationOutcome','substantiated','事实成立',1,'danger'),
  ('hrEmployeeRelationOutcome','unsubstantiated','事实不成立',2,'success'),
  ('hrEmployeeRelationOutcome','inconclusive','证据不足',3,'warning'),
  ('hrEmployeeRelationOutcome','resolved_informally','非正式解决',4,'primary'),
  ('hrEmployeeRelationOutcome','withdrawn','已撤回',5,'info'),
  ('hrEmployeeRelationActionType','coaching','辅导沟通',1,'primary'),
  ('hrEmployeeRelationActionType','mediation','调解',2,'success'),
  ('hrEmployeeRelationActionType','written_warning','书面警示',3,'warning'),
  ('hrEmployeeRelationActionType','investigation_follow_up','调查跟进',4,'primary'),
  ('hrEmployeeRelationActionType','policy_remediation','制度整改',5,'warning'),
  ('hrEmployeeRelationActionType','accommodation','合理便利',6,'success'),
  ('hrEmployeeRelationActionType','disciplinary_recommendation','纪律处分建议',7,'danger'),
  ('hrEmployeeRelationActionType','no_action','无需行动',8,'info'),
  ('hrEmployeeRelationActionStatus','planned','待开始',1,'info'),
  ('hrEmployeeRelationActionStatus','in_progress','进行中',2,'primary'),
  ('hrEmployeeRelationActionStatus','completed','已完成',3,'success'),
  ('hrEmployeeRelationActionStatus','cancelled','已取消',4,'info'),
  ('hrEmployeeRelationEventType','created','创建案件',1,'info'),
  ('hrEmployeeRelationEventType','updated','更新资料',2,'primary'),
  ('hrEmployeeRelationEventType','reported','提交报告',3,'warning'),
  ('hrEmployeeRelationEventType','assigned','分派负责人',4,'primary'),
  ('hrEmployeeRelationEventType','triaged','完成分级',5,'primary'),
  ('hrEmployeeRelationEventType','investigation_started','启动调查',6,'primary'),
  ('hrEmployeeRelationEventType','action_required','进入处置阶段',7,'warning'),
  ('hrEmployeeRelationEventType','resolved','案件解决',8,'success'),
  ('hrEmployeeRelationEventType','closed','案件结案',9,'info'),
  ('hrEmployeeRelationEventType','reopened','重新调查',10,'warning'),
  ('hrEmployeeRelationEventType','cancelled','取消案件',11,'info'),
  ('hrEmployeeRelationEventType','commented','补充说明',12,'info'),
  ('hrEmployeeRelationEventType','action_created','创建处置行动',13,'primary'),
  ('hrEmployeeRelationEventType','action_updated','更新处置行动',14,'primary'),
  ('hrEmployeeRelationEventType','action_started','启动处置行动',15,'primary'),
  ('hrEmployeeRelationEventType','action_completed','完成处置行动',16,'success'),
  ('hrEmployeeRelationEventType','action_cancelled','取消处置行动',17,'info')
)
insert into public.sys_dictionary(
  id, type_id, code, status, create_by, update_by, remark,
  value, label, tenant_id, tag_type, sort
)
select gen_random_uuid(), dictionary_type.id, items.type_code || '_' || items.value,
  '1', '624944977@qq.com', '624944977@qq.com', '企业 HR 员工关系案件字典项',
  items.value, items.label, platform_tenant.id, items.tag_type, items.sort
from items
join public.sys_dict_type dictionary_type on dictionary_type.code = items.type_code
cross join platform_tenant
where not exists (
  select 1 from public.sys_dictionary existing
  where existing.type_id = dictionary_type.id and existing.value = items.value
);

insert into public.sys_menu(
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
) values (
  'c0de0000-0000-4000-8000-000000000207'::uuid,
  'c0de0000-0000-4000-8000-000000000200'::uuid,
  'HrEmployeeRelations', 'employee-relations', '/hr/operations/employee-relations',
  jsonb_build_object('title', '员工关系案件', 'icon', 'ri:team-line',
    'is_hide', false, 'is_enable', true, 'roles', jsonb_build_array()),
  7, 'menu', 'hr', '624944977@qq.com', '624944977@qq.com'
)
on conflict (id) do update set parent_id = excluded.parent_id, name = excluded.name,
  path = excluded.path, component = excluded.component, meta = excluded.meta,
  sort = excluded.sort, type = excluded.type, app_code = excluded.app_code,
  update_by = excluded.update_by, update_time = now();

insert into public.sys_menu(
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
)
select seed.id, 'c0de0000-0000-4000-8000-000000000207'::uuid, seed.name, '', '',
  jsonb_build_object('title', seed.title, 'icon', '', 'is_hide', true,
    'is_enable', true, 'roles', jsonb_build_array()),
  seed.sort, 'button', 'hr', '624944977@qq.com', '624944977@qq.com'
from (values
  ('c0de0000-0000-4000-8207-000000000001'::uuid, 'Hr:EmployeeRelations:View', '查看员工关系案件', 1),
  ('c0de0000-0000-4000-8207-000000000002'::uuid, 'Hr:EmployeeRelations:Add', '新建员工关系案件', 2),
  ('c0de0000-0000-4000-8207-000000000003'::uuid, 'Hr:EmployeeRelations:Edit', '编辑员工关系案件', 3),
  ('c0de0000-0000-4000-8207-000000000004'::uuid, 'Hr:EmployeeRelations:Delete', '删除案件草稿', 4),
  ('c0de0000-0000-4000-8207-000000000005'::uuid, 'Hr:EmployeeRelations:Assign', '分派与分级案件', 5),
  ('c0de0000-0000-4000-8207-000000000006'::uuid, 'Hr:EmployeeRelations:Investigate', '调查员工关系案件', 6),
  ('c0de0000-0000-4000-8207-000000000007'::uuid, 'Hr:EmployeeRelations:Resolve', '解决员工关系案件', 7),
  ('c0de0000-0000-4000-8207-000000000008'::uuid, 'Hr:EmployeeRelations:Close', '结案或重新调查', 8),
  ('c0de0000-0000-4000-8207-000000000009'::uuid, 'Hr:EmployeeRelations:Action:Manage', '管理员工关系处置行动', 9),
  ('c0de0000-0000-4000-8207-000000000010'::uuid, 'Hr:EmployeeRelations:Sensitive:View', '查看员工关系敏感内容', 10)
) seed(id, name, title, sort)
on conflict (id) do update set parent_id = excluded.parent_id, name = excluded.name,
  meta = excluded.meta, sort = excluded.sort, type = excluded.type,
  app_code = excluded.app_code, update_by = excluded.update_by, update_time = now();

insert into public.sys_role_menu(role_id, menu_id, tenant_id, permission, create_by, update_by)
select folder_grant.role_id, target.menu_id, role.tenant_id, '{}'::jsonb,
  '624944977@qq.com', '624944977@qq.com'
from public.sys_role_menu folder_grant
join public.sys_role role on role.id = folder_grant.role_id
cross join (values
  ('c0de0000-0000-4000-8000-000000000207'::uuid),
  ('c0de0000-0000-4000-8207-000000000001'::uuid)
) target(menu_id)
where folder_grant.menu_id = 'c0de0000-0000-4000-8000-000000000200'::uuid
on conflict (role_id, menu_id) do nothing;
