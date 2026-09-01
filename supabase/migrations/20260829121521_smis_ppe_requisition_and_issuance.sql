-- Protective equipment personal requisitions, issuance records and automatic confirmation.

alter table public.smis_ppe_personal_standard_item
  add column if not exists initial_issue_date date,
  add column if not exists last_issue_date date,
  add column if not exists next_issue_date date;

create index if not exists smis_ppe_personal_item_due_idx
  on public.smis_ppe_personal_standard_item (tenant_id, status, next_issue_date)
  where status = 'enabled';

create table public.smis_ppe_setting (
  tenant_id uuid primary key references public.sys_tenant(id) on delete cascade
    default app_private.current_user_tenant_id(),
  auto_confirm_days integer not null default 3
    check (auto_confirm_days between 1 and 30),
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now()
);

create table public.smis_ppe_personal_requisition (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
    references public.sys_tenant(id),
  requisition_no text not null,
  employee_id uuid not null references public.hr_employee(id) on delete restrict,
  employee_no_snapshot text not null,
  employee_name_snapshot text not null,
  position_id uuid references public.hr_position(id) on delete set null,
  position_name_snapshot text,
  organization_id uuid references public.sys_organization(id) on delete set null,
  organization_name_snapshot text,
  operation_department_snapshot text,
  operation_area_snapshot text,
  team_snapshot text,
  planned_issue_date date not null,
  status text not null default 'pending_issue'
    check (status in ('pending_issue','partial','issued_pending_confirmation','confirmed','denied','cancelled')),
  source text not null default 'standard'
    check (source in ('standard','manual','import')),
  reminder text,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_ppe_requisition_id_tenant_unique unique (id, tenant_id),
  constraint smis_ppe_requisition_no_unique unique (tenant_id, requisition_no),
  constraint smis_ppe_requisition_employee_due_unique
    unique (tenant_id, employee_id, planned_issue_date)
);

create table public.smis_ppe_personal_requisition_item (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
    references public.sys_tenant(id),
  requisition_id uuid not null,
  personal_standard_item_id uuid references public.smis_ppe_personal_standard_item(id) on delete set null,
  material_id uuid not null references public.smis_material(id) on delete restrict,
  material_category_snapshot text,
  material_name_snapshot text not null,
  specification_model_snapshot text,
  unit_snapshot text not null,
  image_urls jsonb not null default '[]'::jsonb check (jsonb_typeof(image_urls) = 'array'),
  quota_quantity numeric(12,3) not null check (quota_quantity > 0),
  requested_quantity numeric(12,3) not null check (requested_quantity > 0),
  quota_cycle_months integer not null check (quota_cycle_months between 1 and 1200),
  status text not null default 'pending_issue'
    check (status in ('pending_issue','issued_pending_confirmation','confirmed','denied','cancelled')),
  issued_at timestamptz,
  confirmed_at timestamptz,
  confirmation_source text check (confirmation_source is null or confirmation_source in ('employee','system')),
  denial_reason text check (denial_reason is null or char_length(denial_reason) <= 500),
  remark text check (remark is null or char_length(remark) <= 500),
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_ppe_requisition_item_parent_fkey
    foreign key (requisition_id, tenant_id)
    references public.smis_ppe_personal_requisition(id, tenant_id) on delete cascade,
  constraint smis_ppe_requisition_item_source_unique
    unique (requisition_id, personal_standard_item_id)
);

create table public.smis_ppe_issuance_record (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
    references public.sys_tenant(id),
  issuance_no text not null,
  employee_id uuid not null references public.hr_employee(id) on delete restrict,
  employee_no_snapshot text not null,
  employee_name_snapshot text not null,
  position_name_snapshot text,
  organization_id uuid references public.sys_organization(id) on delete set null,
  organization_name_snapshot text,
  warehouse_id uuid not null references public.smis_storage_location(id) on delete restrict,
  warehouse_name_snapshot text not null,
  issuer_employee_id uuid not null references public.hr_employee(id) on delete restrict,
  issuer_name_snapshot text not null,
  issue_date date not null,
  status text not null default 'draft' check (status in ('draft','posted','voided')),
  posted_at timestamptz,
  remark text check (remark is null or char_length(remark) <= 1000),
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_ppe_issuance_id_tenant_unique unique (id, tenant_id),
  constraint smis_ppe_issuance_no_unique unique (tenant_id, issuance_no)
);

create table public.smis_ppe_issuance_record_item (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
    references public.sys_tenant(id),
  issuance_record_id uuid not null,
  requisition_item_id uuid references public.smis_ppe_personal_requisition_item(id) on delete restrict,
  material_id uuid not null references public.smis_material(id) on delete restrict,
  material_category_snapshot text,
  material_name_snapshot text not null,
  specification_model_snapshot text,
  unit_snapshot text not null,
  issue_quantity numeric(12,3) not null check (issue_quantity > 0),
  remark text check (remark is null or char_length(remark) <= 500),
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_ppe_issuance_item_parent_fkey
    foreign key (issuance_record_id, tenant_id)
    references public.smis_ppe_issuance_record(id, tenant_id) on delete cascade,
  constraint smis_ppe_issuance_item_requisition_unique unique (requisition_item_id)
);

create index smis_ppe_requisition_scope_idx
  on public.smis_ppe_personal_requisition (tenant_id, planned_issue_date desc, organization_id, employee_id);
create index smis_ppe_requisition_status_idx
  on public.smis_ppe_personal_requisition_item (tenant_id, status, issued_at);
create index smis_ppe_issuance_scope_idx
  on public.smis_ppe_issuance_record (tenant_id, issue_date desc, organization_id, employee_id, status);
create index smis_ppe_issuance_item_material_idx
  on public.smis_ppe_issuance_record_item (tenant_id, material_id);

create trigger smis_ppe_setting_create_audit before insert on public.smis_ppe_setting
for each row execute function public.trg_set_create_time_and_by('true','true');
create trigger smis_ppe_setting_update_audit before update on public.smis_ppe_setting
for each row execute function public.trg_set_update_time_and_by();
create trigger smis_ppe_requisition_create_audit before insert on public.smis_ppe_personal_requisition
for each row execute function public.trg_set_create_time_and_by('true','true');
create trigger smis_ppe_requisition_update_audit before update on public.smis_ppe_personal_requisition
for each row execute function public.trg_set_update_time_and_by();
create trigger smis_ppe_requisition_item_create_audit before insert on public.smis_ppe_personal_requisition_item
for each row execute function public.trg_set_create_time_and_by('true','true');
create trigger smis_ppe_requisition_item_update_audit before update on public.smis_ppe_personal_requisition_item
for each row execute function public.trg_set_update_time_and_by();
create trigger smis_ppe_issuance_create_audit before insert on public.smis_ppe_issuance_record
for each row execute function public.trg_set_create_time_and_by('true','true');
create trigger smis_ppe_issuance_update_audit before update on public.smis_ppe_issuance_record
for each row execute function public.trg_set_update_time_and_by();
create trigger smis_ppe_issuance_item_create_audit before insert on public.smis_ppe_issuance_record_item
for each row execute function public.trg_set_create_time_and_by('true','true');
create trigger smis_ppe_issuance_item_update_audit before update on public.smis_ppe_issuance_record_item
for each row execute function public.trg_set_update_time_and_by();

