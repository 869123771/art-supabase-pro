-- Complete the risk-control lifecycle from the evaluated risk list through
-- hierarchical control assignments and automatically generated inspection tasks.

create table public.smis_risk_control_plan (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
    references public.sys_tenant(id) on delete restrict,
  risk_point_id uuid not null,
  control_start_at timestamptz not null default now(),
  status text not null default 'active',
  control_description text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_risk_control_plan_point_fk
    foreign key (tenant_id, risk_point_id)
    references public.smis_risk_point(tenant_id, id) on delete restrict,
  constraint smis_risk_control_plan_point_unique unique (tenant_id, risk_point_id),
  constraint smis_risk_control_plan_tenant_id_id_key unique (tenant_id, id),
  constraint smis_risk_control_plan_status_check check (status in ('active', 'suspended')),
  constraint smis_risk_control_plan_description_check
    check (control_description is null or char_length(control_description) <= 2000)
);

alter table public.smis_duplicate_configuration
  add constraint smis_duplicate_configuration_tenant_id_id_key unique (tenant_id, id);

create table public.smis_risk_control_assignment (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
    references public.sys_tenant(id) on delete restrict,
  plan_id uuid not null,
  control_level text not null,
  responsible_employee_id uuid not null,
  duplicate_configuration_id uuid not null,
  control_measure text,
  status text not null default 'active',
  sort integer not null default 0,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_risk_control_assignment_plan_fk
    foreign key (tenant_id, plan_id)
    references public.smis_risk_control_plan(tenant_id, id) on delete cascade,
  constraint smis_risk_control_assignment_employee_fk
    foreign key (responsible_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint smis_risk_control_assignment_duplicate_fk
    foreign key (tenant_id, duplicate_configuration_id)
    references public.smis_duplicate_configuration(tenant_id, id) on delete restrict,
  constraint smis_risk_control_assignment_level_unique unique (tenant_id, plan_id, control_level),
  constraint smis_risk_control_assignment_tenant_id_id_key unique (tenant_id, id),
  constraint smis_risk_control_assignment_level_check
    check (control_level in ('company', 'department', 'team', 'position')),
  constraint smis_risk_control_assignment_status_check
    check (status in ('active', 'inactive')),
  constraint smis_risk_control_assignment_sort_check check (sort between 0 and 9999),
  constraint smis_risk_control_assignment_measure_check
    check (control_measure is null or char_length(control_measure) <= 2000)
);

create table public.smis_risk_inspection_task (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
    references public.sys_tenant(id) on delete restrict,
  assignment_id uuid not null,
  risk_point_id uuid not null,
  task_no text not null,
  responsible_employee_id uuid not null,
  assignee_employee_id uuid not null,
  actual_executor_employee_id uuid,
  planned_start_at timestamptz not null,
  planned_end_at timestamptz not null,
  actual_start_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  status text not null default 'not_started',
  transfer_reason text,
  cancellation_reason text,
  execution_summary text,
  attachment_urls jsonb not null default '[]'::jsonb,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_risk_inspection_task_assignment_fk
    foreign key (tenant_id, assignment_id)
    references public.smis_risk_control_assignment(tenant_id, id) on delete restrict,
  constraint smis_risk_inspection_task_point_fk
    foreign key (tenant_id, risk_point_id)
    references public.smis_risk_point(tenant_id, id) on delete restrict,
  constraint smis_risk_inspection_task_responsible_fk
    foreign key (responsible_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint smis_risk_inspection_task_assignee_fk
    foreign key (assignee_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint smis_risk_inspection_task_executor_fk
    foreign key (actual_executor_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint smis_risk_inspection_task_no_unique unique (tenant_id, task_no),
  constraint smis_risk_inspection_task_window_unique
    unique (tenant_id, assignment_id, planned_start_at),
  constraint smis_risk_inspection_task_tenant_id_id_key unique (tenant_id, id),
  constraint smis_risk_inspection_task_window_check check (planned_end_at > planned_start_at),
  constraint smis_risk_inspection_task_status_check
    check (status in ('not_started', 'in_progress', 'completed', 'overdue', 'cancelled')),
  constraint smis_risk_inspection_task_attachment_check check (jsonb_typeof(attachment_urls) = 'array')
);

create table public.smis_risk_inspection_task_item (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
    references public.sys_tenant(id) on delete restrict,
  task_id uuid not null,
  risk_item_id uuid,
  control_measure_id uuid,
  inspection_content text not null,
  result text not null default 'pending',
  remark text,
  attachment_urls jsonb not null default '[]'::jsonb,
  sort integer not null default 0,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_risk_inspection_task_item_task_fk
    foreign key (tenant_id, task_id)
    references public.smis_risk_inspection_task(tenant_id, id) on delete cascade,
  constraint smis_risk_inspection_task_item_risk_item_fk
    foreign key (tenant_id, risk_item_id)
    references public.smis_risk_item(tenant_id, id) on delete set null (risk_item_id),
  constraint smis_risk_inspection_task_item_measure_fk
    foreign key (tenant_id, control_measure_id)
    references public.smis_risk_control_measure(tenant_id, id) on delete set null (control_measure_id),
  constraint smis_risk_inspection_task_item_result_check
    check (result in ('pending', 'normal', 'abnormal')),
  constraint smis_risk_inspection_task_item_content_check
    check (char_length(btrim(inspection_content)) between 1 and 2000),
  constraint smis_risk_inspection_task_item_attachment_check
    check (jsonb_typeof(attachment_urls) = 'array')
);

create table public.smis_risk_inspection_task_event (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
    references public.sys_tenant(id) on delete restrict,
  task_id uuid not null,
  event_type text not null,
  event_content text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_risk_inspection_task_event_task_fk
    foreign key (tenant_id, task_id)
    references public.smis_risk_inspection_task(tenant_id, id) on delete cascade,
  constraint smis_risk_inspection_task_event_type_check
    check (event_type in ('generated', 'transferred', 'progress_saved', 'completed', 'cancelled'))
);

create table app_private.smis_risk_inspection_task_counter (
  tenant_id uuid not null references public.sys_tenant(id) on delete cascade,
  month_key date not null,
  last_value integer not null default 0,
  primary key (tenant_id, month_key),
  constraint smis_risk_inspection_task_counter_value_check check (last_value between 0 and 9999)
);

alter table public.smis_risk_control_plan enable row level security;
alter table public.smis_risk_control_assignment enable row level security;
alter table public.smis_risk_inspection_task enable row level security;
alter table public.smis_risk_inspection_task_item enable row level security;
alter table public.smis_risk_inspection_task_event enable row level security;

create index smis_risk_control_plan_tenant_status_idx
  on public.smis_risk_control_plan(tenant_id, status, control_start_at);
create index smis_risk_control_assignment_tenant_plan_idx
  on public.smis_risk_control_assignment(tenant_id, plan_id, sort);
create index smis_risk_control_assignment_employee_idx
  on public.smis_risk_control_assignment(tenant_id, responsible_employee_id);
create index smis_risk_control_assignment_duplicate_idx
  on public.smis_risk_control_assignment(tenant_id, duplicate_configuration_id);
create index smis_risk_inspection_task_tenant_status_start_idx
  on public.smis_risk_inspection_task(tenant_id, status, planned_start_at desc);
create index smis_risk_inspection_task_tenant_point_idx
  on public.smis_risk_inspection_task(tenant_id, risk_point_id, planned_start_at desc);
create index smis_risk_inspection_task_assignee_idx
  on public.smis_risk_inspection_task(tenant_id, assignee_employee_id, status);
create index smis_risk_inspection_task_responsible_idx
  on public.smis_risk_inspection_task(tenant_id, responsible_employee_id, status);
create index smis_risk_inspection_task_item_task_idx
  on public.smis_risk_inspection_task_item(tenant_id, task_id, sort);
create index smis_risk_inspection_task_event_task_idx
  on public.smis_risk_inspection_task_event(tenant_id, task_id, create_time);

create trigger smis_risk_control_plan_create_audit
before insert on public.smis_risk_control_plan for each row
execute function public.trg_set_create_time_and_by('true', 'true');
create trigger smis_risk_control_plan_update_audit
before update on public.smis_risk_control_plan for each row
execute function public.trg_set_update_time_and_by();
create trigger smis_risk_control_assignment_create_audit
before insert on public.smis_risk_control_assignment for each row
execute function public.trg_set_create_time_and_by('true', 'true');
create trigger smis_risk_control_assignment_update_audit
before update on public.smis_risk_control_assignment for each row
execute function public.trg_set_update_time_and_by();
create trigger smis_risk_inspection_task_create_audit
before insert on public.smis_risk_inspection_task for each row
execute function public.trg_set_create_time_and_by('true', 'true');
create trigger smis_risk_inspection_task_update_audit
before update on public.smis_risk_inspection_task for each row
execute function public.trg_set_update_time_and_by();
create trigger smis_risk_inspection_task_item_create_audit
before insert on public.smis_risk_inspection_task_item for each row
execute function public.trg_set_create_time_and_by('true', 'true');
create trigger smis_risk_inspection_task_item_update_audit
before update on public.smis_risk_inspection_task_item for each row
execute function public.trg_set_update_time_and_by();
create trigger smis_risk_inspection_task_event_create_audit
before insert on public.smis_risk_inspection_task_event for each row
execute function public.trg_set_create_time_and_by('true', 'true');
create trigger smis_risk_inspection_task_event_update_audit
before update on public.smis_risk_inspection_task_event for each row
execute function public.trg_set_update_time_and_by();

create policy smis_risk_control_plan_select on public.smis_risk_control_plan
for select to authenticated using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (
      (select app_private.has_permission('SmisDualControlRiskClassificationControl:View'))
      or (select app_private.has_permission('SmisDualControlSafetyRiskList:View'))
      or (select app_private.has_permission('SmisDualControlRiskListSummary:View'))
      or (select app_private.has_permission('SmisDualControlRiskInspectionTask:View'))
    )
  )
);
create policy smis_risk_control_plan_insert on public.smis_risk_control_plan
for insert to authenticated with check (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisDualControlRiskClassificationControl:Add'))
  )
);
create policy smis_risk_control_plan_update on public.smis_risk_control_plan
for update to authenticated using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (
      (select app_private.has_permission('SmisDualControlRiskClassificationControl:Edit'))
      or (select app_private.has_permission('SmisDualControlRiskClassificationControl:Configure'))
    )
  )
) with check (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (
      (select app_private.has_permission('SmisDualControlRiskClassificationControl:Edit'))
      or (select app_private.has_permission('SmisDualControlRiskClassificationControl:Configure'))
    )
  )
);
create policy smis_risk_control_plan_delete on public.smis_risk_control_plan
for delete to authenticated using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisDualControlRiskClassificationControl:Delete'))
  )
);

