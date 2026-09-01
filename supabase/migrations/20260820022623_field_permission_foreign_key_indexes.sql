create index if not exists sys_permission_field_resource_tenant_fk_idx
  on public.sys_permission_field (resource_id, tenant_id);

create index if not exists sys_role_field_permission_field_tenant_fk_idx
  on public.sys_role_field_permission (field_id, resource_id, tenant_id);

create index if not exists sys_role_field_permission_role_tenant_fk_idx
  on public.sys_role_field_permission (role_id, tenant_id);

create index if not exists sys_user_field_permission_field_tenant_fk_idx
  on public.sys_user_field_permission (field_id, resource_id, tenant_id);

create index if not exists sys_user_field_permission_user_tenant_fk_idx
  on public.sys_user_field_permission (user_id, tenant_id);

create index if not exists idx_tms_contract_creator_tenant_fk
  on public.tms_contract (created_by_user_id, tenant_id);

create index if not exists idx_tms_contract_customer_id
  on public.tms_contract (customer_id);

;
