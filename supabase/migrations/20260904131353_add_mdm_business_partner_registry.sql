begin;

create table public.mdm_business_partner (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  partner_code text not null,
  source_code text,
  partner_name text not null,
  legal_name text,
  registration_no text,
  tax_no text,
  enabled boolean not null default true,
  status text not null default 'enabled',
  region text,
  address_detail text,
  contact_name text,
  contact_phone text,
  contact_email text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint mdm_business_partner_id_tenant_key unique (id, tenant_id),
  constraint mdm_business_partner_code_not_blank check (btrim(partner_code) <> ''),
  constraint mdm_business_partner_name_not_blank check (btrim(partner_name) <> '')
);

comment on table public.mdm_business_partner is
  'MDM canonical business-party identity. Role-specific attributes remain in mdm_customer, mdm_carrier, mdm_supplier, mdm_insurance_company, and mdm_external_vendor during the transition.';
comment on column public.mdm_business_partner.partner_code is
  'Tenant-unique canonical code, namespaced by the originating role during initial consolidation.';
comment on column public.mdm_business_partner.source_code is
  'Original role-table business code retained for search and traceability.';

create unique index mdm_business_partner_tenant_code_uq
  on public.mdm_business_partner (tenant_id, lower(partner_code));
create index mdm_business_partner_tenant_name_idx
  on public.mdm_business_partner (tenant_id, lower(partner_name));
create index mdm_business_partner_tenant_tax_idx
  on public.mdm_business_partner (tenant_id, lower(tax_no))
  where tax_no is not null and btrim(tax_no) <> '';
create index mdm_business_partner_tenant_registration_idx
  on public.mdm_business_partner (tenant_id, lower(registration_no))
  where registration_no is not null and btrim(registration_no) <> '';

create table public.mdm_business_partner_role (
  tenant_id uuid not null,
  partner_id uuid not null,
  role_code text not null,
  source_table text not null,
  source_id uuid not null,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint mdm_business_partner_role_pkey
    primary key (tenant_id, partner_id, role_code),
  constraint mdm_business_partner_role_source_key
    unique (source_table, source_id),
  constraint mdm_business_partner_role_partner_fkey
    foreign key (partner_id, tenant_id)
    references public.mdm_business_partner (id, tenant_id)
    on delete cascade,
  constraint mdm_business_partner_role_code_check
    check (role_code in ('customer', 'carrier', 'supplier', 'insurance_company', 'external_vendor')),
  constraint mdm_business_partner_role_source_check
    check (source_table in ('mdm_customer', 'mdm_carrier', 'mdm_supplier', 'mdm_insurance_company', 'mdm_external_vendor'))
);

comment on table public.mdm_business_partner_role is
  'Maps a canonical business party to its current role-specific master record. Maintained by database triggers while legacy role writers are active.';

create index mdm_business_partner_role_tenant_role_idx
  on public.mdm_business_partner_role (tenant_id, role_code, partner_id);

create trigger mdm_business_partner_create_audit
  before insert on public.mdm_business_partner
  for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger mdm_business_partner_update_audit
  before update on public.mdm_business_partner
  for each row execute function public.trg_set_update_time_and_by();
create trigger mdm_business_partner_role_create_audit
  before insert on public.mdm_business_partner_role
  for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger mdm_business_partner_role_update_audit
  before update on public.mdm_business_partner_role
  for each row execute function public.trg_set_update_time_and_by();

alter table public.mdm_business_partner enable row level security;
alter table public.mdm_business_partner_role enable row level security;

create policy mdm_business_partner_tenant_select
  on public.mdm_business_partner
  for select
  to authenticated
  using (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  );

create policy mdm_business_partner_role_tenant_select
  on public.mdm_business_partner_role
  for select
  to authenticated
  using (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  );