create policy smis_risk_control_assignment_select on public.smis_risk_control_assignment
for select to authenticated using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (
      (select app_private.has_permission('SmisDualControlRiskClassificationControl:View'))
      or (select app_private.has_permission('SmisDualControlSafetyRiskList:View'))
      or (select app_private.has_permission('SmisDualControlRiskListSummary:View'))
      or (select app_private.has_permission('SmisDualControlRiskInspectionTask:View'))
    )
  )
);
create policy smis_risk_control_assignment_insert on public.smis_risk_control_assignment
for insert to authenticated with check (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (
      (select app_private.has_permission('SmisDualControlRiskClassificationControl:Add'))
      or (select app_private.has_permission('SmisDualControlRiskClassificationControl:Configure'))
    )
  )
);
create policy smis_risk_control_assignment_update on public.smis_risk_control_assignment
for update to authenticated using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (
      (select app_private.has_permission('SmisDualControlRiskClassificationControl:Edit'))
      or (select app_private.has_permission('SmisDualControlRiskClassificationControl:Configure'))
    )
  )
) with check (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (
      (select app_private.has_permission('SmisDualControlRiskClassificationControl:Edit'))
      or (select app_private.has_permission('SmisDualControlRiskClassificationControl:Configure'))
    )
  )
);
create policy smis_risk_control_assignment_delete on public.smis_risk_control_assignment
for delete to authenticated using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (
      (select app_private.has_permission('SmisDualControlRiskClassificationControl:Delete'))
      or (select app_private.has_permission('SmisDualControlRiskClassificationControl:Configure'))
    )
  )
);

create policy smis_risk_inspection_task_select on public.smis_risk_inspection_task
for select to authenticated using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisDualControlRiskInspectionTask:View'))
  )
);
create policy smis_risk_inspection_task_insert on public.smis_risk_inspection_task
for insert to authenticated with check (false);
create policy smis_risk_inspection_task_update on public.smis_risk_inspection_task
for update to authenticated using (false) with check (false);
create policy smis_risk_inspection_task_delete on public.smis_risk_inspection_task
for delete to authenticated using (false);

create policy smis_risk_inspection_task_item_select on public.smis_risk_inspection_task_item
for select to authenticated using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisDualControlRiskInspectionTask:View'))
  )
);
create policy smis_risk_inspection_task_item_insert on public.smis_risk_inspection_task_item
for insert to authenticated with check (false);
create policy smis_risk_inspection_task_item_update on public.smis_risk_inspection_task_item
for update to authenticated using (false) with check (false);
create policy smis_risk_inspection_task_item_delete on public.smis_risk_inspection_task_item
for delete to authenticated using (false);

create policy smis_risk_inspection_task_event_select on public.smis_risk_inspection_task_event
for select to authenticated using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisDualControlRiskInspectionTask:View'))
  )
);
create policy smis_risk_inspection_task_event_insert on public.smis_risk_inspection_task_event
for insert to authenticated with check (false);
create policy smis_risk_inspection_task_event_update on public.smis_risk_inspection_task_event
for update to authenticated using (false) with check (false);
create policy smis_risk_inspection_task_event_delete on public.smis_risk_inspection_task_event
for delete to authenticated using (false);

revoke all on public.smis_risk_control_plan from anon;
revoke all on public.smis_risk_control_assignment from anon;
revoke all on public.smis_risk_inspection_task from anon;
revoke all on public.smis_risk_inspection_task_item from anon;
revoke all on public.smis_risk_inspection_task_event from anon;
grant select on public.smis_risk_control_plan to authenticated;
grant select on public.smis_risk_control_assignment to authenticated;
grant select on public.smis_risk_inspection_task to authenticated;
grant select on public.smis_risk_inspection_task_item to authenticated;
grant select on public.smis_risk_inspection_task_event to authenticated;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), definitions(code, name, remark, sort) as (
  values
    ('smisRiskControlLevel', '风险管控层级', '风险分级管控责任层级', 537),
    ('smisRiskControlStatus', '风险管控状态', '风险点管控配置状态', 538),
    ('smisRiskInspectionTaskStatus', '风险巡查任务状态', '风险巡查任务生命周期', 539),
    ('smisRiskInspectionResult', '风险巡查结果', '风险巡查任务项目结果', 540)
)
insert into public.sys_dict_type(
  id, name, code, status, create_by, update_by, remark, tenant_id, node_type, sort
)
select gen_random_uuid(), definition.name, definition.code, '1',
  '624944977@qq.com', '624944977@qq.com', definition.remark,
  platform_tenant.id, 'dictionary', definition.sort
from definitions definition cross join platform_tenant
where not exists (
  select 1 from public.sys_dict_type existing
  where existing.tenant_id = platform_tenant.id and existing.code = definition.code
);

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), definitions(type_code, value, label, tag_type, sort) as (
  values
    ('smisRiskControlLevel', 'company', '公司级（厂级）', 'danger', 1),
    ('smisRiskControlLevel', 'department', '车间（部门级）', 'warning', 2),
    ('smisRiskControlLevel', 'team', '班组级', 'primary', 3),
    ('smisRiskControlLevel', 'position', '岗位级', 'success', 4),
    ('smisRiskControlStatus', 'uncontrolled', '未管控', 'info', 1),
    ('smisRiskControlStatus', 'active', '管控中', 'success', 2),
    ('smisRiskControlStatus', 'suspended', '已停用', 'warning', 3),
    ('smisRiskInspectionTaskStatus', 'not_started', '未开始', 'info', 1),
    ('smisRiskInspectionTaskStatus', 'in_progress', '进行中', 'primary', 2),
    ('smisRiskInspectionTaskStatus', 'completed', '已完成', 'success', 3),
    ('smisRiskInspectionTaskStatus', 'overdue', '已过期', 'danger', 4),
    ('smisRiskInspectionTaskStatus', 'cancelled', '已取消', 'warning', 5),
    ('smisRiskInspectionResult', 'pending', '待检查', 'info', 1),
    ('smisRiskInspectionResult', 'normal', '正常', 'success', 2),
    ('smisRiskInspectionResult', 'abnormal', '异常', 'danger', 3)
)
insert into public.sys_dictionary(
  id, type_id, code, status, create_by, update_by, value, label, sort, tenant_id, tag_type
)
select gen_random_uuid(), dict_type.id,
  definition.type_code || '_' || definition.value, '1',
  '624944977@qq.com', '624944977@qq.com', definition.value,
  definition.label, definition.sort, platform_tenant.id, definition.tag_type
from definitions definition cross join platform_tenant
join public.sys_dict_type dict_type
  on dict_type.tenant_id = platform_tenant.id and dict_type.code = definition.type_code
where not exists (
  select 1 from public.sys_dictionary existing
  where existing.type_id = dict_type.id and existing.value = definition.value
);

do $buttons$
declare
  v_page record;
