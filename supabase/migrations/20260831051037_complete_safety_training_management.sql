begin;

create table if not exists public.smis_safety_training_plan (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  plan_no text not null,
  subject text not null,
  training_category text not null,
  training_type text not null,
  training_form text not null,
  training_level text not null,
  organizer_organization_id uuid not null,
  target_organization_id uuid,
  responsible_employee_id uuid,
  instructor_name text,
  planned_start_at timestamptz not null,
  planned_end_at timestamptz not null,
  location text,
  content text not null,
  requirements text,
  training_hours numeric(6, 2) not null default 0,
  assessment_method text not null default 'none',
  warning_status text not null default 'normal',
  status text not null default 'draft',
  attachment_urls text[] not null default '{}',
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_safety_training_plan_tenant_fkey
    foreign key (tenant_id) references public.sys_tenant(id),
  constraint smis_safety_training_plan_organizer_fkey
    foreign key (organizer_organization_id, tenant_id)
    references public.sys_organization(id, tenant_id),
  constraint smis_safety_training_plan_target_fkey
    foreign key (target_organization_id, tenant_id)
    references public.sys_organization(id, tenant_id),
  constraint smis_safety_training_plan_responsible_fkey
    foreign key (responsible_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id),
  constraint smis_safety_training_plan_no_unique unique (tenant_id, plan_no),
  constraint smis_safety_training_plan_id_tenant_unique unique (id, tenant_id),
  constraint smis_safety_training_plan_dates_check check (planned_end_at >= planned_start_at),
  constraint smis_safety_training_plan_hours_check check (training_hours >= 0),
  constraint smis_safety_training_plan_category_check check (
    training_category in ('new_employee', 'annual', 'special', 'transfer', 'temporary')
  ),
  constraint smis_safety_training_plan_type_check check (
    training_type in ('safety_education', 'special_training', 'emergency', 'compliance', 'other')
  ),
  constraint smis_safety_training_plan_form_check check (
    training_form in ('centralized_lecture', 'onsite_practice', 'online', 'external', 'blended')
  ),
  constraint smis_safety_training_plan_level_check check (
    training_level in ('company', 'department', 'area', 'team')
  ),
  constraint smis_safety_training_plan_assessment_check check (
    assessment_method in ('none', 'written', 'practical', 'comprehensive')
  ),
  constraint smis_safety_training_plan_warning_check check (warning_status in ('normal', 'warning')),
  constraint smis_safety_training_plan_status_check check (
    status in ('draft', 'published', 'completed', 'cancelled')
  ),
  constraint smis_safety_training_plan_subject_check check (char_length(btrim(subject)) between 1 and 200),
  constraint smis_safety_training_plan_content_check check (char_length(btrim(content)) between 1 and 4000),
  constraint smis_safety_training_plan_remark_check check (remark is null or char_length(remark) <= 1000)
);

comment on table public.smis_safety_training_plan is
  '安全培训计划主档；发布后锁定，培训记录从计划下推并完成闭环。';

create table if not exists public.smis_safety_training_plan_participant (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  training_plan_id uuid not null,
  employee_id uuid not null,
  employee_no text not null,
  employee_name text not null,
  organization_id uuid,
  organization_name text,
  job_title text,
  phone text,
  sort integer not null default 0,
  create_by text,
  create_time timestamptz not null default now(),
  constraint smis_safety_training_plan_participant_tenant_fkey
    foreign key (tenant_id) references public.sys_tenant(id),
  constraint smis_safety_training_plan_participant_plan_fkey
    foreign key (training_plan_id, tenant_id)
    references public.smis_safety_training_plan(id, tenant_id) on delete cascade,
  constraint smis_safety_training_plan_participant_employee_fkey
    foreign key (employee_id, tenant_id)
    references public.hr_employee(id, tenant_id),
  constraint smis_safety_training_plan_participant_unique
    unique (tenant_id, training_plan_id, employee_id)
);

comment on table public.smis_safety_training_plan_participant is
  '培训计划参训范围；姓名、组织、岗位等字段是计划发布时的审计快照。';

create table if not exists public.smis_safety_training_record (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  training_plan_id uuid not null,
  record_no text not null,
  actual_start_at timestamptz,
  actual_end_at timestamptz,
  location text,
  instructor_name text,
  lecturer_name text,
  training_content text,
  training_hours numeric(6, 2) not null default 0,
  effect_evaluation text,
  attachment_urls text[] not null default '{}',
  sign_in_attachment_urls text[] not null default '{}',
  status text not null default 'draft',
  submitted_at timestamptz,
  submitted_by text,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_safety_training_record_tenant_fkey
    foreign key (tenant_id) references public.sys_tenant(id),
  constraint smis_safety_training_record_plan_fkey
    foreign key (training_plan_id, tenant_id)
    references public.smis_safety_training_plan(id, tenant_id),
  constraint smis_safety_training_record_no_unique unique (tenant_id, record_no),
  constraint smis_safety_training_record_plan_unique unique (tenant_id, training_plan_id),
  constraint smis_safety_training_record_id_tenant_unique unique (id, tenant_id),
  constraint smis_safety_training_record_dates_check check (
    actual_end_at is null or actual_start_at is null or actual_end_at >= actual_start_at
  ),
  constraint smis_safety_training_record_hours_check check (training_hours >= 0),
  constraint smis_safety_training_record_status_check check (status in ('draft', 'submitted')),
  constraint smis_safety_training_record_remark_check check (remark is null or char_length(remark) <= 1000)
);

comment on table public.smis_safety_training_record is
  '安全培训实施记录；一项事件型计划对应一张记录单，提交后形成不可变审计事实。';

create table if not exists public.smis_safety_training_record_participant (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  training_record_id uuid not null,
  employee_id uuid not null,
  employee_no text not null,
  employee_name text not null,
  organization_id uuid,
  organization_name text,
  job_title text,
  phone text,
  attendance_status text not null default 'pending',
  check_in_at timestamptz,
  sign_method text,
  score numeric(5, 2),
  assessment_result text not null default 'not_assessed',
  remark text,
  sort integer not null default 0,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_safety_training_record_participant_tenant_fkey
    foreign key (tenant_id) references public.sys_tenant(id),
  constraint smis_safety_training_record_participant_record_fkey
    foreign key (training_record_id, tenant_id)
    references public.smis_safety_training_record(id, tenant_id) on delete cascade,
  constraint smis_safety_training_record_participant_employee_fkey
    foreign key (employee_id, tenant_id)
    references public.hr_employee(id, tenant_id),
  constraint smis_safety_training_record_participant_unique
    unique (tenant_id, training_record_id, employee_id),
  constraint smis_safety_training_record_participant_attendance_check check (
    attendance_status in ('pending', 'present', 'absent', 'leave')
  ),
  constraint smis_safety_training_record_participant_sign_method_check check (
    sign_method is null or sign_method in ('manual', 'qrcode', 'import')
  ),
  constraint smis_safety_training_record_participant_result_check check (
    assessment_result in ('not_assessed', 'pass', 'fail')
  ),
  constraint smis_safety_training_record_participant_score_check check (
    score is null or (score >= 0 and score <= 100)
  )
);

comment on table public.smis_safety_training_record_participant is
  '培训记录参训及签到明细；人员信息为培训实施时快照，签到状态与时间为审计事实。';

create index if not exists smis_safety_training_plan_tenant_status_start_idx
  on public.smis_safety_training_plan (tenant_id, status, planned_start_at desc);
create index if not exists smis_safety_training_plan_organizer_idx
  on public.smis_safety_training_plan (organizer_organization_id);
create index if not exists smis_safety_training_plan_target_idx
  on public.smis_safety_training_plan (target_organization_id);
create index if not exists smis_safety_training_plan_responsible_idx
  on public.smis_safety_training_plan (responsible_employee_id);
create index if not exists smis_safety_training_plan_participant_plan_idx
  on public.smis_safety_training_plan_participant (training_plan_id);
create index if not exists smis_safety_training_plan_participant_employee_idx
  on public.smis_safety_training_plan_participant (employee_id);
create index if not exists smis_safety_training_record_plan_idx
  on public.smis_safety_training_record (training_plan_id);
create index if not exists smis_safety_training_record_tenant_status_actual_idx
  on public.smis_safety_training_record (tenant_id, status, actual_start_at desc);
create index if not exists smis_safety_training_record_participant_record_idx
  on public.smis_safety_training_record_participant (training_record_id);
create index if not exists smis_safety_training_record_participant_employee_idx
  on public.smis_safety_training_record_participant (employee_id);
