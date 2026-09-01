
insert into public.sys_document_number_rule (
  id, tenant_id, rule_key, rule_name, category, target_table, target_column,
  auto_enabled, template, reset_cycle, sequence_start, timezone, rule_version,
  manual_required, builtin, enabled, remark, create_by, update_by
)
select
  gen_random_uuid(),
  source.tenant_id,
  replace(source.rule_key, 'smis.ppe_', 'smis.tool_'),
  replace(source.rule_name, '防护用品', '工器具'),
  source.category,
  replace(source.target_table, 'smis_ppe_', 'smis_tool_'),
  source.target_column,
  source.auto_enabled,
  case when source.rule_key = 'smis.ppe_issuance_standard'
    then 'GJBZ{YYYY}-{SEQ:3}' else 'GJ{YYYYMM}{SEQ:4}' end,
  source.reset_cycle,
  source.sequence_start,
  source.timezone,
  source.rule_version,
  source.manual_required,
  source.builtin,
  source.enabled,
  replace(source.remark, '发放过账生成', '工器具发放过账生成'),
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_document_number_rule source
where source.rule_key in ('smis.ppe_issuance_standard', 'smis.ppe_issuance_record')
  and not exists (
    select 1 from public.sys_document_number_rule target
    where target.tenant_id = source.tenant_id
      and target.rule_key = replace(source.rule_key, 'smis.ppe_', 'smis.tool_')
  );

insert into public.sys_dict_type (
  id, name, code, status, create_by, update_by, remark,
  tenant_id, parent_id, node_type, sort
)
select
  gen_random_uuid(),
  replace(source.name, '防护用品', '工器具'),
  replace(source.code, 'smisPpe', 'smisTool'),
  source.status,
  '624944977@qq.com',
  '624944977@qq.com',
  source.remark,
  source.tenant_id,
  source.parent_id,
  source.node_type,
  source.sort
from public.sys_dict_type source
where source.code in ('smisPpeIssuanceCycle', 'smisPpeIssuanceStatus')
  and not exists (
    select 1 from public.sys_dict_type target
    where target.tenant_id = source.tenant_id
      and target.code = replace(source.code, 'smisPpe', 'smisTool')
  );

insert into public.sys_dictionary (
  id, type_id, code, status, create_by, update_by, remark, value, label,
  i18n, i18n_scope, color, sort, tenant_id, tag_type, parent_id, cascade_parent_id
)
select
  gen_random_uuid(),
  target_type.id,
  replace(source_item.code, 'smisPpe', 'smisTool'),
  source_item.status,
  '624944977@qq.com',
  '624944977@qq.com',
  source_item.remark,
  source_item.value,
  source_item.label,
  source_item.i18n,
  source_item.i18n_scope,
  source_item.color,
  source_item.sort,
  source_item.tenant_id,
  source_item.tag_type,
  null,
  null
from public.sys_dictionary source_item
join public.sys_dict_type source_type on source_type.id = source_item.type_id
join public.sys_dict_type target_type
  on target_type.tenant_id = source_type.tenant_id
 and target_type.code = replace(source_type.code, 'smisPpe', 'smisTool')
where source_type.code in ('smisPpeIssuanceCycle', 'smisPpeIssuanceStatus')
  and not exists (
    select 1 from public.sys_dictionary target_item
    where target_item.type_id = target_type.id
      and target_item.value = source_item.value
  );

update public.sys_menu
set
  meta = meta || case name
    when 'SmisToolIssuanceStandard' then jsonb_build_object('icon', 'ri:tools-line', 'keep_alive', true)
    when 'SmisToolPersonalStandard' then jsonb_build_object('icon', 'ri:user-settings-line', 'keep_alive', true)
    when 'SmisToolIssuanceRecord' then jsonb_build_object('icon', 'ri:archive-drawer-line', 'keep_alive', true)
    when 'SmisToolPersonalRequisition' then jsonb_build_object('icon', 'ri:inbox-archive-line', 'keep_alive', true)
    else '{}'::jsonb
  end,
  update_by = '624944977@qq.com',
  update_time = now()
where name in (
  'SmisToolIssuanceStandard',
  'SmisToolPersonalStandard',
  'SmisToolIssuanceRecord',
  'SmisToolPersonalRequisition'
);