begin
  for v_page in
    select page.id, page.name from public.sys_menu page
    where page.type = 'menu' and page.name in (
      'SmisDualControlSafetyRiskList',
      'SmisDualControlRiskClassificationControl',
      'SmisDualControlRiskListSummary',
      'SmisDualControlRiskInspectionTask'
    )
  loop
    insert into public.sys_menu(
      id, parent_id, name, path, component, meta, sort,
      create_by, update_by, type, app_code
    )
    select gen_random_uuid(), v_page.id, definition.permission, null, null,
      jsonb_build_object(
        'title', definition.title, 'is_hide', true, 'is_enable', true,
        'roles', '[]'::jsonb, 'icon', ''
      ), definition.sort, '624944977@qq.com', '624944977@qq.com', 'button', 'smis'
    from (
      select * from (values
        ('SmisDualControlSafetyRiskList', 'SmisDualControlSafetyRiskList:View', '查看安全风险清单', 1),
        ('SmisDualControlSafetyRiskList', 'SmisDualControlSafetyRiskList:Add', '新增安全风险', 2),
        ('SmisDualControlSafetyRiskList', 'SmisDualControlSafetyRiskList:Edit', '编辑安全风险', 3),
        ('SmisDualControlSafetyRiskList', 'SmisDualControlSafetyRiskList:Delete', '删除安全风险', 4),
        ('SmisDualControlSafetyRiskList', 'SmisDualControlSafetyRiskList:Export', '导出安全风险清单', 5),
        ('SmisDualControlRiskClassificationControl', 'SmisDualControlRiskClassificationControl:View', '查看风险分级管控', 1),
        ('SmisDualControlRiskClassificationControl', 'SmisDualControlRiskClassificationControl:Add', '新增风险管控配置', 2),
        ('SmisDualControlRiskClassificationControl', 'SmisDualControlRiskClassificationControl:Edit', '编辑风险管控配置', 3),
        ('SmisDualControlRiskClassificationControl', 'SmisDualControlRiskClassificationControl:Delete', '删除风险管控配置', 4),
        ('SmisDualControlRiskClassificationControl', 'SmisDualControlRiskClassificationControl:Import', '导入风险管控配置', 5),
        ('SmisDualControlRiskClassificationControl', 'SmisDualControlRiskClassificationControl:Export', '导出风险管控配置', 6),
        ('SmisDualControlRiskClassificationControl', 'SmisDualControlRiskClassificationControl:Configure', '设置风险分级管控', 7),
        ('SmisDualControlRiskListSummary', 'SmisDualControlRiskListSummary:View', '查看风险清单汇总', 1),
        ('SmisDualControlRiskListSummary', 'SmisDualControlRiskListSummary:Export', '导出风险清单汇总', 2),
        ('SmisDualControlRiskInspectionTask', 'SmisDualControlRiskInspectionTask:View', '查看风险巡查任务', 1),
        ('SmisDualControlRiskInspectionTask', 'SmisDualControlRiskInspectionTask:Export', '导出风险巡查任务', 2),
        ('SmisDualControlRiskInspectionTask', 'SmisDualControlRiskInspectionTask:Cancel', '取消风险巡查任务', 3),
        ('SmisDualControlRiskInspectionTask', 'SmisDualControlRiskInspectionTask:Transfer', '转交风险巡查任务', 4),
        ('SmisDualControlRiskInspectionTask', 'SmisDualControlRiskInspectionTask:Execute', '执行风险巡查任务', 5)
      ) item(menu_name, permission, title, sort)
      where item.menu_name = v_page.name
    ) definition
    where not exists (
      select 1 from public.sys_menu existing where existing.name = definition.permission
    );

    insert into public.sys_role_menu(
      id, role_id, menu_id, tenant_id, permission, create_by, update_by
    )
    select gen_random_uuid(), page_grant.role_id, button.id, page_grant.tenant_id,
      '{}'::jsonb, '624944977@qq.com', '624944977@qq.com'
    from public.sys_role_menu page_grant
    join public.sys_menu button on button.parent_id = v_page.id and button.type = 'button'
    where page_grant.menu_id = v_page.id
      and not exists (
        select 1 from public.sys_role_menu existing
        where existing.role_id = page_grant.role_id
          and existing.menu_id = button.id
          and existing.tenant_id = page_grant.tenant_id
      );
  end loop;
end
$buttons$;

create or replace function app_private.smis_risk_frequency_interval(
  p_frequency smallint,
  p_unit text
)
returns interval
language sql
immutable
set search_path = ''
as $$
  select case p_unit
    when 'shift' then make_interval(hours => greatest(coalesce(p_frequency, 1), 1) * 8)
    when 'day' then make_interval(days => greatest(coalesce(p_frequency, 1), 1))
    when 'week' then make_interval(days => greatest(coalesce(p_frequency, 1), 1) * 7)
    when 'month' then make_interval(months => greatest(coalesce(p_frequency, 1), 1))
    when 'quarter' then make_interval(months => greatest(coalesce(p_frequency, 1), 1) * 3)
    when 'year' then make_interval(years => greatest(coalesce(p_frequency, 1), 1))
    when 'ten_day' then make_interval(days => greatest(coalesce(p_frequency, 1), 1) * 10)
    else make_interval(days => greatest(coalesce(p_frequency, 1), 1))
  end
$$;

create or replace function app_private.smis_align_risk_task_start(
  p_candidate timestamptz,
  p_calendar_type text,
  p_calendar_days smallint[]
)
returns timestamptz
language plpgsql
stable
set search_path = ''
as $$
declare
  v_candidate timestamptz := p_candidate;
  v_loop integer := 0;
begin
  if coalesce(p_calendar_type, 'none') = 'none'
     or cardinality(coalesce(p_calendar_days, '{}'::smallint[])) = 0 then
    return v_candidate;
  end if;
  while v_loop < 366 loop
    if p_calendar_type = 'week'
       and extract(isodow from v_candidate)::smallint = any(p_calendar_days) then
      return v_candidate;
    end if;
    if p_calendar_type = 'month'
       and extract(day from v_candidate)::smallint = any(p_calendar_days) then
      return v_candidate;
    end if;
    v_candidate := v_candidate + interval '1 day';
    v_loop := v_loop + 1;
  end loop;
  return v_candidate;
end;
$$;