create index if not exists smis_safety_training_record_present_idx
  on public.smis_safety_training_record_participant (tenant_id, training_record_id, check_in_at)
  where attendance_status = 'present';

drop trigger if exists smis_safety_training_plan_create_audit on public.smis_safety_training_plan;
create trigger smis_safety_training_plan_create_audit
before insert on public.smis_safety_training_plan
for each row execute function public.trg_set_create_time_and_by('true', 'true');
drop trigger if exists smis_safety_training_plan_update_audit on public.smis_safety_training_plan;
create trigger smis_safety_training_plan_update_audit
before update on public.smis_safety_training_plan
for each row execute function public.trg_set_update_time_and_by();

drop trigger if exists smis_safety_training_plan_participant_create_audit
  on public.smis_safety_training_plan_participant;
create trigger smis_safety_training_plan_participant_create_audit
before insert on public.smis_safety_training_plan_participant
for each row execute function public.trg_set_create_time_and_by('true', 'true');

drop trigger if exists smis_safety_training_record_create_audit on public.smis_safety_training_record;
create trigger smis_safety_training_record_create_audit
before insert on public.smis_safety_training_record
for each row execute function public.trg_set_create_time_and_by('true', 'true');
drop trigger if exists smis_safety_training_record_update_audit on public.smis_safety_training_record;
create trigger smis_safety_training_record_update_audit
before update on public.smis_safety_training_record
for each row execute function public.trg_set_update_time_and_by();

drop trigger if exists smis_safety_training_record_participant_create_audit
  on public.smis_safety_training_record_participant;
create trigger smis_safety_training_record_participant_create_audit
before insert on public.smis_safety_training_record_participant
for each row execute function public.trg_set_create_time_and_by('true', 'true');
drop trigger if exists smis_safety_training_record_participant_update_audit
  on public.smis_safety_training_record_participant;
create trigger smis_safety_training_record_participant_update_audit
before update on public.smis_safety_training_record_participant
for each row execute function public.trg_set_update_time_and_by();

alter table public.smis_safety_training_plan enable row level security;
alter table public.smis_safety_training_plan_participant enable row level security;
alter table public.smis_safety_training_record enable row level security;
alter table public.smis_safety_training_record_participant enable row level security;

do $policy$
declare
  v_table text;
  v_operation text;
begin
  foreach v_table in array array[
    'smis_safety_training_plan',
    'smis_safety_training_plan_participant',
    'smis_safety_training_record',
    'smis_safety_training_record_participant'
  ] loop
    foreach v_operation in array array['select', 'insert', 'update', 'delete'] loop
      execute format('drop policy if exists %I on public.%I', v_table || '_tenant_' || v_operation, v_table);
      if v_operation = 'select' then
        execute format(
          'create policy %I on public.%I for select to authenticated using ((select app_private.is_platform_super()) or tenant_id = (select app_private.current_user_tenant_id()))',
          v_table || '_tenant_select', v_table
        );
      elsif v_operation = 'insert' then
        execute format(
          'create policy %I on public.%I for insert to authenticated with check ((select app_private.is_platform_super()) or tenant_id = (select app_private.current_user_tenant_id()))',
          v_table || '_tenant_insert', v_table
        );
      elsif v_operation = 'update' then
        execute format(
          'create policy %I on public.%I for update to authenticated using ((select app_private.is_platform_super()) or tenant_id = (select app_private.current_user_tenant_id())) with check ((select app_private.is_platform_super()) or tenant_id = (select app_private.current_user_tenant_id()))',
          v_table || '_tenant_update', v_table
        );
      else
        execute format(
          'create policy %I on public.%I for delete to authenticated using ((select app_private.is_platform_super()) or tenant_id = (select app_private.current_user_tenant_id()))',
          v_table || '_tenant_delete', v_table
        );
      end if;
    end loop;
  end loop;
end;
$policy$;

revoke all on table public.smis_safety_training_plan from anon;
revoke all on table public.smis_safety_training_plan_participant from anon;
revoke all on table public.smis_safety_training_record from anon;
revoke all on table public.smis_safety_training_record_participant from anon;
grant select, insert, update, delete on table public.smis_safety_training_plan to authenticated;
grant select, insert, update, delete on table public.smis_safety_training_plan_participant to authenticated;
grant select, insert, update, delete on table public.smis_safety_training_record to authenticated;
grant select, insert, update, delete on table public.smis_safety_training_record_participant to authenticated;

with parent as (
  select id, tenant_id
  from public.sys_dict_type
  where code = 'smisSafetyProduction'
)
insert into public.sys_dict_type (
  id, name, code, status, create_by, create_time, update_by, update_time,
  remark, tenant_id, parent_id, node_type, sort
)
select
  gen_random_uuid(), '培训管理', 'smisTrainingManagement', '1',
  '624944977@qq.com', now(), '624944977@qq.com', now(),
  '安全培训计划、实施记录、签到与统计相关字典。', parent.tenant_id,
  parent.id, 'directory', 90
from parent
where not exists (
  select 1 from public.sys_dict_type existing where existing.code = 'smisTrainingManagement'
);

with dictionary_parent as (
  select id, tenant_id from public.sys_dict_type where code = 'smisTrainingManagement'
), dictionary(name, code, remark, sort) as (
  values
    ('安全培训计划状态', 'smisSafetyTrainingPlanStatus', '计划发布与实施闭环状态。', 1),
    ('安全培训执行状态', 'smisSafetyTrainingExecutionStatus', '按计划日期和记录提交情况实时计算。', 2),
    ('安全培训预警状态', 'smisSafetyTrainingWarningStatus', '计划人工或业务预警标识。', 3),
    ('安全培训类别', 'smisSafetyTrainingCategory', '入职、年度、专项、转岗和临时培训。', 4),
    ('安全培训类型', 'smisSafetyTrainingType', '安全教育、专项、应急、合规及其他培训。', 5),
    ('安全培训形式', 'smisSafetyTrainingForm', '集中讲授、现场实操、线上、外训和混合培训。', 6),
    ('安全培训级别', 'smisSafetyTrainingLevel', '公司、部门、作业区和班组级培训。', 7),
    ('培训考核方式', 'smisSafetyTrainingAssessmentMethod', '不考核、笔试、实操和综合考核。', 8),
    ('培训签到状态', 'smisSafetyTrainingAttendanceStatus', '待签到、已签到、缺席和请假。', 9),
    ('培训签到方式', 'smisSafetyTrainingSignMethod', '手工、二维码和导入签到。', 10),
    ('培训考核结果', 'smisSafetyTrainingAssessmentResult', '未考核、通过和未通过。', 11),
    ('安全培训记录状态', 'smisSafetyTrainingRecordStatus', '记录草稿与正式提交状态。', 12)
)
insert into public.sys_dict_type (
  id, name, code, status, create_by, create_time, update_by, update_time,
  remark, tenant_id, parent_id, node_type, sort
)
select
  gen_random_uuid(), dictionary.name, dictionary.code, '1',
  '624944977@qq.com', now(), '624944977@qq.com', now(), dictionary.remark,
  parent.tenant_id, parent.id, 'dictionary', dictionary.sort
from dictionary_parent parent
cross join dictionary
where not exists (
  select 1 from public.sys_dict_type existing where existing.code = dictionary.code
);

