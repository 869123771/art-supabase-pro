-- Secure contingent-workforce APIs and lifecycle controls.

create or replace function app_private.hr_mask_external_phone(p_value text)
returns text
language sql
immutable
set search_path = ''
as $function$
  select case
    when nullif(btrim(p_value), '') is null then null
    when length(btrim(p_value)) >= 7
      then left(btrim(p_value), 3) || '****' || right(btrim(p_value), 4)
    else '***'
  end;
$function$;

create or replace function app_private.hr_mask_external_email(p_value text)
returns text
language sql
immutable
set search_path = ''
as $function$
  select case
    when nullif(btrim(p_value), '') is null then null
    when strpos(btrim(p_value), '@') > 1
      then left(btrim(p_value), 1) || '***' || substring(btrim(p_value) from strpos(btrim(p_value), '@'))
    else '***'
  end;
$function$;

revoke all on function app_private.hr_mask_external_phone(text) from public, anon, authenticated;
revoke all on function app_private.hr_mask_external_email(text) from public, anon, authenticated;

create or replace function public.hr_contingent_workforce_overview_secure(
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set timezone = 'Asia/Shanghai'
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_today date := current_date;
begin
  if auth.uid() is null or not app_private.can_execute_business_action(
    'HrContingentWorkforce', 'Hr:ContingentWorkforce:View', null, false
  ) then
    raise exception '当前账号没有查看外部用工的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  return jsonb_build_object(
    'pii_access', app_private.can_execute_business_action(
      'HrContingentWorkforce', 'Hr:ContingentWorkforce:PII:View', null, false
    ),
    'cost_access', app_private.can_execute_business_action(
      'HrContingentWorkforce', 'Hr:ContingentWorkforce:Cost:View', null, false
    ),
    'active_vendor_count', (
      select count(*) from public.hr_external_vendor vendor
      where (p_tenant_id is null or vendor.tenant_id = p_tenant_id)
        and vendor.status = 'active'
    ),
    'active_worker_count', (
      select count(*) from public.hr_external_worker worker
      where (p_tenant_id is null or worker.tenant_id = p_tenant_id)
        and worker.status = 'active'
    ),
    'active_engagement_count', (
      select count(*) from public.hr_external_engagement engagement
      where (p_tenant_id is null or engagement.tenant_id = p_tenant_id)
        and engagement.status = 'active'
    ),
    'pending_review_count', (
      select count(*) from public.hr_external_engagement engagement
      where (p_tenant_id is null or engagement.tenant_id = p_tenant_id)
        and engagement.status = 'pending_review'
    ),
    'pending_control_count', (
      select count(*)
      from public.hr_external_engagement_control control
      join public.hr_external_engagement engagement on engagement.id = control.engagement_id
      where (p_tenant_id is null or control.tenant_id = p_tenant_id)
        and engagement.status in ('draft', 'pending_review', 'active', 'offboarding')
        and control.required
        and control.status not in ('completed', 'waived')
    ),
    'ending_soon_count', (
      select count(*) from public.hr_external_engagement engagement
      where (p_tenant_id is null or engagement.tenant_id = p_tenant_id)
        and engagement.status = 'active'
        and engagement.end_date between v_today and v_today + 30
    ),
    'access_expiring_count', (
      select count(*) from public.hr_external_engagement engagement
      where (p_tenant_id is null or engagement.tenant_id = p_tenant_id)
        and engagement.status in ('active', 'offboarding')
        and engagement.access_expiry_date between v_today and v_today + 14
    ),
    'blocked_count', (
      select count(*) from public.hr_external_engagement engagement
      where (p_tenant_id is null or engagement.tenant_id = p_tenant_id)
        and engagement.status in ('draft', 'pending_review', 'active')
        and engagement.compliance_status = 'blocked'
    )
  );
end;
$function$;

create or replace function public.hr_list_contingent_workforce_records_secure(
  p_kind text,
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_status text default null,
  p_engagement_id uuid default null,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set timezone = 'Asia/Shanghai'
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_offset integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer := least(500, greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1));
  v_keyword text := nullif(btrim(p_keyword), '');
  v_pii_access boolean;
  v_cost_access boolean;
  v_records jsonb := '[]'::jsonb;
  v_total integer := 0;
