with feature_type as (
  select id, tenant_id
  from public.sys_dict_type
  where code = 'aiRunFeature'
    and tenant_id = (
      select id from public.sys_tenant where tenant_code = 'platform' limit 1
    )
),
feature_rows(code, value, label, remark, sort, tag_type) as (
  values
    ('waybill_receipt_ocr','waybill_receipt_ocr','AI 回单识别与签收异常检测','识别签收人、签收时间、签收结果并与运单号、计划到达和货量核对',77::bigint,'warning'),
    ('cash_voucher_ocr','cash_voucher_ocr','AI 收付款凭证识别与匹配','识别收付款凭证并推荐已确认且未结清的客户或承运商对账单',78::bigint,'primary')
)
insert into public.sys_dictionary (
  id,type_id,code,status,create_by,update_by,remark,value,label,i18n_scope,sort,tenant_id,tag_type
)
select
  gen_random_uuid(),feature_type.id,feature_rows.code,'1','624944977@qq.com','624944977@qq.com',
  feature_rows.remark,feature_rows.value,feature_rows.label,'1',feature_rows.sort,feature_type.tenant_id,
  feature_rows.tag_type
from feature_type
cross join feature_rows
where not exists (
  select 1 from public.sys_dictionary dictionary
  where dictionary.type_id = feature_type.id
    and dictionary.value = feature_rows.value
    and dictionary.tenant_id = feature_type.tenant_id
);;