with dictionary_value(dict_code, value, label, sort, tag_type) as (
  values
    ('smisSafetyTrainingPlanStatus', 'draft', '草稿', 1, 'info'),
    ('smisSafetyTrainingPlanStatus', 'published', '已发布', 2, 'primary'),
    ('smisSafetyTrainingPlanStatus', 'completed', '已完成', 3, 'success'),
    ('smisSafetyTrainingPlanStatus', 'cancelled', '已取消', 4, 'danger'),
    ('smisSafetyTrainingExecutionStatus', 'not_started', '未开始', 1, 'info'),
    ('smisSafetyTrainingExecutionStatus', 'in_progress', '进行中', 2, 'warning'),
    ('smisSafetyTrainingExecutionStatus', 'ended', '已结束', 3, 'success'),
    ('smisSafetyTrainingWarningStatus', 'normal', '正常', 1, 'success'),
    ('smisSafetyTrainingWarningStatus', 'warning', '预警', 2, 'warning'),
    ('smisSafetyTrainingCategory', 'new_employee', '新员工入职培训', 1, null),
    ('smisSafetyTrainingCategory', 'annual', '年度再培训', 2, null),
    ('smisSafetyTrainingCategory', 'special', '专项培训', 3, 'primary'),
    ('smisSafetyTrainingCategory', 'transfer', '转岗复工培训', 4, 'warning'),
    ('smisSafetyTrainingCategory', 'temporary', '临时培训', 5, 'info'),
    ('smisSafetyTrainingType', 'safety_education', '安全教育培训', 1, null),
    ('smisSafetyTrainingType', 'special_training', '专项安全培训', 2, 'primary'),
    ('smisSafetyTrainingType', 'emergency', '应急能力培训', 3, 'warning'),
    ('smisSafetyTrainingType', 'compliance', '法规制度培训', 4, 'success'),
    ('smisSafetyTrainingType', 'other', '其他培训', 5, 'info'),
    ('smisSafetyTrainingForm', 'centralized_lecture', '集中讲授', 1, null),
    ('smisSafetyTrainingForm', 'onsite_practice', '现场实操', 2, 'primary'),
    ('smisSafetyTrainingForm', 'online', '线上培训', 3, 'info'),
    ('smisSafetyTrainingForm', 'external', '外部培训', 4, 'warning'),
    ('smisSafetyTrainingForm', 'blended', '混合培训', 5, 'success'),
    ('smisSafetyTrainingLevel', 'company', '公司级', 1, 'primary'),
    ('smisSafetyTrainingLevel', 'department', '部门级', 2, null),
    ('smisSafetyTrainingLevel', 'area', '作业区级', 3, null),
    ('smisSafetyTrainingLevel', 'team', '班组级', 4, 'info'),
    ('smisSafetyTrainingAssessmentMethod', 'none', '不考核', 1, 'info'),
    ('smisSafetyTrainingAssessmentMethod', 'written', '笔试', 2, null),
    ('smisSafetyTrainingAssessmentMethod', 'practical', '实操', 3, 'primary'),
    ('smisSafetyTrainingAssessmentMethod', 'comprehensive', '综合考核', 4, 'success'),
    ('smisSafetyTrainingAttendanceStatus', 'pending', '待签到', 1, 'info'),
    ('smisSafetyTrainingAttendanceStatus', 'present', '已签到', 2, 'success'),
    ('smisSafetyTrainingAttendanceStatus', 'absent', '缺席', 3, 'danger'),
    ('smisSafetyTrainingAttendanceStatus', 'leave', '请假', 4, 'warning'),
    ('smisSafetyTrainingSignMethod', 'manual', '手工签到', 1, null),
    ('smisSafetyTrainingSignMethod', 'qrcode', '二维码签到', 2, 'primary'),
    ('smisSafetyTrainingSignMethod', 'import', '批量导入', 3, 'info'),
    ('smisSafetyTrainingAssessmentResult', 'not_assessed', '未考核', 1, 'info'),
    ('smisSafetyTrainingAssessmentResult', 'pass', '通过', 2, 'success'),
    ('smisSafetyTrainingAssessmentResult', 'fail', '未通过', 3, 'danger'),
    ('smisSafetyTrainingRecordStatus', 'draft', '草稿', 1, 'info'),
    ('smisSafetyTrainingRecordStatus', 'submitted', '已提交', 2, 'success')
)
insert into public.sys_dictionary (
  id, type_id, code, status, create_by, create_time, update_by, update_time,
  value, label, sort, tenant_id, tag_type
)
select
  gen_random_uuid(), type.id, value.dict_code || '_' || value.value, '1',
  '624944977@qq.com', now(), '624944977@qq.com', now(),
  value.value, value.label, value.sort, type.tenant_id, value.tag_type
from dictionary_value value
join public.sys_dict_type type on type.code = value.dict_code
where not exists (
  select 1 from public.sys_dictionary existing
  where existing.type_id = type.id and existing.value = value.value
);

with button_seed(page_name, action, title, sort) as (
  values
    ('SmisSafetyTrainingPlan', 'View', '查看安全培训计划', 1),
    ('SmisSafetyTrainingPlan', 'Add', '新增安全培训计划', 2),
    ('SmisSafetyTrainingPlan', 'Copy', '复制并新增安全培训计划', 3),
    ('SmisSafetyTrainingPlan', 'Edit', '编辑安全培训计划', 4),
    ('SmisSafetyTrainingPlan', 'Delete', '删除安全培训计划', 5),
    ('SmisSafetyTrainingPlan', 'Publish', '发布安全培训计划', 6),
    ('SmisSafetyTrainingPlan', 'CreateRecord', '创建安全培训记录', 7),
    ('SmisSafetyTrainingPlan', 'Export', '导出安全培训计划', 8),
    ('SmisSafetyTrainingRecord', 'View', '查看安全培训记录', 1),
    ('SmisSafetyTrainingRecord', 'Add', '新增安全培训记录', 2),
    ('SmisSafetyTrainingRecord', 'Edit', '编辑安全培训记录', 3),
    ('SmisSafetyTrainingRecord', 'Delete', '删除安全培训记录', 4),
    ('SmisSafetyTrainingRecord', 'Submit', '提交安全培训记录', 5),
    ('SmisSafetyTrainingRecord', 'Export', '导出安全培训记录', 7),
    ('SmisTrainingStatisticsReport', 'View', '查看培训统计报表', 1),
    ('SmisTrainingStatisticsReport', 'Export', '导出培训统计报表', 2)
)
insert into public.sys_menu (
  id, parent_id, name, path, component, meta, sort,
  create_by, create_time, update_by, update_time, type, app_code
)
select
  gen_random_uuid(), page.id, seed.page_name || ':' || seed.action, '', null,
  jsonb_build_object(
    'icon', '', 'roles', jsonb_build_array(), 'title', seed.title,
    'is_hide', true, 'is_enable', true
  ),
  seed.sort, '624944977@qq.com', now(), '624944977@qq.com', now(),
  'button', page.app_code
from button_seed seed
join public.sys_menu page on page.name = seed.page_name
where not exists (
  select 1 from public.sys_menu existing
  where existing.parent_id = page.id and existing.name = seed.page_name || ':' || seed.action
);

insert into public.sys_role_menu (
  id, role_id, menu_id, tenant_id, permission,
  create_by, create_time, update_by, update_time
)
select
  gen_random_uuid(), assignment.role_id, button.id, assignment.tenant_id,
  '{}'::jsonb, '624944977@qq.com', now(), '624944977@qq.com', now()
from public.sys_role_menu assignment
join public.sys_menu page on page.id = assignment.menu_id
  and page.name in (
    'SmisSafetyTrainingPlan', 'SmisSafetyTrainingRecord', 'SmisTrainingStatisticsReport'
  )
join public.sys_menu button on button.parent_id = page.id and button.type = 'button'
where not exists (
  select 1 from public.sys_role_menu existing
  where existing.role_id = assignment.role_id
    and existing.menu_id = button.id
    and existing.tenant_id = assignment.tenant_id
);

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform'
), scene(rule_key, rule_name, field_label, menu_name, target_table, target_column, template, remark) as (
  values
    (
      'smis.safety_training_plan', '安全培训计划编号', '计划编号',
      'SmisSafetyTrainingPlan', 'smis_safety_training_plan', 'plan_no',
      'PX{YYYY}{MM}-{SEQ:4}', '安全培训计划编号按月重置四位流水'
    ),
    (
      'smis.safety_training_record', '安全培训记录单号', '培训记录单号',
      'SmisSafetyTrainingRecord', 'smis_safety_training_record', 'record_no',
      'SJ{YYYY}{MM}-{SEQ:4}', '安全培训记录单号按月重置四位流水'
    )
)
insert into public.sys_document_number_scene (
  rule_key, rule_name, field_label, category, menu_id, target_table, target_column,
  default_template, default_reset_cycle, manual_required, enabled, remark,
  create_by, create_time, update_by, update_time, tenant_id
)
select
  scene.rule_key, scene.rule_name, scene.field_label, 'business_document', page.id,
  scene.target_table, scene.target_column, scene.template, 'month', false, true,
  scene.remark, 'number-engine', now(), 'number-engine', now(), tenant.id
from scene
join public.sys_menu page on page.name = scene.menu_name
cross join platform_tenant tenant
where not exists (
  select 1 from public.sys_document_number_scene existing where existing.rule_key = scene.rule_key
);

