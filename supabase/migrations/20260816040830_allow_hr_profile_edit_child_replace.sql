
alter policy hr_employee_contract_tenant_insert on public.hr_employee_contract
  with check (
    (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
    and (
      current_has_permission('Hr:Employee:Add')
      or current_has_permission('Hr:Employee:Edit')
    )
  );
alter policy hr_employee_contract_tenant_delete on public.hr_employee_contract
  using (
    (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
    and (
      current_has_permission('Hr:Employee:Delete')
      or current_has_permission('Hr:Employee:Edit')
    )
  );

alter policy hr_employee_education_tenant_insert on public.hr_employee_education
  with check (
    (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
    and (
      current_has_permission('Hr:Employee:Add')
      or current_has_permission('Hr:Employee:Edit')
    )
  );
alter policy hr_employee_education_tenant_delete on public.hr_employee_education
  using (
    (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
    and (
      current_has_permission('Hr:Employee:Delete')
      or current_has_permission('Hr:Employee:Edit')
    )
  );

alter policy hr_employee_work_experience_tenant_insert on public.hr_employee_work_experience
  with check (
    (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
    and (
      current_has_permission('Hr:Employee:Add')
      or current_has_permission('Hr:Employee:Edit')
    )
  );
alter policy hr_employee_work_experience_tenant_delete on public.hr_employee_work_experience
  using (
    (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
    and (
      current_has_permission('Hr:Employee:Delete')
      or current_has_permission('Hr:Employee:Edit')
    )
  );

alter policy hr_employee_training_tenant_insert on public.hr_employee_training
  with check (
    (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
    and (
      current_has_permission('Hr:Employee:Add')
      or current_has_permission('Hr:Employee:Edit')
    )
  );
alter policy hr_employee_training_tenant_delete on public.hr_employee_training
  using (
    (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
    and (
      current_has_permission('Hr:Employee:Delete')
      or current_has_permission('Hr:Employee:Edit')
    )
  );

alter policy hr_employee_reward_tenant_insert on public.hr_employee_reward
  with check (
    (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
    and (
      current_has_permission('Hr:Employee:Add')
      or current_has_permission('Hr:Employee:Edit')
    )
  );
alter policy hr_employee_reward_tenant_delete on public.hr_employee_reward
  using (
    (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
    and (
      current_has_permission('Hr:Employee:Delete')
      or current_has_permission('Hr:Employee:Edit')
    )
  );
;
