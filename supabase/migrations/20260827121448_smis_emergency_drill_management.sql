-- 应急演练计划、记录、人员快照与报表基础模型。

alter table public.smis_emergency_drill_plan
  drop constraint if exists smis_emergency_drill_plan_tenant_id_source_plan_id_status_key;

alter table public.smis_emergency_drill_plan
  add column if not exists plan_no text,
  add column if not exists compilation_organization_id uuid,
  add column if not exists drill_form text,
  add column if not exists responsible_employee_id uuid,
  add column if not exists plan_start_date date,
  add column if not exists plan_end_date date,
  add column if not exists drill_location text,
  add column if not exists drill_subject text,
  add column if not exists drill_purpose text,
  add column if not exists plan_level text,
  add column if not exists is_special_equipment_drill boolean not null default false,
  add column if not exists attachment_urls text[] not null default '{}',
  add column if not exists remark text;

update public.smis_emergency_drill_plan
set plan_end_date = coalesce(plan_end_date, planned_date),
    plan_start_date = coalesce(plan_start_date, planned_date),
    compilation_organization_id = coalesce(compilation_organization_id, applicable_organization_id),
    drill_form = coalesce(drill_form, 'onsite'),
    plan_level = coalesce(plan_level, app_private.smis_plan_level_for_organization(tenant_id, applicable_organization_id));

alter table public.smis_emergency_drill_plan
  alter column compilation_organization_id set not null,
  alter column drill_form set not null,
  alter column plan_level set not null;

