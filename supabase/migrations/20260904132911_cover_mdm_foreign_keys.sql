begin;

create index if not exists mdm_business_partner_role_partner_tenant_idx
  on public.mdm_business_partner_role (partner_id, tenant_id);

create index if not exists mdm_employee_assignment_employee_tenant_fk_idx
  on public.mdm_employee_assignment (employee_id, tenant_id);
create index if not exists mdm_employee_assignment_organization_tenant_fk_idx
  on public.mdm_employee_assignment (organization_id, tenant_id);
create index if not exists mdm_employee_assignment_position_tenant_fk_idx
  on public.mdm_employee_assignment (position_id, tenant_id);

create index if not exists mdm_site_tenant_organization_fk_idx
  on public.mdm_site (tenant_id, organization_id);
create index if not exists mdm_site_tenant_parent_fk_idx
  on public.mdm_site (tenant_id, parent_id)
  where parent_id is not null;

commit;
