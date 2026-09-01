-- Import approved HR compensation into an editable FMS payroll run.
-- Existing payroll lines are deliberately preserved: finance owns the period
-- calculation and may already have entered attendance-driven adjustments.

create or replace function public.fms_import_hr_compensation_lines_secure(p_run_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_run public.fms_payroll_run%rowtype;
  v_inputs jsonb;
  v_input jsonb;
  v_gross numeric(20, 2);
  v_deduction numeric(20, 2);
  v_employer_cost numeric(20, 2);
  v_imported integer := 0;
  v_skipped integer := 0;
begin
  select * into v_run
  from public.fms_payroll_run run_row
  where run_row.id = p_run_id
    and run_row.tenant_id = app_private.current_user_tenant_id()
  for update;
  if not found then
    raise exception 'Payroll run does not exist in the current tenant' using errcode = 'P0002';
  end if;
  if v_run.status not in ('draft', 'calculated') then
    raise exception '只有草稿或已计算薪资批次可以同步 HR 薪酬' using errcode = '23514';
  end if;
  if not app_private.can_execute_business_action(
    'FinancePayroll', 'FinancePayroll:Calculate', null, false
  ) then
    raise exception 'Missing payroll calculation permission' using errcode = '42501';
  end if;

  v_inputs := public.hr_compensation_payroll_inputs_secure(
    v_run.payroll_month,
    v_run.tenant_id
  );

  for v_input in select value from jsonb_array_elements(v_inputs)
  loop
    if exists (
      select 1 from public.fms_payroll_line line_row
      where line_row.run_id = p_run_id
        and line_row.employee_id = (v_input->>'employee_id')::uuid
    ) then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    select coalesce(sum(coalesce((item->>'amount')::numeric, 0)), 0)
    into v_gross
    from jsonb_array_elements(coalesce(v_input->'earning_items', '[]'::jsonb)) item;
    select coalesce(sum(coalesce((item->>'amount')::numeric, 0)), 0)
    into v_deduction
    from jsonb_array_elements(coalesce(v_input->'deduction_items', '[]'::jsonb)) item;
    select coalesce(sum(coalesce((item->>'amount')::numeric, 0)), 0)
    into v_employer_cost
    from jsonb_array_elements(coalesce(v_input->'employer_cost_items', '[]'::jsonb)) item;

    perform public.save_fms_payroll_line_secure(
      p_run_id,
      jsonb_build_object(
        'employeeId', v_input->>'employee_id',
        'earningItems', coalesce(v_input->'earning_items', '[]'::jsonb),
        'deductionItems', coalesce(v_input->'deduction_items', '[]'::jsonb),
        'employerCostItems', coalesce(v_input->'employer_cost_items', '[]'::jsonb),
        'grossAmount', v_gross,
        'deductionAmount', v_deduction,
        'employerCostAmount', v_employer_cost,
        'remark', format(
          '由 HR 薪酬管理同步（方案：%s，薪酬记录：%s）',
          coalesce(v_input->>'plan_name', '未命名'),
          v_input->>'compensation_id'
        )
      )
    );
    v_imported := v_imported + 1;
  end loop;

  return jsonb_build_object(
    'eligible_count', jsonb_array_length(v_inputs),
    'imported_count', v_imported,
    'skipped_count', v_skipped
  );
end;
$function$;
revoke all on function public.fms_import_hr_compensation_lines_secure(uuid) from public, anon;
grant execute on function public.fms_import_hr_compensation_lines_secure(uuid)
  to authenticated, service_role;