with scene as (
  select * from public.sys_document_number_scene
  where rule_key in ('smis.safety_training_plan', 'smis.safety_training_record')
)
insert into public.sys_document_number_rule (
  tenant_id, rule_key, rule_name, category, target_table, target_column,
  auto_enabled, template, reset_cycle, sequence_start, timezone, rule_version,
  manual_required, builtin, enabled, remark, create_by, create_time, update_by, update_time
)
select
  tenant.id, scene.rule_key, scene.rule_name, scene.category, scene.target_table,
  scene.target_column, true, scene.default_template, scene.default_reset_cycle,
  1, 'Asia/Shanghai', 1, scene.manual_required, true, true, scene.remark,
  'number-engine', now(), 'number-engine', now()
from public.sys_tenant tenant
cross join scene
where not exists (
  select 1 from public.sys_document_number_rule existing
  where existing.tenant_id = tenant.id and existing.rule_key = scene.rule_key
);

create or replace function public.smis_list_safety_training_plans_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_status text default null,
  p_execution_status text default null,
  p_training_category text default null,
  p_organization_id uuid default null,
  p_start_at timestamptz default null,
  p_end_at timestamptz default null,
  p_warning_status text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant uuid;
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_to integer := greatest(coalesce(p_to, 19), greatest(coalesce(p_from, 0), 0));
begin
  if auth.uid() is null then raise exception '登录已失效，请重新登录' using errcode = '42501'; end if;
  if not app_private.has_permission('SmisSafetyTrainingPlan:View') then
    raise exception '没有查看安全培训计划的权限' using errcode = '42501';
  end if;
  v_tenant := app_private.current_user_tenant_id();

  return (
    with recursive org_scope as (
      select organization.id
      from public.sys_organization organization
      where organization.tenant_id = v_tenant and organization.id = p_organization_id
      union all
      select child.id
      from public.sys_organization child
      join org_scope parent on parent.id = child.parent_id
      where child.tenant_id = v_tenant
    ), plan_base as (
      select
        plan.*,
        organizer.organization_name as organizer_organization_name,
        target.organization_name as target_organization_name,
        responsible.employee_no as responsible_employee_no,
        responsible.employee_name as responsible_employee_name,
        case
          when plan.status in ('completed', 'cancelled') or plan.planned_end_at < now() then 'ended'
          when plan.planned_start_at <= now() and plan.planned_end_at >= now() then 'in_progress'
          else 'not_started'
        end as execution_status,
        record.id as record_id,
        record.record_no,
        record.status as record_status,
        (select count(*)::integer from public.smis_safety_training_plan_participant participant
          where participant.tenant_id = v_tenant and participant.training_plan_id = plan.id) as participant_count
      from public.smis_safety_training_plan plan
      join public.sys_organization organizer
        on organizer.id = plan.organizer_organization_id and organizer.tenant_id = plan.tenant_id
      left join public.sys_organization target
        on target.id = plan.target_organization_id and target.tenant_id = plan.tenant_id
      left join public.hr_employee responsible
        on responsible.id = plan.responsible_employee_id and responsible.tenant_id = plan.tenant_id
      left join public.smis_safety_training_record record
        on record.training_plan_id = plan.id and record.tenant_id = plan.tenant_id
      where plan.tenant_id = v_tenant
    ), filtered as (
      select * from plan_base plan
      where (
        nullif(btrim(coalesce(p_keyword, '')), '') is null
        or plan.plan_no ilike '%' || btrim(p_keyword) || '%'
        or plan.subject ilike '%' || btrim(p_keyword) || '%'
        or coalesce(plan.instructor_name, '') ilike '%' || btrim(p_keyword) || '%'
      )
        and (p_status is null or plan.status = p_status)
        and (p_execution_status is null or plan.execution_status = p_execution_status)
        and (p_training_category is null or plan.training_category = p_training_category)
        and (p_warning_status is null or plan.warning_status = p_warning_status)
        and (p_start_at is null or plan.planned_end_at >= p_start_at)
        and (p_end_at is null or plan.planned_start_at <= p_end_at)
        and (
          p_organization_id is null
          or plan.organizer_organization_id in (select id from org_scope)
          or plan.target_organization_id in (select id from org_scope)
        )
    ), page as (
      select * from filtered
      order by planned_start_at desc, create_time desc
      offset v_from limit v_to - v_from + 1
    )
    select jsonb_build_object(
      'records', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', plan.id,
          'tenantId', plan.tenant_id,
          'planNo', plan.plan_no,
          'subject', plan.subject,
          'trainingCategory', plan.training_category,
          'trainingType', plan.training_type,
          'trainingForm', plan.training_form,
          'trainingLevel', plan.training_level,
          'organizerOrganizationId', plan.organizer_organization_id,
          'organizerOrganizationName', plan.organizer_organization_name,
          'targetOrganizationId', plan.target_organization_id,
          'targetOrganizationName', plan.target_organization_name,
          'responsibleEmployeeId', plan.responsible_employee_id,
          'responsibleEmployeeNo', plan.responsible_employee_no,
          'responsibleEmployeeName', plan.responsible_employee_name,
          'instructorName', plan.instructor_name,
          'plannedStartAt', plan.planned_start_at,
          'plannedEndAt', plan.planned_end_at,
          'location', plan.location,
          'content', plan.content,
          'requirements', plan.requirements,
          'trainingHours', plan.training_hours,
          'assessmentMethod', plan.assessment_method,
          'warningStatus', plan.warning_status,
          'status', plan.status,
          'executionStatus', plan.execution_status,
          'attachmentUrls', to_jsonb(plan.attachment_urls),
          'remark', plan.remark,
          'participantCount', plan.participant_count,
          'participants', coalesce((
            select jsonb_agg(jsonb_build_object(
              'employeeId', participant.employee_id,
              'employeeNo', participant.employee_no,
              'employeeName', participant.employee_name,
              'organizationId', participant.organization_id,
              'organizationName', participant.organization_name,
              'jobTitle', participant.job_title,
              'phone', participant.phone
            ) order by participant.sort, participant.employee_name)
            from public.smis_safety_training_plan_participant participant
            where participant.tenant_id = v_tenant and participant.training_plan_id = plan.id
          ), '[]'::jsonb),
          'recordId', plan.record_id,
          'recordNo', plan.record_no,
          'recordStatus', plan.record_status,
          'createBy', plan.create_by,
          'createTime', plan.create_time,
          'updateBy', plan.update_by,
          'updateTime', plan.update_time
        ) order by plan.planned_start_at desc, plan.create_time desc)
        from page plan
      ), '[]'::jsonb),
      'total', (select count(*) from filtered),
      'overview', jsonb_build_object(
        'total', (select count(*) from plan_base),
        'draft', (select count(*) from plan_base where status = 'draft'),
        'published', (select count(*) from plan_base where status = 'published'),
        'completed', (select count(*) from plan_base where status = 'completed'),
        'warning', (select count(*) from plan_base where warning_status = 'warning'
          or (status = 'published' and planned_end_at < now()))
      ),
      'organizations', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', organization.id,
          'parentId', organization.parent_id,
          'organizationCode', organization.organization_code,
          'organizationName', organization.organization_name,
          'sort', organization.sort
        ) order by organization.sort, organization.organization_name)
        from public.sys_organization organization
        where organization.tenant_id = v_tenant and organization.status = '1'
      ), '[]'::jsonb)
    )
  );
end;
$function$;

revoke all on function public.smis_list_safety_training_plans_secure(
  integer, integer, text, text, text, text, uuid, timestamptz, timestamptz, text
) from public, anon;
grant execute on function public.smis_list_safety_training_plans_secure(
  integer, integer, text, text, text, text, uuid, timestamptz, timestamptz, text
) to authenticated;