create or replace function app_private.smis_next_risk_inspection_task_no(
  p_tenant_id uuid,
  p_now timestamptz default now()
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_month date := date_trunc('month', p_now)::date;
  v_value integer;
begin
  insert into app_private.smis_risk_inspection_task_counter(tenant_id, month_key, last_value)
  values (p_tenant_id, v_month, 1)
  on conflict (tenant_id, month_key)
  do update set last_value = app_private.smis_risk_inspection_task_counter.last_value + 1
  returning last_value into v_value;

  if v_value > 9999 then
    raise exception '本月风险巡查任务编号已超过 4 位流水上限' using errcode = '22003';
  end if;
  return 'FXBSRW' || to_char(p_now, 'YYYYMM') || lpad(v_value::text, 4, '0');
end;
$$;

create or replace function app_private.smis_generate_due_risk_inspection_tasks(
  p_tenant_id uuid default null,
  p_horizon timestamptz default now() + interval '1 day'
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_assignment record;
  v_candidate timestamptz;
  v_end_at timestamptz;
  v_interval interval;
  v_task_id uuid;
  v_count integer := 0;
  v_loop integer;
begin
  update public.smis_risk_inspection_task
  set status = 'overdue'
  where status in ('not_started', 'in_progress')
    and planned_end_at < now()
    and (p_tenant_id is null or tenant_id = p_tenant_id);

  for v_assignment in
    select
      assignment.id,
      assignment.tenant_id,
      plan.risk_point_id,
      plan.control_start_at,
      assignment.responsible_employee_id,
      duplicate.repeat_frequency,
      duplicate.frequency_unit,
      duplicate.calendar_type,
      duplicate.calendar_days,
      duplicate.deadline_time,
      (
        select max(task.planned_start_at)
        from public.smis_risk_inspection_task task
        where task.tenant_id = assignment.tenant_id
          and task.assignment_id = assignment.id
      ) as last_start_at
    from public.smis_risk_control_assignment assignment
    join public.smis_risk_control_plan plan
      on plan.tenant_id = assignment.tenant_id and plan.id = assignment.plan_id
    join public.smis_duplicate_configuration duplicate
      on duplicate.tenant_id = assignment.tenant_id
      and duplicate.id = assignment.duplicate_configuration_id
    join public.smis_risk_point point
      on point.tenant_id = plan.tenant_id and point.id = plan.risk_point_id
    where plan.status = 'active'
      and assignment.status = 'active'
      and point.status = 'enabled'
      and duplicate.status = 'enabled'
      and duplicate.repeat_enabled
      and (p_tenant_id is null or assignment.tenant_id = p_tenant_id)
  loop
    v_interval := app_private.smis_risk_frequency_interval(
      v_assignment.repeat_frequency,
      v_assignment.frequency_unit
    );
    v_candidate := case
      when v_assignment.last_start_at is null
        then greatest(v_assignment.control_start_at, date_trunc('day', now()))
      else v_assignment.last_start_at + v_interval
    end;
    v_candidate := app_private.smis_align_risk_task_start(
      v_candidate,
      v_assignment.calendar_type,
      v_assignment.calendar_days
    );
    v_loop := 0;

    while v_candidate <= p_horizon and v_loop < 8 loop
      if v_assignment.deadline_time is not null then
        v_end_at := date_trunc('day', v_candidate) + v_assignment.deadline_time;
        if v_end_at <= v_candidate then
          v_end_at := v_end_at + interval '1 day';
        end if;
      else
        v_end_at := v_candidate + v_interval;
      end if;

      insert into public.smis_risk_inspection_task(
        tenant_id, assignment_id, risk_point_id, task_no,
        responsible_employee_id, assignee_employee_id,
        planned_start_at, planned_end_at, status
      ) values (
        v_assignment.tenant_id, v_assignment.id, v_assignment.risk_point_id,
        app_private.smis_next_risk_inspection_task_no(v_assignment.tenant_id, v_candidate),
        v_assignment.responsible_employee_id, v_assignment.responsible_employee_id,
        v_candidate, v_end_at,
        case when v_end_at < now() then 'overdue' else 'not_started' end
      )
      on conflict (tenant_id, assignment_id, planned_start_at) do nothing
      returning id into v_task_id;

      if v_task_id is not null then
        insert into public.smis_risk_inspection_task_item(
          tenant_id, task_id, risk_item_id, control_measure_id,
          inspection_content, result, sort
        )
        select
          item.tenant_id,
          v_task_id,
          item.id,
          measure.id,
          coalesce(
            nullif(btrim(measure.control_measure), ''),
            concat(item.hazard_factor, coalesce('：' || nullif(item.consequence, ''), ''))
          ),
          'pending',
          row_number() over (order by item.sort, item.item_no, measure.sort nulls last)::integer
        from public.smis_risk_item item
        left join public.smis_risk_control_measure measure
          on measure.tenant_id = item.tenant_id
          and measure.risk_item_id = item.id
          and measure.status = 'enabled'
        where item.tenant_id = v_assignment.tenant_id
          and item.risk_point_id = v_assignment.risk_point_id
          and item.status <> 'voided';

        insert into public.smis_risk_inspection_task_event(
          tenant_id, task_id, event_type, event_content
        ) values (
          v_assignment.tenant_id, v_task_id, 'generated',
          '系统根据风险分级管控频率自动生成巡查任务'
        );
        v_count := v_count + 1;
      end if;

      v_task_id := null;
      v_candidate := app_private.smis_align_risk_task_start(
        v_candidate + v_interval,
        v_assignment.calendar_type,
        v_assignment.calendar_days
      );
      v_loop := v_loop + 1;
    end loop;
  end loop;
  return v_count;
end;
$$;

create or replace function app_private.smis_upsert_risk_item(
  p_id uuid,
  p_risk_point_id uuid,
  p_payload jsonb,
  p_activity_ids uuid[] default '{}'::uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_id uuid;
  v_point_name text;
  v_organization_id uuid;
  v_factor text := btrim(coalesce(p_payload->>'hazard_factor', ''));
  v_category_id uuid;
  v_activity_id uuid;
begin
  if v_factor = '' then
    raise exception '请输入危险源或危害因素' using errcode = '22023';
  end if;
  begin
    v_category_id := nullif(p_payload->>'factor_category_id', '')::uuid;
  exception when others then
    raise exception '危害因素类别格式无效' using errcode = '22023';
  end;
  select point.point_name, site.organization_id
  into v_point_name, v_organization_id
  from public.smis_risk_point point
  join public.smis_site site
    on site.tenant_id = point.tenant_id and site.id = point.site_id
  where point.id = p_risk_point_id
    and point.tenant_id = v_tenant_id
    and point.status = 'enabled';
  if v_point_name is null then
    raise exception '风险点不存在、已作废或不属于当前租户' using errcode = 'P0002';
  end if;
  if v_category_id is not null and not exists (
    select 1 from public.smis_hazard_factor_category category
    where category.id = v_category_id
      and category.tenant_id = v_tenant_id
      and category.status = 'enabled'
  ) then
    raise exception '危害因素类别不存在、已停用或不属于当前租户' using errcode = '22023';
  end if;
  if exists (
    select 1 from unnest(coalesce(p_activity_ids, '{}'::uuid[])) activity_id
    where not exists (
      select 1 from public.smis_risk_activity activity
      where activity.id = activity_id
        and activity.risk_point_id = p_risk_point_id
        and activity.tenant_id = v_tenant_id
    )
  ) then
    raise exception '关联作业活动包含无效或跨风险点记录' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.smis_risk_item(
      tenant_id, risk_point_id, item_no, risk_point, hazard_factor,
      factor_category_id, organization_id, accident_types, consequence, sort, status
    ) values (
      v_tenant_id, p_risk_point_id,
      app_private.smis_next_risk_item_no(v_tenant_id, p_risk_point_id),
      v_point_name, v_factor, v_category_id, v_organization_id,
      coalesce(
        array(select jsonb_array_elements_text(coalesce(p_payload->'accident_types', '[]'::jsonb))),
        '{}'::text[]
      ),
      nullif(btrim(coalesce(p_payload->>'consequence', '')), ''),
      greatest(coalesce((p_payload->>'sort')::integer, 0), 0),
      'identified'
    ) returning id into v_id;
  else
    update public.smis_risk_item
    set risk_point_id = p_risk_point_id,
        risk_point = v_point_name,
        hazard_factor = v_factor,
        factor_category_id = v_category_id,
        organization_id = v_organization_id,
        accident_types = coalesce(
          array(select jsonb_array_elements_text(coalesce(p_payload->'accident_types', '[]'::jsonb))),
          '{}'::text[]
        ),
        consequence = nullif(btrim(coalesce(p_payload->>'consequence', '')), ''),
        sort = greatest(coalesce((p_payload->>'sort')::integer, 0), 0)
    where id = p_id
      and tenant_id = v_tenant_id
      and status <> 'voided'
    returning id into v_id;
    if v_id is null then
      raise exception '安全风险不存在、已作废或不属于当前租户' using errcode = 'P0002';
    end if;
    delete from public.smis_risk_item_activity
    where risk_item_id = v_id and tenant_id = v_tenant_id;
  end if;

  foreach v_activity_id in array coalesce(p_activity_ids, '{}'::uuid[]) loop
    insert into public.smis_risk_item_activity(tenant_id, risk_item_id, activity_id)
    values (v_tenant_id, v_id, v_activity_id);
  end loop;
  return v_id;
end;
$$;

create or replace function app_private.smis_delete_risk_items(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from public.smis_risk_item item
  where item.tenant_id = app_private.current_user_tenant_id()
    and item.id = any(coalesce(p_ids, '{}'::uuid[]))
    and not exists (
      select 1 from public.smis_risk_evaluation evaluation
      where evaluation.tenant_id = item.tenant_id and evaluation.risk_item_id = item.id
    );
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.smis_save_risk_hazard_secure(
  p_id uuid,
  p_risk_point_id uuid,
  p_payload jsonb,
  p_activity_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not app_private.has_permission('SmisDualControlRiskIdentification:MaintainHazards') then
    raise exception '当前账号没有维护危害因素的权限' using errcode = '42501';
  end if;
  return app_private.smis_upsert_risk_item(p_id, p_risk_point_id, p_payload, p_activity_ids);
end;
$$;

create or replace function public.smis_delete_risk_hazards_secure(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not app_private.has_permission('SmisDualControlRiskIdentification:MaintainHazards') then
    raise exception '当前账号没有删除危害因素的权限' using errcode = '42501';
  end if;
  return app_private.smis_delete_risk_items(p_ids);
end;
$$;

create or replace function public.smis_save_safety_risk_secure(
  p_id uuid,
  p_risk_point_id uuid,
  p_payload jsonb,
  p_activity_ids uuid[] default '{}'::uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_id is null and not app_private.has_permission('SmisDualControlSafetyRiskList:Add') then
    raise exception '当前账号没有新增安全风险的权限' using errcode = '42501';
  end if;
  if p_id is not null and not app_private.has_permission('SmisDualControlSafetyRiskList:Edit') then
    raise exception '当前账号没有编辑安全风险的权限' using errcode = '42501';
  end if;
  return app_private.smis_upsert_risk_item(p_id, p_risk_point_id, p_payload, p_activity_ids);
end;
$$;

create or replace function public.smis_delete_safety_risks_secure(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not app_private.has_permission('SmisDualControlSafetyRiskList:Delete') then
    raise exception '当前账号没有删除安全风险的权限' using errcode = '42501';
  end if;
  v_count := app_private.smis_delete_risk_items(p_ids);
  if v_count <> cardinality(coalesce(p_ids, '{}'::uuid[])) then
    raise exception '已完成风险评价的记录不能删除，请保留其评价与审计链路' using errcode = '23503';
  end if;
  return v_count;
end;
$$;

create or replace function public.smis_list_safety_risk_options_secure()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not (
    app_private.has_permission('SmisDualControlSafetyRiskList:View')
    or app_private.has_permission('SmisDualControlSafetyRiskList:Add')
    or app_private.has_permission('SmisDualControlSafetyRiskList:Edit')
  ) then
    raise exception '当前账号没有查看安全风险选项的权限' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'riskPoints', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', point.id, 'pointNo', point.point_no, 'pointName', point.point_name,
        'riskType', point.risk_type, 'siteName', site.site_name
      ) order by point.sort, point.point_no)
      from public.smis_risk_point point
      join public.smis_site site
        on site.tenant_id = point.tenant_id and site.id = point.site_id
      where point.tenant_id = v_tenant_id and point.status = 'enabled'
    ), '[]'::jsonb),
    'hazardCategories', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', category.id, 'categoryCode', category.category_code,
        'categoryName', category.category_name, 'factorType', category.factor_type
      ) order by category.sort, category.category_name)
      from public.smis_hazard_factor_category category
      where category.tenant_id = v_tenant_id and category.status = 'enabled'
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.smis_list_safety_risks_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_risk_name text default null,
  p_accident_type text default null,
  p_identified_from timestamptz default null,
  p_identified_to timestamptz default null,
  p_control_level text default null,
  p_status text default null,
  p_responsible_keyword text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_result jsonb;
begin
  if not (
    app_private.has_permission('SmisDualControlSafetyRiskList:View')
    or app_private.has_permission('SmisDualControlRiskListSummary:View')
  ) then
    raise exception '当前账号没有查看安全风险清单的权限' using errcode = '42501';
  end if;

  with records as (
    select
      item.id,
      item.item_no,
      item.risk_point_id,
      point.point_no,
      point.point_name,
      point.risk_type,
      site.site_name,
      organization.organization_name,
      item.hazard_factor,
      category.category_name as factor_category_name,
      item.accident_types,
      item.consequence,
      item.status,
      item.create_by,
      item.create_time,
      coalesce(activity.activity_ids, '{}'::uuid[]) as activity_ids,
      coalesce(activity.activity_names, '') as activity_names,
      evaluation.method_code,
      evaluation.d_value,
      evaluation.level_code,
      evaluation.level_name,
      evaluation.level_color,
      coalesce(measure.engineering_measures, '') as engineering_measures,
      coalesce(measure.management_measures, '') as management_measures,
      coalesce(measure.education_measures, '') as education_measures,
      coalesce(measure.personal_protection_measures, '') as personal_protection_measures,
      coalesce(measure.emergency_measures, '') as emergency_measures,
      coalesce(control.control_levels, '{}'::text[]) as control_levels,
      coalesce(control.responsible_employee_ids, '{}'::uuid[]) as responsible_employee_ids,
      coalesce(control.responsible_names, '') as responsible_names,
      coalesce(control.responsible_departments, '') as responsible_departments
    from public.smis_risk_item item
    join public.smis_risk_point point
      on point.tenant_id = item.tenant_id and point.id = item.risk_point_id
    join public.smis_site site
      on site.tenant_id = point.tenant_id and site.id = point.site_id
    left join public.sys_organization organization
      on organization.tenant_id = site.tenant_id and organization.id = site.organization_id
    left join public.smis_hazard_factor_category category
      on category.tenant_id = item.tenant_id and category.id = item.factor_category_id
    left join lateral (
      select
        array_agg(relation.activity_id order by risk_activity.sort) as activity_ids,
        string_agg(risk_activity.activity_name, '、' order by risk_activity.sort) as activity_names
      from public.smis_risk_item_activity relation
      join public.smis_risk_activity risk_activity
        on risk_activity.tenant_id = relation.tenant_id and risk_activity.id = relation.activity_id
      where relation.tenant_id = item.tenant_id and relation.risk_item_id = item.id
    ) activity on true
    left join lateral (
      select
        risk_evaluation.method_code,
        risk_evaluation.d_value,
        risk_level.level_code,
        risk_level.level_name,
        risk_level.color as level_color
      from public.smis_risk_evaluation risk_evaluation
      join public.smis_risk_assessment_level risk_level
        on risk_level.tenant_id = risk_evaluation.tenant_id
        and risk_level.id = risk_evaluation.risk_level_id
      where risk_evaluation.tenant_id = item.tenant_id
        and risk_evaluation.risk_item_id = item.id
      order by risk_evaluation.update_time desc
      limit 1
    ) evaluation on true
    left join lateral (
      select
        string_agg(control_measure, '；' order by sort)
          filter (where control_measure_category = 'engineering') as engineering_measures,
        string_agg(control_measure, '；' order by sort)
          filter (where control_measure_category = 'management') as management_measures,
        string_agg(control_measure, '；' order by sort)
          filter (where control_measure_category = 'education') as education_measures,
        string_agg(control_measure, '；' order by sort)
          filter (where control_measure_category = 'personal_protection') as personal_protection_measures,
        string_agg(control_measure, '；' order by sort)
          filter (where control_measure_category = 'emergency') as emergency_measures
      from public.smis_risk_control_measure risk_measure
      where risk_measure.tenant_id = item.tenant_id
        and risk_measure.risk_item_id = item.id
        and risk_measure.status = 'enabled'
    ) measure on true
    left join lateral (
      select
        array_agg(distinct assignment.control_level) as control_levels,
        array_agg(distinct employee.id) as responsible_employee_ids,
        string_agg(distinct employee.employee_name, '、') as responsible_names,
        string_agg(distinct employee_organization.organization_name, '、') as responsible_departments
      from public.smis_risk_control_plan plan
      join public.smis_risk_control_assignment assignment
        on assignment.tenant_id = plan.tenant_id and assignment.plan_id = plan.id
      join public.hr_employee employee
        on employee.tenant_id = assignment.tenant_id
        and employee.id = assignment.responsible_employee_id
      left join public.sys_organization employee_organization
        on employee_organization.tenant_id = employee.tenant_id
        and employee_organization.id = employee.organization_id
      where plan.tenant_id = item.tenant_id
        and plan.risk_point_id = item.risk_point_id
        and plan.status = 'active'
        and assignment.status = 'active'
    ) control on true
    where item.tenant_id = v_tenant_id
      and (p_keyword is null or btrim(p_keyword) = '' or
        item.item_no ilike '%' || btrim(p_keyword) || '%'
        or item.hazard_factor ilike '%' || btrim(p_keyword) || '%'
        or point.point_no ilike '%' || btrim(p_keyword) || '%')
      and (p_risk_name is null or btrim(p_risk_name) = ''
        or point.point_name ilike '%' || btrim(p_risk_name) || '%')
      and (p_accident_type is null or p_accident_type = any(item.accident_types))
      and (p_identified_from is null or item.create_time >= p_identified_from)
      and (p_identified_to is null or item.create_time <= p_identified_to)
      and (p_status is null or item.status = p_status)
  ), filtered as (
    select * from records
    where (p_control_level is null or p_control_level = any(control_levels))
      and (p_responsible_keyword is null or btrim(p_responsible_keyword) = ''
        or responsible_names ilike '%' || btrim(p_responsible_keyword) || '%')
  ), paged as (
    select * from filtered
    order by create_time desc, item_no
    offset greatest(coalesce(p_from, 0), 0)
    limit greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id,
        'hazardNo', item_no,
        'riskPointId', risk_point_id,
        'riskPointNo', point_no,
        'riskName', point_name,
        'riskPointType', risk_type,
        'siteName', site_name,
        'organizationName', organization_name,
        'hazardSource', hazard_factor,
        'factorCategoryName', factor_category_name,
        'activityNames', activity_names,
        'activityIds', to_jsonb(activity_ids),
        'accidentTypes', to_jsonb(accident_types),
        'riskDescription', consequence,
        'engineeringMeasures', engineering_measures,
        'managementMeasures', management_measures,
        'educationMeasures', education_measures,
        'personalProtectionMeasures', personal_protection_measures,
        'emergencyMeasures', emergency_measures,
        'riskAssessmentMethod', method_code,
        'riskScore', d_value,
        'riskLevelCode', level_code,
        'riskLevelName', level_name,
        'riskLevelColor', level_color,
        'controlLevels', to_jsonb(control_levels),
        'responsibleEmployeeIds', to_jsonb(responsible_employee_ids),
        'responsibleNames', responsible_names,
        'responsibleDepartments', responsible_departments,
        'identifiedBy', create_by,
        'identifiedAt', create_time,
        'status', status
      ) order by create_time desc, item_no) from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'overview', jsonb_build_object(
      'total', (select count(*) from filtered),
      'evaluated', (select count(*) from filtered where method_code is not null),
      'major', (select count(*) from filtered where level_code = 'major'),
      'controlled', (select count(*) from filtered where cardinality(control_levels) > 0)
    )
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.smis_list_risk_control_options_secure()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not (
    app_private.has_permission('SmisDualControlRiskClassificationControl:View')
    or app_private.has_permission('SmisDualControlRiskClassificationControl:Add')
    or app_private.has_permission('SmisDualControlRiskClassificationControl:Edit')
    or app_private.has_permission('SmisDualControlRiskClassificationControl:Configure')
  ) then
    raise exception '当前账号没有查看风险管控选项的权限' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'riskPoints', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', point.id, 'pointNo', point.point_no, 'pointName', point.point_name,
        'riskType', point.risk_type, 'siteName', site.site_name
      ) order by point.sort, point.point_no)
      from public.smis_risk_point point
      join public.smis_site site
        on site.tenant_id = point.tenant_id and site.id = point.site_id
      where point.tenant_id = v_tenant_id
        and point.status = 'enabled'
        and exists (
          select 1
          from public.smis_risk_item item
          join public.smis_risk_evaluation evaluation
            on evaluation.tenant_id = item.tenant_id and evaluation.risk_item_id = item.id
          where item.tenant_id = point.tenant_id
            and item.risk_point_id = point.id
            and item.status <> 'voided'
        )
    ), '[]'::jsonb),
    'duplicateConfigurations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', duplicate.id,
        'contentItem', duplicate.content_item,
        'repeatFrequency', duplicate.repeat_frequency,
        'frequencyUnit', duplicate.frequency_unit,
        'calendarType', duplicate.calendar_type,
        'calendarDays', to_jsonb(duplicate.calendar_days),
        'deadlineTime', duplicate.deadline_time,
        'displayLabel', concat(
          duplicate.content_item, ' · 每 ', duplicate.repeat_frequency,
          case duplicate.frequency_unit
            when 'shift' then '班' when 'day' then '日' when 'week' then '周'
            when 'month' then '月' when 'quarter' then '季' when 'year' then '年'
            when 'ten_day' then '旬' else duplicate.frequency_unit
          end
        )
      ) order by duplicate.sort, duplicate.content_item)
      from public.smis_duplicate_configuration duplicate
      where duplicate.tenant_id = v_tenant_id
        and duplicate.status = 'enabled'
        and duplicate.repeat_enabled
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.smis_list_risk_control_points_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_risk_type text default null,
  p_control_level text default null,
  p_control_status text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_result jsonb;
