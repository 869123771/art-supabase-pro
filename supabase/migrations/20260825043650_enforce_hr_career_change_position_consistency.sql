create or replace function app_private.validate_hr_personnel_change_target()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_position public.hr_position%rowtype;
begin
  select position_row.*
  into v_position
  from public.hr_position position_row
  where position_row.id = new.to_position_id
    and position_row.tenant_id = new.tenant_id;

  if not found then
    raise exception '目标岗位不存在';
  end if;
  if v_position.job_profile_id <> new.to_job_profile_id then
    raise exception '目标标准职务必须与目标岗位的标准职务一致';
  end if;
  if v_position.organization_id is not null
     and v_position.organization_id <> new.to_organization_id then
    raise exception '目标组织必须与目标岗位所属组织一致';
  end if;

  if new.change_type in ('promotion', 'demotion')
     and new.to_position_id is not distinct from new.from_position_id
     and new.to_job_profile_id is not distinct from new.from_job_profile_id
     and new.to_grade_id is not distinct from new.from_grade_id
     and new.to_business_title is not distinct from new.from_business_title then
    raise exception '晋升或降职至少需要实际调整岗位、职级或任职称谓';
  end if;
  return new;
end;
$function$;
drop trigger if exists hr_personnel_change_validate_target
on public.hr_personnel_change;
create trigger hr_personnel_change_validate_target
before insert or update of
  change_type,
  from_position_id,
  to_position_id,
  from_job_profile_id,
  to_job_profile_id,
  from_grade_id,
  to_grade_id,
  from_business_title,
  to_business_title,
  to_organization_id
on public.hr_personnel_change
for each row execute function app_private.validate_hr_personnel_change_target();