alter table public.smis_ppe_setting enable row level security;
alter table public.smis_ppe_personal_requisition enable row level security;
alter table public.smis_ppe_personal_requisition_item enable row level security;
alter table public.smis_ppe_issuance_record enable row level security;
alter table public.smis_ppe_issuance_record_item enable row level security;

create policy smis_ppe_setting_select on public.smis_ppe_setting for select to authenticated
using ((select app_private.is_platform_super()) or tenant_id = (select app_private.auth_user_tenant_id()));
create policy smis_ppe_setting_insert on public.smis_ppe_setting for insert to authenticated
with check (tenant_id = (select app_private.auth_user_tenant_id()) and (select app_private.has_permission('SmisPpePersonalRequisition:Configure')));
create policy smis_ppe_setting_update on public.smis_ppe_setting for update to authenticated
using (tenant_id = (select app_private.auth_user_tenant_id()) and (select app_private.has_permission('SmisPpePersonalRequisition:Configure')))
with check (tenant_id = (select app_private.auth_user_tenant_id()) and (select app_private.has_permission('SmisPpePersonalRequisition:Configure')));

create policy smis_ppe_requisition_select on public.smis_ppe_personal_requisition for select to authenticated
using ((select app_private.is_platform_super()) or (tenant_id = (select app_private.auth_user_tenant_id()) and (select app_private.has_permission('SmisPpePersonalRequisition:View'))));
create policy smis_ppe_requisition_item_select on public.smis_ppe_personal_requisition_item for select to authenticated
using ((select app_private.is_platform_super()) or (tenant_id = (select app_private.auth_user_tenant_id()) and (select app_private.has_permission('SmisPpePersonalRequisition:View'))));
create policy smis_ppe_issuance_select on public.smis_ppe_issuance_record for select to authenticated
using ((select app_private.is_platform_super()) or (tenant_id = (select app_private.auth_user_tenant_id()) and (select app_private.has_permission('SmisPpeIssuanceRecord:View'))));
create policy smis_ppe_issuance_item_select on public.smis_ppe_issuance_record_item for select to authenticated
using ((select app_private.is_platform_super()) or (tenant_id = (select app_private.auth_user_tenant_id()) and (select app_private.has_permission('SmisPpeIssuanceRecord:View'))));

revoke all on public.smis_ppe_setting, public.smis_ppe_personal_requisition,
  public.smis_ppe_personal_requisition_item, public.smis_ppe_issuance_record,
  public.smis_ppe_issuance_record_item from anon;
grant select on public.smis_ppe_setting, public.smis_ppe_personal_requisition,
  public.smis_ppe_personal_requisition_item, public.smis_ppe_issuance_record,
  public.smis_ppe_issuance_record_item to authenticated;

create or replace function app_private.ppe_cycle_months(p_cycle text, p_frequency integer)
returns integer language sql immutable set search_path = '' as $$
  select greatest(1, case p_cycle
    when 'day' then ceil(p_frequency::numeric / 30)::integer
    when 'week' then ceil(p_frequency::numeric * 7 / 30)::integer
    when 'month' then p_frequency
    when 'quarter' then p_frequency * 3
    when 'half_year' then p_frequency * 6
    when 'year' then p_frequency * 12
    else p_frequency end)
$$;

create or replace function app_private.refresh_ppe_requisition_status(p_requisition_id uuid)
returns void language plpgsql set search_path = '' as $$
declare v_status text;
begin
  select case
    when bool_and(i.status = 'confirmed') then 'confirmed'
    when bool_and(i.status = 'denied') then 'denied'
    when bool_and(i.status in ('confirmed','denied')) then 'partial'
    when bool_or(i.status = 'issued_pending_confirmation') then 'issued_pending_confirmation'
    when bool_or(i.status = 'pending_issue') then 'pending_issue'
    else 'partial' end
  into v_status from public.smis_ppe_personal_requisition_item i
  where i.requisition_id = p_requisition_id;
  update public.smis_ppe_personal_requisition set status = coalesce(v_status, status)
  where id = p_requisition_id;
end $$;

create or replace function app_private.generate_due_ppe_requisitions(p_due_date date default current_date)
returns jsonb language plpgsql set search_path = '' as $$
declare v_employee record; v_requisition_id uuid; v_count integer := 0; v_item_count integer := 0; v_inserted integer;
begin
  for v_employee in
    select ps.tenant_id, ps.employee_id, e.employee_no, e.employee_name, e.position_id,
      p.position_name, e.organization_id, o.organization_name,
      min(i.next_issue_date) as planned_issue_date
    from public.smis_ppe_personal_standard ps
    join public.smis_ppe_personal_standard_item i on i.personal_standard_id = ps.id
    join public.hr_employee e on e.id = ps.employee_id
    left join public.hr_position p on p.id = e.position_id
    left join public.sys_organization o on o.id = e.organization_id
    where ps.status = 'enabled' and i.status = 'enabled'
      and coalesce(i.next_issue_date, i.initial_issue_date) <= p_due_date
      and not exists (
        select 1 from public.smis_ppe_personal_requisition_item ri
        join public.smis_ppe_personal_requisition r on r.id = ri.requisition_id
        where ri.personal_standard_item_id = i.id
          and ri.status in ('pending_issue','issued_pending_confirmation')
      )
    group by ps.tenant_id, ps.employee_id, e.employee_no, e.employee_name,
      e.position_id, p.position_name, e.organization_id, o.organization_name
  loop
    insert into public.smis_ppe_personal_requisition(
      tenant_id,requisition_no,employee_id,employee_no_snapshot,employee_name_snapshot,
      position_id,position_name_snapshot,organization_id,organization_name_snapshot,
      planned_issue_date,status,source,reminder)
    values (v_employee.tenant_id,
      app_private.next_document_number('smis.ppe_personal_requisition',v_employee.tenant_id),
      v_employee.employee_id,v_employee.employee_no,v_employee.employee_name,
      v_employee.position_id,v_employee.position_name,v_employee.organization_id,
      v_employee.organization_name,v_employee.planned_issue_date,'pending_issue','standard','已到防护用品领用周期')
    on conflict (tenant_id,employee_id,planned_issue_date) do update set update_time = now()
    returning id into v_requisition_id;

    insert into public.smis_ppe_personal_requisition_item(
      tenant_id,requisition_id,personal_standard_item_id,material_id,material_category_snapshot,
      material_name_snapshot,specification_model_snapshot,unit_snapshot,image_urls,
      quota_quantity,requested_quantity,quota_cycle_months,status)
    select i.tenant_id,v_requisition_id,i.id,i.material_id,c.category_name,m.material_name,
      m.specification_model,m.basic_unit,m.image_urls,i.quota_quantity,i.quota_quantity,
      app_private.ppe_cycle_months(i.issuance_cycle,i.issuance_frequency),'pending_issue'
    from public.smis_ppe_personal_standard_item i
    join public.smis_material m on m.id = i.material_id
    join public.smis_material_category c on c.id = m.category_id
    where i.personal_standard_id in (
      select ps.id from public.smis_ppe_personal_standard ps
      where ps.tenant_id = v_employee.tenant_id and ps.employee_id = v_employee.employee_id)
      and i.status = 'enabled' and coalesce(i.next_issue_date,i.initial_issue_date) <= p_due_date
      and not exists (
        select 1 from public.smis_ppe_personal_requisition_item existing
        where existing.personal_standard_item_id = i.id
          and existing.status in ('pending_issue','issued_pending_confirmation'))
    on conflict (requisition_id,personal_standard_item_id) do nothing;
    get diagnostics v_inserted = row_count;
    if v_inserted > 0 then v_count := v_count + 1; v_item_count := v_item_count + v_inserted; end if;
  end loop;
  return jsonb_build_object('documentCount',v_count,'itemCount',v_item_count);
