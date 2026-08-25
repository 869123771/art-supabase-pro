-- Align compensation functions with the enterprise assignment column introduced
-- by 20260825040001_enterprise_hr_assignments_personnel_changes.sql.
do $migration$
declare
  v_signature text;
  v_definition text;
begin
  foreach v_signature in array array[
    'public.hr_list_compensation_options_secure(text,uuid)',
    'public.hr_save_employee_compensation_secure(uuid,jsonb)'
  ]
  loop
    select pg_get_functiondef(v_signature::regprocedure) into v_definition;
    if position('assignment.is_primary' in v_definition) = 0 then
      raise exception 'Expected primary-assignment reference not found in %', v_signature;
    end if;
    v_definition := replace(
      v_definition,
      'assignment.is_primary',
      'assignment.primary_assignment'
    );
    execute v_definition;
  end loop;
end;
$migration$