with button_source(menu_name, suffix, title, sort) as (
  values
    ('SmisToolIssuanceStandard', 'View', '查看发放标准', 1),
    ('SmisToolIssuanceStandard', 'Add', '新增发放标准', 2),
    ('SmisToolIssuanceStandard', 'Edit', '编辑发放标准', 3),
    ('SmisToolIssuanceStandard', 'Delete', '删除发放标准', 4),
    ('SmisToolIssuanceStandard', 'Export', '导出发放标准', 5),
    ('SmisToolPersonalStandard', 'View', '查看个人标准', 1),
    ('SmisToolPersonalStandard', 'Generate', '生成个人标准', 2),
    ('SmisToolPersonalStandard', 'Export', '导出个人标准', 3),
    ('SmisToolPersonalStandard', 'Schedule', '设置领用计划', 4),
    ('SmisToolIssuanceRecord', 'View', '查看发放记录', 1),
    ('SmisToolIssuanceRecord', 'Add', '新增发放记录', 2),
    ('SmisToolIssuanceRecord', 'Copy', '复制并新增', 3),
    ('SmisToolIssuanceRecord', 'Edit', '编辑发放记录', 4),
    ('SmisToolIssuanceRecord', 'Delete', '删除发放记录', 5),
    ('SmisToolIssuanceRecord', 'Issue', '发放过账', 6),
    ('SmisToolIssuanceRecord', 'Import', '导入发放记录', 7),
    ('SmisToolIssuanceRecord', 'DownloadTemplate', '下载导入模板', 8),
    ('SmisToolIssuanceRecord', 'Export', '导出发放记录', 9),
    ('SmisToolIssuanceRecord', 'Statistics', '发放统计分析', 10),
    ('SmisToolIssuanceRecord', 'Print', '打印工器具发放单', 11),
    ('SmisToolPersonalRequisition', 'View', '查看个人领用', 1),
    ('SmisToolPersonalRequisition', 'Generate', '生成到期领用单', 2),
    ('SmisToolPersonalRequisition', 'Push', '下推发放', 3),
    ('SmisToolPersonalRequisition', 'Confirm', '确认本人领用', 4),
    ('SmisToolPersonalRequisition', 'Export', '导出个人领用', 5),
    ('SmisToolPersonalRequisition', 'Statistics', '个人领用统计', 6),
    ('SmisToolPersonalRequisition', 'Configure', '配置自动确认', 7)
)
insert into public.sys_menu (
  id, parent_id, name, path, component, meta, sort,
  create_by, update_by, type, app_code
)
select
  gen_random_uuid(),
  parent.id,
  source.menu_name || ':' || source.suffix,
  '',
  '',
  jsonb_build_object(
    'title', source.title,
    'is_hide', true,
    'is_enable', true,
    'roles', jsonb_build_array()
  ),
  source.sort,
  '624944977@qq.com',
  '624944977@qq.com',
  'button',
  'smis'
from button_source source
join public.sys_menu parent on parent.name = source.menu_name
where not exists (
  select 1 from public.sys_menu existing
  where existing.name = source.menu_name || ':' || source.suffix
    and existing.parent_id = parent.id
);

insert into public.sys_role_menu (
  id, role_id, menu_id, permission, create_by, update_by, tenant_id
)
select
  gen_random_uuid(),
  parent_grant.role_id,
  button.id,
  coalesce(parent_grant.permission, '[]'::jsonb),
  '624944977@qq.com',
  '624944977@qq.com',
  parent_grant.tenant_id
from public.sys_menu button
join public.sys_menu parent on parent.id = button.parent_id
join public.sys_role_menu parent_grant on parent_grant.menu_id = parent.id
where parent.name in (
  'SmisToolIssuanceStandard',
  'SmisToolPersonalStandard',
  'SmisToolIssuanceRecord',
  'SmisToolPersonalRequisition'
)
  and button.type = 'button'
  and not exists (
    select 1 from public.sys_role_menu existing
    where existing.role_id = parent_grant.role_id
      and existing.menu_id = button.id
      and existing.tenant_id = parent_grant.tenant_id
  );

notify pgrst, 'reload schema';
;