create or replace function public.smis_save_safety_training_plan_secure(
  p_id uuid,
  p_payload jsonb,
  p_publish boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant uuid;
  v_id uuid := p_id;
  v_status text;
  v_participant_ids jsonb := coalesce(p_payload -> 'participant_ids', '[]'::jsonb);
  v_start timestamptz;
  v_end timestamptz;
  v_subject text := btrim(coalesce(p_payload ->> 'subject', ''));
  v_content text := btrim(coalesce(p_payload ->> 'content', ''));
begin
  if auth.uid() is null then raise exception '登录已失效，请重新登录' using errcode = '42501'; end if;
  if p_id is null and not app_private.has_permission('SmisSafetyTrainingPlan:Add') then
    raise exception '没有新增安全培训计划的权限' using errcode = '42501';
  end if;
  if p_id is not null and not app_private.has_permission('SmisSafetyTrainingPlan:Edit') then
    raise exception '没有编辑安全培训计划的权限' using errcode = '42501';
  end if;
  if p_publish and not app_private.has_permission('SmisSafetyTrainingPlan:Publish') then
    raise exception '没有发布安全培训计划的权限' using errcode = '42501';
  end if;
  v_tenant := app_private.current_user_tenant_id();
  if jsonb_typeof(v_participant_ids) <> 'array' then
    raise exception '参训人员数据格式不正确';
  end if;
  v_start := nullif(p_payload ->> 'planned_start_at', '')::timestamptz;
  v_end := nullif(p_payload ->> 'planned_end_at', '')::timestamptz;
  if v_subject = '' then raise exception '请输入培训主题'; end if;
  if v_content = '' then raise exception '请输入培训内容'; end if;
  if v_start is null or v_end is null or v_end < v_start then
    raise exception '培训结束时间不能早于开始时间';
  end if;
  if not exists (
    select 1 from public.sys_organization organization
    where organization.id = nullif(p_payload ->> 'organizer_organization_id', '')::uuid
      and organization.tenant_id = v_tenant and organization.status = '1'
  ) then raise exception '请选择当前租户内有效的组织单位'; end if;
  if p_publish and jsonb_array_length(v_participant_ids) = 0 then
    raise exception '发布培训计划前至少选择一名参训人员';
  end if;

  if p_id is null then
    insert into public.smis_safety_training_plan (
      tenant_id, plan_no, subject, training_category, training_type, training_form,
      training_level, organizer_organization_id, target_organization_id,
      responsible_employee_id, instructor_name, planned_start_at, planned_end_at,
      location, content, requirements, training_hours, assessment_method,
      warning_status, status, attachment_urls, remark
    ) values (
      v_tenant,
      app_private.next_document_number('smis.safety_training_plan', v_tenant),
      v_subject,
      p_payload ->> 'training_category',
      p_payload ->> 'training_type',
      p_payload ->> 'training_form',
      p_payload ->> 'training_level',
      (p_payload ->> 'organizer_organization_id')::uuid,
      nullif(p_payload ->> 'target_organization_id', '')::uuid,
      nullif(p_payload ->> 'responsible_employee_id', '')::uuid,
      nullif(btrim(coalesce(p_payload ->> 'instructor_name', '')), ''),
      v_start, v_end,
      nullif(btrim(coalesce(p_payload ->> 'location', '')), ''),
      v_content,
      nullif(btrim(coalesce(p_payload ->> 'requirements', '')), ''),
      coalesce(nullif(p_payload ->> 'training_hours', '')::numeric, 0),
      coalesce(nullif(p_payload ->> 'assessment_method', ''), 'none'),
      coalesce(nullif(p_payload ->> 'warning_status', ''), 'normal'),
      case when p_publish then 'published' else 'draft' end,
      coalesce(array(select jsonb_array_elements_text(coalesce(p_payload -> 'attachment_urls', '[]'::jsonb))), '{}'),
      nullif(btrim(coalesce(p_payload ->> 'remark', '')), '')
    ) returning id into v_id;
  else
    select status into v_status
    from public.smis_safety_training_plan
    where id = p_id and tenant_id = v_tenant for update;
    if not found then raise exception '培训计划不存在或不在当前租户'; end if;
    if v_status <> 'draft' then raise exception '仅草稿计划允许编辑'; end if;
    update public.smis_safety_training_plan set
      subject = v_subject,
      training_category = p_payload ->> 'training_category',
      training_type = p_payload ->> 'training_type',
      training_form = p_payload ->> 'training_form',
      training_level = p_payload ->> 'training_level',
      organizer_organization_id = (p_payload ->> 'organizer_organization_id')::uuid,
      target_organization_id = nullif(p_payload ->> 'target_organization_id', '')::uuid,
      responsible_employee_id = nullif(p_payload ->> 'responsible_employee_id', '')::uuid,
      instructor_name = nullif(btrim(coalesce(p_payload ->> 'instructor_name', '')), ''),
      planned_start_at = v_start,
      planned_end_at = v_end,
      location = nullif(btrim(coalesce(p_payload ->> 'location', '')), ''),
      content = v_content,
      requirements = nullif(btrim(coalesce(p_payload ->> 'requirements', '')), ''),
      training_hours = coalesce(nullif(p_payload ->> 'training_hours', '')::numeric, 0),
      assessment_method = coalesce(nullif(p_payload ->> 'assessment_method', ''), 'none'),
      warning_status = coalesce(nullif(p_payload ->> 'warning_status', ''), 'normal'),
      status = case when p_publish then 'published' else 'draft' end,
      attachment_urls = coalesce(array(select jsonb_array_elements_text(coalesce(p_payload -> 'attachment_urls', '[]'::jsonb))), '{}'),
      remark = nullif(btrim(coalesce(p_payload ->> 'remark', '')), '')
    where id = v_id and tenant_id = v_tenant;
    delete from public.smis_safety_training_plan_participant
    where tenant_id = v_tenant and training_plan_id = v_id;
  end if;

  insert into public.smis_safety_training_plan_participant (
    tenant_id, training_plan_id, employee_id, employee_no, employee_name,
    organization_id, organization_name, job_title, phone, sort
  )
  select
    v_tenant, v_id, employee.id, employee.employee_no, employee.employee_name,
    employee.organization_id, organization.organization_name,
    employee.job_title, employee.phone, selected.ordinality::integer
  from jsonb_array_elements_text(v_participant_ids) with ordinality selected(employee_id, ordinality)
  join public.hr_employee employee
    on employee.id = selected.employee_id::uuid and employee.tenant_id = v_tenant
  left join public.sys_organization organization
    on organization.id = employee.organization_id and organization.tenant_id = employee.tenant_id
  on conflict (tenant_id, training_plan_id, employee_id) do nothing;

  if p_publish and (
    select count(*) from public.smis_safety_training_plan_participant
    where tenant_id = v_tenant and training_plan_id = v_id
  ) <> jsonb_array_length(v_participant_ids) then
    raise exception '参训人员中存在无效或跨租户员工，请重新选择';
  end if;
  return v_id;
end;
$function$;

revoke all on function public.smis_save_safety_training_plan_secure(uuid, jsonb, boolean)
  from public, anon;
grant execute on function public.smis_save_safety_training_plan_secure(uuid, jsonb, boolean)
  to authenticated;

create or replace function public.smis_delete_safety_training_plans_secure(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant uuid;
  v_deleted integer;
begin
  if auth.uid() is null then raise exception '登录已失效，请重新登录' using errcode = '42501'; end if;
  if not app_private.has_permission('SmisSafetyTrainingPlan:Delete') then
    raise exception '没有删除安全培训计划的权限' using errcode = '42501';
  end if;
  v_tenant := app_private.current_user_tenant_id();
  if exists (
    select 1 from public.smis_safety_training_plan
    where id = any(coalesce(p_ids, '{}')) and tenant_id = v_tenant and status <> 'draft'
  ) then raise exception '仅草稿培训计划允许删除'; end if;
  delete from public.smis_safety_training_plan
  where id = any(coalesce(p_ids, '{}')) and tenant_id = v_tenant and status = 'draft';
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$function$;

revoke all on function public.smis_delete_safety_training_plans_secure(uuid[]) from public, anon;
grant execute on function public.smis_delete_safety_training_plans_secure(uuid[]) to authenticated;

create or replace function public.smis_list_safety_training_records_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_status text default null,
  p_start_at timestamptz default null,
  p_end_at timestamptz default null,
  p_organization_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant uuid;
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_to integer := greatest(coalesce(p_to, 19), greatest(coalesce(p_from, 0), 0));
begin
  if auth.uid() is null then raise exception '登录已失效，请重新登录' using errcode = '42501'; end if;
  if not app_private.has_permission('SmisSafetyTrainingRecord:View') then
    raise exception '没有查看安全培训记录的权限' using errcode = '42501';
  end if;
  v_tenant := app_private.current_user_tenant_id();
  return (
    with recursive org_scope as (
      select organization.id from public.sys_organization organization
      where organization.tenant_id = v_tenant and organization.id = p_organization_id
      union all
      select child.id from public.sys_organization child
      join org_scope parent on parent.id = child.parent_id
      where child.tenant_id = v_tenant
    ), record_base as (
      select
        record.*,
        plan.plan_no,
        plan.subject,
        plan.training_category,
        plan.training_type,
        plan.training_form,
        plan.training_level,
        plan.organizer_organization_id,
        organizer.organization_name as organizer_organization_name,
        plan.target_organization_id,
        target.organization_name as target_organization_name,
        plan.assessment_method,
        (select count(*)::integer from public.smis_safety_training_record_participant participant
          where participant.tenant_id = v_tenant and participant.training_record_id = record.id) as participant_count,
        (select count(*)::integer from public.smis_safety_training_record_participant participant
          where participant.tenant_id = v_tenant and participant.training_record_id = record.id
            and participant.attendance_status = 'present') as present_count
      from public.smis_safety_training_record record
      join public.smis_safety_training_plan plan
        on plan.id = record.training_plan_id and plan.tenant_id = record.tenant_id
      join public.sys_organization organizer
        on organizer.id = plan.organizer_organization_id and organizer.tenant_id = plan.tenant_id
      left join public.sys_organization target
        on target.id = plan.target_organization_id and target.tenant_id = plan.tenant_id
      where record.tenant_id = v_tenant
    ), filtered as (
      select * from record_base record
      where (
        nullif(btrim(coalesce(p_keyword, '')), '') is null
        or record.record_no ilike '%' || btrim(p_keyword) || '%'
        or record.plan_no ilike '%' || btrim(p_keyword) || '%'
        or record.subject ilike '%' || btrim(p_keyword) || '%'
      )
        and (p_status is null or record.status = p_status)
        and (p_start_at is null or coalesce(record.actual_end_at, record.actual_start_at) >= p_start_at)
        and (p_end_at is null or coalesce(record.actual_start_at, record.actual_end_at) <= p_end_at)
        and (
          p_organization_id is null
          or record.organizer_organization_id in (select id from org_scope)
          or record.target_organization_id in (select id from org_scope)
        )
    ), page as (
      select * from filtered
      order by coalesce(actual_start_at, create_time) desc, create_time desc
      offset v_from limit v_to - v_from + 1
    )
    select jsonb_build_object(
      'records', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', record.id,
          'tenantId', record.tenant_id,
          'trainingPlanId', record.training_plan_id,
          'recordNo', record.record_no,
          'planNo', record.plan_no,
          'subject', record.subject,
          'trainingCategory', record.training_category,
          'trainingType', record.training_type,
          'trainingForm', record.training_form,
          'trainingLevel', record.training_level,
          'organizerOrganizationId', record.organizer_organization_id,
          'organizerOrganizationName', record.organizer_organization_name,
          'targetOrganizationId', record.target_organization_id,
          'targetOrganizationName', record.target_organization_name,
          'assessmentMethod', record.assessment_method,
          'actualStartAt', record.actual_start_at,
          'actualEndAt', record.actual_end_at,
          'location', record.location,
          'instructorName', record.instructor_name,
          'lecturerName', record.lecturer_name,
          'trainingContent', record.training_content,
          'trainingHours', record.training_hours,
          'effectEvaluation', record.effect_evaluation,
          'attachmentUrls', to_jsonb(record.attachment_urls),
          'signInAttachmentUrls', to_jsonb(record.sign_in_attachment_urls),
          'status', record.status,
          'submittedAt', record.submitted_at,
          'submittedBy', record.submitted_by,
          'remark', record.remark,
          'participantCount', record.participant_count,
          'presentCount', record.present_count,
          'attendanceRate', case when record.participant_count = 0 then 0
            else round(record.present_count::numeric * 100 / record.participant_count, 2) end,
          'participants', coalesce((
            select jsonb_agg(jsonb_build_object(
              'employeeId', participant.employee_id,
              'employeeNo', participant.employee_no,
              'employeeName', participant.employee_name,
              'organizationId', participant.organization_id,
              'organizationName', participant.organization_name,
              'jobTitle', participant.job_title,
              'phone', participant.phone,
              'attendanceStatus', participant.attendance_status,
              'checkInAt', participant.check_in_at,
              'signMethod', participant.sign_method,
              'score', participant.score,
              'assessmentResult', participant.assessment_result,
              'remark', participant.remark
            ) order by participant.sort, participant.employee_name)
            from public.smis_safety_training_record_participant participant
            where participant.tenant_id = v_tenant and participant.training_record_id = record.id
          ), '[]'::jsonb),
          'createBy', record.create_by,
          'createTime', record.create_time,
          'updateBy', record.update_by,
          'updateTime', record.update_time
        ) order by coalesce(record.actual_start_at, record.create_time) desc)
        from page record
      ), '[]'::jsonb),
      'total', (select count(*) from filtered),
      'overview', jsonb_build_object(
        'total', (select count(*) from record_base),
        'draft', (select count(*) from record_base where status = 'draft'),
        'submitted', (select count(*) from record_base where status = 'submitted'),
        'participantCount', (select coalesce(sum(participant_count), 0) from record_base),
        'presentCount', (select coalesce(sum(present_count), 0) from record_base)
      ),
      'planOptions', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', plan.id,
          'planNo', plan.plan_no,
          'subject', plan.subject,
          'plannedStartAt', plan.planned_start_at,
          'plannedEndAt', plan.planned_end_at,
          'location', plan.location,
          'instructorName', plan.instructor_name,
          'trainingHours', plan.training_hours,
          'content', plan.content,
          'assessmentMethod', plan.assessment_method,
          'participants', coalesce((
            select jsonb_agg(jsonb_build_object(
              'employeeId', participant.employee_id,
              'employeeNo', participant.employee_no,
              'employeeName', participant.employee_name,
              'organizationId', participant.organization_id,
              'organizationName', participant.organization_name,
              'jobTitle', participant.job_title,
              'phone', participant.phone
            ) order by participant.sort, participant.employee_name)
            from public.smis_safety_training_plan_participant participant
            where participant.tenant_id = v_tenant and participant.training_plan_id = plan.id
          ), '[]'::jsonb)
        ) order by plan.planned_start_at desc, plan.plan_no)
        from public.smis_safety_training_plan plan
        where plan.tenant_id = v_tenant and plan.status = 'published'
          and not exists (
            select 1 from public.smis_safety_training_record existing
            where existing.tenant_id = v_tenant and existing.training_plan_id = plan.id
          )
      ), '[]'::jsonb),
      'organizations', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', organization.id, 'parentId', organization.parent_id,
          'organizationCode', organization.organization_code,
          'organizationName', organization.organization_name, 'sort', organization.sort
        ) order by organization.sort, organization.organization_name)
        from public.sys_organization organization
        where organization.tenant_id = v_tenant and organization.status = '1'
      ), '[]'::jsonb)
    )
  );
