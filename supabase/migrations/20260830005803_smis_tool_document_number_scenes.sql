
insert into public.sys_document_number_scene (
  rule_key,
  rule_name,
  field_label,
  category,
  menu_id,
  target_table,
  target_column,
  default_template,
  default_reset_cycle,
  manual_required,
  enabled,
  remark,
  create_by,
  update_by,
  tenant_id
)
select
  replace(source.rule_key, 'smis.ppe_', 'smis.tool_'),
  replace(source.rule_name, '防护用品', '工器具'),
  source.field_label,
  source.category,
  target_menu.id,
  replace(source.target_table, 'smis_ppe_', 'smis_tool_'),
  source.target_column,
  case
    when source.rule_key = 'smis.ppe_issuance_standard' then 'GJBZ{YYYY}-{SEQ:3}'
    else 'GJ{YYYYMM}{SEQ:4}'
  end,
  source.default_reset_cycle,
  source.manual_required,
  source.enabled,
  replace(source.remark, '发放过账生成', '工器具发放过账生成'),
  '624944977@qq.com',
  '624944977@qq.com',
  source.tenant_id
from public.sys_document_number_scene source
join public.sys_menu target_menu
  on target_menu.name = case
    when source.rule_key = 'smis.ppe_issuance_standard' then 'SmisToolIssuanceStandard'
    else 'SmisToolIssuanceRecord'
  end
where source.rule_key in ('smis.ppe_issuance_standard', 'smis.ppe_issuance_record')
  and not exists (
    select 1
    from public.sys_document_number_scene target
    where target.rule_key = replace(source.rule_key, 'smis.ppe_', 'smis.tool_')
  );
;
