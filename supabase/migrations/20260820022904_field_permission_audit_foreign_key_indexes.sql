create index if not exists sys_permission_audit_log_actor_tenant_fk_idx
  on public.sys_permission_audit_log (actor_user_id, tenant_id);

create index if not exists sys_permission_audit_log_resource_tenant_fk_idx
  on public.sys_permission_audit_log (resource_id, tenant_id);

;