begin
  if p_kind not in ('vendor', 'worker', 'engagement', 'control') then
    raise exception '不支持的外部用工记录类型';
  end if;
  if auth.uid() is null or not app_private.can_execute_business_action(
    'HrContingentWorkforce', 'Hr:ContingentWorkforce:View', null, false
  ) then
    raise exception '当前账号没有查看外部用工的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;
  v_pii_access := app_private.can_execute_business_action(
    'HrContingentWorkforce', 'Hr:ContingentWorkforce:PII:View', null, false
  );
  v_cost_access := app_private.can_execute_business_action(
    'HrContingentWorkforce', 'Hr:ContingentWorkforce:Cost:View', null, false
  );

  if p_kind = 'vendor' then
    select count(*)::integer into v_total
    from public.hr_external_vendor vendor
    where (p_tenant_id is null or vendor.tenant_id = p_tenant_id)
      and (p_status is null or p_status = '' or vendor.status = p_status)
      and (v_keyword is null or vendor.vendor_code ilike '%' || v_keyword || '%'
        or vendor.vendor_name ilike '%' || v_keyword || '%'
        or vendor.contract_no ilike '%' || v_keyword || '%');

    select coalesce(jsonb_agg(row_data order by sort_active, vendor_name), '[]'::jsonb)
    into v_records
    from (
      select
        case vendor.status when 'active' then 0 else 1 end as sort_active,
        vendor.vendor_name,
        jsonb_build_object(
          'id', vendor.id,
          'tenant_id', vendor.tenant_id,
          'vendor_code', vendor.vendor_code,
          'vendor_name', vendor.vendor_name,
          'registration_no', vendor.registration_no,
          'contact_name', case when v_pii_access then vendor.contact_name else app_private.hr_mask_external_phone(vendor.contact_name) end,
          'contact_phone', case when v_pii_access then vendor.contact_phone else app_private.hr_mask_external_phone(vendor.contact_phone) end,
          'contact_email', case when v_pii_access then vendor.contact_email else app_private.hr_mask_external_email(vendor.contact_email) end,
          'service_scope', vendor.service_scope,
          'contract_no', vendor.contract_no,
          'contract_start_date', vendor.contract_start_date,
          'contract_end_date', vendor.contract_end_date,
          'compliance_status', vendor.compliance_status,
          'risk_level', vendor.risk_level,
          'status', vendor.status,
          'note', vendor.note,
          'active_engagement_count', (
            select count(*) from public.hr_external_engagement engagement
            where engagement.vendor_id = vendor.id and engagement.status = 'active'
          ),
          'worker_count', (
            select count(*) from public.hr_external_worker worker where worker.vendor_id = vendor.id
          ),
          'create_time', vendor.create_time,
          'update_time', vendor.update_time
        ) as row_data
      from public.hr_external_vendor vendor
      where (p_tenant_id is null or vendor.tenant_id = p_tenant_id)
        and (p_status is null or p_status = '' or vendor.status = p_status)
        and (v_keyword is null or vendor.vendor_code ilike '%' || v_keyword || '%'
          or vendor.vendor_name ilike '%' || v_keyword || '%'
          or vendor.contract_no ilike '%' || v_keyword || '%')
      order by sort_active, vendor.vendor_name
      offset v_offset limit v_limit
    ) rows;
  elsif p_kind = 'worker' then
    select count(*)::integer into v_total
    from public.hr_external_worker worker
    left join public.hr_external_vendor vendor on vendor.id = worker.vendor_id
    where (p_tenant_id is null or worker.tenant_id = p_tenant_id)
      and (p_status is null or p_status = '' or worker.status = p_status)
      and (v_keyword is null or worker.worker_no ilike '%' || v_keyword || '%'
        or worker.worker_name ilike '%' || v_keyword || '%'
        or worker.vendor_worker_no ilike '%' || v_keyword || '%'
        or vendor.vendor_name ilike '%' || v_keyword || '%');

    select coalesce(jsonb_agg(row_data order by sort_active, worker_name), '[]'::jsonb)
    into v_records
    from (
      select
        case worker.status when 'active' then 0 when 'ready' then 1 else 2 end as sort_active,
        worker.worker_name,
        jsonb_build_object(
          'id', worker.id,
          'tenant_id', worker.tenant_id,
          'worker_no', worker.worker_no,
          'worker_name', worker.worker_name,
          'worker_type', worker.worker_type,
          'vendor_id', worker.vendor_id,
          'vendor_name', vendor.vendor_name,
          'vendor_worker_no', worker.vendor_worker_no,
          'phone', case when v_pii_access then worker.phone else app_private.hr_mask_external_phone(worker.phone) end,
          'email', case when v_pii_access then worker.email else app_private.hr_mask_external_email(worker.email) end,
          'identity_check_status', worker.identity_check_status,
          'status', worker.status,
          'note', worker.note,
          'active_engagement_count', (
            select count(*) from public.hr_external_engagement engagement
            where engagement.worker_id = worker.id and engagement.status = 'active'
          ),
          'next_end_date', (
            select min(engagement.end_date) from public.hr_external_engagement engagement
            where engagement.worker_id = worker.id and engagement.status = 'active'
          ),
          'create_time', worker.create_time,
          'update_time', worker.update_time
        ) as row_data
      from public.hr_external_worker worker
      left join public.hr_external_vendor vendor on vendor.id = worker.vendor_id
      where (p_tenant_id is null or worker.tenant_id = p_tenant_id)
        and (p_status is null or p_status = '' or worker.status = p_status)
        and (v_keyword is null or worker.worker_no ilike '%' || v_keyword || '%'
          or worker.worker_name ilike '%' || v_keyword || '%'
          or worker.vendor_worker_no ilike '%' || v_keyword || '%'
          or vendor.vendor_name ilike '%' || v_keyword || '%')
      order by sort_active, worker.worker_name
      offset v_offset limit v_limit
    ) rows;
  elsif p_kind = 'engagement' then
    select count(*)::integer into v_total
    from public.hr_external_engagement engagement
    join public.hr_external_worker worker on worker.id = engagement.worker_id
    join public.sys_organization organization on organization.id = engagement.organization_id
    where (p_tenant_id is null or engagement.tenant_id = p_tenant_id)
      and (p_status is null or p_status = '' or engagement.status = p_status)
      and (v_keyword is null or engagement.engagement_no ilike '%' || v_keyword || '%'
        or engagement.service_title ilike '%' || v_keyword || '%'
        or worker.worker_name ilike '%' || v_keyword || '%'
        or organization.organization_name ilike '%' || v_keyword || '%');

    select coalesce(jsonb_agg(row_data order by sort_active, end_date, worker_name), '[]'::jsonb)
    into v_records
    from (
      select
        case engagement.status when 'active' then 0 when 'pending_review' then 1 when 'offboarding' then 2 else 3 end as sort_active,
        engagement.end_date,
        worker.worker_name,
        jsonb_build_object(
          'id', engagement.id,
          'tenant_id', engagement.tenant_id,
          'engagement_no', engagement.engagement_no,
          'worker_id', engagement.worker_id,
          'worker_no', worker.worker_no,
          'worker_name', worker.worker_name,
          'worker_type', worker.worker_type,
          'vendor_id', engagement.vendor_id,
          'vendor_name', vendor.vendor_name,
          'organization_id', engagement.organization_id,
          'organization_name', organization.organization_name,
          'position_id', engagement.position_id,
          'position_name', position.position_name,
          'sponsor_employee_id', engagement.sponsor_employee_id,
          'sponsor_employee_name', sponsor.employee_name,
          'service_title', engagement.service_title,
          'work_location', engagement.work_location,
          'start_date', engagement.start_date,
          'end_date', engagement.end_date,
          'access_expiry_date', engagement.access_expiry_date,
          'actual_exit_date', engagement.actual_exit_date,
          'fte', engagement.fte,
          'billing_rate', case when v_cost_access then to_jsonb(engagement.billing_rate) else to_jsonb('***'::text) end,
          'billing_unit', case when v_cost_access then engagement.billing_unit else null end,
          'currency_code', case when v_cost_access then engagement.currency_code else null end,
          'compliance_status', engagement.compliance_status,
          'status', engagement.status,
          'activation_note', engagement.activation_note,
          'end_reason', engagement.end_reason,
          'version', engagement.version,
          'pending_control_count', (
            select count(*) from public.hr_external_engagement_control control
            where control.engagement_id = engagement.id and control.required
              and control.status not in ('completed', 'waived')
          ),
          'control_count', (
            select count(*) from public.hr_external_engagement_control control
            where control.engagement_id = engagement.id
          ),
          'create_time', engagement.create_time,
          'update_time', engagement.update_time
        ) as row_data
      from public.hr_external_engagement engagement
      join public.hr_external_worker worker on worker.id = engagement.worker_id
      left join public.hr_external_vendor vendor on vendor.id = engagement.vendor_id
      join public.sys_organization organization on organization.id = engagement.organization_id
      left join public.hr_position position on position.id = engagement.position_id
      join public.hr_employee sponsor on sponsor.id = engagement.sponsor_employee_id
      where (p_tenant_id is null or engagement.tenant_id = p_tenant_id)
        and (p_status is null or p_status = '' or engagement.status = p_status)
        and (v_keyword is null or engagement.engagement_no ilike '%' || v_keyword || '%'
          or engagement.service_title ilike '%' || v_keyword || '%'
          or worker.worker_name ilike '%' || v_keyword || '%'
          or organization.organization_name ilike '%' || v_keyword || '%')
      order by sort_active, engagement.end_date, worker.worker_name
      offset v_offset limit v_limit
    ) rows;
  else
    select count(*)::integer into v_total
    from public.hr_external_engagement_control control
    join public.hr_external_engagement engagement on engagement.id = control.engagement_id
    join public.hr_external_worker worker on worker.id = engagement.worker_id
    where (p_tenant_id is null or control.tenant_id = p_tenant_id)
      and (p_engagement_id is null or control.engagement_id = p_engagement_id)
      and (p_status is null or p_status = '' or control.status = p_status)
      and (v_keyword is null or control.control_name ilike '%' || v_keyword || '%'
        or engagement.engagement_no ilike '%' || v_keyword || '%'
        or worker.worker_name ilike '%' || v_keyword || '%');

    select coalesce(jsonb_agg(row_data order by required desc, due_date nulls last, control_name), '[]'::jsonb)
    into v_records
    from (
      select
        control.required,
        control.due_date,
        control.control_name,
        jsonb_build_object(
          'id', control.id,
          'tenant_id', control.tenant_id,
          'engagement_id', control.engagement_id,
          'engagement_no', engagement.engagement_no,
          'engagement_status', engagement.status,
          'worker_name', worker.worker_name,
          'control_type', control.control_type,
          'control_name', control.control_name,
          'required', control.required,
          'status', control.status,
          'due_date', control.due_date,
          'completed_at', control.completed_at,
          'completed_by', control.completed_by,
          'evidence_reference', control.evidence_reference,
          'note', control.note,
          'create_time', control.create_time,
          'update_time', control.update_time
        ) as row_data
      from public.hr_external_engagement_control control
      join public.hr_external_engagement engagement on engagement.id = control.engagement_id
      join public.hr_external_worker worker on worker.id = engagement.worker_id
      where (p_tenant_id is null or control.tenant_id = p_tenant_id)
        and (p_engagement_id is null or control.engagement_id = p_engagement_id)
        and (p_status is null or p_status = '' or control.status = p_status)
        and (v_keyword is null or control.control_name ilike '%' || v_keyword || '%'
          or engagement.engagement_no ilike '%' || v_keyword || '%'
          or worker.worker_name ilike '%' || v_keyword || '%')
      order by control.required desc, control.due_date nulls last, control.control_name
      offset v_offset limit v_limit
    ) rows;
  end if;

  return jsonb_build_object(
    'records', v_records,
    'total', v_total,
    'pii_access', v_pii_access,
    'cost_access', v_cost_access
  );
