with platform as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), parent as (
  select parent_id from public.sys_dict_type where code = 'tmsCashTransactionStatus' and tenant_id = (select id from platform) limit 1
), rows(name, code, sort) as (values
  ('签收异常工单状态', 'tmsReceiptExceptionStatus', 20::bigint),
  ('签收异常严重程度', 'tmsReceiptExceptionSeverity', 21::bigint),
  ('AI 银行流水行状态', 'aiBankBatchRowStatus', 22::bigint)
)
insert into public.sys_dict_type(id,name,code,status,create_by,update_by,tenant_id,parent_id,node_type,sort)
select gen_random_uuid(),rows.name,rows.code,'1','624944977@qq.com','624944977@qq.com',platform.id,parent.parent_id,'dictionary',rows.sort
from rows cross join platform cross join parent
where not exists (
  select 1 from public.sys_dict_type existing where existing.code=rows.code and existing.tenant_id=platform.id
);

with platform as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), rows(type_code, code, label, sort, tag_type) as (values
  ('tmsReceiptExceptionStatus','pending','待处理',1::bigint,'warning'),
  ('tmsReceiptExceptionStatus','in_progress','处理中',2::bigint,'primary'),
  ('tmsReceiptExceptionStatus','resolved','已解决',3::bigint,'success'),
  ('tmsReceiptExceptionStatus','closed','已关闭',4::bigint,'info'),
  ('tmsReceiptExceptionStatus','cancelled','已取消',5::bigint,'info'),
  ('tmsReceiptExceptionSeverity','low','低风险',1::bigint,'info'),
  ('tmsReceiptExceptionSeverity','medium','中风险',2::bigint,'warning'),
  ('tmsReceiptExceptionSeverity','high','高风险',3::bigint,'danger'),
  ('tmsReceiptExceptionSeverity','critical','严重风险',4::bigint,'danger'),
  ('aiBankBatchRowStatus','ready','可入账',1::bigint,'success'),
  ('aiBankBatchRowStatus','review','需复核',2::bigint,'warning'),
  ('aiBankBatchRowStatus','duplicate','重复',3::bigint,'info'),
  ('aiBankBatchRowStatus','invalid','无效',4::bigint,'danger')
), resolved as (
  select rows.*,dict_type.id type_id,platform.id tenant_id
  from rows cross join platform
  join public.sys_dict_type dict_type on dict_type.code=rows.type_code and dict_type.tenant_id=platform.id
)
insert into public.sys_dictionary(
  id,type_id,code,status,create_by,update_by,value,label,i18n_scope,sort,tenant_id,tag_type
)
select gen_random_uuid(),type_id,code,'1','624944977@qq.com','624944977@qq.com',code,label,'1',sort,tenant_id,tag_type
from resolved
where not exists (
  select 1 from public.sys_dictionary existing
  where existing.type_id=resolved.type_id and existing.value=resolved.code and existing.tenant_id=resolved.tenant_id
);

;