end $$;

create or replace function app_private.auto_confirm_ppe_requisitions()
returns integer language plpgsql set search_path = '' as $$
declare v_count integer; v_requisition uuid;
begin
  update public.smis_ppe_personal_requisition_item i
  set status='confirmed', confirmed_at=now(), confirmation_source='system', denial_reason=null
  from public.smis_ppe_personal_requisition r
  left join public.smis_ppe_setting s on s.tenant_id=r.tenant_id
  where i.requisition_id=r.id and i.status='issued_pending_confirmation'
    and i.issued_at <= now() - make_interval(days => coalesce(s.auto_confirm_days,3));
  get diagnostics v_count = row_count;
  for v_requisition in select distinct r.id from public.smis_ppe_personal_requisition r
    join public.smis_ppe_personal_requisition_item i on i.requisition_id=r.id
    where r.status in ('issued_pending_confirmation','partial')
  loop perform app_private.refresh_ppe_requisition_status(v_requisition); end loop;
  return v_count;
end $$;

create or replace function app_private.run_daily_ppe_automation()
returns jsonb language plpgsql set search_path = '' as $$
declare v_generated jsonb; v_confirmed integer;
begin
  v_generated := app_private.generate_due_ppe_requisitions(current_date);
  v_confirmed := app_private.auto_confirm_ppe_requisitions();
  return jsonb_build_object('generated',v_generated,'confirmedItemCount',v_confirmed);
end $$;

revoke all on function app_private.ppe_cycle_months(text,integer) from public,anon,authenticated;
revoke all on function app_private.refresh_ppe_requisition_status(uuid) from public,anon,authenticated;
revoke all on function app_private.generate_due_ppe_requisitions(date) from public,anon,authenticated;
revoke all on function app_private.auto_confirm_ppe_requisitions() from public,anon,authenticated;
revoke all on function app_private.run_daily_ppe_automation() from public,anon,authenticated;

create or replace function public.smis_get_ppe_setting_secure()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_tenant uuid;
begin
  if (select auth.uid()) is null then raise exception '请先登录' using errcode='42501'; end if;
  if not (app_private.is_platform_super() or app_private.has_permission('SmisPpePersonalRequisition:View')) then raise exception '当前账号没有查看领用配置的权限' using errcode='42501'; end if;
  v_tenant := app_private.current_read_tenant_id();
  return jsonb_build_object('autoConfirmDays',coalesce((select auto_confirm_days from public.smis_ppe_setting where tenant_id=v_tenant),3));
end $$;

create or replace function public.smis_save_ppe_setting_secure(p_auto_confirm_days integer)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_tenant uuid;
begin
  if (select auth.uid()) is null then raise exception '请先登录' using errcode='42501'; end if;
  if not app_private.has_permission('SmisPpePersonalRequisition:Configure') then raise exception '当前账号没有配置自动确认规则的权限' using errcode='42501'; end if;
  if p_auto_confirm_days not between 1 and 30 then raise exception '自动确认天数必须在 1 至 30 天之间' using errcode='22023'; end if;
  v_tenant := app_private.auth_user_tenant_id();
  insert into public.smis_ppe_setting(tenant_id,auto_confirm_days) values(v_tenant,p_auto_confirm_days)
  on conflict(tenant_id) do update set auto_confirm_days=excluded.auto_confirm_days;
  return p_auto_confirm_days;
end $$;

create or replace function public.smis_set_ppe_personal_issue_plan_secure(p_employee_id uuid,p_items jsonb)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_item jsonb; v_count integer := 0;
begin
  if (select auth.uid()) is null or not app_private.has_permission('SmisPpePersonalStandard:Schedule') then raise exception '当前账号没有设置个人领用计划的权限' using errcode='42501'; end if;
  if jsonb_typeof(coalesce(p_items,'[]'::jsonb)) <> 'array' then raise exception '领用计划格式无效' using errcode='22023'; end if;
  for v_item in select value from jsonb_array_elements(p_items) loop
    update public.smis_ppe_personal_standard_item i set
      initial_issue_date=(v_item->>'initial_issue_date')::date,
      next_issue_date=(v_item->>'next_issue_date')::date,
      issuance_cycle=coalesce(v_item->>'issuance_cycle',i.issuance_cycle),
      issuance_frequency=coalesce((v_item->>'issuance_frequency')::integer,i.issuance_frequency)
    from public.smis_ppe_personal_standard ps
    where i.id=(v_item->>'id')::uuid and ps.id=i.personal_standard_id
      and ps.employee_id=p_employee_id
      and (app_private.is_platform_super() or i.tenant_id=app_private.auth_user_tenant_id());
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

create or replace function public.smis_generate_due_ppe_requisitions_secure(p_due_date date default current_date)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null or not app_private.has_permission('SmisPpePersonalRequisition:Generate') then raise exception '当前账号没有生成领用单的权限' using errcode='42501'; end if;
  return app_private.generate_due_ppe_requisitions(coalesce(p_due_date,current_date));