end;
$function$;

create or replace function public.hr_list_contingent_workforce_options_secure(
  p_kind text,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_result jsonb := '[]'::jsonb;
begin
  if p_kind not in ('vendor', 'worker', 'organization', 'position', 'sponsor', 'engagement') then
    raise exception '不支持的外部用工选项类型';
  end if;
  if auth.uid() is null or not app_private.can_execute_business_action(
    'HrContingentWorkforce', 'Hr:ContingentWorkforce:View', null, false
  ) then
    raise exception '当前账号没有查看外部用工的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  if p_kind = 'vendor' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', vendor.id, 'code', vendor.vendor_code, 'name', vendor.vendor_name,
      'status', vendor.status, 'extra', vendor.compliance_status
    ) order by vendor.vendor_name), '[]'::jsonb)
    into v_result
    from public.hr_external_vendor vendor
    where (p_tenant_id is null or vendor.tenant_id = p_tenant_id)
      and vendor.status <> 'inactive';
  elsif p_kind = 'worker' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', worker.id, 'code', worker.worker_no, 'name', worker.worker_name,
      'status', worker.status, 'extra', worker.worker_type, 'vendor_id', worker.vendor_id
    ) order by worker.worker_name), '[]'::jsonb)
    into v_result
    from public.hr_external_worker worker
    where (p_tenant_id is null or worker.tenant_id = p_tenant_id)
      and worker.status <> 'blocked';
  elsif p_kind = 'organization' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', organization.id, 'code', organization.organization_code,
      'name', organization.organization_name, 'status', organization.status
    ) order by organization.sort, organization.organization_name), '[]'::jsonb)
    into v_result
    from public.sys_organization organization
    where (p_tenant_id is null or organization.tenant_id = p_tenant_id);
  elsif p_kind = 'position' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', position.id, 'code', position.position_code, 'name', position.position_name,
      'status', case when position.enabled then 'active' else 'inactive' end,
      'organization_id', position.organization_id
    ) order by position.sort, position.position_name), '[]'::jsonb)
    into v_result
    from public.hr_position position
    where (p_tenant_id is null or position.tenant_id = p_tenant_id) and position.enabled;
  elsif p_kind = 'sponsor' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', employee.id, 'code', employee.employee_no, 'name', employee.employee_name,
      'status', employee.employment_status, 'organization_id', employee.organization_id
    ) order by employee.employee_name), '[]'::jsonb)
    into v_result
    from public.hr_employee employee
    where (p_tenant_id is null or employee.tenant_id = p_tenant_id)
      and employee.employment_status = 'active';
  else
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', engagement.id, 'code', engagement.engagement_no,
      'name', worker.worker_name || ' · ' || engagement.service_title,
      'status', engagement.status, 'extra', engagement.end_date
    ) order by engagement.end_date, worker.worker_name), '[]'::jsonb)
    into v_result
    from public.hr_external_engagement engagement
    join public.hr_external_worker worker on worker.id = engagement.worker_id
    where (p_tenant_id is null or engagement.tenant_id = p_tenant_id)
      and engagement.status in ('draft', 'pending_review', 'active', 'offboarding');
  end if;

  return v_result;