do $$ begin
  alter table public.smis_emergency_drill_plan add constraint smis_emergency_drill_plan_id_tenant_key unique(id,tenant_id);
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.smis_emergency_drill_plan add constraint smis_emergency_drill_plan_compilation_org_fkey
    foreign key (tenant_id, compilation_organization_id) references public.sys_organization(tenant_id,id) on delete restrict;
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.smis_emergency_drill_plan add constraint smis_emergency_drill_plan_responsible_employee_fkey
    foreign key (responsible_employee_id, tenant_id) references public.hr_employee(id,tenant_id) on delete restrict;
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.smis_emergency_drill_plan add constraint smis_emergency_drill_plan_form_check
    check (drill_form in ('onsite','desktop'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.smis_emergency_drill_plan add constraint smis_emergency_drill_plan_category_check
    check (plan_category in ('comprehensive','onsite','special'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.smis_emergency_drill_plan add constraint smis_emergency_drill_plan_level_check
    check (plan_level in ('company','operation_department','operation_area','team'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.smis_emergency_drill_plan add constraint smis_emergency_drill_plan_dates_check
    check (plan_start_date is null or plan_end_date is null or plan_end_date >= plan_start_date);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.smis_emergency_drill_plan add constraint smis_emergency_drill_plan_text_length_check
    check (char_length(drill_name) <= 160 and (remark is null or char_length(remark) <= 2000));
exception when duplicate_object then null; end $$;

create unique index if not exists smis_emergency_drill_plan_tenant_no_uidx
  on public.smis_emergency_drill_plan(tenant_id,plan_no) where plan_no is not null;
create index if not exists smis_emergency_drill_plan_tenant_source_idx
  on public.smis_emergency_drill_plan(tenant_id,source_plan_id);
create index if not exists smis_emergency_drill_plan_tenant_due_idx
  on public.smis_emergency_drill_plan(tenant_id,status,plan_end_date);
create index if not exists smis_emergency_drill_plan_compilation_org_idx
  on public.smis_emergency_drill_plan(tenant_id,compilation_organization_id);
create index if not exists smis_emergency_drill_plan_responsible_idx
  on public.smis_emergency_drill_plan(tenant_id,responsible_employee_id) where responsible_employee_id is not null;

create table if not exists public.smis_emergency_drill_plan_trainee (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id() references public.sys_tenant(id) on delete restrict,
  drill_plan_id uuid not null,
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
  constraint smis_emergency_drill_plan_trainee_plan_fkey foreign key(drill_plan_id,tenant_id)
    references public.smis_emergency_drill_plan(id,tenant_id) on delete cascade,
  constraint smis_emergency_drill_plan_trainee_employee_fkey foreign key(employee_id,tenant_id)
    references public.hr_employee(id,tenant_id) on delete restrict,
  constraint smis_emergency_drill_plan_trainee_unique unique(tenant_id,drill_plan_id,employee_id)
);
create index if not exists smis_emergency_drill_plan_trainee_plan_idx
  on public.smis_emergency_drill_plan_trainee(tenant_id,drill_plan_id);
create index if not exists smis_emergency_drill_plan_trainee_employee_idx
  on public.smis_emergency_drill_plan_trainee(tenant_id,employee_id);

create table if not exists public.smis_emergency_drill_record (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id() references public.sys_tenant(id) on delete restrict,
  drill_plan_id uuid not null,
  actual_start_date date,
  actual_end_date date,
  drill_location text,
  drill_subject text,
  drill_purpose text,
  drill_process text,
  drill_summary text,
  drill_evaluation text,
  drill_team text,
  equipment_materials text,
  image_urls text[] not null default '{}',
  attachment_urls text[] not null default '{}',
  status text not null default 'draft',
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_emergency_drill_record_id_tenant_key unique(id,tenant_id),
  constraint smis_emergency_drill_record_plan_unique unique(tenant_id,drill_plan_id),
  constraint smis_emergency_drill_record_plan_fkey foreign key(drill_plan_id,tenant_id)
    references public.smis_emergency_drill_plan(id,tenant_id) on delete restrict,
  constraint smis_emergency_drill_record_status_check check(status in ('draft','submitted')),
  constraint smis_emergency_drill_record_dates_check check(actual_start_date is null or actual_end_date is null or actual_end_date >= actual_start_date),
  constraint smis_emergency_drill_record_remark_check check(remark is null or char_length(remark) <= 2000)
);
create index if not exists smis_emergency_drill_record_tenant_date_idx
  on public.smis_emergency_drill_record(tenant_id,status,actual_start_date);

create table if not exists public.smis_emergency_drill_record_participant (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id() references public.sys_tenant(id) on delete restrict,
  drill_record_id uuid not null,
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
  constraint smis_emergency_drill_record_participant_record_fkey foreign key(drill_record_id,tenant_id)
    references public.smis_emergency_drill_record(id,tenant_id) on delete cascade,
  constraint smis_emergency_drill_record_participant_employee_fkey foreign key(employee_id,tenant_id)
    references public.hr_employee(id,tenant_id) on delete restrict,
  constraint smis_emergency_drill_record_participant_unique unique(tenant_id,drill_record_id,employee_id)
);
create index if not exists smis_emergency_drill_record_participant_record_idx
  on public.smis_emergency_drill_record_participant(tenant_id,drill_record_id);
create index if not exists smis_emergency_drill_record_participant_employee_idx
  on public.smis_emergency_drill_record_participant(tenant_id,employee_id);

alter table public.smis_emergency_drill_plan_trainee enable row level security;
alter table public.smis_emergency_drill_record enable row level security;
alter table public.smis_emergency_drill_record_participant enable row level security;

drop policy if exists smis_emergency_drill_plan_select on public.smis_emergency_drill_plan;
create policy smis_emergency_drill_plan_select on public.smis_emergency_drill_plan for select to authenticated
using ((tenant_id=(select app_private.current_user_tenant_id()) and
       ((select app_private.has_permission('SmisEmergencyDrillPlan:View')) or
        (select app_private.has_permission('SmisEmergencyRescuePlan:Push')))) or
       (select app_private.is_platform_super()));
create policy smis_emergency_drill_plan_trainee_select on public.smis_emergency_drill_plan_trainee for select to authenticated
using ((tenant_id=(select app_private.current_user_tenant_id()) and
       (select app_private.has_permission('SmisEmergencyDrillPlan:View'))) or
       (select app_private.is_platform_super()));
create policy smis_emergency_drill_record_select on public.smis_emergency_drill_record for select to authenticated
using ((tenant_id=(select app_private.current_user_tenant_id()) and
       ((select app_private.has_permission('SmisEmergencyDrillRecord:View')) or
        (select app_private.has_permission('SmisEmergencyDrillReport:View')))) or
       (select app_private.is_platform_super()));
create policy smis_emergency_drill_record_participant_select on public.smis_emergency_drill_record_participant for select to authenticated
using ((tenant_id=(select app_private.current_user_tenant_id()) and
       (select app_private.has_permission('SmisEmergencyDrillRecord:View'))) or
       (select app_private.is_platform_super()));

revoke insert,update,delete on public.smis_emergency_drill_plan from authenticated;
revoke insert,update,delete on public.smis_emergency_drill_plan_trainee from authenticated;
revoke insert,update,delete on public.smis_emergency_drill_record from authenticated;
revoke insert,update,delete on public.smis_emergency_drill_record_participant from authenticated;
grant select on public.smis_emergency_drill_plan,public.smis_emergency_drill_plan_trainee,
  public.smis_emergency_drill_record,public.smis_emergency_drill_record_participant to authenticated;

drop trigger if exists smis_emergency_drill_plan_trainee_create_audit on public.smis_emergency_drill_plan_trainee;
create trigger smis_emergency_drill_plan_trainee_create_audit before insert on public.smis_emergency_drill_plan_trainee
for each row execute function public.trg_set_create_time_and_by('true','true');
drop trigger if exists smis_emergency_drill_record_create_audit on public.smis_emergency_drill_record;
create trigger smis_emergency_drill_record_create_audit before insert on public.smis_emergency_drill_record
for each row execute function public.trg_set_create_time_and_by('true','true');
drop trigger if exists smis_emergency_drill_record_update_audit on public.smis_emergency_drill_record;
create trigger smis_emergency_drill_record_update_audit before update on public.smis_emergency_drill_record
for each row execute function public.trg_set_update_time_and_by();
drop trigger if exists smis_emergency_drill_record_participant_create_audit on public.smis_emergency_drill_record_participant;
create trigger smis_emergency_drill_record_participant_create_audit before insert on public.smis_emergency_drill_record_participant
for each row execute function public.trg_set_create_time_and_by('true','true');

-- 月度重置、三位流水号，按租户继承编号引擎。
insert into public.sys_document_number_scene(
  rule_key,rule_name,field_label,category,menu_id,target_table,target_column,default_template,
  default_reset_cycle,manual_required,enabled,remark,create_by,update_by,tenant_id)
select 'smis.emergency_drill_plan','应急演练计划编号','计划编号','business_document',menu.id,
  'smis_emergency_drill_plan','plan_no','YL{YYYY}{MM}-{SEQ:3}','month',false,true,
  '应急演练计划编号按月重置三位流水','number-engine','number-engine',seed.tenant_id
from public.sys_menu menu
cross join lateral (select tenant_id from public.sys_document_number_scene where rule_key='smis.emergency_rescue_plan' limit 1) seed
where menu.name='SmisEmergencyDrillPlan'
  and not exists(select 1 from public.sys_document_number_scene where rule_key='smis.emergency_drill_plan')
limit 1;

insert into public.sys_document_number_rule(
  tenant_id,rule_key,rule_name,category,target_table,target_column,auto_enabled,template,
  reset_cycle,sequence_start,timezone,rule_version,manual_required,builtin,enabled,remark,create_by,update_by)
select tenant.id,'smis.emergency_drill_plan','应急演练计划编号','business_document',
  'smis_emergency_drill_plan','plan_no',true,'YL{YYYY}{MM}-{SEQ:3}','month',1,
  'Asia/Shanghai',1,false,true,true,'应急演练计划默认编号规则','number-engine','number-engine'
from public.sys_tenant tenant
where not exists(select 1 from public.sys_document_number_rule rule
  where rule.tenant_id=tenant.id and rule.rule_key='smis.emergency_drill_plan');

-- 租户字典。
with dictionary_types(name,code,sort,remark) as (values
 ('演练形式','smisEmergencyDrillForm',68,'现场演练、桌面演练'),
 ('演练计划状态','smisEmergencyDrillPlanStatus',69,'草稿、计划中、已完成、已取消'),
 ('演练记录状态','smisEmergencyDrillRecordStatus',70,'草稿、已提交'))
insert into public.sys_dict_type(id,name,code,status,create_by,update_by,remark,tenant_id,parent_id,node_type,sort)
select gen_random_uuid(),d.name,d.code,'1','system','system',d.remark,t.id,
  root.id,
  'dictionary',d.sort
from dictionary_types d
cross join lateral (select id,tenant_id from public.sys_dict_type where code='smisManage' limit 1) root
cross join lateral (select root.tenant_id id) t
where not exists(select 1 from public.sys_dict_type x where x.code=d.code);

with items(type_code,code,value,label,color,tag_type,sort) as (values
 ('smisEmergencyDrillForm','onsite','onsite','现场演练','#409eff','primary',1::bigint),
 ('smisEmergencyDrillForm','desktop','desktop','桌面演练','#909399','info',2::bigint),
 ('smisEmergencyDrillPlanStatus','draft','draft','草稿','#909399','info',1::bigint),
 ('smisEmergencyDrillPlanStatus','planned','planned','计划中','#409eff','primary',2::bigint),
 ('smisEmergencyDrillPlanStatus','completed','completed','已完成','#67c23a','success',3::bigint),
 ('smisEmergencyDrillPlanStatus','cancelled','cancelled','已取消','#909399','info',4::bigint),
 ('smisEmergencyDrillRecordStatus','draft','draft','草稿','#909399','info',1::bigint),
 ('smisEmergencyDrillRecordStatus','submitted','submitted','已提交','#67c23a','success',2::bigint))
insert into public.sys_dictionary(id,type_id,code,status,create_by,update_by,value,label,color,tag_type,sort,tenant_id)
select gen_random_uuid(),dt.id,i.code,'1','system','system',i.value,i.label,i.color,i.tag_type,i.sort,dt.tenant_id
from items i join public.sys_dict_type dt on dt.code=i.type_code
where not exists(select 1 from public.sys_dictionary x where x.type_id=dt.id and x.value=i.value);

-- 菜单权限按钮。
with permissions(parent_name,name,title,sort) as (values
 ('SmisEmergencyDrillPlan','SmisEmergencyDrillPlan:View','查看',1),
 ('SmisEmergencyDrillPlan','SmisEmergencyDrillPlan:Add','新增',2),
 ('SmisEmergencyDrillPlan','SmisEmergencyDrillPlan:Edit','编辑',3),
 ('SmisEmergencyDrillPlan','SmisEmergencyDrillPlan:Delete','删除',4),
 ('SmisEmergencyDrillPlan','SmisEmergencyDrillPlan:Submit','提交',5),
 ('SmisEmergencyDrillPlan','SmisEmergencyDrillPlan:Push','下推演练记录',6),
 ('SmisEmergencyDrillRecord','SmisEmergencyDrillRecord:View','查看',1),
 ('SmisEmergencyDrillRecord','SmisEmergencyDrillRecord:Add','新增',2),
 ('SmisEmergencyDrillRecord','SmisEmergencyDrillRecord:Edit','编辑',3),
 ('SmisEmergencyDrillRecord','SmisEmergencyDrillRecord:Delete','删除',4),
 ('SmisEmergencyDrillRecord','SmisEmergencyDrillRecord:Submit','提交',5),
 ('SmisEmergencyDrillReport','SmisEmergencyDrillReport:View','查看',1))
insert into public.sys_menu(id,parent_id,name,path,component,meta,sort,type,app_code,create_by,update_by)
select gen_random_uuid(),parent.id,p.name,'','',jsonb_build_object('title',p.title,'is_hide',true,'is_enable',true,'roles',jsonb_build_array()),
  p.sort,'button','smis','system','system'
from permissions p join public.sys_menu parent on parent.name=p.parent_name
where not exists(select 1 from public.sys_menu existing where existing.name=p.name and existing.parent_id=parent.id);

;