begin
  if not app_private.has_permission('SmisDualControlRiskClassificationControl:View') then
    raise exception '当前账号没有查看风险分级管控的权限' using errcode = '42501';
  end if;
  with records as (
    select
      point.id as risk_point_id,
      point.point_no,
      point.point_name,
      point.risk_type,
      site.site_name,
      plan.id as plan_id,
      plan.control_start_at,
      plan.control_description,
      coalesce(plan.status, 'uncontrolled') as control_status,
      risk.level_code,
      risk.level_name,
      risk.level_color,
      coalesce(risk.accident_types, '{}'::text[]) as accident_types,
      coalesce(assignment.assignments, '[]'::jsonb) as assignments,
      coalesce(assignment.control_levels, '{}'::text[]) as control_levels,
      coalesce(assignment.responsible_names, '') as responsible_names,
      coalesce(assignment.task_count, 0) as task_count,
      greatest(point.update_time, coalesce(plan.update_time, point.update_time)) as updated_at
    from public.smis_risk_point point
    join public.smis_site site
      on site.tenant_id = point.tenant_id and site.id = point.site_id
    left join public.smis_risk_control_plan plan
      on plan.tenant_id = point.tenant_id and plan.risk_point_id = point.id
    join lateral (
      select
        level.level_code,
        level.level_name,
        level.color as level_color,
        array_agg(distinct accident_type) filter (where accident_type is not null) as accident_types
      from public.smis_risk_item item
      join public.smis_risk_evaluation evaluation
        on evaluation.tenant_id = item.tenant_id and evaluation.risk_item_id = item.id
      join public.smis_risk_assessment_level level
        on level.tenant_id = evaluation.tenant_id and level.id = evaluation.risk_level_id
      left join lateral unnest(item.accident_types) accident_type on true
      where item.tenant_id = point.tenant_id
        and item.risk_point_id = point.id
        and item.status <> 'voided'
      group by level.level_code, level.level_name, level.color, level.sort
      order by level.sort
      limit 1
    ) risk on true
    left join lateral (
      select
        jsonb_agg(jsonb_build_object(
          'id', control_assignment.id,
          'controlLevel', control_assignment.control_level,
          'responsibleEmployeeId', employee.id,
          'responsibleEmployeeNo', employee.employee_no,
          'responsibleEmployeeName', employee.employee_name,
          'responsibleOrganizationId', employee.organization_id,
          'responsibleOrganizationName', employee_organization.organization_name,
          'duplicateConfigurationId', duplicate.id,
          'frequencyLabel', concat(
            '每 ', duplicate.repeat_frequency,
            case duplicate.frequency_unit
              when 'shift' then '班' when 'day' then '日' when 'week' then '周'
              when 'month' then '月' when 'quarter' then '季' when 'year' then '年'
              when 'ten_day' then '旬' else duplicate.frequency_unit
            end
          ),
          'controlMeasure', control_assignment.control_measure,
          'sort', control_assignment.sort
        ) order by control_assignment.sort, control_assignment.control_level) as assignments,
        array_agg(control_assignment.control_level order by control_assignment.sort) as control_levels,
        string_agg(distinct employee.employee_name, '、') as responsible_names,
        sum((
          select count(*) from public.smis_risk_inspection_task task
          where task.tenant_id = control_assignment.tenant_id
            and task.assignment_id = control_assignment.id
        ))::integer as task_count
      from public.smis_risk_control_assignment control_assignment
      join public.hr_employee employee
        on employee.tenant_id = control_assignment.tenant_id
        and employee.id = control_assignment.responsible_employee_id
      left join public.sys_organization employee_organization
        on employee_organization.tenant_id = employee.tenant_id
        and employee_organization.id = employee.organization_id
      join public.smis_duplicate_configuration duplicate
        on duplicate.tenant_id = control_assignment.tenant_id
        and duplicate.id = control_assignment.duplicate_configuration_id
      where control_assignment.tenant_id = plan.tenant_id
        and control_assignment.plan_id = plan.id
        and control_assignment.status = 'active'
    ) assignment on true
    where point.tenant_id = v_tenant_id
      and point.status = 'enabled'
      and (p_keyword is null or btrim(p_keyword) = ''
        or point.point_no ilike '%' || btrim(p_keyword) || '%'
        or point.point_name ilike '%' || btrim(p_keyword) || '%')
      and (p_risk_type is null or point.risk_type = p_risk_type)
  ), filtered as (
    select * from records
    where (p_control_level is null or p_control_level = any(control_levels))
      and (p_control_status is null or control_status = p_control_status)
  ), paged as (
    select * from filtered
    order by updated_at desc, point_no
    offset greatest(coalesce(p_from, 0), 0)
    limit greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(jsonb_build_object(
        'riskPointId', risk_point_id,
        'riskPointNo', point_no,
        'riskPointName', point_name,
        'riskPointType', risk_type,
        'siteName', site_name,
        'riskLevelCode', level_code,
        'riskLevelName', level_name,
        'riskLevelColor', level_color,
        'accidentTypes', to_jsonb(accident_types),
        'planId', plan_id,
        'controlStartAt', control_start_at,
        'controlDescription', control_description,
        'controlStatus', control_status,
        'controlLevels', to_jsonb(control_levels),
        'responsibleNames', responsible_names,
        'taskCount', task_count,
        'assignments', assignments
      ) order by updated_at desc, point_no) from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'overview', jsonb_build_object(
      'total', (select count(*) from filtered),
      'uncontrolled', (select count(*) from filtered where control_status = 'uncontrolled'),
      'active', (select count(*) from filtered where control_status = 'active'),
      'major', (select count(*) from filtered where level_code = 'major')
    )
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.smis_save_risk_control_plan_secure(
  p_id uuid,
  p_risk_point_id uuid,
  p_control_start_at timestamptz,
  p_status text,
  p_control_description text,
  p_assignments jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_id uuid;
  v_existing_id uuid;
  v_assignment jsonb;
  v_control_level text;
  v_employee_id uuid;
  v_duplicate_id uuid;
begin
  select plan.id into v_existing_id
  from public.smis_risk_control_plan plan
  where plan.tenant_id = v_tenant_id and plan.risk_point_id = p_risk_point_id;

  if p_id is null and v_existing_id is null and not (
    app_private.has_permission('SmisDualControlRiskClassificationControl:Add')
    or app_private.has_permission('SmisDualControlRiskClassificationControl:Configure')
  ) then
    raise exception '当前账号没有新增风险管控配置的权限' using errcode = '42501';
  end if;
  if coalesce(p_id, v_existing_id) is not null and not (
    app_private.has_permission('SmisDualControlRiskClassificationControl:Edit')
    or app_private.has_permission('SmisDualControlRiskClassificationControl:Configure')
  ) then
    raise exception '当前账号没有编辑风险管控配置的权限' using errcode = '42501';
  end if;
  if coalesce(p_status, 'active') not in ('active', 'suspended') then
    raise exception '管控状态无效' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_assignments, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_assignments, '[]'::jsonb)) = 0 then
    raise exception '请至少配置一个管控层级' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.smis_risk_point point
    where point.tenant_id = v_tenant_id
      and point.id = p_risk_point_id
      and point.status = 'enabled'
      and exists (
        select 1
        from public.smis_risk_item item
        join public.smis_risk_evaluation evaluation
          on evaluation.tenant_id = item.tenant_id and evaluation.risk_item_id = item.id
        where item.tenant_id = point.tenant_id
          and item.risk_point_id = point.id
          and item.status <> 'voided'
      )
  ) then
    raise exception '风险点未完成定量评价，不能配置分级管控' using errcode = '22023';
  end if;
  if (
    select count(*) <> count(distinct item->>'control_level')
    from jsonb_array_elements(p_assignments) item
  ) then
    raise exception '同一管控层级不能重复配置' using errcode = '23505';
  end if;

  v_id := coalesce(p_id, v_existing_id);

  if v_id is null then
    insert into public.smis_risk_control_plan(
      tenant_id, risk_point_id, control_start_at, status, control_description
    ) values (
      v_tenant_id, p_risk_point_id, coalesce(p_control_start_at, now()),
      coalesce(p_status, 'active'), nullif(btrim(coalesce(p_control_description, '')), '')
    ) returning id into v_id;
  else
    update public.smis_risk_control_plan
    set control_start_at = coalesce(p_control_start_at, control_start_at),
        status = coalesce(p_status, status),
        control_description = nullif(btrim(coalesce(p_control_description, '')), '')
    where id = v_id and tenant_id = v_tenant_id and risk_point_id = p_risk_point_id
    returning id into v_id;
    if v_id is null then
      raise exception '风险管控配置不存在或不属于当前风险点' using errcode = 'P0002';
    end if;
  end if;

  update public.smis_risk_control_assignment
  set status = 'inactive'
  where tenant_id = v_tenant_id and plan_id = v_id;

  for v_assignment in select * from jsonb_array_elements(p_assignments)
  loop
    v_control_level := v_assignment->>'control_level';
    begin
      v_employee_id := (v_assignment->>'responsible_employee_id')::uuid;
      v_duplicate_id := (v_assignment->>'duplicate_configuration_id')::uuid;
    exception when others then
      raise exception '管控责任人或管控频率格式无效' using errcode = '22023';
    end;
    if v_control_level not in ('company', 'department', 'team', 'position') then
      raise exception '管控层级无效' using errcode = '22023';
    end if;
    if not exists (
      select 1 from public.hr_employee employee
      where employee.tenant_id = v_tenant_id
        and employee.id = v_employee_id
        and employee.employment_status = 'active'
    ) then
      raise exception '管控责任人不存在、已离职或不属于当前租户' using errcode = '22023';
    end if;
    if not exists (
      select 1 from public.smis_duplicate_configuration duplicate
      where duplicate.tenant_id = v_tenant_id
        and duplicate.id = v_duplicate_id
        and duplicate.status = 'enabled'
        and duplicate.repeat_enabled
    ) then
      raise exception '管控频率不存在、已停用或未启用重复规则' using errcode = '22023';
    end if;

    insert into public.smis_risk_control_assignment(
      tenant_id, plan_id, control_level, responsible_employee_id,
      duplicate_configuration_id, control_measure, status, sort
    ) values (
      v_tenant_id, v_id, v_control_level, v_employee_id, v_duplicate_id,
      nullif(btrim(coalesce(v_assignment->>'control_measure', '')), ''),
      'active', greatest(coalesce((v_assignment->>'sort')::integer, 0), 0)
    )
    on conflict (tenant_id, plan_id, control_level)
    do update set
      responsible_employee_id = excluded.responsible_employee_id,
      duplicate_configuration_id = excluded.duplicate_configuration_id,
      control_measure = excluded.control_measure,
      status = 'active',
      sort = excluded.sort;
  end loop;

  perform app_private.smis_generate_due_risk_inspection_tasks(v_tenant_id, now() + interval '1 day');
  return v_id;