revoke all on table public.mdm_business_partner from anon, authenticated;
revoke all on table public.mdm_business_partner_role from anon, authenticated;
grant select on table public.mdm_business_partner to authenticated;
grant select on table public.mdm_business_partner_role to authenticated;
grant all on table public.mdm_business_partner to service_role;
grant all on table public.mdm_business_partner_role to service_role;

do $$
begin
  if exists (
    with source_ids as (
      select id from public.mdm_customer
      union all select id from public.mdm_carrier
      union all select id from public.mdm_supplier
      union all select id from public.mdm_insurance_company
      union all select id from public.mdm_external_vendor
    )
    select 1 from source_ids group by id having count(*) > 1
  ) then
    raise exception 'Cannot initialize MDM partner registry: a UUID is reused by multiple role records';
  end if;
end;
$$;

insert into public.mdm_business_partner (
  id,
  tenant_id,
  partner_code,
  source_code,
  partner_name,
  legal_name,
  registration_no,
  tax_no,
  enabled,
  status,
  region,
  address_detail,
  contact_name,
  contact_phone,
  contact_email,
  create_by,
  create_time,
  update_by,
  update_time
)
select
  id,
  tenant_id,
  'customer:' || customer_code,
  customer_code,
  customer_name,
  coalesce(nullif(invoice_title, ''), customer_name),
  null,
  nullif(tax_no, ''),
  enabled,
  case when enabled then 'enabled' else 'disabled' end,
  region,
  address_detail,
  contact_name,
  contact_phone,
  contact_email,
  create_by,
  create_time,
  update_by,
  update_time
from public.mdm_customer
union all
select
  id,
  tenant_id,
  'carrier:' || carrier_code,
  carrier_code,
  company_name,
  company_name,
  nullif(business_license_no, ''),
  coalesce(nullif(tax_no, ''), nullif(tax_registration_no, '')),
  enabled,
  case when enabled then 'enabled' else 'disabled' end,
  region,
  address_detail,
  contact_name,
  contact_phone,
  contact_email,
  create_by,
  create_time,
  update_by,
  update_time
from public.mdm_carrier
union all
select
  id,
  tenant_id,
  'supplier:' || supplier_code,
  supplier_code,
  supplier_name::text,
  supplier_name::text,
  null,
  null,
  true,
  'enabled',
  region::text,
  address_detail::text,
  contact_person::text,
  contact_phone::text,
  null,
  create_by,
  create_time,
  update_by,
  update_time
from public.mdm_supplier
union all
select
  id,
  tenant_id,
  'insurance_company:' || id::text,
  null,
  company_name,
  company_name,
  null,
  null,
  true,
  'enabled',
  region,
  address_detail,
  contact_person,
  contact_phone,
  null,
  create_by,
  create_time,
  update_by,
  update_time
from public.mdm_insurance_company
union all
select
  id,
  tenant_id,
  'external_vendor:' || vendor_code,
  vendor_code,
  vendor_name,
  vendor_name,
  nullif(registration_no, ''),
  null,
  status not in ('disabled', 'inactive', 'archived'),
  status,
  null,
  null,
  contact_name,
  contact_phone,
  contact_email,
  create_by,
  create_time,
  update_by,
  update_time
from public.mdm_external_vendor;

insert into public.mdm_business_partner_role (
  tenant_id,
  partner_id,
  role_code,
  source_table,
  source_id,
  create_by,
  create_time,
  update_by,
  update_time
)
select tenant_id, id, 'customer', 'mdm_customer', id, create_by, create_time, update_by, update_time
from public.mdm_customer
union all
select tenant_id, id, 'carrier', 'mdm_carrier', id, create_by, create_time, update_by, update_time
from public.mdm_carrier
union all
select tenant_id, id, 'supplier', 'mdm_supplier', id, create_by, create_time, update_by, update_time
from public.mdm_supplier
union all
select tenant_id, id, 'insurance_company', 'mdm_insurance_company', id, create_by, create_time, update_by, update_time
from public.mdm_insurance_company
union all
select tenant_id, id, 'external_vendor', 'mdm_external_vendor', id, create_by, create_time, update_by, update_time
from public.mdm_external_vendor;