end $$;

create or replace function public.smis_list_ppe_personal_requisitions_secure(
  p_from integer default 0,p_to integer default 19,p_date_from date default null,p_date_to date default null,
  p_organization_id uuid default null,p_employee_id uuid default null,p_status text default null,
  p_keyword text default null,p_purpose text default 'list')
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_from integer:=greatest(coalesce(p_from,0),0); v_to integer:=greatest(coalesce(p_to,19),v_from); v_keyword text:=nullif(btrim(coalesce(p_keyword,'')),'');
begin
  if (select auth.uid()) is null then raise exception '请先登录' using errcode='42501'; end if;
  if p_purpose='export' and not app_private.has_permission('SmisPpePersonalRequisition:Export') then raise exception '当前账号没有导出领用单的权限' using errcode='42501'; end if;
  if p_purpose='list' and not (app_private.is_platform_super() or app_private.has_permission('SmisPpePersonalRequisition:View')) then raise exception '当前账号没有查看领用单的权限' using errcode='42501'; end if;
  return (with filtered as (
    select i.*,r.requisition_no,r.employee_id,r.employee_no_snapshot,r.employee_name_snapshot,
      r.position_name_snapshot,r.organization_id,r.organization_name_snapshot,
      r.operation_department_snapshot,r.operation_area_snapshot,r.team_snapshot,r.planned_issue_date,
      r.reminder,r.remark as header_remark
    from public.smis_ppe_personal_requisition_item i
    join public.smis_ppe_personal_requisition r on r.id=i.requisition_id
    where (app_private.current_read_tenant_id() is null or r.tenant_id=app_private.current_read_tenant_id())
      and (p_date_from is null or r.planned_issue_date>=p_date_from)
      and (p_date_to is null or r.planned_issue_date<=p_date_to)
      and (p_organization_id is null or r.organization_id=p_organization_id)
      and (p_employee_id is null or r.employee_id=p_employee_id)
      and (p_status is null or i.status=p_status)
      and (v_keyword is null or r.requisition_no ilike '%'||v_keyword||'%' or r.employee_name_snapshot ilike '%'||v_keyword||'%' or i.material_name_snapshot ilike '%'||v_keyword||'%')
  ), rows as (
    select id,"tenantId","requisitionId","requisitionNo","employeeId","employeeNo","employeeName","positionName",
      "organizationId","organizationName","operationDepartment","operationArea","team","materialId","materialCategory",
      "materialName","specificationModel","unit","imageUrls","quotaQuantity","requestedQuantity","quotaCycleMonths",
      "plannedIssueDate",status,"reminder","issuedAt","confirmedAt","confirmationSource","denialReason",remark
    from (select f.id,f.tenant_id as "tenantId",f.requisition_id as "requisitionId",f.requisition_no as "requisitionNo",
      f.employee_id as "employeeId",f.employee_no_snapshot as "employeeNo",f.employee_name_snapshot as "employeeName",
      f.position_name_snapshot as "positionName",f.organization_id as "organizationId",f.organization_name_snapshot as "organizationName",
      f.operation_department_snapshot as "operationDepartment",f.operation_area_snapshot as "operationArea",f.team_snapshot as team,
      f.material_id as "materialId",f.material_category_snapshot as "materialCategory",f.material_name_snapshot as "materialName",
      f.specification_model_snapshot as "specificationModel",f.unit_snapshot as unit,f.image_urls as "imageUrls",
      f.quota_quantity as "quotaQuantity",f.requested_quantity as "requestedQuantity",f.quota_cycle_months as "quotaCycleMonths",
      f.planned_issue_date as "plannedIssueDate",f.status,f.reminder,f.issued_at as "issuedAt",f.confirmed_at as "confirmedAt",
      f.confirmation_source as "confirmationSource",f.denial_reason as "denialReason",coalesce(f.remark,f.header_remark) as remark
      from filtered f order by f.planned_issue_date desc,f.requisition_no,f.employee_name_snapshot,f.material_name_snapshot
      offset v_from limit v_to-v_from+1) page
  ) select jsonb_build_object('records',coalesce((select jsonb_agg(rows) from rows),'[]'::jsonb),'total',(select count(*) from filtered),
    'overview',(select jsonb_build_object('total',count(*),'pending',count(*) filter(where status='pending_issue'),'waitingConfirmation',count(*) filter(where status='issued_pending_confirmation'),'confirmed',count(*) filter(where status='confirmed'),'overdue',count(*) filter(where status='pending_issue' and planned_issue_date<current_date)) from filtered)));
end $$;

create or replace function public.smis_list_ppe_issuance_records_secure(
  p_from integer default 0,p_to integer default 19,p_date_from date default null,p_date_to date default null,
  p_organization_id uuid default null,p_employee_id uuid default null,p_status text default null,
  p_keyword text default null,p_purpose text default 'list')
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_from integer:=greatest(coalesce(p_from,0),0); v_to integer:=greatest(coalesce(p_to,19),v_from); v_keyword text:=nullif(btrim(coalesce(p_keyword,'')),'');
begin
  if (select auth.uid()) is null then raise exception '请先登录' using errcode='42501'; end if;
  if p_purpose='export' and not app_private.has_permission('SmisPpeIssuanceRecord:Export') then raise exception '当前账号没有导出发放记录的权限' using errcode='42501'; end if;
  if p_purpose='list' and not (app_private.is_platform_super() or app_private.has_permission('SmisPpeIssuanceRecord:View')) then raise exception '当前账号没有查看发放记录的权限' using errcode='42501'; end if;
  return (with filtered as (
    select r.* from public.smis_ppe_issuance_record r
    where (app_private.current_read_tenant_id() is null or r.tenant_id=app_private.current_read_tenant_id())
      and (p_date_from is null or r.issue_date>=p_date_from) and (p_date_to is null or r.issue_date<=p_date_to)
      and (p_organization_id is null or r.organization_id=p_organization_id)
      and (p_employee_id is null or r.employee_id=p_employee_id) and (p_status is null or r.status=p_status)
      and (v_keyword is null or r.issuance_no ilike '%'||v_keyword||'%' or r.employee_name_snapshot ilike '%'||v_keyword||'%' or r.warehouse_name_snapshot ilike '%'||v_keyword||'%')
  ), rows as (
    select r.id,r.tenant_id as "tenantId",r.issuance_no as "issuanceNo",r.employee_id as "employeeId",
      r.employee_no_snapshot as "employeeNo",r.employee_name_snapshot as "employeeName",r.position_name_snapshot as "positionName",
      r.organization_id as "organizationId",r.organization_name_snapshot as "organizationName",r.warehouse_id as "warehouseId",
      r.warehouse_name_snapshot as "warehouseName",r.issuer_employee_id as "issuerEmployeeId",r.issuer_name_snapshot as "issuerName",
      r.issue_date as "issueDate",r.status,r.posted_at as "postedAt",r.remark,r.create_time as "createTime",
      coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'requisitionItemId',i.requisition_item_id,'materialId',i.material_id,
        'materialCategory',i.material_category_snapshot,'materialName',i.material_name_snapshot,'specificationModel',i.specification_model_snapshot,
        'unit',i.unit_snapshot,'issueQuantity',i.issue_quantity,'remark',i.remark) order by i.material_name_snapshot)
        from public.smis_ppe_issuance_record_item i where i.issuance_record_id=r.id),'[]'::jsonb) items
    from filtered r order by r.issue_date desc,r.create_time desc offset v_from limit v_to-v_from+1
  ) select jsonb_build_object('records',coalesce((select jsonb_agg(rows) from rows),'[]'::jsonb),'total',(select count(*) from filtered),
    'overview',(select jsonb_build_object('total',count(*),'draft',count(*) filter(where status='draft'),'posted',count(*) filter(where status='posted'),'today',count(*) filter(where issue_date=current_date),'quantity',coalesce(sum((select sum(i.issue_quantity) from public.smis_ppe_issuance_record_item i where i.issuance_record_id=filtered.id)),0)) from filtered)));