end;
$$;

create or replace function public.smis_delete_risk_control_plans_secure(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_count integer := 0;
  v_id uuid;
begin
  if not app_private.has_permission('SmisDualControlRiskClassificationControl:Delete') then
    raise exception '当前账号没有删除风险管控配置的权限' using errcode = '42501';
  end if;
  foreach v_id in array coalesce(p_ids, '{}'::uuid[]) loop
    if exists (
      select 1
      from public.smis_risk_control_assignment assignment
      join public.smis_risk_inspection_task task
        on task.tenant_id = assignment.tenant_id and task.assignment_id = assignment.id
      where assignment.tenant_id = v_tenant_id and assignment.plan_id = v_id
    ) then
      update public.smis_risk_control_plan set status = 'suspended'
      where tenant_id = v_tenant_id and id = v_id;
      if found then
        v_count := v_count + 1;
        update public.smis_risk_control_assignment set status = 'inactive'
        where tenant_id = v_tenant_id and plan_id = v_id;
      end if;
    else
      delete from public.smis_risk_control_plan
      where tenant_id = v_tenant_id and id = v_id;
      if found then v_count := v_count + 1; end if;
    end if;
  end loop;
  return v_count;
end;
$$;

create or replace function public.smis_generate_due_risk_inspection_tasks_secure()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not app_private.has_permission('SmisDualControlRiskInspectionTask:View') then
    raise exception '当前账号没有生成风险巡查任务的权限' using errcode = '42501';
  end if;
  return app_private.smis_generate_due_risk_inspection_tasks(
    app_private.current_user_tenant_id(),
    now() + interval '1 day'
  );
end;
$$;

create or replace function public.smis_list_risk_inspection_tasks_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_risk_name text default null,
  p_risk_type text default null,
  p_planned_from timestamptz default null,
  p_planned_to timestamptz default null,
  p_responsible_employee_id uuid default null,
  p_status text default null,
  p_executor_keyword text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_result jsonb;
begin
  if not app_private.has_permission('SmisDualControlRiskInspectionTask:View') then
    raise exception '当前账号没有查看风险巡查任务的权限' using errcode = '42501';
  end if;
  perform app_private.smis_generate_due_risk_inspection_tasks(v_tenant_id, now() + interval '1 day');

  with records as (
    select
      task.id,
      task.task_no,
      task.risk_point_id,
      point.point_no,
      point.point_name,
      point.risk_type,
      risk.level_code,
      risk.level_name,
      risk.level_color,
      assignment.control_level,
      task.responsible_employee_id,
      responsible.employee_no as responsible_employee_no,
      responsible.employee_name as responsible_employee_name,
      task.assignee_employee_id,
      assignee.employee_no as assignee_employee_no,
      assignee.employee_name as assignee_employee_name,
      task.actual_executor_employee_id,
      executor.employee_no as actual_executor_employee_no,
      executor.employee_name as actual_executor_employee_name,
      task.planned_start_at,
      task.planned_end_at,
      task.actual_start_at,
      task.completed_at,
      task.status,
      task.execution_summary,
      coalesce(item.item_count, 0) as item_count,
      coalesce(item.completed_item_count, 0) as completed_item_count,
      coalesce(item.abnormal_count, 0) as abnormal_count,
      task.create_time,
      task.update_time
    from public.smis_risk_inspection_task task
    join public.smis_risk_control_assignment assignment
      on assignment.tenant_id = task.tenant_id and assignment.id = task.assignment_id
    join public.smis_risk_point point
      on point.tenant_id = task.tenant_id and point.id = task.risk_point_id
    join public.hr_employee responsible
      on responsible.tenant_id = task.tenant_id and responsible.id = task.responsible_employee_id
    join public.hr_employee assignee
      on assignee.tenant_id = task.tenant_id and assignee.id = task.assignee_employee_id
    left join public.hr_employee executor
      on executor.tenant_id = task.tenant_id and executor.id = task.actual_executor_employee_id
    left join lateral (
      select level.level_code, level.level_name, level.color as level_color
      from public.smis_risk_item risk_item
      join public.smis_risk_evaluation evaluation
        on evaluation.tenant_id = risk_item.tenant_id and evaluation.risk_item_id = risk_item.id
      join public.smis_risk_assessment_level level
        on level.tenant_id = evaluation.tenant_id and level.id = evaluation.risk_level_id
      where risk_item.tenant_id = task.tenant_id
        and risk_item.risk_point_id = task.risk_point_id
        and risk_item.status <> 'voided'
      order by level.sort
      limit 1
    ) risk on true
    left join lateral (
      select
        count(*)::integer as item_count,
        count(*) filter (where task_item.result <> 'pending')::integer as completed_item_count,
        count(*) filter (where task_item.result = 'abnormal')::integer as abnormal_count
      from public.smis_risk_inspection_task_item task_item
      where task_item.tenant_id = task.tenant_id and task_item.task_id = task.id
    ) item on true
    where task.tenant_id = v_tenant_id
      and (p_keyword is null or btrim(p_keyword) = ''
        or task.task_no ilike '%' || btrim(p_keyword) || '%'
        or point.point_no ilike '%' || btrim(p_keyword) || '%')
      and (p_risk_name is null or btrim(p_risk_name) = ''
        or point.point_name ilike '%' || btrim(p_risk_name) || '%')
      and (p_risk_type is null or point.risk_type = p_risk_type)
      and (p_planned_from is null or task.planned_start_at >= p_planned_from)
      and (p_planned_to is null or task.planned_start_at <= p_planned_to)
      and (p_responsible_employee_id is null
        or task.responsible_employee_id = p_responsible_employee_id)
      and (p_status is null or task.status = p_status)
      and (p_executor_keyword is null or btrim(p_executor_keyword) = ''
        or executor.employee_name ilike '%' || btrim(p_executor_keyword) || '%'
        or executor.employee_no ilike '%' || btrim(p_executor_keyword) || '%')
  ), paged as (
    select * from records
    order by planned_start_at desc, task_no desc
    offset greatest(coalesce(p_from, 0), 0)
    limit greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id,
        'taskNo', task_no,
        'riskPointId', risk_point_id,
        'riskPointNo', point_no,
        'riskPointName', point_name,
        'riskPointType', risk_type,
        'riskLevelCode', level_code,
        'riskLevelName', level_name,
        'riskLevelColor', level_color,
        'controlLevel', control_level,
        'responsibleEmployeeId', responsible_employee_id,
        'responsibleEmployeeNo', responsible_employee_no,
        'responsibleEmployeeName', responsible_employee_name,
        'assigneeEmployeeId', assignee_employee_id,
        'assigneeEmployeeNo', assignee_employee_no,
        'assigneeEmployeeName', assignee_employee_name,
        'actualExecutorEmployeeId', actual_executor_employee_id,
        'actualExecutorEmployeeNo', actual_executor_employee_no,
        'actualExecutorEmployeeName', actual_executor_employee_name,
        'plannedStartAt', planned_start_at,
        'plannedEndAt', planned_end_at,
        'actualStartAt', actual_start_at,
        'completedAt', completed_at,
        'status', status,
        'executionSummary', execution_summary,
        'itemCount', item_count,
        'completedItemCount', completed_item_count,
        'abnormalCount', abnormal_count,
        'createTime', create_time,
        'updateTime', update_time
      ) order by planned_start_at desc, task_no desc) from paged
    ), '[]'::jsonb),
    'total', (select count(*) from records),
    'overview', jsonb_build_object(
      'total', (select count(*) from records),
      'notStarted', (select count(*) from records where status = 'not_started'),
      'inProgress', (select count(*) from records where status = 'in_progress'),
      'overdue', (select count(*) from records where status = 'overdue'),
      'completed', (select count(*) from records where status = 'completed')
    )
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.smis_get_risk_inspection_task_secure(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_result jsonb;
begin
  if not app_private.has_permission('SmisDualControlRiskInspectionTask:View') then
    raise exception '当前账号没有查看风险巡查任务详情的权限' using errcode = '42501';
  end if;
  select jsonb_build_object(
    'id', task.id,
    'taskNo', task.task_no,
    'riskPointId', task.risk_point_id,
    'riskPointNo', point.point_no,
    'riskPointName', point.point_name,
    'riskPointType', point.risk_type,
    'controlLevel', assignment.control_level,
    'responsibleEmployeeId', task.responsible_employee_id,
    'responsibleEmployeeNo', responsible.employee_no,
    'responsibleEmployeeName', responsible.employee_name,
    'assigneeEmployeeId', task.assignee_employee_id,
    'assigneeEmployeeNo', assignee.employee_no,
    'assigneeEmployeeName', assignee.employee_name,
    'actualExecutorEmployeeId', task.actual_executor_employee_id,
    'actualExecutorEmployeeNo', executor.employee_no,
    'actualExecutorEmployeeName', executor.employee_name,
    'plannedStartAt', task.planned_start_at,
    'plannedEndAt', task.planned_end_at,
    'actualStartAt', task.actual_start_at,
    'completedAt', task.completed_at,
    'cancelledAt', task.cancelled_at,
    'status', task.status,
    'transferReason', task.transfer_reason,
    'cancellationReason', task.cancellation_reason,
    'executionSummary', task.execution_summary,
    'attachmentUrls', task.attachment_urls,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', item.id,
        'riskItemId', item.risk_item_id,
        'controlMeasureId', item.control_measure_id,
        'hazardNo', risk_item.item_no,
        'hazardSource', risk_item.hazard_factor,
        'inspectionContent', item.inspection_content,
        'result', item.result,
        'remark', item.remark,
        'attachmentUrls', item.attachment_urls,
        'sort', item.sort
      ) order by item.sort, item.create_time)
      from public.smis_risk_inspection_task_item item
      left join public.smis_risk_item risk_item
        on risk_item.tenant_id = item.tenant_id and risk_item.id = item.risk_item_id
      where item.tenant_id = task.tenant_id and item.task_id = task.id
    ), '[]'::jsonb),
    'events', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', event.id,
        'eventType', event.event_type,
        'eventContent', event.event_content,
        'operatorName', event.create_by,
        'eventAt', event.create_time
      ) order by event.create_time, event.id)
      from public.smis_risk_inspection_task_event event
      where event.tenant_id = task.tenant_id and event.task_id = task.id
    ), '[]'::jsonb)
  ) into v_result
  from public.smis_risk_inspection_task task
  join public.smis_risk_control_assignment assignment
    on assignment.tenant_id = task.tenant_id and assignment.id = task.assignment_id
  join public.smis_risk_point point
    on point.tenant_id = task.tenant_id and point.id = task.risk_point_id
  join public.hr_employee responsible
    on responsible.tenant_id = task.tenant_id and responsible.id = task.responsible_employee_id
  join public.hr_employee assignee
    on assignee.tenant_id = task.tenant_id and assignee.id = task.assignee_employee_id
  left join public.hr_employee executor
    on executor.tenant_id = task.tenant_id and executor.id = task.actual_executor_employee_id
  where task.tenant_id = v_tenant_id and task.id = p_id;
  if v_result is null then
    raise exception '风险巡查任务不存在或不属于当前租户' using errcode = 'P0002';
  end if;
  return v_result;