create or replace function app_private.sync_mdm_business_partner_role()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  source_row jsonb;
  source_id_value uuid;
  tenant_id_value uuid;
  role_code_value text;
  source_code_value text;
  partner_code_value text;
  partner_name_value text;
  legal_name_value text;
  registration_no_value text;
  tax_no_value text;
  enabled_value boolean;
  status_value text;
  region_value text;
  address_value text;
  contact_name_value text;
  contact_phone_value text;
  contact_email_value text;
  old_source_id uuid;
  old_tenant_id uuid;
begin
  if tg_op = 'DELETE' then
    source_row := to_jsonb(old);
  else
    source_row := to_jsonb(new);
  end if;

  source_id_value := (source_row ->> 'id')::uuid;
  tenant_id_value := (source_row ->> 'tenant_id')::uuid;

  case tg_table_name
    when 'mdm_customer' then
      role_code_value := 'customer';
      source_code_value := source_row ->> 'customer_code';
      partner_name_value := source_row ->> 'customer_name';
      legal_name_value := coalesce(nullif(source_row ->> 'invoice_title', ''), partner_name_value);
      tax_no_value := nullif(source_row ->> 'tax_no', '');
      enabled_value := coalesce((source_row ->> 'enabled')::boolean, true);
      status_value := case when enabled_value then 'enabled' else 'disabled' end;
      contact_name_value := source_row ->> 'contact_name';
    when 'mdm_carrier' then
      role_code_value := 'carrier';
      source_code_value := source_row ->> 'carrier_code';
      partner_name_value := source_row ->> 'company_name';
      legal_name_value := partner_name_value;
      registration_no_value := nullif(source_row ->> 'business_license_no', '');
      tax_no_value := coalesce(nullif(source_row ->> 'tax_no', ''), nullif(source_row ->> 'tax_registration_no', ''));
      enabled_value := coalesce((source_row ->> 'enabled')::boolean, true);
      status_value := case when enabled_value then 'enabled' else 'disabled' end;
      contact_name_value := source_row ->> 'contact_name';
    when 'mdm_supplier' then
      role_code_value := 'supplier';
      source_code_value := source_row ->> 'supplier_code';
      partner_name_value := source_row ->> 'supplier_name';
      legal_name_value := partner_name_value;
      enabled_value := true;
      status_value := 'enabled';
      contact_name_value := source_row ->> 'contact_person';
    when 'mdm_insurance_company' then
      role_code_value := 'insurance_company';
      partner_name_value := source_row ->> 'company_name';
      legal_name_value := partner_name_value;
      enabled_value := true;
      status_value := 'enabled';
      contact_name_value := source_row ->> 'contact_person';
    when 'mdm_external_vendor' then
      role_code_value := 'external_vendor';
      source_code_value := source_row ->> 'vendor_code';
      partner_name_value := source_row ->> 'vendor_name';
      legal_name_value := partner_name_value;
      registration_no_value := nullif(source_row ->> 'registration_no', '');
      status_value := coalesce(nullif(source_row ->> 'status', ''), 'draft');
      enabled_value := status_value not in ('disabled', 'inactive', 'archived');
      contact_name_value := source_row ->> 'contact_name';
    else
      raise exception 'Unsupported MDM role source table: %', tg_table_name;
  end case;

  partner_code_value := role_code_value || ':' || coalesce(nullif(btrim(source_code_value), ''), source_id_value::text);
  region_value := source_row ->> 'region';
  address_value := source_row ->> 'address_detail';
  contact_phone_value := source_row ->> 'contact_phone';
  contact_email_value := source_row ->> 'contact_email';

  if tg_op = 'DELETE' then
    delete from public.mdm_business_partner_role
    where source_table = tg_table_name and source_id = source_id_value;

    delete from public.mdm_business_partner partner
    where partner.id = source_id_value
      and partner.tenant_id = tenant_id_value
      and not exists (
        select 1
        from public.mdm_business_partner_role role_record
        where role_record.partner_id = partner.id
          and role_record.tenant_id = partner.tenant_id
      );
    return old;
  end if;

  if tg_op = 'UPDATE' then
    old_source_id := old.id;
    old_tenant_id := old.tenant_id;
    if old_source_id <> source_id_value or old_tenant_id <> tenant_id_value then
      delete from public.mdm_business_partner_role
      where source_table = tg_table_name and source_id = old_source_id;

      delete from public.mdm_business_partner partner
      where partner.id = old_source_id
        and partner.tenant_id = old_tenant_id
        and not exists (
          select 1
          from public.mdm_business_partner_role role_record
          where role_record.partner_id = partner.id
            and role_record.tenant_id = partner.tenant_id
        );
    end if;
  end if;

  insert into public.mdm_business_partner (
    id,
    tenant_id,
    partner_code,
    source_code,
    partner_name,
    legal_name,
    registration_no,
    tax_no,
    enabled,
    status,
    region,
    address_detail,
    contact_name,
    contact_phone,
    contact_email
  ) values (
    source_id_value,
    tenant_id_value,
    partner_code_value,
    source_code_value,
    partner_name_value,
    legal_name_value,
    registration_no_value,
    tax_no_value,
    enabled_value,
    status_value,
    region_value,
    address_value,
    contact_name_value,
    contact_phone_value,
    contact_email_value
  )
  on conflict (id) do update
  set partner_code = excluded.partner_code,
      source_code = excluded.source_code,
      partner_name = excluded.partner_name,
      legal_name = excluded.legal_name,
      registration_no = excluded.registration_no,
      tax_no = excluded.tax_no,
      enabled = excluded.enabled,
      status = excluded.status,
      region = excluded.region,
      address_detail = excluded.address_detail,
      contact_name = excluded.contact_name,
      contact_phone = excluded.contact_phone,
      contact_email = excluded.contact_email
  where mdm_business_partner.tenant_id = excluded.tenant_id;

  if not found then
    raise exception 'Business partner UUID % is already owned by another tenant', source_id_value;
  end if;

  insert into public.mdm_business_partner_role (
    tenant_id,
    partner_id,
    role_code,
    source_table,
    source_id
  ) values (
    tenant_id_value,
    source_id_value,
    role_code_value,
    tg_table_name,
    source_id_value
  )
  on conflict (source_table, source_id) do update
  set tenant_id = excluded.tenant_id,
      partner_id = excluded.partner_id,
      role_code = excluded.role_code;

  return new;
end;
$$;

comment on function app_private.sync_mdm_business_partner_role() is
  'Maintains canonical business-party identity and role mapping from transitional role-specific MDM tables.';

revoke all on function app_private.sync_mdm_business_partner_role()
  from public, anon, authenticated, service_role;

create trigger mdm_customer_sync_business_partner
  after insert or update or delete on public.mdm_customer
  for each row execute function app_private.sync_mdm_business_partner_role();
create trigger mdm_carrier_sync_business_partner
  after insert or update or delete on public.mdm_carrier
  for each row execute function app_private.sync_mdm_business_partner_role();
create trigger mdm_supplier_sync_business_partner
  after insert or update or delete on public.mdm_supplier
  for each row execute function app_private.sync_mdm_business_partner_role();
create trigger mdm_insurance_company_sync_business_partner
  after insert or update or delete on public.mdm_insurance_company
  for each row execute function app_private.sync_mdm_business_partner_role();
create trigger mdm_external_vendor_sync_business_partner
  after insert or update or delete on public.mdm_external_vendor
  for each row execute function app_private.sync_mdm_business_partner_role();

commit;
