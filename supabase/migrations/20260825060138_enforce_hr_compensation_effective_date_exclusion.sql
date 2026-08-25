-- Database-level concurrency protection for effective-dated HR compensation.
-- Application checks provide friendly errors; exclusion constraints remain the
-- authoritative guard when two approvals race in separate transactions.

create extension if not exists btree_gist with schema extensions

do $migration$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'hr_salary_band_approved_no_overlap'
      and conrelid = 'public.hr_salary_band'::regclass
  ) then
    alter table public.hr_salary_band
      add constraint hr_salary_band_approved_no_overlap
      exclude using gist (
        tenant_id with =,
        grade_id with =,
        currency_code with =,
        daterange(
          effective_from,
          coalesce(effective_to, 'infinity'::date),
          '[]'
        ) with &&
      )
      where (status = 'approved');
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'hr_employee_compensation_approved_no_overlap'
      and conrelid = 'public.hr_employee_compensation'::regclass
  ) then
    alter table public.hr_employee_compensation
      add constraint hr_employee_compensation_approved_no_overlap
      exclude using gist (
        tenant_id with =,
        employee_id with =,
        daterange(
          effective_from,
          coalesce(effective_to, 'infinity'::date),
          '[]'
        ) with &&
      )
      where (status = 'approved');
  end if;
end;
$migration$
