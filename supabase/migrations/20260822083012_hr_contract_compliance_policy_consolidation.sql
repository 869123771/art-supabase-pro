-- Consolidate roster and compliance access into one permissive policy per action.
drop policy if exists hr_employee_contract_tenant_select on public.hr_employee_contract;
drop policy if exists hr_employee_contract_tenant_insert on public.hr_employee_contract;
drop policy if exists hr_employee_contract_tenant_update on public.hr_employee_contract;
drop policy if exists hr_employee_contract_tenant_delete on public.hr_employee_contract;
drop policy if exists hr_employee_contract_compliance_select on public.hr_employee_contract;
drop policy if exists hr_employee_contract_compliance_insert on public.hr_employee_contract;
drop policy if exists hr_employee_contract_compliance_update on public.hr_employee_contract;
drop policy if exists hr_employee_contract_compliance_delete on public.hr_employee_contract;

create policy hr_employee_contract_tenant_select
on public.hr_employee_contract for select to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id=(select app_private.current_user_tenant_id())
    and (
      (select app_private.has_permission('Hr:Employee:View'))
      or (select app_private.has_permission('Hr:Compliance:View'))
    )
  )
);

create policy hr_employee_contract_tenant_insert
on public.hr_employee_contract for insert to authenticated
with check (
  (select app_private.is_platform_super())
  or (
    tenant_id=(select app_private.current_user_tenant_id())
    and (
      (select app_private.has_permission('Hr:Employee:Add'))
      or (select app_private.has_permission('Hr:Employee:Edit'))
      or (select app_private.has_permission('Hr:Compliance:Add'))
    )
  )
);

create policy hr_employee_contract_tenant_update
on public.hr_employee_contract for update to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id=(select app_private.current_user_tenant_id())
    and (
      (select app_private.has_permission('Hr:Employee:Edit'))
      or (select app_private.has_permission('Hr:Compliance:Edit'))
    )
  )
)
with check (
  (select app_private.is_platform_super())
  or tenant_id=(select app_private.current_user_tenant_id())
);

create policy hr_employee_contract_tenant_delete
on public.hr_employee_contract for delete to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id=(select app_private.current_user_tenant_id())
    and (
      (select app_private.has_permission('Hr:Employee:Delete'))
      or (select app_private.has_permission('Hr:Employee:Edit'))
      or (select app_private.has_permission('Hr:Compliance:Delete'))
    )
  )
);
;