end;
$function$;

create or replace function public.hr_save_contingent_workforce_record_secure(
  p_kind text,
  p_id uuid,
  p_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
set timezone = 'Asia/Shanghai'
as $function$
declare
  v_current_tenant uuid := app_private.current_user_tenant_id();
  v_tenant_id uuid := case
    when app_private.is_platform_super() and nullif(p_payload ->> 'tenant_id', '') is not null
      then (p_payload ->> 'tenant_id')::uuid
    else v_current_tenant
  end;
  v_action text;
  v_id uuid := coalesce(p_id, gen_random_uuid());
  v_worker public.hr_external_worker%rowtype;
  v_engagement public.hr_external_engagement%rowtype;
  v_position_organization uuid;
  v_billing_rate numeric(18, 2);
  v_expected_version integer;
begin
  if p_kind not in ('vendor', 'worker', 'engagement', 'control') then
    raise exception '不支持的外部用工记录类型';
  end if;
  v_action := case p_kind
    when 'vendor' then 'Hr:ContingentWorkforce:Vendor:Manage'
    when 'worker' then 'Hr:ContingentWorkforce:Worker:Manage'
    when 'engagement' then 'Hr:ContingentWorkforce:Engagement:Manage'
    else 'Hr:ContingentWorkforce:Control:Manage'
  end;
  if auth.uid() is null or not app_private.can_execute_business_action(
    'HrContingentWorkforce', v_action, null, false
  ) then
    raise exception '当前账号没有维护外部用工记录的权限' using errcode = '42501';
  end if;

  if p_kind = 'vendor' then
    if p_id is null then
      insert into public.hr_external_vendor(
        id, tenant_id, vendor_code, vendor_name, registration_no,
        contact_name, contact_phone, contact_email, service_scope,
        contract_no, contract_start_date, contract_end_date,
        compliance_status, risk_level, status, note
      ) values (
        v_id, v_tenant_id, btrim(p_payload ->> 'vendor_code'), btrim(p_payload ->> 'vendor_name'),
        nullif(btrim(p_payload ->> 'registration_no'), ''),
        nullif(btrim(p_payload ->> 'contact_name'), ''),
        nullif(btrim(p_payload ->> 'contact_phone'), ''),
        nullif(btrim(p_payload ->> 'contact_email'), ''),
        nullif(btrim(p_payload ->> 'service_scope'), ''),
        nullif(btrim(p_payload ->> 'contract_no'), ''),
        nullif(p_payload ->> 'contract_start_date', '')::date,
        nullif(p_payload ->> 'contract_end_date', '')::date,
        coalesce(nullif(p_payload ->> 'compliance_status', ''), 'pending'),
        coalesce(nullif(p_payload ->> 'risk_level', ''), 'medium'),
        'draft', nullif(btrim(p_payload ->> 'note'), '')
      );
    else
      update public.hr_external_vendor set
        vendor_code = btrim(p_payload ->> 'vendor_code'),
        vendor_name = btrim(p_payload ->> 'vendor_name'),
        registration_no = nullif(btrim(p_payload ->> 'registration_no'), ''),
        contact_name = nullif(btrim(p_payload ->> 'contact_name'), ''),
        contact_phone = nullif(btrim(p_payload ->> 'contact_phone'), ''),
        contact_email = nullif(btrim(p_payload ->> 'contact_email'), ''),
        service_scope = nullif(btrim(p_payload ->> 'service_scope'), ''),
        contract_no = nullif(btrim(p_payload ->> 'contract_no'), ''),
        contract_start_date = nullif(p_payload ->> 'contract_start_date', '')::date,
        contract_end_date = nullif(p_payload ->> 'contract_end_date', '')::date,
        compliance_status = coalesce(nullif(p_payload ->> 'compliance_status', ''), compliance_status),
        risk_level = coalesce(nullif(p_payload ->> 'risk_level', ''), risk_level),
        note = nullif(btrim(p_payload ->> 'note'), '')
      where id = p_id and tenant_id = v_tenant_id;
      if not found then raise exception '供应商不存在或不属于当前租户'; end if;
    end if;
  elsif p_kind = 'worker' then
    if coalesce(nullif(p_payload ->> 'worker_type', ''), '') in ('outsourced', 'dispatch')
       and nullif(p_payload ->> 'vendor_id', '') is null then
      raise exception '外包或劳务派遣人员必须关联供应商';
    end if;
    if p_id is null then
      insert into public.hr_external_worker(
        id, tenant_id, worker_no, worker_name, worker_type, vendor_id,
        vendor_worker_no, phone, email, identity_check_status, status, note
      ) values (
        v_id, v_tenant_id, btrim(p_payload ->> 'worker_no'), btrim(p_payload ->> 'worker_name'),
        p_payload ->> 'worker_type', nullif(p_payload ->> 'vendor_id', '')::uuid,
        nullif(btrim(p_payload ->> 'vendor_worker_no'), ''),
        nullif(btrim(p_payload ->> 'phone'), ''), nullif(btrim(p_payload ->> 'email'), ''),
        coalesce(nullif(p_payload ->> 'identity_check_status', ''), 'pending'),
        'candidate', nullif(btrim(p_payload ->> 'note'), '')
      );
    else
      update public.hr_external_worker set
        worker_no = btrim(p_payload ->> 'worker_no'),
        worker_name = btrim(p_payload ->> 'worker_name'),
        worker_type = p_payload ->> 'worker_type',
        vendor_id = nullif(p_payload ->> 'vendor_id', '')::uuid,
        vendor_worker_no = nullif(btrim(p_payload ->> 'vendor_worker_no'), ''),
        phone = nullif(btrim(p_payload ->> 'phone'), ''),
        email = nullif(btrim(p_payload ->> 'email'), ''),
        identity_check_status = coalesce(nullif(p_payload ->> 'identity_check_status', ''), identity_check_status),
        note = nullif(btrim(p_payload ->> 'note'), '')
      where id = p_id and tenant_id = v_tenant_id and status <> 'blocked';
      if not found then raise exception '外部人员不存在、已锁定或不属于当前租户'; end if;
    end if;
  elsif p_kind = 'engagement' then
    select * into v_worker from public.hr_external_worker
    where id = (p_payload ->> 'worker_id')::uuid and tenant_id = v_tenant_id;
    if not found then raise exception '外部人员不存在或不属于当前租户'; end if;
    if v_worker.status = 'blocked' then raise exception '已锁定的外部人员不能建立用工任务'; end if;

    if nullif(p_payload ->> 'position_id', '') is not null then
      select organization_id into v_position_organization from public.hr_position
      where id = (p_payload ->> 'position_id')::uuid and tenant_id = v_tenant_id and enabled;
      if not found then raise exception '岗位不存在、已停用或不属于当前租户'; end if;
      if v_position_organization is not null
         and v_position_organization <> (p_payload ->> 'organization_id')::uuid then
        raise exception '所选岗位不属于当前组织';
      end if;
    end if;

    if nullif(p_payload ->> 'billing_rate', '') is not null then
      if not app_private.can_execute_business_action(
        'HrContingentWorkforce', 'Hr:ContingentWorkforce:Cost:Edit', null, false
      ) then
        raise exception '当前账号没有编辑外部用工成本的权限' using errcode = '42501';
      end if;
      v_billing_rate := (p_payload ->> 'billing_rate')::numeric;
    end if;

    if p_id is null then
      insert into public.hr_external_engagement(
        id, tenant_id, engagement_no, worker_id, vendor_id, organization_id,
        position_id, sponsor_employee_id, service_title, work_location,
        start_date, end_date, access_expiry_date, fte, billing_rate,
        billing_unit, currency_code, compliance_status, status, activation_note
      ) values (
        v_id, v_tenant_id, btrim(p_payload ->> 'engagement_no'), v_worker.id,
        coalesce(nullif(p_payload ->> 'vendor_id', '')::uuid, v_worker.vendor_id),
        (p_payload ->> 'organization_id')::uuid,
        nullif(p_payload ->> 'position_id', '')::uuid,
        (p_payload ->> 'sponsor_employee_id')::uuid,
        btrim(p_payload ->> 'service_title'), nullif(btrim(p_payload ->> 'work_location'), ''),
        (p_payload ->> 'start_date')::date, (p_payload ->> 'end_date')::date,
        coalesce(nullif(p_payload ->> 'access_expiry_date', '')::date, (p_payload ->> 'end_date')::date),
        coalesce(nullif(p_payload ->> 'fte', '')::numeric, 1), v_billing_rate,
        nullif(p_payload ->> 'billing_unit', ''),
        coalesce(nullif(upper(p_payload ->> 'currency_code'), ''), 'CNY'),
        'pending', 'draft', nullif(btrim(p_payload ->> 'activation_note'), '')
      );

      insert into public.hr_external_engagement_control(
        tenant_id, engagement_id, control_type, control_name, required, due_date
      ) values
        (v_tenant_id, v_id, 'identity', '身份核验', true, (p_payload ->> 'start_date')::date),
        (v_tenant_id, v_id, 'contract', '用工合同或订单', true, (p_payload ->> 'start_date')::date),
        (v_tenant_id, v_id, 'nda', '保密协议', true, (p_payload ->> 'start_date')::date),
        (v_tenant_id, v_id, 'safety_training', '入场安全培训', true, (p_payload ->> 'start_date')::date),
        (v_tenant_id, v_id, 'access_badge', '门禁授权', true, (p_payload ->> 'start_date')::date),
        (v_tenant_id, v_id, 'system_account', '系统账号授权', true, (p_payload ->> 'start_date')::date);
    else
      select * into v_engagement from public.hr_external_engagement
      where id = p_id and tenant_id = v_tenant_id for update;
      if not found then raise exception '用工任务不存在或不属于当前租户'; end if;
      if v_engagement.status not in ('draft', 'pending_review') then
        raise exception '只有草稿或待审核任务可以修改核心信息';
      end if;
      v_expected_version := nullif(p_payload ->> 'version', '')::integer;
      if v_expected_version is not null and v_expected_version <> v_engagement.version then
        raise exception '用工任务已被其他用户更新，请刷新后重试' using errcode = '40001';
      end if;

      update public.hr_external_engagement set
        engagement_no = btrim(p_payload ->> 'engagement_no'),
        worker_id = v_worker.id,
        vendor_id = coalesce(nullif(p_payload ->> 'vendor_id', '')::uuid, v_worker.vendor_id),
        organization_id = (p_payload ->> 'organization_id')::uuid,
        position_id = nullif(p_payload ->> 'position_id', '')::uuid,
        sponsor_employee_id = (p_payload ->> 'sponsor_employee_id')::uuid,
        service_title = btrim(p_payload ->> 'service_title'),
        work_location = nullif(btrim(p_payload ->> 'work_location'), ''),
        start_date = (p_payload ->> 'start_date')::date,
        end_date = (p_payload ->> 'end_date')::date,
        access_expiry_date = coalesce(nullif(p_payload ->> 'access_expiry_date', '')::date, (p_payload ->> 'end_date')::date),
        fte = coalesce(nullif(p_payload ->> 'fte', '')::numeric, fte),
        billing_rate = case when p_payload ? 'billing_rate' then v_billing_rate else billing_rate end,
        billing_unit = case when p_payload ? 'billing_unit' then nullif(p_payload ->> 'billing_unit', '') else billing_unit end,
        currency_code = case when p_payload ? 'currency_code' then upper(p_payload ->> 'currency_code') else currency_code end,
        activation_note = nullif(btrim(p_payload ->> 'activation_note'), ''),
        version = version + 1
      where id = p_id;

      update public.hr_external_engagement_control set
        due_date = (p_payload ->> 'start_date')::date
      where engagement_id = p_id and status = 'pending';
    end if;
  else
    if p_id is null then
      insert into public.hr_external_engagement_control(
        id, tenant_id, engagement_id, control_type, control_name, required,
        status, due_date, completed_at, completed_by, evidence_reference, note
      ) values (
        v_id, v_tenant_id, (p_payload ->> 'engagement_id')::uuid,
        p_payload ->> 'control_type', btrim(p_payload ->> 'control_name'),
        coalesce((p_payload ->> 'required')::boolean, true),
        coalesce(nullif(p_payload ->> 'status', ''), 'pending'),
        nullif(p_payload ->> 'due_date', '')::date,
        case when p_payload ->> 'status' = 'completed' then now() else null end,
        case when p_payload ->> 'status' = 'completed' then coalesce(auth.jwt() ->> 'email', auth.uid()::text) else null end,
        nullif(btrim(p_payload ->> 'evidence_reference'), ''),
        nullif(btrim(p_payload ->> 'note'), '')
      );
    else
      update public.hr_external_engagement_control set
        control_type = p_payload ->> 'control_type',
        control_name = btrim(p_payload ->> 'control_name'),
        required = coalesce((p_payload ->> 'required')::boolean, required),
        status = coalesce(nullif(p_payload ->> 'status', ''), status),
        due_date = nullif(p_payload ->> 'due_date', '')::date,
        completed_at = case
          when p_payload ->> 'status' = 'completed' then coalesce(completed_at, now()) else null
        end,
        completed_by = case
          when p_payload ->> 'status' = 'completed'
            then coalesce(completed_by, auth.jwt() ->> 'email', auth.uid()::text)
          else null
        end,
        evidence_reference = nullif(btrim(p_payload ->> 'evidence_reference'), ''),
        note = nullif(btrim(p_payload ->> 'note'), '')
      where id = p_id and tenant_id = v_tenant_id;
      if not found then raise exception '准入控制项不存在或不属于当前租户'; end if;
    end if;

    update public.hr_external_engagement engagement set
      compliance_status = case
        when exists (
          select 1 from public.hr_external_engagement_control control
          where control.engagement_id = engagement.id and control.status = 'failed'
        ) then 'blocked'
        when not exists (
          select 1 from public.hr_external_engagement_control control
          where control.engagement_id = engagement.id and control.required
            and control.status not in ('completed', 'waived')
        ) then 'cleared'
        else 'pending'
      end,
      version = version + 1
    where engagement.id = (p_payload ->> 'engagement_id')::uuid
      or engagement.id = (
        select control.engagement_id from public.hr_external_engagement_control control where control.id = v_id
      );
  end if;

  return v_id;
end;
$function$;

create or replace function public.hr_transition_contingent_workforce_record_secure(
  p_kind text,
  p_id uuid,
  p_action text,
  p_comment text default null,
  p_effective_date date default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
set timezone = 'Asia/Shanghai'
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_vendor public.hr_external_vendor%rowtype;
  v_worker public.hr_external_worker%rowtype;
  v_engagement public.hr_external_engagement%rowtype;
  v_action_permission text;
  v_exit_date date := coalesce(p_effective_date, current_date);
begin
  if p_kind not in ('vendor', 'worker', 'engagement') then
    raise exception '不支持的外部用工流转类型';
  end if;
  v_action_permission := case
    when p_kind = 'vendor' then 'Hr:ContingentWorkforce:Vendor:Manage'
    when p_kind = 'worker' then 'Hr:ContingentWorkforce:Worker:Manage'
    when p_action = 'activate' then 'Hr:ContingentWorkforce:Activate'
    when p_action in ('begin_exit', 'end') then 'Hr:ContingentWorkforce:End'
    else 'Hr:ContingentWorkforce:Engagement:Manage'
  end;
  if auth.uid() is null or not app_private.can_execute_business_action(
    'HrContingentWorkforce', v_action_permission, null, false
  ) then
    raise exception '当前账号没有执行此外部用工流转的权限' using errcode = '42501';
  end if;

  if p_kind = 'vendor' then
    select * into v_vendor from public.hr_external_vendor
    where id = p_id and (app_private.is_platform_super() or tenant_id = v_tenant_id) for update;
    if not found then raise exception '供应商不存在或不属于当前租户'; end if;

    if p_action = 'verify' and v_vendor.compliance_status in ('pending', 'rejected', 'expired') then
      update public.hr_external_vendor set compliance_status = 'verified', note = coalesce(nullif(btrim(p_comment), ''), note)
      where id = p_id;
    elsif p_action = 'activate' and v_vendor.status in ('draft', 'suspended', 'inactive') then
      if v_vendor.compliance_status <> 'verified' then raise exception '供应商合规审核未通过'; end if;
      if v_vendor.contract_start_date is null or v_vendor.contract_end_date is null
         or current_date not between v_vendor.contract_start_date and v_vendor.contract_end_date then
        raise exception '供应商合同不在有效期内';
      end if;
      update public.hr_external_vendor set status = 'active', note = coalesce(nullif(btrim(p_comment), ''), note)
      where id = p_id;
    elsif p_action = 'suspend' and v_vendor.status = 'active' then
      update public.hr_external_vendor set status = 'suspended', note = coalesce(nullif(btrim(p_comment), ''), note)
      where id = p_id;
    elsif p_action = 'deactivate' and v_vendor.status in ('draft', 'suspended', 'expired') then
      if exists (select 1 from public.hr_external_engagement where vendor_id = p_id and status = 'active') then
        raise exception '供应商仍有在场用工任务，不能停用';
      end if;
      update public.hr_external_vendor set status = 'inactive', note = coalesce(nullif(btrim(p_comment), ''), note)
      where id = p_id;
    else
      raise exception '供应商当前状态不支持此操作';
    end if;
  elsif p_kind = 'worker' then
    select * into v_worker from public.hr_external_worker
    where id = p_id and (app_private.is_platform_super() or tenant_id = v_tenant_id) for update;
    if not found then raise exception '外部人员不存在或不属于当前租户'; end if;

    if p_action = 'verify_identity' and v_worker.status in ('candidate', 'ready') then
      update public.hr_external_worker set identity_check_status = 'passed', status = 'ready',
        note = coalesce(nullif(btrim(p_comment), ''), note) where id = p_id;
    elsif p_action = 'block' and v_worker.status <> 'blocked' then
      if nullif(btrim(p_comment), '') is null then raise exception '锁定外部人员必须填写原因'; end if;
      update public.hr_external_worker set status = 'blocked', note = btrim(p_comment) where id = p_id;
      update public.hr_external_engagement set compliance_status = 'blocked', version = version + 1
      where worker_id = p_id and status in ('draft', 'pending_review', 'active');
    elsif p_action = 'unblock' and v_worker.status = 'blocked' then
      update public.hr_external_worker set status = case when identity_check_status = 'passed' then 'ready' else 'candidate' end,
        note = coalesce(nullif(btrim(p_comment), ''), note) where id = p_id;
    else
      raise exception '外部人员当前状态不支持此操作';
    end if;
  else
    select * into v_engagement from public.hr_external_engagement
    where id = p_id and (app_private.is_platform_super() or tenant_id = v_tenant_id) for update;
    if not found then raise exception '用工任务不存在或不属于当前租户'; end if;
    select * into v_worker from public.hr_external_worker where id = v_engagement.worker_id for update;

    if p_action = 'submit' and v_engagement.status = 'draft' then
      update public.hr_external_engagement set status = 'pending_review', version = version + 1,
        activation_note = coalesce(nullif(btrim(p_comment), ''), activation_note) where id = p_id;
    elsif p_action = 'activate' and v_engagement.status = 'pending_review' then
      if v_worker.status = 'blocked' or v_worker.identity_check_status <> 'passed' then
        raise exception '外部人员身份核验未通过或已锁定';
      end if;
      if v_engagement.vendor_id is not null then
        select * into v_vendor from public.hr_external_vendor where id = v_engagement.vendor_id;
        if v_vendor.status <> 'active' or v_vendor.compliance_status <> 'verified' then
          raise exception '关联供应商未处于合规有效状态';
        end if;
        if v_vendor.contract_start_date is null or v_vendor.contract_end_date is null
           or v_engagement.start_date < v_vendor.contract_start_date
           or v_engagement.end_date > v_vendor.contract_end_date then
          raise exception '用工任务周期超出供应商合同有效期';
        end if;
      elsif v_worker.worker_type in ('outsourced', 'dispatch') then
        raise exception '外包或劳务派遣任务必须关联供应商';
      end if;
      if exists (
        select 1 from public.hr_external_engagement_control control
        where control.engagement_id = p_id and control.required
          and control.status not in ('completed', 'waived')
      ) then
        raise exception '仍有必需准入控制项未完成';
      end if;
      if exists (
        select 1 from public.hr_external_engagement_control control
        where control.engagement_id = p_id and control.status = 'failed'
      ) then
        raise exception '存在失败的准入控制项';
      end if;
      update public.hr_external_engagement set status = 'active', compliance_status = 'cleared',
        activation_note = coalesce(nullif(btrim(p_comment), ''), activation_note), version = version + 1
      where id = p_id;
      update public.hr_external_worker set status = 'active' where id = v_engagement.worker_id;
    elsif p_action = 'begin_exit' and v_engagement.status = 'active' then
      update public.hr_external_engagement set status = 'offboarding', end_reason = nullif(btrim(p_comment), ''),
        version = version + 1 where id = p_id;
      insert into public.hr_external_engagement_control(
        tenant_id, engagement_id, control_type, control_name, required, due_date
      ) values
        (v_engagement.tenant_id, p_id, 'access_badge', '门禁卡与现场权限回收', true, v_exit_date),
        (v_engagement.tenant_id, p_id, 'system_account', '系统账号停用', true, v_exit_date),
        (v_engagement.tenant_id, p_id, 'equipment', '公司设备与资产归还', true, v_exit_date)
      on conflict (engagement_id, lower(control_name)) do nothing;
    elsif p_action = 'end' and v_engagement.status in ('active', 'offboarding') then
      if nullif(btrim(p_comment), '') is null then raise exception '退场必须填写原因'; end if;
      if exists (
        select 1 from public.hr_external_engagement_control control
        where control.engagement_id = p_id and control.required
          and control.control_name in ('门禁卡与现场权限回收', '系统账号停用', '公司设备与资产归还')
          and control.status not in ('completed', 'waived')
      ) then
        raise exception '退场控制项尚未全部完成';
      end if;
      update public.hr_external_engagement set status = 'ended', actual_exit_date = v_exit_date,
        access_expiry_date = least(access_expiry_date, v_exit_date), end_reason = btrim(p_comment),
        version = version + 1 where id = p_id;
      if not exists (
        select 1 from public.hr_external_engagement engagement
        where engagement.worker_id = v_engagement.worker_id and engagement.id <> p_id
          and engagement.status = 'active'
      ) then
        update public.hr_external_worker set status = 'inactive' where id = v_engagement.worker_id;
      end if;
    elsif p_action = 'cancel' and v_engagement.status in ('draft', 'pending_review') then
      update public.hr_external_engagement set status = 'cancelled', end_reason = nullif(btrim(p_comment), ''),
        version = version + 1 where id = p_id;
    else
      raise exception '用工任务当前状态不支持此操作';
    end if;
  end if;

  return true;
end;
$function$;

create or replace function public.hr_delete_contingent_workforce_record_secure(
  p_kind text,
  p_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_permission text;
begin
  if p_kind not in ('vendor', 'worker', 'engagement', 'control') then
    raise exception '不支持的外部用工记录类型';
  end if;
  v_permission := case p_kind
    when 'vendor' then 'Hr:ContingentWorkforce:Vendor:Manage'
    when 'worker' then 'Hr:ContingentWorkforce:Worker:Manage'
    when 'engagement' then 'Hr:ContingentWorkforce:Engagement:Manage'
    else 'Hr:ContingentWorkforce:Control:Manage'
  end;
  if auth.uid() is null or not app_private.can_execute_business_action(
    'HrContingentWorkforce', v_permission, null, false
  ) then
    raise exception '当前账号没有删除外部用工记录的权限' using errcode = '42501';
  end if;

  if p_kind = 'vendor' then
    delete from public.hr_external_vendor
    where id = p_id and (app_private.is_platform_super() or tenant_id = v_tenant_id)
      and status = 'draft';
  elsif p_kind = 'worker' then
    delete from public.hr_external_worker
    where id = p_id and (app_private.is_platform_super() or tenant_id = v_tenant_id)
      and status = 'candidate';
  elsif p_kind = 'engagement' then
    delete from public.hr_external_engagement
    where id = p_id and (app_private.is_platform_super() or tenant_id = v_tenant_id)
      and status = 'draft';
  else
    delete from public.hr_external_engagement_control control
    using public.hr_external_engagement engagement
    where control.id = p_id and control.engagement_id = engagement.id
      and (app_private.is_platform_super() or control.tenant_id = v_tenant_id)
      and engagement.status in ('draft', 'pending_review');
  end if;
  if not found then raise exception '记录不存在、已进入流程或不允许删除'; end if;
  return true;
end;
$function$;

revoke all on function public.hr_contingent_workforce_overview_secure(uuid)
from public, anon, authenticated;
revoke all on function public.hr_list_contingent_workforce_records_secure(text, integer, integer, text, text, uuid, uuid)
from public, anon, authenticated;
revoke all on function public.hr_list_contingent_workforce_options_secure(text, uuid)
from public, anon, authenticated;
revoke all on function public.hr_save_contingent_workforce_record_secure(text, uuid, jsonb)
from public, anon, authenticated;
revoke all on function public.hr_transition_contingent_workforce_record_secure(text, uuid, text, text, date)
from public, anon, authenticated;
revoke all on function public.hr_delete_contingent_workforce_record_secure(text, uuid)
from public, anon, authenticated;

grant execute on function public.hr_contingent_workforce_overview_secure(uuid) to authenticated;
grant execute on function public.hr_list_contingent_workforce_records_secure(text, integer, integer, text, text, uuid, uuid) to authenticated;
grant execute on function public.hr_list_contingent_workforce_options_secure(text, uuid) to authenticated;
grant execute on function public.hr_save_contingent_workforce_record_secure(text, uuid, jsonb) to authenticated;
grant execute on function public.hr_transition_contingent_workforce_record_secure(text, uuid, text, text, date) to authenticated;
grant execute on function public.hr_delete_contingent_workforce_record_secure(text, uuid) to authenticated;

;
