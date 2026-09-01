-- Align legacy position capacity with the actual incumbent population before
-- enforcing enterprise headcount controls.
with incumbent_counts as (
  select
    employee_row.tenant_id,
    employee_row.position_id,
    count(*)::integer as incumbent_count
  from public.hr_employee employee_row
  where employee_row.employment_status <> 'terminated'
  group by employee_row.tenant_id, employee_row.position_id
)
update public.hr_position position_row
set
  headcount_limit = greatest(position_row.headcount_limit, counts.incumbent_count),
  multiple_incumbents_allowed = position_row.multiple_incumbents_allowed
    or counts.incumbent_count > 1
from incumbent_counts counts
where counts.tenant_id = position_row.tenant_id
  and counts.position_id = position_row.id
  and (
    position_row.headcount_limit < counts.incumbent_count
    or (counts.incumbent_count > 1 and not position_row.multiple_incumbents_allowed)
  );
create or replace function app_private.validate_hr_position_capacity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_incumbent_count integer;
begin
  select count(*)::integer
  into v_incumbent_count
  from public.hr_employee_assignment assignment_row
  where assignment_row.tenant_id = new.tenant_id
    and assignment_row.position_id = new.id
    and assignment_row.primary_assignment
    and assignment_row.effective_end is null
    and assignment_row.assignment_status <> 'ended';

  if new.headcount_limit < v_incumbent_count then
    raise exception '岗位编制上限不能低于当前任职人数（%）', v_incumbent_count;
  end if;
  if not new.multiple_incumbents_allowed and v_incumbent_count > 1 then
    raise exception '当前岗位已有多人任职，不能改为单人岗位';
  end if;
  return new;
end;
$function$;
drop trigger if exists hr_position_validate_capacity on public.hr_position;
create trigger hr_position_validate_capacity
before update of headcount_limit, multiple_incumbents_allowed on public.hr_position
for each row execute function app_private.validate_hr_position_capacity();
create or replace function app_private.validate_hr_employee_assignment_capacity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_position public.hr_position%rowtype;
  v_incumbent_count integer;
begin
  if not new.primary_assignment
     or new.effective_end is not null
     or new.assignment_status = 'ended' then
    return new;
  end if;

  select position_row.*
  into v_position
  from public.hr_position position_row
  where position_row.id = new.position_id
    and position_row.tenant_id = new.tenant_id
  for update;

  if not found then
    raise exception '任职岗位不存在';
  end if;
  if not v_position.enabled then
    raise exception '任职岗位已停用';
  end if;
  if v_position.organization_id is not null
     and v_position.organization_id <> new.organization_id then
    raise exception '任职组织与岗位所属组织不一致';
  end if;
  if v_position.job_profile_id <> new.job_profile_id then
    raise exception '任职标准职务与岗位标准职务不一致';
  end if;

  select count(*)::integer
  into v_incumbent_count
  from public.hr_employee_assignment assignment_row
  where assignment_row.tenant_id = new.tenant_id
    and assignment_row.position_id = new.position_id
    and assignment_row.primary_assignment
    and assignment_row.effective_end is null
    and assignment_row.assignment_status <> 'ended'
    and assignment_row.id <> new.id;

  if not v_position.multiple_incumbents_allowed and v_incumbent_count >= 1 then
    raise exception '该岗位仅允许一人任职';
  end if;
  if v_incumbent_count >= v_position.headcount_limit then
    raise exception '该岗位编制已满（上限 % 人）', v_position.headcount_limit;
  end if;
  return new;
end;
$function$;
drop trigger if exists hr_employee_assignment_validate_capacity
on public.hr_employee_assignment;
create trigger hr_employee_assignment_validate_capacity
before insert or update of
  organization_id,
  position_id,
  job_profile_id,
  assignment_status,
  primary_assignment,
  effective_end
on public.hr_employee_assignment
for each row execute function app_private.validate_hr_employee_assignment_capacity();
