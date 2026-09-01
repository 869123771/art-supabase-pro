with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), dictionary_parent as (
  select parent_id from public.sys_dict_type where code = 'smisPpeIssuanceCycle' limit 1
)
insert into public.sys_dict_type(
  id, name, code, status, create_by, update_by, remark, tenant_id, parent_id, node_type, sort
)
select gen_random_uuid(), '工器具领用状态', 'smisToolRequisitionStatus', '1',
       'system', 'system', '工器具个人领用状态', p.id, dp.parent_id, 'dictionary', 51
from platform_tenant p
cross join dictionary_parent dp
on conflict (code) do update
set name = excluded.name,
    status = '1',
    remark = excluded.remark,
    update_by = excluded.update_by;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), items(suffix, value, label, sort, tag_type) as (
  values
    ('pending_issue','pending_issue','待发放',1,'warning'),
    ('issued_pending_confirmation','issued_pending_confirmation','待本人确认',2,'primary'),
    ('confirmed','confirmed','已确认',3,'success'),
    ('denied','denied','已否认',4,'danger'),
    ('cancelled','cancelled','已取消',5,'info')
)
insert into public.sys_dictionary(
  id, type_id, code, status, create_by, update_by, value, label, i18n_scope,
  sort, tenant_id, tag_type
)
select gen_random_uuid(), t.id, 'smisToolRequisitionStatus_' || i.suffix, '1',
       'system', 'system', i.value, i.label, '1',
       i.sort, p.id, i.tag_type
from items i
join public.sys_dict_type t on t.code = 'smisToolRequisitionStatus'
cross join platform_tenant p
where not exists (
  select 1
  from public.sys_dictionary d
  where d.code = 'smisToolRequisitionStatus_' || i.suffix
);

notify pgrst, 'reload schema';;