end;
$function$;

revoke all on function public.smis_list_safety_training_records_secure(
  integer, integer, text, text, timestamptz, timestamptz, uuid
) from public, anon;
grant execute on function public.smis_list_safety_training_records_secure(
  integer, integer, text, text, timestamptz, timestamptz, uuid
) to authenticated;

create or replace function public.smis_save_safety_training_record_secure(
  p_id uuid,
  p_payload jsonb,
  p_submit boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant uuid;
  v_id uuid := p_id;
  v_plan_id uuid := nullif(p_payload ->> 'training_plan_id', '')::uuid;
  v_record_status text;
  v_plan_status text;
  v_record_plan_id uuid;
  v_participants jsonb := coalesce(p_payload -> 'participants', '[]'::jsonb);
  v_actual_start timestamptz := nullif(p_payload ->> 'actual_start_at', '')::timestamptz;
  v_actual_end timestamptz := nullif(p_payload ->> 'actual_end_at', '')::timestamptz;
begin
  if auth.uid() is null then raise exception '登录已失效，请重新登录' using errcode = '42501'; end if;
  if p_id is null and not app_private.has_permission('SmisSafetyTrainingRecord:Add') then
    raise exception '没有新增安全培训记录的权限' using errcode = '42501';
  end if;
  if p_id is not null and not app_private.has_permission('SmisSafetyTrainingRecord:Edit') then
    raise exception '没有编辑安全培训记录的权限' using errcode = '42501';
  end if;
  if p_submit and not app_private.has_permission('SmisSafetyTrainingRecord:Submit') then
    raise exception '没有提交安全培训记录的权限' using errcode = '42501';
  end if;
  v_tenant := app_private.current_user_tenant_id();
  if v_plan_id is null then raise exception '请选择关联培训计划'; end if;
  if jsonb_typeof(v_participants) <> 'array' then raise exception '参训签到数据格式不正确'; end if;
  select status into v_plan_status
  from public.smis_safety_training_plan
  where id = v_plan_id and tenant_id = v_tenant for update;
  if not found then raise exception '关联培训计划不存在或不在当前租户'; end if;
  if p_id is null and v_plan_status <> 'published' then
    raise exception '仅已发布培训计划允许创建培训记录';
  end if;
  if v_actual_start is not null and v_actual_end is not null and v_actual_end < v_actual_start then
    raise exception '实际结束时间不能早于开始时间';
  end if;
  if p_submit and (v_actual_start is null or v_actual_end is null) then
    raise exception '提交前请填写实际培训起止时间';
  end if;
  if p_submit and jsonb_array_length(v_participants) = 0 then
    raise exception '提交前至少保留一名参训人员';
  end if;
  if p_submit and exists (
    select 1 from jsonb_array_elements(v_participants) participant
    where coalesce(participant ->> 'attendance_status', 'pending') = 'pending'
  ) then raise exception '提交前请完成全部参训人员的签到状态'; end if;
  if p_submit and exists (
    select 1 from jsonb_array_elements(v_participants) participant
    where participant ->> 'attendance_status' = 'present'
      and nullif(participant ->> 'check_in_at', '') is null
  ) then raise exception '已签到人员必须填写签到时间'; end if;

  if p_id is null then
    insert into public.smis_safety_training_record (
      tenant_id, training_plan_id, record_no, actual_start_at, actual_end_at,
      location, instructor_name, lecturer_name, training_content, training_hours,
      effect_evaluation, attachment_urls, sign_in_attachment_urls, status,
      submitted_at, submitted_by, remark
    ) values (
      v_tenant, v_plan_id,
      app_private.next_document_number('smis.safety_training_record', v_tenant),
      v_actual_start, v_actual_end,
      nullif(btrim(coalesce(p_payload ->> 'location', '')), ''),
      nullif(btrim(coalesce(p_payload ->> 'instructor_name', '')), ''),
      nullif(btrim(coalesce(p_payload ->> 'lecturer_name', '')), ''),
      nullif(btrim(coalesce(p_payload ->> 'training_content', '')), ''),
      coalesce(nullif(p_payload ->> 'training_hours', '')::numeric, 0),
      nullif(btrim(coalesce(p_payload ->> 'effect_evaluation', '')), ''),
      coalesce(array(select jsonb_array_elements_text(coalesce(p_payload -> 'attachment_urls', '[]'::jsonb))), '{}'),
      coalesce(array(select jsonb_array_elements_text(coalesce(p_payload -> 'sign_in_attachment_urls', '[]'::jsonb))), '{}'),
      case when p_submit then 'submitted' else 'draft' end,
      case when p_submit then now() else null end,
      case when p_submit then public.get_app_user_display_name() else null end,
      nullif(btrim(coalesce(p_payload ->> 'remark', '')), '')
    ) returning id into v_id;
  else
    select status, training_plan_id into v_record_status, v_record_plan_id
    from public.smis_safety_training_record
    where id = p_id and tenant_id = v_tenant for update;
    if not found then raise exception '培训记录不存在或不在当前租户'; end if;
    if v_record_plan_id <> v_plan_id then raise exception '已创建记录不允许更换关联培训计划'; end if;
    if v_record_status <> 'draft' then raise exception '已提交培训记录不允许修改'; end if;
    update public.smis_safety_training_record set
      actual_start_at = v_actual_start,
      actual_end_at = v_actual_end,
      location = nullif(btrim(coalesce(p_payload ->> 'location', '')), ''),
      instructor_name = nullif(btrim(coalesce(p_payload ->> 'instructor_name', '')), ''),
      lecturer_name = nullif(btrim(coalesce(p_payload ->> 'lecturer_name', '')), ''),
      training_content = nullif(btrim(coalesce(p_payload ->> 'training_content', '')), ''),
      training_hours = coalesce(nullif(p_payload ->> 'training_hours', '')::numeric, 0),
      effect_evaluation = nullif(btrim(coalesce(p_payload ->> 'effect_evaluation', '')), ''),
      attachment_urls = coalesce(array(select jsonb_array_elements_text(coalesce(p_payload -> 'attachment_urls', '[]'::jsonb))), '{}'),
      sign_in_attachment_urls = coalesce(array(select jsonb_array_elements_text(coalesce(p_payload -> 'sign_in_attachment_urls', '[]'::jsonb))), '{}'),
      status = case when p_submit then 'submitted' else 'draft' end,
      submitted_at = case when p_submit then now() else null end,
      submitted_by = case when p_submit then public.get_app_user_display_name() else null end,
      remark = nullif(btrim(coalesce(p_payload ->> 'remark', '')), '')
    where id = v_id and tenant_id = v_tenant;
    delete from public.smis_safety_training_record_participant
    where tenant_id = v_tenant and training_record_id = v_id;
  end if;

  insert into public.smis_safety_training_record_participant (
    tenant_id, training_record_id, employee_id, employee_no, employee_name,
    organization_id, organization_name, job_title, phone, attendance_status,
    check_in_at, sign_method, score, assessment_result, remark, sort
  )
  select
    v_tenant, v_id, employee.id, employee.employee_no, employee.employee_name,
    employee.organization_id, organization.organization_name, employee.job_title,
    employee.phone,
    coalesce(nullif(participant.value ->> 'attendance_status', ''), 'pending'),
    nullif(participant.value ->> 'check_in_at', '')::timestamptz,
    nullif(participant.value ->> 'sign_method', ''),
    nullif(participant.value ->> 'score', '')::numeric,
    coalesce(nullif(participant.value ->> 'assessment_result', ''), 'not_assessed'),
    nullif(btrim(coalesce(participant.value ->> 'remark', '')), ''),
    participant.ordinality::integer
  from jsonb_array_elements(v_participants) with ordinality participant(value, ordinality)
  join public.hr_employee employee
    on employee.id = (participant.value ->> 'employee_id')::uuid and employee.tenant_id = v_tenant
  left join public.sys_organization organization
    on organization.id = employee.organization_id and organization.tenant_id = employee.tenant_id
  on conflict (tenant_id, training_record_id, employee_id) do nothing;

  if p_submit and (
    select count(*) from public.smis_safety_training_record_participant
    where tenant_id = v_tenant and training_record_id = v_id
  ) <> jsonb_array_length(v_participants) then
    raise exception '签到人员中存在无效或跨租户员工，请重新选择';
  end if;
  if p_submit then
    update public.smis_safety_training_plan set status = 'completed'
    where id = v_plan_id and tenant_id = v_tenant and status = 'published';
  end if;
  return v_id;
end;
$function$;

revoke all on function public.smis_save_safety_training_record_secure(uuid, jsonb, boolean)
  from public, anon;
grant execute on function public.smis_save_safety_training_record_secure(uuid, jsonb, boolean)
  to authenticated;

create or replace function public.smis_delete_safety_training_records_secure(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant uuid;
  v_deleted integer;
begin
  if auth.uid() is null then raise exception '登录已失效，请重新登录' using errcode = '42501'; end if;
  if not app_private.has_permission('SmisSafetyTrainingRecord:Delete') then
    raise exception '没有删除安全培训记录的权限' using errcode = '42501';
  end if;
  v_tenant := app_private.current_user_tenant_id();
  if exists (
    select 1 from public.smis_safety_training_record
    where id = any(coalesce(p_ids, '{}')) and tenant_id = v_tenant and status <> 'draft'
  ) then raise exception '仅草稿培训记录允许删除'; end if;
  delete from public.smis_safety_training_record
  where id = any(coalesce(p_ids, '{}')) and tenant_id = v_tenant and status = 'draft';
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$function$;

revoke all on function public.smis_delete_safety_training_records_secure(uuid[]) from public, anon;
grant execute on function public.smis_delete_safety_training_records_secure(uuid[]) to authenticated;

create or replace function public.smis_safety_training_report_secure(
  p_start_date date default null,
  p_end_date date default null,
  p_organization_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant uuid;
  v_start date := coalesce(p_start_date, date_trunc('year', current_date)::date);
  v_end date := coalesce(p_end_date, current_date);
begin
  if auth.uid() is null then raise exception '登录已失效，请重新登录' using errcode = '42501'; end if;
  if not app_private.has_permission('SmisTrainingStatisticsReport:View') then
    raise exception '没有查看培训统计报表的权限' using errcode = '42501';
  end if;
  if v_end < v_start then raise exception '统计结束日期不能早于开始日期'; end if;
  v_tenant := app_private.current_user_tenant_id();
  return (
    with recursive org_scope as (
      select organization.id from public.sys_organization organization
      where organization.tenant_id = v_tenant and organization.id = p_organization_id
      union all
      select child.id from public.sys_organization child
      join org_scope parent on parent.id = child.parent_id
      where child.tenant_id = v_tenant
    ), scoped_plan as (
      select plan.*, organization.organization_name
      from public.smis_safety_training_plan plan
      join public.sys_organization organization
        on organization.id = plan.organizer_organization_id and organization.tenant_id = plan.tenant_id
      where plan.tenant_id = v_tenant
        and plan.planned_start_at::date <= v_end
        and plan.planned_end_at::date >= v_start
        and (
          p_organization_id is null
          or plan.organizer_organization_id in (select id from org_scope)
          or plan.target_organization_id in (select id from org_scope)
        )
    ), scoped_record as (
      select record.*, plan.organizer_organization_id, plan.organization_name,
        plan.training_category, plan.training_type, plan.training_form
      from public.smis_safety_training_record record
      join scoped_plan plan on plan.id = record.training_plan_id
      where record.status = 'submitted'
        and record.actual_start_at::date between v_start and v_end
    ), organization_stat as (
      select
        organization.id as organization_id,
        organization.organization_name,
        (select count(*)::integer from scoped_plan plan
          where plan.organizer_organization_id = organization.id) as plan_count,
        (select count(*)::integer from scoped_record record
          where record.organizer_organization_id = organization.id) as record_count,
        (select count(*)::integer
          from public.smis_safety_training_plan_participant participant
          join scoped_plan plan on plan.id = participant.training_plan_id
          where participant.tenant_id = v_tenant
            and plan.organizer_organization_id = organization.id) as planned_person_times,
        (select count(*)::integer
          from public.smis_safety_training_record_participant participant
          join scoped_record record on record.id = participant.training_record_id
          where participant.tenant_id = v_tenant
            and participant.attendance_status = 'present'
            and record.organizer_organization_id = organization.id) as actual_person_times,
        (select coalesce(sum(record.training_hours), 0)::numeric
          from scoped_record record
          where record.organizer_organization_id = organization.id) as training_hours
      from public.sys_organization organization
      where organization.tenant_id = v_tenant and organization.status = '1'
        and (p_organization_id is null or organization.id in (select id from org_scope))
        and (
          exists (select 1 from scoped_plan plan
            where plan.organizer_organization_id = organization.id)
          or exists (select 1 from scoped_record record
            where record.organizer_organization_id = organization.id)
        )
    ), monthly_trend as (
      select
        to_char(month.month_start, 'YYYY-MM') as month,
        (select count(*)::integer from scoped_plan plan
          where date_trunc('month', plan.planned_start_at) = month.month_start) as plan_count,
        (select count(*)::integer from scoped_record record
          where date_trunc('month', record.actual_start_at) = month.month_start) as record_count,
        (select count(*)::integer
          from public.smis_safety_training_record_participant participant
          join scoped_record record on record.id = participant.training_record_id
          where participant.tenant_id = v_tenant
            and participant.attendance_status = 'present'
            and date_trunc('month', record.actual_start_at) = month.month_start) as attendance_count,
        (select coalesce(sum(record.training_hours), 0)::numeric from scoped_record record
          where date_trunc('month', record.actual_start_at) = month.month_start) as training_hours
      from generate_series(
        date_trunc('month', v_start::timestamp),
        date_trunc('month', v_end::timestamp),
        interval '1 month'
      ) month(month_start)
      order by month.month_start
    ), category_stat as (
      select 'trainingCategory'::text as dimension, training_category as value,
        count(*)::integer as plan_count
      from scoped_plan group by training_category
      union all
      select 'trainingType', training_type, count(*)::integer
      from scoped_plan group by training_type
      union all
      select 'trainingForm', training_form, count(*)::integer
      from scoped_plan group by training_form
    ), attendance_stat as (
      select participant.attendance_status as value, count(*)::integer as count
      from scoped_record record
      join public.smis_safety_training_record_participant participant
        on participant.training_record_id = record.id and participant.tenant_id = v_tenant
      group by participant.attendance_status
    ), outstanding as (
      select plan.*
      from scoped_plan plan
      where plan.status = 'published'
        and not exists (
          select 1 from public.smis_safety_training_record record
          where record.tenant_id = v_tenant and record.training_plan_id = plan.id
            and record.status = 'submitted'
        )
      order by plan.planned_end_at, plan.plan_no
    ), overview as (
      select
        (select count(*)::integer from scoped_plan) as plan_count,
        (select count(*)::integer from scoped_plan where status = 'completed') as completed_plan_count,
        (select count(*)::integer from scoped_record) as record_count,
        (select count(*)::integer from public.smis_safety_training_plan_participant participant
          join scoped_plan plan on plan.id = participant.training_plan_id) as planned_person_times,
        (select count(*)::integer from public.smis_safety_training_record_participant participant
          join scoped_record record on record.id = participant.training_record_id
          where participant.attendance_status = 'present') as actual_person_times,
        (select coalesce(sum(training_hours), 0) from scoped_record) as training_hours,
        (select count(*)::integer from outstanding) as outstanding_count
    )
    select jsonb_build_object(
      'overview', (select jsonb_build_object(
        'planCount', plan_count,
        'completedPlanCount', completed_plan_count,
        'recordCount', record_count,
        'plannedPersonTimes', planned_person_times,
        'actualPersonTimes', actual_person_times,
        'trainingHours', training_hours,
        'outstandingCount', outstanding_count,
        'completionRate', case when plan_count = 0 then 0
          else round(completed_plan_count::numeric * 100 / plan_count, 2) end,
        'attendanceRate', case when planned_person_times = 0 then 0
          else round(actual_person_times::numeric * 100 / planned_person_times, 2) end
      ) from overview),
      'organizationStats', coalesce((
        select jsonb_agg(jsonb_build_object(
          'organizationId', stat.organization_id,
          'organizationName', stat.organization_name,
          'planCount', stat.plan_count,
          'recordCount', stat.record_count,
          'plannedPersonTimes', stat.planned_person_times,
          'actualPersonTimes', stat.actual_person_times,
          'trainingHours', stat.training_hours,
          'completionRate', case when stat.plan_count = 0 then 0
            else round(stat.record_count::numeric * 100 / stat.plan_count, 2) end,
          'attendanceRate', case when stat.planned_person_times = 0 then 0
            else round(stat.actual_person_times::numeric * 100 / stat.planned_person_times, 2) end
        ) order by stat.plan_count desc, stat.organization_name)
        from organization_stat stat
      ), '[]'::jsonb),
      'monthlyTrend', coalesce((
        select jsonb_agg(jsonb_build_object(
          'month', trend.month,
          'planCount', trend.plan_count,
          'recordCount', trend.record_count,
          'attendanceCount', trend.attendance_count,
          'trainingHours', trend.training_hours
        ) order by trend.month) from monthly_trend trend
      ), '[]'::jsonb),
      'categoryStats', coalesce((
        select jsonb_agg(jsonb_build_object(
          'dimension', stat.dimension, 'value', stat.value, 'planCount', stat.plan_count
        ) order by stat.dimension, stat.plan_count desc, stat.value)
        from category_stat stat
      ), '[]'::jsonb),
      'attendanceStats', coalesce((
        select jsonb_agg(jsonb_build_object('value', stat.value, 'count', stat.count)
          order by stat.count desc, stat.value) from attendance_stat stat
      ), '[]'::jsonb),
      'outstandingPlans', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', plan.id,
          'planNo', plan.plan_no,
          'subject', plan.subject,
          'organizationName', plan.organization_name,
          'plannedEndAt', plan.planned_end_at,
          'warningStatus', case when plan.planned_end_at < now() then 'warning' else plan.warning_status end,
          'participantCount', (select count(*) from public.smis_safety_training_plan_participant participant
            where participant.tenant_id = v_tenant and participant.training_plan_id = plan.id)
        ) order by plan.planned_end_at, plan.plan_no) from outstanding plan
      ), '[]'::jsonb),
      'organizationOptions', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', organization.id, 'parentId', organization.parent_id,
          'organizationCode', organization.organization_code,
          'organizationName', organization.organization_name, 'sort', organization.sort
        ) order by organization.sort, organization.organization_name)
        from public.sys_organization organization
        where organization.tenant_id = v_tenant and organization.status = '1'
      ), '[]'::jsonb)
    )
  );
end;
$function$;

revoke all on function public.smis_safety_training_report_secure(date, date, uuid)
  from public, anon;
grant execute on function public.smis_safety_training_report_secure(date, date, uuid)
  to authenticated;

commit;

;