end $$;

create or replace function public.smis_save_ppe_issuance_record_secure(p_id uuid,p_payload jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_tenant uuid; v_id uuid; v_employee record; v_warehouse record; v_issuer record; v_item jsonb; v_material record;
begin
  if (select auth.uid()) is null then raise exception '请先登录' using errcode='42501'; end if;
  if p_id is null and not app_private.has_permission('SmisPpeIssuanceRecord:Add') then raise exception '当前账号没有新增发放记录的权限' using errcode='42501'; end if;
  if p_id is not null and not app_private.has_permission('SmisPpeIssuanceRecord:Edit') then raise exception '当前账号没有编辑发放记录的权限' using errcode='42501'; end if;
  v_tenant:=app_private.resolve_mutation_tenant_id((select tenant_id from public.smis_ppe_issuance_record where id=p_id));
  select e.*,o.organization_name,p.position_name into v_employee from public.hr_employee e left join public.sys_organization o on o.id=e.organization_id left join public.hr_position p on p.id=e.position_id where e.id=(p_payload->>'employee_id')::uuid and e.tenant_id=v_tenant;
  select * into v_warehouse from public.smis_storage_location where id=(p_payload->>'warehouse_id')::uuid and tenant_id=v_tenant and status='enabled';
  select * into v_issuer from public.hr_employee where id=(p_payload->>'issuer_employee_id')::uuid and tenant_id=v_tenant;
  if v_employee.id is null or v_warehouse.id is null or v_issuer.id is null then raise exception '领用人、发放仓库或发放人无效' using errcode='P0002'; end if;
  if jsonb_array_length(coalesce(p_payload->'items','[]'::jsonb))=0 then raise exception '请至少添加一条发放明细' using errcode='22023'; end if;
  if p_id is null then
    insert into public.smis_ppe_issuance_record(tenant_id,issuance_no,employee_id,employee_no_snapshot,employee_name_snapshot,position_name_snapshot,organization_id,organization_name_snapshot,warehouse_id,warehouse_name_snapshot,issuer_employee_id,issuer_name_snapshot,issue_date,status,remark)
    values(v_tenant,app_private.next_document_number('smis.ppe_issuance_record',v_tenant),v_employee.id,v_employee.employee_no,v_employee.employee_name,v_employee.position_name,v_employee.organization_id,v_employee.organization_name,v_warehouse.id,v_warehouse.location_name,v_issuer.id,v_issuer.employee_name,coalesce((p_payload->>'issue_date')::date,current_date),'draft',nullif(btrim(coalesce(p_payload->>'remark','')),'')) returning id into v_id;
  else
    if not exists(select 1 from public.smis_ppe_issuance_record where id=p_id and tenant_id=v_tenant and status='draft') then raise exception '仅草稿状态允许编辑' using errcode='P0001'; end if;
    update public.smis_ppe_issuance_record set employee_id=v_employee.id,employee_no_snapshot=v_employee.employee_no,employee_name_snapshot=v_employee.employee_name,position_name_snapshot=v_employee.position_name,organization_id=v_employee.organization_id,organization_name_snapshot=v_employee.organization_name,warehouse_id=v_warehouse.id,warehouse_name_snapshot=v_warehouse.location_name,issuer_employee_id=v_issuer.id,issuer_name_snapshot=v_issuer.employee_name,issue_date=coalesce((p_payload->>'issue_date')::date,current_date),remark=nullif(btrim(coalesce(p_payload->>'remark','')),'') where id=p_id returning id into v_id;
    delete from public.smis_ppe_issuance_record_item where issuance_record_id=v_id;
  end if;
  for v_item in select value from jsonb_array_elements(p_payload->'items') loop
    select m.*,c.category_name into v_material from public.smis_material m join public.smis_material_category c on c.id=m.category_id where m.id=(v_item->>'material_id')::uuid and m.tenant_id=v_tenant and m.material_type='protective_equipment';
    if v_material.id is null then raise exception '发放明细中的防护用品无效' using errcode='P0002'; end if;
    insert into public.smis_ppe_issuance_record_item(tenant_id,issuance_record_id,requisition_item_id,material_id,material_category_snapshot,material_name_snapshot,specification_model_snapshot,unit_snapshot,issue_quantity,remark)
    values(v_tenant,v_id,nullif(v_item->>'requisition_item_id','')::uuid,v_material.id,v_material.category_name,v_material.material_name,v_material.specification_model,v_material.basic_unit,(v_item->>'issue_quantity')::numeric,nullif(btrim(coalesce(v_item->>'remark','')),''));
  end loop;
  return v_id;
end $$;

create or replace function public.smis_delete_ppe_issuance_records_secure(p_ids uuid[])
returns integer language plpgsql security definer set search_path = '' as $$
declare v_count integer;
begin
  if (select auth.uid()) is null or not app_private.has_permission('SmisPpeIssuanceRecord:Delete') then raise exception '当前账号没有删除发放记录的权限' using errcode='42501'; end if;
  if exists(select 1 from public.smis_ppe_issuance_record where id=any(coalesce(p_ids,array[]::uuid[])) and status<>'draft') then raise exception '仅草稿状态允许删除' using errcode='P0001'; end if;
  delete from public.smis_ppe_issuance_record where id=any(coalesce(p_ids,array[]::uuid[])) and (app_private.is_platform_super() or tenant_id=app_private.auth_user_tenant_id());
  get diagnostics v_count=row_count; return v_count;
end $$;

create or replace function app_private.post_ppe_issuance_record(p_record_id uuid)
returns text language plpgsql set search_path = '' as $$
declare v_record record; v_item record; v_months integer;
begin
  select * into v_record from public.smis_ppe_issuance_record where id=p_record_id for update;
  if v_record.id is null or v_record.status<>'draft' then raise exception '仅草稿状态允许发放过账' using errcode='P0001'; end if;
  update public.smis_ppe_issuance_record set status='posted',posted_at=now() where id=p_record_id;
  for v_item in select i.*,ri.requisition_id,ri.personal_standard_item_id,ri.quota_cycle_months from public.smis_ppe_issuance_record_item i left join public.smis_ppe_personal_requisition_item ri on ri.id=i.requisition_item_id where i.issuance_record_id=p_record_id loop
    if v_item.requisition_item_id is not null then
      update public.smis_ppe_personal_requisition_item set status='issued_pending_confirmation',issued_at=now() where id=v_item.requisition_item_id;
      perform app_private.refresh_ppe_requisition_status(v_item.requisition_id);
    end if;
    update public.smis_ppe_personal_standard_item psi set last_issue_date=v_record.issue_date,next_issue_date=v_record.issue_date+make_interval(months=>app_private.ppe_cycle_months(psi.issuance_cycle,psi.issuance_frequency)) where psi.id=v_item.personal_standard_item_id;
  end loop;
  return v_record.issuance_no;
end $$;

create or replace function public.smis_post_ppe_issuance_record_secure(p_record_id uuid)
returns text language plpgsql security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null or not app_private.has_permission('SmisPpeIssuanceRecord:Issue') then raise exception '当前账号没有发放过账权限' using errcode='42501'; end if;
  if not exists(select 1 from public.smis_ppe_issuance_record where id=p_record_id and (app_private.is_platform_super() or tenant_id=app_private.auth_user_tenant_id())) then raise exception '发放记录不存在或不属于当前租户' using errcode='P0002'; end if;
  return app_private.post_ppe_issuance_record(p_record_id);
end $$;

create or replace function public.smis_push_ppe_requisition_items_secure(p_item_ids uuid[],p_warehouse_id uuid,p_issuer_employee_id uuid,p_issue_date date default current_date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_tenant uuid; v_employee uuid; v_record_id uuid; v_no text; v_employee_row record; v_warehouse record; v_issuer record;
begin
  if (select auth.uid()) is null or not app_private.has_permission('SmisPpePersonalRequisition:Push') then raise exception '当前账号没有下推发放的权限' using errcode='42501'; end if;
  if cardinality(coalesce(p_item_ids,array[]::uuid[]))=0 then raise exception '请选择待发放的领用明细' using errcode='22023'; end if;
  select min(r.tenant_id),min(r.employee_id) into v_tenant,v_employee from public.smis_ppe_personal_requisition_item i join public.smis_ppe_personal_requisition r on r.id=i.requisition_id where i.id=any(p_item_ids) and i.status='pending_issue';
  if v_tenant is null or exists(select 1 from public.smis_ppe_personal_requisition_item i join public.smis_ppe_personal_requisition r on r.id=i.requisition_id where i.id=any(p_item_ids) and (r.tenant_id<>v_tenant or r.employee_id<>v_employee or i.status<>'pending_issue')) then raise exception '只能选择同一领用人的待发放明细' using errcode='22023'; end if;
  if not app_private.is_platform_super() and v_tenant<>app_private.auth_user_tenant_id() then raise exception '所选数据不属于当前租户' using errcode='42501'; end if;
  select e.*,o.organization_name,p.position_name into v_employee_row from public.hr_employee e left join public.sys_organization o on o.id=e.organization_id left join public.hr_position p on p.id=e.position_id where e.id=v_employee and e.tenant_id=v_tenant;
  select * into v_warehouse from public.smis_storage_location where id=p_warehouse_id and tenant_id=v_tenant and status='enabled';
  select * into v_issuer from public.hr_employee where id=p_issuer_employee_id and tenant_id=v_tenant;
  if v_employee_row.id is null or v_warehouse.id is null or v_issuer.id is null then raise exception '领用人、发放仓库或发放人无效' using errcode='P0002'; end if;
  insert into public.smis_ppe_issuance_record(tenant_id,issuance_no,employee_id,employee_no_snapshot,employee_name_snapshot,position_name_snapshot,organization_id,organization_name_snapshot,warehouse_id,warehouse_name_snapshot,issuer_employee_id,issuer_name_snapshot,issue_date,status)
  values(v_tenant,app_private.next_document_number('smis.ppe_issuance_record',v_tenant),v_employee_row.id,v_employee_row.employee_no,v_employee_row.employee_name,v_employee_row.position_name,v_employee_row.organization_id,v_employee_row.organization_name,v_warehouse.id,v_warehouse.location_name,v_issuer.id,v_issuer.employee_name,coalesce(p_issue_date,current_date),'draft') returning id into v_record_id;
  insert into public.smis_ppe_issuance_record_item(tenant_id,issuance_record_id,requisition_item_id,material_id,material_category_snapshot,material_name_snapshot,specification_model_snapshot,unit_snapshot,issue_quantity)
  select v_tenant,v_record_id,i.id,i.material_id,i.material_category_snapshot,i.material_name_snapshot,i.specification_model_snapshot,i.unit_snapshot,i.requested_quantity
  from public.smis_ppe_personal_requisition_item i where i.id=any(p_item_ids);
  v_no:=app_private.post_ppe_issuance_record(v_record_id);
  return jsonb_build_object('id',v_record_id,'issuanceNo',v_no);
end $$;

create or replace function public.smis_confirm_ppe_requisition_items_secure(p_item_ids uuid[],p_confirmed boolean,p_reason text default null)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_current_employee uuid; v_count integer; v_requisition uuid;
begin
  if (select auth.uid()) is null or not app_private.has_permission('SmisPpePersonalRequisition:Confirm') then raise exception '当前账号没有确认领用的权限' using errcode='42501'; end if;
  select hr_employee_id into v_current_employee from public.sys_user where auth_user_id=(select auth.uid()) and deleted_at is null;
  if v_current_employee is null then raise exception '当前登录账号未关联员工花名册，无法确认领用' using errcode='42501'; end if;
  if cardinality(coalesce(p_item_ids,array[]::uuid[]))=0 then raise exception '请选择待确认的领用明细' using errcode='22023'; end if;
  if exists(select 1 from public.smis_ppe_personal_requisition_item i join public.smis_ppe_personal_requisition r on r.id=i.requisition_id where i.id=any(p_item_ids) and (r.employee_id<>v_current_employee or i.status<>'issued_pending_confirmation')) then raise exception '只能确认本人已发放且待确认的领用明细' using errcode='42501'; end if;
  if not p_confirmed and nullif(btrim(coalesce(p_reason,'')),'') is null then raise exception '否认领用时必须填写原因' using errcode='22023'; end if;
  update public.smis_ppe_personal_requisition_item set status=case when p_confirmed then 'confirmed' else 'denied' end,confirmed_at=now(),confirmation_source='employee',denial_reason=case when p_confirmed then null else btrim(p_reason) end where id=any(p_item_ids);
  get diagnostics v_count=row_count;
  for v_requisition in select distinct requisition_id from public.smis_ppe_personal_requisition_item where id=any(p_item_ids) loop perform app_private.refresh_ppe_requisition_status(v_requisition); end loop;
  return v_count;
end $$;

create or replace function public.smis_get_ppe_issuance_statistics_secure(p_date_from date,p_date_to date,p_organization_id uuid default null,p_employee_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null or not (app_private.is_platform_super() or app_private.has_permission('SmisPpeIssuanceRecord:Statistics') or app_private.has_permission('SmisPpePersonalRequisition:Statistics')) then raise exception '当前账号没有统计分析权限' using errcode='42501'; end if;
  return (with base as (
    select r.id as record_id,r.organization_id,r.organization_name_snapshot,r.employee_id,r.employee_name_snapshot,r.issue_date,i.material_name_snapshot,i.specification_model_snapshot,i.unit_snapshot,i.issue_quantity
    from public.smis_ppe_issuance_record r join public.smis_ppe_issuance_record_item i on i.issuance_record_id=r.id
    where r.status='posted' and (app_private.current_read_tenant_id() is null or r.tenant_id=app_private.current_read_tenant_id())
      and (p_date_from is null or r.issue_date>=p_date_from) and (p_date_to is null or r.issue_date<=p_date_to)
      and (p_organization_id is null or r.organization_id=p_organization_id) and (p_employee_id is null or r.employee_id=p_employee_id)
  ) select jsonb_build_object('summary',jsonb_build_object('documentCount',(select count(distinct record_id) from base),'employeeCount',(select count(distinct employee_id) from base),'materialCount',(select count(distinct (material_name_snapshot,specification_model_snapshot)) from base),'totalQuantity',coalesce((select sum(issue_quantity) from base),0)),
    'rows',coalesce((select jsonb_agg(x order by x."organizationName",x."materialName") from (select organization_id as "organizationId",coalesce(organization_name_snapshot,'未分配组织') as "organizationName",material_name_snapshot as "materialName",specification_model_snapshot as "specificationModel",unit_snapshot as unit,sum(issue_quantity) as quantity,count(distinct employee_id) as "employeeCount" from base group by organization_id,organization_name_snapshot,material_name_snapshot,specification_model_snapshot,unit_snapshot) x),'[]'::jsonb)));
end $$;

revoke all on function public.smis_get_ppe_setting_secure() from public,anon;
revoke all on function public.smis_save_ppe_setting_secure(integer) from public,anon;
revoke all on function public.smis_set_ppe_personal_issue_plan_secure(uuid,jsonb) from public,anon;
revoke all on function public.smis_generate_due_ppe_requisitions_secure(date) from public,anon;
revoke all on function public.smis_list_ppe_personal_requisitions_secure(integer,integer,date,date,uuid,uuid,text,text,text) from public,anon;
revoke all on function public.smis_list_ppe_issuance_records_secure(integer,integer,date,date,uuid,uuid,text,text,text) from public,anon;
revoke all on function public.smis_save_ppe_issuance_record_secure(uuid,jsonb) from public,anon;
revoke all on function public.smis_delete_ppe_issuance_records_secure(uuid[]) from public,anon;
revoke all on function app_private.post_ppe_issuance_record(uuid) from public,anon,authenticated;
revoke all on function public.smis_post_ppe_issuance_record_secure(uuid) from public,anon;
revoke all on function public.smis_push_ppe_requisition_items_secure(uuid[],uuid,uuid,date) from public,anon;
revoke all on function public.smis_confirm_ppe_requisition_items_secure(uuid[],boolean,text) from public,anon;
revoke all on function public.smis_get_ppe_issuance_statistics_secure(date,date,uuid,uuid) from public,anon;
grant execute on function public.smis_get_ppe_setting_secure() to authenticated;
grant execute on function public.smis_save_ppe_setting_secure(integer) to authenticated;
grant execute on function public.smis_set_ppe_personal_issue_plan_secure(uuid,jsonb) to authenticated;
grant execute on function public.smis_generate_due_ppe_requisitions_secure(date) to authenticated;
grant execute on function public.smis_list_ppe_personal_requisitions_secure(integer,integer,date,date,uuid,uuid,text,text,text) to authenticated;
grant execute on function public.smis_list_ppe_issuance_records_secure(integer,integer,date,date,uuid,uuid,text,text,text) to authenticated;
grant execute on function public.smis_save_ppe_issuance_record_secure(uuid,jsonb) to authenticated;
grant execute on function public.smis_delete_ppe_issuance_records_secure(uuid[]) to authenticated;
grant execute on function public.smis_post_ppe_issuance_record_secure(uuid) to authenticated;
grant execute on function public.smis_push_ppe_requisition_items_secure(uuid[],uuid,uuid,date) to authenticated;
grant execute on function public.smis_confirm_ppe_requisition_items_secure(uuid[],boolean,text) to authenticated;
grant execute on function public.smis_get_ppe_issuance_statistics_secure(date,date,uuid,uuid) to authenticated;

do $$
declare v_platform uuid; v_menu record; v_button record;
begin
  select id into v_platform from public.sys_tenant where tenant_code='platform' limit 1;
  update public.sys_menu set meta=meta||jsonb_build_object('icon',case name when 'SmisPpeIssuanceRecord' then 'ri:archive-drawer-line' else 'ri:user-received-2-line' end,'keep_alive',true,'is_hide',false,'is_enable',true),update_time=now()
  where app_code='smis' and name in('SmisPpeIssuanceRecord','SmisPpePersonalRequisition');

  for v_button in select * from (values
    ('SmisPpeIssuanceRecord','SmisPpeIssuanceRecord:View','查看发放记录',1),
    ('SmisPpeIssuanceRecord','SmisPpeIssuanceRecord:Add','新增发放记录',2),
    ('SmisPpeIssuanceRecord','SmisPpeIssuanceRecord:Copy','复制并新增',3),
    ('SmisPpeIssuanceRecord','SmisPpeIssuanceRecord:Edit','编辑发放记录',4),
    ('SmisPpeIssuanceRecord','SmisPpeIssuanceRecord:Delete','删除发放记录',5),
    ('SmisPpeIssuanceRecord','SmisPpeIssuanceRecord:Issue','发放过账',6),
    ('SmisPpeIssuanceRecord','SmisPpeIssuanceRecord:Import','导入发放记录',7),
    ('SmisPpeIssuanceRecord','SmisPpeIssuanceRecord:DownloadTemplate','下载导入模板',8),
    ('SmisPpeIssuanceRecord','SmisPpeIssuanceRecord:Export','导出发放记录',9),
    ('SmisPpeIssuanceRecord','SmisPpeIssuanceRecord:Statistics','发放统计分析',10),
    ('SmisPpeIssuanceRecord','SmisPpeIssuanceRecord:Print','打印劳保单',11),
    ('SmisPpePersonalRequisition','SmisPpePersonalRequisition:View','查看个人领用',1),
    ('SmisPpePersonalRequisition','SmisPpePersonalRequisition:Generate','生成到期领用单',2),
    ('SmisPpePersonalRequisition','SmisPpePersonalRequisition:Push','下推发放',3),
    ('SmisPpePersonalRequisition','SmisPpePersonalRequisition:Confirm','确认本人领用',4),
    ('SmisPpePersonalRequisition','SmisPpePersonalRequisition:Export','导出个人领用',5),
    ('SmisPpePersonalRequisition','SmisPpePersonalRequisition:Statistics','个人领用统计',6),
    ('SmisPpePersonalRequisition','SmisPpePersonalRequisition:Configure','配置自动确认',7),
    ('SmisPpePersonalStandard','SmisPpePersonalStandard:Schedule','设置领用计划',4)
  ) t(parent_name,button_name,title,sort) loop
    insert into public.sys_menu(id,name,path,component,meta,sort,create_by,update_by,parent_id,type,app_code)
    select gen_random_uuid(),v_button.button_name,'','',jsonb_build_object('title',v_button.title,'roles',jsonb_build_array(),'is_hide',true,'is_enable',true),v_button.sort,'624944977@qq.com','624944977@qq.com',p.id,'button','smis'
    from public.sys_menu p where p.app_code='smis' and p.name=v_button.parent_name
      and not exists(select 1 from public.sys_menu e where e.app_code='smis' and e.name=v_button.button_name)
    order by p.create_time limit 1;
  end loop;

  insert into public.sys_role_menu(role_id,menu_id,permission,create_by,update_by,tenant_id)
  select page_grant.role_id,button.id,'{}'::jsonb,'624944977@qq.com','624944977@qq.com',page_grant.tenant_id
  from public.sys_role_menu page_grant
  join public.sys_menu page on page.id=page_grant.menu_id and page.app_code='smis' and page.name in('SmisPpeIssuanceRecord','SmisPpePersonalRequisition','SmisPpePersonalStandard')
  join public.sys_menu button on button.parent_id=page.id and button.type='button'
    and (button.name like 'SmisPpeIssuanceRecord:%' or button.name like 'SmisPpePersonalRequisition:%' or button.name='SmisPpePersonalStandard:Schedule')
  where not exists(select 1 from public.sys_role_menu existing where existing.role_id=page_grant.role_id and existing.menu_id=button.id);

  insert into public.sys_document_number_scene(rule_key,rule_name,field_label,category,menu_id,target_table,target_column,default_template,default_reset_cycle,manual_required,enabled,remark,create_by,update_by,tenant_id)
  select 'smis.ppe_personal_requisition','防护用品个人领用单号','个人领用单号','business_document',m.id,'smis_ppe_personal_requisition','requisition_no','LY{YYYYMM}{SEQ:4}','month',false,true,'系统按标准到期生成，4 位流水码每月重置','624944977@qq.com','624944977@qq.com',v_platform
  from public.sys_menu m where m.app_code='smis' and m.name='SmisPpePersonalRequisition' and not exists(select 1 from public.sys_document_number_scene s where s.rule_key='smis.ppe_personal_requisition') order by m.create_time limit 1;
  insert into public.sys_document_number_scene(rule_key,rule_name,field_label,category,menu_id,target_table,target_column,default_template,default_reset_cycle,manual_required,enabled,remark,create_by,update_by,tenant_id)
  select 'smis.ppe_issuance_record','防护用品发放单号','发放单号','business_document',m.id,'smis_ppe_issuance_record','issuance_no','FF{YYYYMM}{SEQ:4}','month',false,true,'发放过账生成，4 位流水码每月重置','624944977@qq.com','624944977@qq.com',v_platform
  from public.sys_menu m where m.app_code='smis' and m.name='SmisPpeIssuanceRecord' and not exists(select 1 from public.sys_document_number_scene s where s.rule_key='smis.ppe_issuance_record') order by m.create_time limit 1;
  insert into public.sys_document_number_rule(tenant_id,rule_key,rule_name,category,target_table,target_column,auto_enabled,template,reset_cycle,sequence_start,timezone,rule_version,manual_required,builtin,enabled,remark,create_by,update_by)
  select t.id,x.rule_key,x.rule_name,'business_document',x.target_table,x.target_column,true,x.template,'month',1,'Asia/Shanghai',1,false,true,true,x.remark,'624944977@qq.com','624944977@qq.com'
  from public.sys_tenant t cross join (values
    ('smis.ppe_personal_requisition','防护用品个人领用单号','smis_ppe_personal_requisition','requisition_no','LY{YYYYMM}{SEQ:4}','系统按标准到期生成，4 位流水码每月重置'),
    ('smis.ppe_issuance_record','防护用品发放单号','smis_ppe_issuance_record','issuance_no','FF{YYYYMM}{SEQ:4}','发放过账生成，4 位流水码每月重置')
  ) x(rule_key,rule_name,target_table,target_column,template,remark)
  where not exists(select 1 from public.sys_document_number_rule r where r.tenant_id=t.id and r.rule_key=x.rule_key);

  if exists(select 1 from pg_extension where extname='pg_cron') then
    if not exists(select 1 from cron.job where jobname='smis-ppe-daily-requisition-and-confirmation') then
      perform cron.schedule('smis-ppe-daily-requisition-and-confirmation','15 16 * * *',
        'select app_private.run_daily_ppe_automation();');
    end if;
  end if;
end $$;

select app_private.run_daily_ppe_automation();

;
