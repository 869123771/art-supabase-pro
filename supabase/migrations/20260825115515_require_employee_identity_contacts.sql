-- Employee identity and primary contact details are required for roster records.
-- Recover trustworthy contact values first, then use explicit non-routable/test
-- placeholders only where no authoritative historical value exists.

update public.hr_employee employee_row
set email = account_row.user_email
from public.sys_user account_row
where account_row.tenant_id = employee_row.tenant_id
  and account_row.hr_employee_id = employee_row.id
  and nullif(btrim(employee_row.email), '') is null
  and nullif(btrim(account_row.user_email), '') is not null;

update public.hr_employee employee_row
set email = lower(regexp_replace(employee_row.employee_no, '[^a-zA-Z0-9._-]+', '-', 'g'))
  || '@placeholder.invalid'
where nullif(btrim(employee_row.email), '') is null;

with missing_identity as (
  select
    employee_row.id,
    row_number() over (
      partition by employee_row.tenant_id
      order by employee_row.employee_no, employee_row.id
    ) as placeholder_sequence
  from public.hr_employee employee_row
  where nullif(btrim(employee_row.id_card_no), '') is null
)
update public.hr_employee employee_row
set id_card_no = '999999'
  || to_char(coalesce(employee_row.birth_date, date '1900-01-01'), 'YYYYMMDD')
  || lpad((missing_identity.placeholder_sequence % 10000)::text, 4, '0')
from missing_identity
where missing_identity.id = employee_row.id;

update public.hr_employee
set
  id_card_no = btrim(id_card_no),
  phone = btrim(phone),
  email = btrim(email);

alter table public.hr_employee
  alter column id_card_no set not null,
  alter column phone set not null,
  alter column email set not null;

alter table public.hr_employee
  add constraint hr_employee_id_card_no_required_check
    check (btrim(id_card_no) <> ''),
  add constraint hr_employee_id_card_no_format_check
    check ((id_card_no ~ '^[0-9]{15}$') or (id_card_no ~ '^[0-9]{17}[0-9Xx]$')),
  add constraint hr_employee_phone_required_check
    check (btrim(phone) <> ''),
  add constraint hr_employee_phone_format_check
    check (phone ~ '^1[3-9][0-9]{9}$'),
  add constraint hr_employee_email_required_check
    check (btrim(email) <> ''),
  add constraint hr_employee_email_format_check
    check (email ~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$');

comment on column public.hr_employee.id_card_no is
  'Employee ID card number; required. Values starting with invalid region code 999999 are explicit historical test placeholders pending manual correction.';
comment on column public.hr_employee.phone is 'Employee primary mobile number; required.';
comment on column public.hr_employee.email is 'Employee primary email address; required.';