end;
$$;

create or replace function public.smis_cancel_risk_inspection_task_secure(
  p_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.has_permission('SmisDualControlRiskInspectionTask:Cancel') then
    raise exception '当前账号没有取消风险巡查任务的权限' using errcode = '42501';
  end if;
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception '请输入取消原因' using errcode = '22023';
  end if;
  update public.smis_risk_inspection_task
  set status = 'cancelled', cancelled_at = now(), cancellation_reason = btrim(p_reason)
  where tenant_id = v_tenant_id and id = p_id
    and status in ('not_started', 'in_progress', 'overdue');
  if not found then
    raise exception '任务不存在、已完成或已取消' using errcode = 'P0002';
  end if;
  insert into public.smis_risk_inspection_task_event(
    tenant_id, task_id, event_type, event_content
  ) values (v_tenant_id, p_id, 'cancelled', '取消原因：' || btrim(p_reason));
end;
$$;

create or replace function public.smis_transfer_risk_inspection_task_secure(
  p_id uuid,
  p_employee_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_employee_name text;
begin
  if not app_private.has_permission('SmisDualControlRiskInspectionTask:Transfer') then
    raise exception '当前账号没有转交风险巡查任务的权限' using errcode = '42501';
  end if;
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception '请输入转交原因' using errcode = '22023';
  end if;
  select employee.employee_name into v_employee_name
  from public.hr_employee employee
  where employee.tenant_id = v_tenant_id
    and employee.id = p_employee_id
    and employee.employment_status = 'active';
  if v_employee_name is null then
    raise exception '接收人不存在、已离职或不属于当前租户' using errcode = '22023';
  end if;
  update public.smis_risk_inspection_task
  set assignee_employee_id = p_employee_id, transfer_reason = btrim(p_reason)
  where tenant_id = v_tenant_id and id = p_id
    and status in ('not_started', 'in_progress', 'overdue');
  if not found then
    raise exception '任务不存在、已完成或已取消' using errcode = 'P0002';
  end if;
  insert into public.smis_risk_inspection_task_event(
    tenant_id, task_id, event_type, event_content
  ) values (
    v_tenant_id, p_id, 'transferred',
    '任务转交给 ' || v_employee_name || '；原因：' || btrim(p_reason)
  );
end;
$$;

create or replace function public.smis_save_risk_inspection_execution_secure(
  p_id uuid,
  p_actual_executor_employee_id uuid,
  p_execution_summary text,
  p_attachment_urls jsonb,
  p_items jsonb,
  p_complete boolean default false
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_item jsonb;
  v_item_id uuid;
  v_result text;
begin
  if not app_private.has_permission('SmisDualControlRiskInspectionTask:Execute') then
    raise exception '当前账号没有执行风险巡查任务的权限' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.hr_employee employee
    where employee.tenant_id = v_tenant_id
      and employee.id = p_actual_executor_employee_id
      and employee.employment_status = 'active'
  ) then
    raise exception '实际执行人不存在、已离职或不属于当前租户' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array' then
    raise exception '巡查项目结果格式无效' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_attachment_urls, '[]'::jsonb)) <> 'array' then
    raise exception '任务附件格式无效' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.smis_risk_inspection_task task
    where task.tenant_id = v_tenant_id and task.id = p_id
      and task.status in ('not_started', 'in_progress', 'overdue')
  ) then
    raise exception '任务不存在、已完成或已取消' using errcode = 'P0002';
  end if;

  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    begin
      v_item_id := (v_item->>'id')::uuid;
    exception when others then
      raise exception '巡查项目编号格式无效' using errcode = '22023';
    end;
    v_result := coalesce(v_item->>'result', 'pending');
    if v_result not in ('pending', 'normal', 'abnormal') then
      raise exception '巡查结果无效' using errcode = '22023';
    end if;
    update public.smis_risk_inspection_task_item
    set result = v_result,
        remark = nullif(btrim(coalesce(v_item->>'remark', '')), ''),
        attachment_urls = coalesce(v_item->'attachment_urls', '[]'::jsonb)
    where tenant_id = v_tenant_id and task_id = p_id and id = v_item_id;
    if not found then
      raise exception '巡查项目不存在或不属于当前任务' using errcode = 'P0002';
    end if;
  end loop;

  if p_complete and exists (
    select 1 from public.smis_risk_inspection_task_item item
    where item.tenant_id = v_tenant_id and item.task_id = p_id and item.result = 'pending'
  ) then
    raise exception '提交完成前请填写全部巡查项目结果' using errcode = '22023';
  end if;

  update public.smis_risk_inspection_task
  set actual_executor_employee_id = p_actual_executor_employee_id,
      actual_start_at = coalesce(actual_start_at, now()),
      completed_at = case when p_complete then now() else completed_at end,
      status = case when p_complete then 'completed' else 'in_progress' end,
      execution_summary = nullif(btrim(coalesce(p_execution_summary, '')), ''),
      attachment_urls = coalesce(p_attachment_urls, '[]'::jsonb)
  where tenant_id = v_tenant_id and id = p_id;

  insert into public.smis_risk_inspection_task_event(
    tenant_id, task_id, event_type, event_content
  ) values (
    v_tenant_id, p_id,
    case when p_complete then 'completed' else 'progress_saved' end,
    case when p_complete then '已提交巡查结果并完成任务' else '已保存巡查进度' end
  );
