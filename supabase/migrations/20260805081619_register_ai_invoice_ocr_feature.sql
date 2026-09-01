with feature_type as (
  select id, tenant_id
  from public.sys_dict_type
  where code = 'aiRunFeature'
    and tenant_id = (
      select id
      from public.sys_tenant
      where tenant_code = 'platform'
      limit 1
    )
),
feature_row(code, value, label, remark, sort, tag_type) as (
  values (
    'invoice_ocr',
    'invoice_ocr',
    'AI 发票票面识别',
    '发票附件 OCR、字段置信度、金额勾稽与人工确认回填',
    76::bigint,
    'primary'
  )
)
insert into public.sys_dictionary (
  id,
  type_id,
  code,
  status,
  create_by,
  update_by,
  remark,
  value,
  label,
  i18n_scope,
  sort,
  tenant_id,
  tag_type
)
select
  gen_random_uuid(),
  feature_type.id,
  feature_row.code,
  '1',
  '624944977@qq.com',
  '624944977@qq.com',
  feature_row.remark,
  feature_row.value,
  feature_row.label,
  '1',
  feature_row.sort,
  feature_type.tenant_id,
  feature_row.tag_type
from feature_type
cross join feature_row
where not exists (
  select 1
  from public.sys_dictionary dictionary
  where dictionary.type_id = feature_type.id
    and dictionary.value = feature_row.value
    and dictionary.tenant_id = feature_type.tenant_id
);

;
