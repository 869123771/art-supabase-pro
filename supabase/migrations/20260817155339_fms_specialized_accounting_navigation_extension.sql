begin;

insert into public.sys_menu(id,parent_id,name,path,component,type,sort,meta,create_by,update_by)
values
  ('a1000000-0000-4000-8000-000000000031'::uuid,'a1000000-0000-4000-8000-000000000029'::uuid,
   'FinanceFixedAsset','fixed-asset','/fms/fixed-asset/index','menu',2,
   jsonb_build_object('icon','ri:building-2-line','title','固定资产','is_hide',false,'is_enable',true,'menu_type','menu','keep_alive',true),
   '624944977@qq.com','624944977@qq.com'),
  ('a1000000-0000-4000-8000-000000000032'::uuid,'a1000000-0000-4000-8000-000000000029'::uuid,
   'FinancePayroll','payroll','/fms/payroll/index','menu',3,
   jsonb_build_object('icon','ri:team-line','title','薪资核算','is_hide',false,'is_enable',true,'menu_type','menu','keep_alive',true),
   '624944977@qq.com','624944977@qq.com'),
  ('a1000000-0000-4000-8000-000000000033'::uuid,'a1000000-0000-4000-8000-000000000029'::uuid,
   'FinanceTaxManagement','tax-management','/fms/tax-management/index','menu',4,
   jsonb_build_object('icon','ri:government-line','title','税务管理','is_hide',false,'is_enable',true,'menu_type','menu','keep_alive',true),
   '624944977@qq.com','624944977@qq.com'),
  ('a1000000-0000-4000-8000-000000000034'::uuid,'a1000000-0000-4000-8000-000000000029'::uuid,
   'FinancePeriodClose','period-close','/fms/period-close/index','menu',5,
   jsonb_build_object('icon','ri:lock-2-line','title','月末结账','is_hide',false,'is_enable',true,'menu_type','menu','keep_alive',true),
   '624944977@qq.com','624944977@qq.com')
on conflict(id) do update set parent_id=excluded.parent_id,name=excluded.name,path=excluded.path,
  component=excluded.component,type=excluded.type,sort=excluded.sort,meta=excluded.meta,
  update_by=excluded.update_by,update_time=now();

with finance_roles as (
  select distinct role_id,tenant_id from public.sys_role_menu
  where menu_id='a1000000-0000-4000-8000-000000000001'::uuid
)
insert into public.sys_role_menu(role_id,menu_id,tenant_id,permission,create_by,update_by)
select r.role_id,m.menu_id,r.tenant_id,'{}'::jsonb,'624944977@qq.com','624944977@qq.com'
from finance_roles r cross join (values
  ('a1000000-0000-4000-8000-000000000031'::uuid),
  ('a1000000-0000-4000-8000-000000000032'::uuid),
  ('a1000000-0000-4000-8000-000000000033'::uuid),
  ('a1000000-0000-4000-8000-000000000034'::uuid)
) m(menu_id)
on conflict(role_id,menu_id) do nothing;

with platform_tenant as (
  select id from public.sys_tenant where builtin_type='platform' limit 1
), scenes as (
  select * from (values
    ('fms.fixed_asset','固定资产编号','资产编号','business_document','FinanceFixedAsset','fms_fixed_asset','asset_no','ZC{YYYYMM}-{SEQ:5}','year','固定资产卡片内部编号'),
    ('fms.asset_depreciation_run','折旧批次编号','折旧批次号','business_document','FinanceFixedAsset','fms_asset_depreciation_run','run_no','ZJ{YYYYMM}-{SEQ:4}','month','月度折旧批次编号'),
    ('fms.payroll_run','薪资批次编号','薪资批次号','business_document','FinancePayroll','fms_payroll_run','run_no','XZ{YYYYMM}-{SEQ:4}','month','月度薪资核算批次编号'),
    ('fms.period_close_run','关账批次编号','关账批次号','business_document','FinancePeriodClose','fms_period_close_run','run_no','GZ{YYYYMM}-{SEQ:4}','month','月末关账检查批次编号')
  ) s(rule_key,rule_name,field_label,category,menu_name,target_table,target_column,default_template,default_reset_cycle,remark)
)
insert into public.sys_document_number_scene(
  rule_key,rule_name,field_label,category,menu_id,target_table,target_column,
  default_template,default_reset_cycle,manual_required,enabled,remark,tenant_id
)
select s.rule_key,s.rule_name,s.field_label,s.category,m.id,s.target_table,s.target_column,
  s.default_template,s.default_reset_cycle,false,true,s.remark,p.id
from platform_tenant p cross join scenes s join public.sys_menu m on m.name=s.menu_name
on conflict(rule_key) do update set rule_name=excluded.rule_name,field_label=excluded.field_label,
  category=excluded.category,menu_id=excluded.menu_id,target_table=excluded.target_table,
  target_column=excluded.target_column,default_template=excluded.default_template,
  default_reset_cycle=excluded.default_reset_cycle,manual_required=excluded.manual_required,
  enabled=excluded.enabled,remark=excluded.remark,update_time=now();

insert into public.sys_document_number_rule(
  tenant_id,rule_key,rule_name,category,target_table,target_column,auto_enabled,
  template,reset_cycle,sequence_start,timezone,manual_required,builtin,enabled,remark,create_by,update_by
)
select t.id,s.rule_key,s.rule_name,s.category,s.target_table,s.target_column,true,
  s.default_template,s.default_reset_cycle,1,'Asia/Shanghai',s.manual_required,true,true,s.remark,
  'number-engine','number-engine'
from public.sys_tenant t join public.sys_document_number_scene s
  on s.rule_key in ('fms.fixed_asset','fms.asset_depreciation_run','fms.payroll_run','fms.period_close_run')
on conflict(tenant_id,rule_key) do nothing;

drop trigger if exists document_number_asset_no on public.fms_fixed_asset;
create trigger document_number_asset_no before insert on public.fms_fixed_asset
for each row execute function app_private.trg_assign_configurable_number('fms.fixed_asset','asset_no');

drop trigger if exists document_number_depreciation_run_no on public.fms_asset_depreciation_run;
create trigger document_number_depreciation_run_no before insert on public.fms_asset_depreciation_run
for each row execute function app_private.trg_assign_configurable_number('fms.asset_depreciation_run','run_no');

drop trigger if exists document_number_payroll_run_no on public.fms_payroll_run;
create trigger document_number_payroll_run_no before insert on public.fms_payroll_run
for each row execute function app_private.trg_assign_configurable_number('fms.payroll_run','run_no');

drop trigger if exists document_number_close_run_no on public.fms_period_close_run;
create trigger document_number_close_run_no before insert on public.fms_period_close_run
for each row execute function app_private.trg_assign_configurable_number('fms.period_close_run','run_no');

commit;

;
