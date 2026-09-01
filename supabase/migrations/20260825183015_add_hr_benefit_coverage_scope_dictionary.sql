-- Add the plan-level coverage scope dictionary referenced by the benefits UI.
-- Kept idempotent so environments that replay the consolidated foundation stay aligned.

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
)
insert into public.sys_dict_type(
  id, name, code, status, remark, tenant_id, create_by, update_by,
  parent_id, node_type, sort
)
select gen_random_uuid(), '福利覆盖范围', 'hrBenefitCoverageScope', '1',
  '企业 HR 福利与参保字典', platform_tenant.id,
  '624944977@qq.com', '624944977@qq.com',
  (select id from public.sys_dict_type where code = 'hrManage' limit 1),
  'dictionary', 141
from platform_tenant
on conflict (code) do update set
  name = excluded.name,
  status = excluded.status,
  update_by = excluded.update_by,
  update_time = now(),
  remark = excluded.remark,
  sort = excluded.sort;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), dictionary_seed(value, label, sort, tag_type) as (
  values
    ('employee', '仅员工', 1, 'primary'),
    ('employee_family', '员工及家庭', 2, 'success')
)
insert into public.sys_dictionary(
  id, type_id, code, status, create_by, update_by, remark,
  value, label, tenant_id, tag_type, sort
)
select gen_random_uuid(), dictionary_type.id,
  'hrBenefitCoverageScope_' || seed.value,
  '1', '624944977@qq.com', '624944977@qq.com',
  '企业 HR 福利与参保字典项', seed.value, seed.label,
  platform_tenant.id, seed.tag_type, seed.sort
from dictionary_seed seed
join public.sys_dict_type dictionary_type
  on dictionary_type.code = 'hrBenefitCoverageScope'
cross join platform_tenant
where not exists (
  select 1
  from public.sys_dictionary existing
  where existing.type_id = dictionary_type.id
    and existing.value = seed.value
);

;