end;
$$;

revoke all on function public.smis_save_safety_risk_secure(uuid, uuid, jsonb, uuid[]) from public, anon;
revoke all on function public.smis_delete_safety_risks_secure(uuid[]) from public, anon;
revoke all on function public.smis_list_safety_risk_options_secure() from public, anon;
revoke all on function public.smis_list_safety_risks_secure(integer, integer, text, text, text, timestamptz, timestamptz, text, text, text) from public, anon;
revoke all on function public.smis_list_risk_control_options_secure() from public, anon;
revoke all on function public.smis_list_risk_control_points_secure(integer, integer, text, text, text, text) from public, anon;
revoke all on function public.smis_save_risk_control_plan_secure(uuid, uuid, timestamptz, text, text, jsonb) from public, anon;
revoke all on function public.smis_delete_risk_control_plans_secure(uuid[]) from public, anon;
revoke all on function public.smis_generate_due_risk_inspection_tasks_secure() from public, anon;
revoke all on function public.smis_list_risk_inspection_tasks_secure(integer, integer, text, text, text, timestamptz, timestamptz, uuid, text, text) from public, anon;
revoke all on function public.smis_get_risk_inspection_task_secure(uuid) from public, anon;
revoke all on function public.smis_cancel_risk_inspection_task_secure(uuid, text) from public, anon;
revoke all on function public.smis_transfer_risk_inspection_task_secure(uuid, uuid, text) from public, anon;
revoke all on function public.smis_save_risk_inspection_execution_secure(uuid, uuid, text, jsonb, jsonb, boolean) from public, anon;

grant execute on function public.smis_save_safety_risk_secure(uuid, uuid, jsonb, uuid[]) to authenticated;
grant execute on function public.smis_delete_safety_risks_secure(uuid[]) to authenticated;
grant execute on function public.smis_list_safety_risk_options_secure() to authenticated;
grant execute on function public.smis_list_safety_risks_secure(integer, integer, text, text, text, timestamptz, timestamptz, text, text, text) to authenticated;
grant execute on function public.smis_list_risk_control_options_secure() to authenticated;
grant execute on function public.smis_list_risk_control_points_secure(integer, integer, text, text, text, text) to authenticated;
grant execute on function public.smis_save_risk_control_plan_secure(uuid, uuid, timestamptz, text, text, jsonb) to authenticated;
grant execute on function public.smis_delete_risk_control_plans_secure(uuid[]) to authenticated;
grant execute on function public.smis_generate_due_risk_inspection_tasks_secure() to authenticated;
grant execute on function public.smis_list_risk_inspection_tasks_secure(integer, integer, text, text, text, timestamptz, timestamptz, uuid, text, text) to authenticated;
grant execute on function public.smis_get_risk_inspection_task_secure(uuid) to authenticated;
grant execute on function public.smis_cancel_risk_inspection_task_secure(uuid, text) to authenticated;
grant execute on function public.smis_transfer_risk_inspection_task_secure(uuid, uuid, text) to authenticated;
grant execute on function public.smis_save_risk_inspection_execution_secure(uuid, uuid, text, jsonb, jsonb, boolean) to authenticated;

revoke all on table app_private.smis_risk_inspection_task_counter from public, anon, authenticated;
revoke all on function app_private.smis_risk_frequency_interval(smallint, text) from public, anon, authenticated;
revoke all on function app_private.smis_align_risk_task_start(timestamptz, text, smallint[]) from public, anon, authenticated;
revoke all on function app_private.smis_next_risk_inspection_task_no(uuid, timestamptz) from public, anon, authenticated;
revoke all on function app_private.smis_generate_due_risk_inspection_tasks(uuid, timestamptz) from public, anon, authenticated;
revoke all on function app_private.smis_upsert_risk_item(uuid, uuid, jsonb, uuid[]) from public, anon, authenticated;
revoke all on function app_private.smis_delete_risk_items(uuid[]) from public, anon, authenticated;

do $cron$
declare
  v_job_id bigint;
begin
  select jobid into v_job_id from cron.job where jobname = 'smis-risk-inspection-task-generator';
  if v_job_id is not null then
    perform cron.unschedule(v_job_id);
  end if;
  perform cron.schedule(
    'smis-risk-inspection-task-generator',
    '15 * * * *',
    'select app_private.smis_generate_due_risk_inspection_tasks(null, now() + interval ''1 day'');'
  );
end;
$cron$;

;
