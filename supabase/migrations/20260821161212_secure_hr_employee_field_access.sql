-- Secure HR employee identity, contact, compensation, career-history and audit fields.
-- Existing employee menu/button definitions remain unchanged.

alter table public.hr_employee
  add column if not exists created_by_user_id uuid;

update public.hr_employee employee_row
set created_by_user_id = (
  select user_row.id
  from public.sys_user user_row
  where user_row.tenant_id = employee_row.tenant_id
    and (
      user_row.auth_user_id::text = employee_row.create_by
      or lower(user_row.user_email) = lower(employee_row.create_by)
    )
  order by
    case when user_row.auth_user_id::text = employee_row.create_by then 0 else 1 end,
    user_row.create_time,
    user_row.id
  limit 1
)
where employee_row.created_by_user_id is null
  and nullif(btrim(coalesce(employee_row.create_by, '')), '') is not null;

create index if not exists hr_employee_tenant_creator_idx
  on public.hr_employee(tenant_id, created_by_user_id);
create index if not exists hr_employee_creator_tenant_idx
  on public.hr_employee(created_by_user_id, tenant_id)
  where created_by_user_id is not null;

alter table public.hr_employee
  drop constraint if exists hr_employee_creator_tenant_fkey;
alter table public.hr_employee
  add constraint hr_employee_creator_tenant_fkey
  foreign key (tenant_id, created_by_user_id)
  references public.sys_user(tenant_id, id);

create or replace function app_private.set_hr_employee_creator_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current_user_id uuid := app_private.current_app_user_id();
  v_current_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if tg_op = 'INSERT' then
    if v_current_user_id is not null and v_current_tenant_id = new.tenant_id then
      if new.created_by_user_id is null then
        new.created_by_user_id := v_current_user_id;
      elsif new.created_by_user_id <> v_current_user_id then
        raise exception 'Employee creator must be the current tenant user'
          using errcode = '42501';
      end if;
    elsif v_current_user_id is not null and not app_private.is_platform_super() then
      raise exception 'Employee tenant must match the current user tenant'
        using errcode = '42501';
    elsif new.created_by_user_id is null
      and nullif(btrim(coalesce(new.create_by, '')), '') is not null then
      select user_row.id into new.created_by_user_id
      from public.sys_user user_row
      where user_row.tenant_id = new.tenant_id
        and (
          user_row.auth_user_id::text = new.create_by
          or lower(user_row.user_email) = lower(new.create_by)
        )
      order by
        case when user_row.auth_user_id::text = new.create_by then 0 else 1 end,
        user_row.create_time,
        user_row.id
      limit 1;
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Employee creator cannot be changed' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists hr_employee_creator_identity on public.hr_employee;
create trigger hr_employee_creator_identity
before insert or update of created_by_user_id on public.hr_employee
for each row execute function app_private.set_hr_employee_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
  rename to seed_field_permission_catalog_before_hr_employee;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_hr_employee(p_tenant_id);

  insert into public.sys_permission_resource(
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'hr.employee', '员工档案', 'HrEmployeeRoster',
    'created_by_user_id', '624944977@qq.com', '624944977@qq.com'
  )
  on conflict (tenant_id, resource_key) do update
    set resource_label = excluded.resource_label,
        menu_name = excluded.menu_name,
        owner_column = excluded.owner_column,
        enabled = true,
        update_by = excluded.update_by,
        update_time = now()
  returning id into v_resource_id;

  insert into public.sys_permission_field(
    tenant_id, resource_id, field_key, field_label, default_access, mask_strategy,
    owner_override_enabled, sensitive, enabled, sort, create_by, update_by
  ) values
    (
      p_tenant_id, v_resource_id, 'contactDetails',
      '手机、邮箱、住址及紧急联系人',
      'hidden', 'phone', true, true, true, 10,
      '624944977@qq.com', '624944977@qq.com'
    ),
    (
      p_tenant_id, v_resource_id, 'identityDetails',
      '身份证、出生日期及个人身份信息',
      'hidden', 'id_card', true, true, true, 20,
      '624944977@qq.com', '624944977@qq.com'
    ),
    (
      p_tenant_id, v_resource_id, 'compensationDetails',
      '合同月薪、培训费用及奖惩金额',
      'hidden', 'amount', true, true, true, 30,
      '624944977@qq.com', '624944977@qq.com'
    ),
    (
      p_tenant_id, v_resource_id, 'careerRecords',
      '合同、教育、工作、培训及奖惩履历',
      'hidden', 'none', true, true, true, 40,
      '624944977@qq.com', '624944977@qq.com'
    ),
    (
      p_tenant_id, v_resource_id, 'maintenanceAudit',
      '账号关联、创建维护人员及时间',
      'hidden', 'none', true, true, true, 50,
      '624944977@qq.com', '624944977@qq.com'
    )
  on conflict (tenant_id, resource_id, field_key) do update
    set field_label = excluded.field_label,
        mask_strategy = excluded.mask_strategy,
        owner_override_enabled = excluded.owner_override_enabled,
        sensitive = true,
        enabled = true,
        sort = excluded.sort,
        update_by = excluded.update_by,
        update_time = now();
end;
$$;

select app_private.seed_field_permission_catalog(tenant_row.id)
from public.sys_tenant tenant_row;

insert into public.sys_role_field_permission(
  tenant_id, role_id, resource_id, field_id, access_level, create_by, update_by
)
select distinct
  resource_row.tenant_id,
  role_menu.role_id,
  resource_row.id,
  field_row.id,
  'edit',
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_permission_resource resource_row
join public.sys_permission_field field_row
  on field_row.tenant_id = resource_row.tenant_id
 and field_row.resource_id = resource_row.id
join public.sys_menu menu_row
  on menu_row.type = 'menu'
 and menu_row.name = 'HrEmployeeRoster'
join public.sys_role_menu role_menu
  on role_menu.tenant_id = resource_row.tenant_id
 and role_menu.menu_id = menu_row.id
where resource_row.resource_key = 'hr.employee'
  and resource_row.enabled
  and field_row.enabled
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

create or replace function app_private.assert_hr_employee_readable()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not app_private.can_execute_business_action(
    'HrEmployeeRoster', 'Hr:Employee:View', null, false
  ) then
    raise exception 'Missing employee view permission' using errcode = '42501';
  end if;
end;
$$;

create or replace function app_private.hr_employee_to_secure_json(
  p_employee_id uuid,
  p_owner_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb := app_private.field_access_map('hr.employee', p_owner_id);
  v_contact_access text := coalesce(v_access ->> 'contactDetails', 'hidden');
  v_identity_access text := coalesce(v_access ->> 'identityDetails', 'hidden');
  v_career_access text := coalesce(v_access ->> 'careerRecords', 'hidden');
  v_audit_access text := coalesce(v_access ->> 'maintenanceAudit', 'hidden');
  v_data jsonb;
begin
  select
    (to_jsonb(employee_row) - 'created_by_user_id')
    || jsonb_build_object(
      'tenant', jsonb_build_object(
        'id', tenant_row.id,
        'tenant_code', tenant_row.tenant_code,
        'tenant_name', tenant_row.tenant_name
      ),
      'organization', case when organization_row.id is null then null else jsonb_build_object(
        'id', organization_row.id,
        'organization_code', organization_row.organization_code,
        'organization_name', organization_row.organization_name
      ) end,
      'account', case when account_row.id is null then null else jsonb_build_object(
        'id', account_row.id,
        'user_email', account_row.user_email,
        'status', account_row.status
      ) end
    )
  into v_data
  from public.hr_employee employee_row
  join public.sys_tenant tenant_row on tenant_row.id = employee_row.tenant_id
  left join public.sys_organization organization_row
    on organization_row.id = employee_row.organization_id
   and organization_row.tenant_id = employee_row.tenant_id
  left join lateral (
    select user_row.id, user_row.user_email, user_row.status
    from public.sys_user user_row
    where user_row.hr_employee_id = employee_row.id
      and user_row.tenant_id = employee_row.tenant_id
      and user_row.deleted_at is null
    order by user_row.create_time, user_row.id
    limit 1
  ) account_row on true
  where employee_row.id = p_employee_id
    and (
      app_private.is_platform_super()
      or employee_row.tenant_id = app_private.current_user_tenant_id()
    );

  if v_data is null then return null; end if;

  if v_contact_access = 'hidden' then
    v_data := v_data
      - 'phone' - 'email' - 'home_address'
      - 'emergency_contact_name' - 'emergency_contact_relation'
      - 'emergency_contact_phone';
  elsif v_contact_access = 'masked' then
    v_data := jsonb_set(
      v_data, '{phone}',
      coalesce(to_jsonb(app_private.mask_permission_value(v_data ->> 'phone', 'phone')), 'null'::jsonb),
      true
    );
    v_data := jsonb_set(v_data, '{email}', case when v_data ->> 'email' is null then 'null'::jsonb else '"***"'::jsonb end, true);
    v_data := jsonb_set(
      v_data, '{home_address}',
      coalesce(to_jsonb(app_private.mask_permission_value(v_data ->> 'home_address', 'address')), 'null'::jsonb),
      true
    );
    v_data := jsonb_set(v_data, '{emergency_contact_name}', case when v_data ->> 'emergency_contact_name' is null then 'null'::jsonb else '"***"'::jsonb end, true);
    v_data := jsonb_set(v_data, '{emergency_contact_relation}', case when v_data ->> 'emergency_contact_relation' is null then 'null'::jsonb else '"***"'::jsonb end, true);
    v_data := jsonb_set(
      v_data, '{emergency_contact_phone}',
      coalesce(to_jsonb(app_private.mask_permission_value(v_data ->> 'emergency_contact_phone', 'phone')), 'null'::jsonb),
      true
    );
  end if;

  if v_identity_access = 'hidden' then
    v_data := v_data
      - 'gender' - 'birth_date' - 'id_card_no' - 'ethnicity'
      - 'education_level' - 'school_name' - 'major_name'
      - 'marital_status' - 'political_status' - 'native_place';
  elsif v_identity_access = 'masked' then
    v_data := app_private.apply_jsonb_text_access(
      v_data,
      array[
        'gender', 'birth_date', 'ethnicity', 'education_level', 'school_name',
        'major_name', 'marital_status', 'political_status', 'native_place'
      ]::text[],
      'masked'
    );
    v_data := jsonb_set(
      v_data, '{id_card_no}',
      coalesce(to_jsonb(app_private.mask_permission_value(v_data ->> 'id_card_no', 'id_card')), 'null'::jsonb),
      true
    );
  end if;

  v_data := app_private.apply_jsonb_text_access(
    v_data, array['remark']::text[], v_career_access
  );

  if v_audit_access = 'hidden' then
    v_data := v_data
      - 'account' - 'create_by' - 'create_time' - 'update_by' - 'update_time';
  elsif v_audit_access = 'masked' then
    v_data := app_private.apply_jsonb_text_access(
      v_data,
      array['create_by', 'create_time', 'update_by', 'update_time']::text[],
      'masked'
    );
    if v_data -> 'account' is not null and v_data -> 'account' <> 'null'::jsonb then
      v_data := jsonb_set(
        v_data, '{account}',
        jsonb_build_object('user_email', '***', 'status', '***'),
        true
      );
    end if;
  end if;

  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_owner_id is not null
      and p_owner_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function app_private.hr_employee_histories_to_secure_json(
  p_employee_id uuid,
  p_owner_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb := app_private.field_access_map('hr.employee', p_owner_id);
  v_career_access text := coalesce(v_access ->> 'careerRecords', 'hidden');
  v_compensation_access text := coalesce(v_access ->> 'compensationDetails', 'hidden');
  v_contact_access text := coalesce(v_access ->> 'contactDetails', 'hidden');
  v_audit_access text := coalesce(v_access ->> 'maintenanceAudit', 'hidden');
  v_contracts jsonb := '[]'::jsonb;
  v_educations jsonb := '[]'::jsonb;
  v_work_experiences jsonb := '[]'::jsonb;
  v_trainings jsonb := '[]'::jsonb;
  v_rewards jsonb := '[]'::jsonb;
  v_history_counts jsonb;
begin
  if v_career_access = 'hidden' then
    return jsonb_build_object(
      'contracts', '[]'::jsonb,
      'educations', '[]'::jsonb,
      'work_experiences', '[]'::jsonb,
      'trainings', '[]'::jsonb,
      'rewards', '[]'::jsonb,
      'histories_masked', false
    );
  end if;

  select jsonb_build_object(
    'contracts', (select count(*) from public.hr_employee_contract where employee_id = p_employee_id),
    'educations', (select count(*) from public.hr_employee_education where employee_id = p_employee_id),
    'work_experiences', (select count(*) from public.hr_employee_work_experience where employee_id = p_employee_id),
    'trainings', (select count(*) from public.hr_employee_training where employee_id = p_employee_id),
    'rewards', (select count(*) from public.hr_employee_reward where employee_id = p_employee_id)
  ) into v_history_counts;

  if v_career_access = 'masked' then
    return jsonb_build_object(
      'contracts', '[]'::jsonb,
      'educations', '[]'::jsonb,
      'work_experiences', '[]'::jsonb,
      'trainings', '[]'::jsonb,
      'rewards', '[]'::jsonb,
      'histories_masked', true,
      'history_counts', v_history_counts
    );
  end if;

  select coalesce(jsonb_agg(
    app_private.apply_jsonb_amount_access(
      case when v_audit_access in ('read', 'edit') then
        to_jsonb(contract_row) - 'tenant_id' - 'employee_id'
      else
        to_jsonb(contract_row)
          - 'tenant_id' - 'employee_id'
          - 'create_by' - 'create_time' - 'update_by' - 'update_time'
      end,
      array['monthly_salary']::text[],
      v_compensation_access
    ) order by contract_row.start_date desc, contract_row.create_time desc
  ), '[]'::jsonb)
  into v_contracts
  from public.hr_employee_contract contract_row
  where contract_row.employee_id = p_employee_id;

  select coalesce(jsonb_agg(
    case when v_audit_access in ('read', 'edit') then
      to_jsonb(education_row) - 'tenant_id' - 'employee_id'
    else
      to_jsonb(education_row)
        - 'tenant_id' - 'employee_id'
        - 'create_by' - 'create_time' - 'update_by' - 'update_time'
    end
    order by education_row.start_date desc nulls last, education_row.create_time desc
  ), '[]'::jsonb)
  into v_educations
  from public.hr_employee_education education_row
  where education_row.employee_id = p_employee_id;

  select coalesce(jsonb_agg(
    case
      when v_contact_access = 'hidden' then v_work_data - 'reference_name' - 'reference_phone'
      when v_contact_access = 'masked' then
        jsonb_set(
          jsonb_set(
            v_work_data,
            '{reference_name}',
            case when v_work_data ->> 'reference_name' is null then 'null'::jsonb else '"***"'::jsonb end,
            true
          ),
          '{reference_phone}',
          coalesce(to_jsonb(app_private.mask_permission_value(v_work_data ->> 'reference_phone', 'phone')), 'null'::jsonb),
          true
        )
      else v_work_data
    end
    order by v_start_date desc, v_create_time desc
  ), '[]'::jsonb)
  into v_work_experiences
  from (
    select
      work_row.start_date as v_start_date,
      work_row.create_time as v_create_time,
      case when v_audit_access in ('read', 'edit') then
        to_jsonb(work_row) - 'tenant_id' - 'employee_id'
      else
        to_jsonb(work_row)
          - 'tenant_id' - 'employee_id'
          - 'create_by' - 'create_time' - 'update_by' - 'update_time'
      end as v_work_data
    from public.hr_employee_work_experience work_row
    where work_row.employee_id = p_employee_id
  ) work_rows;

  select coalesce(jsonb_agg(
    app_private.apply_jsonb_amount_access(
      case when v_audit_access in ('read', 'edit') then
        to_jsonb(training_row) - 'tenant_id' - 'employee_id'
      else
        to_jsonb(training_row)
          - 'tenant_id' - 'employee_id'
          - 'create_by' - 'create_time' - 'update_by' - 'update_time'
      end,
      array['cost']::text[],
      v_compensation_access
    ) order by training_row.start_date desc, training_row.create_time desc
  ), '[]'::jsonb)
  into v_trainings
  from public.hr_employee_training training_row
  where training_row.employee_id = p_employee_id;

  select coalesce(jsonb_agg(
    app_private.apply_jsonb_amount_access(
      case when v_audit_access in ('read', 'edit') then
        to_jsonb(reward_row) - 'tenant_id' - 'employee_id'
      else
        to_jsonb(reward_row)
          - 'tenant_id' - 'employee_id'
          - 'create_by' - 'create_time' - 'update_by' - 'update_time'
      end,
      array['amount']::text[],
      v_compensation_access
    ) order by reward_row.record_date desc, reward_row.create_time desc
  ), '[]'::jsonb)
  into v_rewards
  from public.hr_employee_reward reward_row
  where reward_row.employee_id = p_employee_id;

  return jsonb_build_object(
    'contracts', v_contracts,
    'educations', v_educations,
    'work_experiences', v_work_experiences,
    'trainings', v_trainings,
    'rewards', v_rewards,
    'histories_masked', false,
    'history_counts', v_history_counts
  );
end;
$$;

create or replace function public.hr_list_employees_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_tenant_id uuid default null,
  p_organization_ids uuid[] default null,
  p_organization_unassigned boolean default false,
  p_employment_status text default null,
  p_employment_type text default null,
  p_keyword text default null,
  p_hire_start date default null,
  p_hire_end date default null,
  p_record_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_target_tenant_id uuid;
  v_current_user_id uuid := app_private.current_app_user_id();
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer := least(
    greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1),
    1000
  );
  v_keyword text := nullif(btrim(p_keyword), '');
  v_contact_access text := app_private.resolve_field_access(
    'hr.employee', 'contactDetails', null
  );
  v_identity_access text := app_private.resolve_field_access(
    'hr.employee', 'identityDetails', null
  );
  v_total bigint;
  v_records jsonb := '[]'::jsonb;
  v_row record;
begin
  perform app_private.assert_hr_employee_readable();

  v_target_tenant_id := case
    when app_private.is_platform_super() and p_tenant_id is not null then p_tenant_id
    else v_tenant_id
  end;
  if v_target_tenant_id is null then
    raise exception 'Employee tenant is required' using errcode = '22023';
  end if;

  select count(*) into v_total
  from public.hr_employee employee_row
  where employee_row.tenant_id = v_target_tenant_id
    and (p_record_id is null or employee_row.id = p_record_id)
    and (
      not coalesce(p_organization_unassigned, false)
      or employee_row.organization_id is null
    )
    and (
      coalesce(p_organization_unassigned, false)
      or p_organization_ids is null
      or employee_row.organization_id = any(p_organization_ids)
    )
    and (p_employment_status is null or employee_row.employment_status = p_employment_status)
    and (p_employment_type is null or employee_row.employment_type = p_employment_type)
    and (p_hire_start is null or employee_row.hire_date >= p_hire_start)
    and (p_hire_end is null or employee_row.hire_date <= p_hire_end)
    and (
      v_keyword is null
      or employee_row.employee_no ilike '%' || v_keyword || '%'
      or employee_row.employee_name ilike '%' || v_keyword || '%'
      or employee_row.job_title ilike '%' || v_keyword || '%'
      or (
        (
          employee_row.created_by_user_id = v_current_user_id
          or v_contact_access in ('read', 'edit')
        )
        and (
          employee_row.phone ilike '%' || v_keyword || '%'
          or employee_row.email ilike '%' || v_keyword || '%'
        )
      )
      or (
        (
          employee_row.created_by_user_id = v_current_user_id
          or v_identity_access in ('read', 'edit')
        )
        and employee_row.id_card_no ilike '%' || v_keyword || '%'
      )
    );

  for v_row in
    select employee_row.id, employee_row.created_by_user_id
    from public.hr_employee employee_row
    where employee_row.tenant_id = v_target_tenant_id
      and (p_record_id is null or employee_row.id = p_record_id)
      and (
        not coalesce(p_organization_unassigned, false)
        or employee_row.organization_id is null
      )
      and (
        coalesce(p_organization_unassigned, false)
        or p_organization_ids is null
        or employee_row.organization_id = any(p_organization_ids)
      )
      and (p_employment_status is null or employee_row.employment_status = p_employment_status)
      and (p_employment_type is null or employee_row.employment_type = p_employment_type)
      and (p_hire_start is null or employee_row.hire_date >= p_hire_start)
      and (p_hire_end is null or employee_row.hire_date <= p_hire_end)
      and (
        v_keyword is null
        or employee_row.employee_no ilike '%' || v_keyword || '%'
        or employee_row.employee_name ilike '%' || v_keyword || '%'
        or employee_row.job_title ilike '%' || v_keyword || '%'
        or (
          (
            employee_row.created_by_user_id = v_current_user_id
            or v_contact_access in ('read', 'edit')
          )
          and (
            employee_row.phone ilike '%' || v_keyword || '%'
            or employee_row.email ilike '%' || v_keyword || '%'
          )
        )
        or (
          (
            employee_row.created_by_user_id = v_current_user_id
            or v_identity_access in ('read', 'edit')
          )
          and employee_row.id_card_no ilike '%' || v_keyword || '%'
        )
      )
    order by
      employee_row.employment_status,
      employee_row.hire_date desc nulls last,
      employee_row.create_time desc,
      employee_row.id
    offset v_from limit v_limit
  loop
    v_records := v_records || jsonb_build_array(
      app_private.hr_employee_to_secure_json(v_row.id, v_row.created_by_user_id)
    );
  end loop;

  return jsonb_build_object(
    'records', v_records,
    'total', v_total,
    'field_access', app_private.field_access_map('hr.employee', null)
  );
end;
$$;

create or replace function public.hr_get_employee_profile_secure(p_employee_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_employee jsonb;
begin
  perform app_private.assert_hr_employee_readable();

  select employee_row.created_by_user_id into v_owner_id
  from public.hr_employee employee_row
  where employee_row.id = p_employee_id
    and (
      app_private.is_platform_super()
      or employee_row.tenant_id = app_private.current_user_tenant_id()
    );
  if not found then
    raise exception 'Employee profile not found' using errcode = 'P0002';
  end if;

  v_employee := app_private.hr_employee_to_secure_json(p_employee_id, v_owner_id);
  return v_employee || app_private.hr_employee_histories_to_secure_json(
    p_employee_id, v_owner_id
  );
end;
$$;

create or replace function public.hr_list_employee_organization_scope_secure(
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_target_tenant_id uuid;
begin
  perform app_private.assert_hr_employee_readable();
  v_target_tenant_id := case
    when app_private.is_platform_super() and p_tenant_id is not null then p_tenant_id
    else v_tenant_id
  end;
  if v_target_tenant_id is null then return '[]'::jsonb; end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', organization_row.id,
      'tenant_id', organization_row.tenant_id,
      'parent_id', organization_row.parent_id,
      'organization_code', organization_row.organization_code,
      'organization_name', organization_row.organization_name,
      'organization_type', organization_row.organization_type,
      'status', organization_row.status,
      'sort', organization_row.sort,
      'is_system', organization_row.is_system,
      'scope_count', (
        select count(*)
        from public.hr_employee employee_row
        where employee_row.tenant_id = organization_row.tenant_id
          and employee_row.organization_id = organization_row.id
      )
    ) order by organization_row.sort, organization_row.organization_name)
    from public.sys_organization organization_row
    where organization_row.tenant_id = v_target_tenant_id
      and organization_row.status = '1'
  ), '[]'::jsonb);
end;
$$;

create or replace function public.hr_list_employee_selector_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_tenant_id uuid default null,
  p_keyword text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_target_tenant_id uuid;
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer := least(
    greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1),
    200
  );
  v_keyword text := nullif(btrim(p_keyword), '');
  v_has_hr_menu boolean := app_private.can_execute_business_action(
    'HrEmployeeRoster', null, null, false
  );
  v_contact_access text := case when v_has_hr_menu then app_private.resolve_field_access(
    'hr.employee', 'contactDetails', null
  ) else 'hidden' end;
  v_identity_access text := case when v_has_hr_menu then app_private.resolve_field_access(
    'hr.employee', 'identityDetails', null
  ) else 'hidden' end;
  v_total bigint;
  v_records jsonb;
begin
  if not (
    app_private.can_execute_business_action(
      'HrEmployeeRoster', 'Hr:Employee:View', null, false
    )
    or app_private.can_execute_business_action('User', 'System:User:Add', null, false)
    or app_private.can_execute_business_action('User', 'System:User:Edit', null, false)
  ) then
    raise exception 'Missing employee selector permission' using errcode = '42501';
  end if;

  v_target_tenant_id := case
    when app_private.is_platform_super() and p_tenant_id is not null then p_tenant_id
    else v_tenant_id
  end;
  if v_target_tenant_id is null then
    return jsonb_build_object('records', '[]'::jsonb, 'total', 0);
  end if;

  with filtered as materialized (
    select
      employee_row.*,
      organization_row.organization_code,
      organization_row.organization_name
    from public.hr_employee employee_row
    left join public.sys_organization organization_row
      on organization_row.id = employee_row.organization_id
     and organization_row.tenant_id = employee_row.tenant_id
    where employee_row.tenant_id = v_target_tenant_id
      and employee_row.employment_status in ('probation', 'active')
      and not exists (
        select 1
        from public.sys_user user_row
        where user_row.hr_employee_id = employee_row.id
          and user_row.tenant_id = employee_row.tenant_id
          and user_row.deleted_at is null
      )
      and (
        v_keyword is null
        or employee_row.employee_no ilike '%' || v_keyword || '%'
        or employee_row.employee_name ilike '%' || v_keyword || '%'
        or employee_row.job_title ilike '%' || v_keyword || '%'
        or (
          v_contact_access in ('read', 'edit')
          and (
            employee_row.phone ilike '%' || v_keyword || '%'
            or employee_row.email ilike '%' || v_keyword || '%'
          )
        )
      )
  ), paged as (
    select *
    from filtered
    order by employee_name, employee_no, id
    offset v_from limit v_limit
  )
  select
    (select count(*) from filtered),
    coalesce((
      select jsonb_agg(
        jsonb_strip_nulls(jsonb_build_object(
          'id', paged.id,
          'tenant_id', paged.tenant_id,
          'organization_id', paged.organization_id,
          'employee_no', paged.employee_no,
          'employee_name', paged.employee_name,
          'avatar_url', paged.avatar_url,
          'job_title', paged.job_title,
          'employment_status', paged.employment_status,
          'organization', case when paged.organization_id is null then null else jsonb_build_object(
            'id', paged.organization_id,
            'organization_code', paged.organization_code,
            'organization_name', paged.organization_name
          ) end,
          'gender', case when v_identity_access in ('read', 'edit') then paged.gender else null end,
          'phone', case when v_contact_access in ('read', 'edit') then paged.phone else null end,
          'email', case when v_contact_access in ('read', 'edit') then paged.email else null end
        )) order by paged.employee_name, paged.employee_no, paged.id
      )
      from paged
    ), '[]'::jsonb)
  into v_total, v_records;

  return jsonb_build_object(
    'records', v_records,
    'total', v_total,
    'field_access', case when v_has_hr_menu
      then app_private.field_access_map('hr.employee', null)
      else '{}'::jsonb
    end
  );
end;
$$;

create or replace function public.hr_save_employee_profile_secure(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_employee_json jsonb := coalesce(p_payload -> 'employee', '{}'::jsonb);
  v_employee_id uuid := nullif(v_employee_json ->> 'id', '')::uuid;
  v_current public.hr_employee%rowtype;
  v_input public.hr_employee%rowtype;
  v_safe_employee jsonb;
  v_create_result jsonb;
  v_tenant_id uuid;
  v_owner_id uuid;
  v_contact_access text;
  v_identity_access text;
  v_compensation_access text;
  v_career_access text;
  v_item jsonb;
  v_child_id uuid;
  v_records jsonb;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object'
     or jsonb_typeof(v_employee_json) <> 'object' then
    raise exception '员工档案数据格式不正确';
  end if;
  if exists (
    select 1 from jsonb_object_keys(p_payload) payload_key
    where payload_key <> all(array[
      'employee', 'driver', 'contracts', 'educations',
      'work_experiences', 'trainings', 'rewards'
    ]::text[])
  ) then
    raise exception '员工档案包含不允许写入的模块';
  end if;
  if exists (
    select 1 from jsonb_object_keys(v_employee_json) employee_key
    where employee_key <> all(array[
      'id', 'tenant_id', 'organization_id', 'employee_no', 'employee_name',
      'avatar_url', 'position_id', 'job_title', 'employment_status', 'employment_type',
      'gender', 'birth_date', 'phone', 'email', 'id_card_no', 'ethnicity',
      'education_level', 'school_name', 'major_name', 'marital_status',
      'political_status', 'native_place', 'home_address', 'hire_date',
      'probation_end_date', 'leave_date', 'contract_start_date', 'contract_end_date',
      'emergency_contact_name', 'emergency_contact_relation',
      'emergency_contact_phone', 'remark'
    ]::text[])
  ) then
    raise exception '员工基础档案包含不允许写入的字段';
  end if;

  if v_employee_id is null then
    if not app_private.can_execute_business_action(
      'HrEmployeeRoster', 'Hr:Employee:Add', null, false
    ) then
      raise exception 'Missing employee create permission' using errcode = '42501';
    end if;

    v_create_result := public.hr_create_employee_with_driver_secure(
      v_employee_json - 'id' - 'job_title',
      case when p_payload -> 'driver' = 'null'::jsonb then null else p_payload -> 'driver' end
    );
    v_employee_id := nullif(v_create_result ->> 'employee_id', '')::uuid;
    if v_employee_id is null then
      raise exception '保存员工基础档案后未返回员工 ID';
    end if;

    select employee_row.* into v_current
    from public.hr_employee employee_row
    where employee_row.id = v_employee_id
    for update;
  else
    if not app_private.can_execute_business_action(
      'HrEmployeeRoster', 'Hr:Employee:Edit', null, false
    ) then
      raise exception 'Missing employee edit permission' using errcode = '42501';
    end if;

    select employee_row.* into v_current
    from public.hr_employee employee_row
    where employee_row.id = v_employee_id
      and (
        app_private.is_platform_super()
        or employee_row.tenant_id = app_private.current_user_tenant_id()
      )
    for update;
    if not found then
      raise exception '员工档案不存在或无权编辑' using errcode = 'P0002';
    end if;

    v_contact_access := app_private.resolve_field_access(
      'hr.employee', 'contactDetails', v_current.created_by_user_id
    );
    v_identity_access := app_private.resolve_field_access(
      'hr.employee', 'identityDetails', v_current.created_by_user_id
    );
    v_career_access := app_private.resolve_field_access(
      'hr.employee', 'careerRecords', v_current.created_by_user_id
    );

    v_safe_employee := v_employee_json - 'id' - 'tenant_id' - 'job_title';
    if v_contact_access <> 'edit' then
      v_safe_employee := v_safe_employee
        - 'phone' - 'email' - 'home_address'
        - 'emergency_contact_name' - 'emergency_contact_relation'
        - 'emergency_contact_phone';
    end if;
    if v_identity_access <> 'edit' then
      v_safe_employee := v_safe_employee
        - 'gender' - 'birth_date' - 'id_card_no' - 'ethnicity'
        - 'education_level' - 'school_name' - 'major_name'
        - 'marital_status' - 'political_status' - 'native_place';
    end if;
    if v_career_access <> 'edit' then
      v_safe_employee := v_safe_employee - 'remark';
    end if;

    select populated.* into v_input
    from jsonb_populate_record(null::public.hr_employee, v_safe_employee) populated;

    if v_safe_employee ? 'organization_id' and not exists (
      select 1 from public.sys_organization organization_row
      where organization_row.id = v_input.organization_id
        and organization_row.tenant_id = v_current.tenant_id
        and organization_row.status = '1'
    ) then
      raise exception '所选组织不存在、已停用或不属于员工所在租户';
    end if;

    update public.hr_employee employee_row
    set
      organization_id = case when v_safe_employee ? 'organization_id' then v_input.organization_id else employee_row.organization_id end,
      employee_no = case when v_safe_employee ? 'employee_no' then btrim(v_input.employee_no) else employee_row.employee_no end,
      employee_name = case when v_safe_employee ? 'employee_name' then btrim(v_input.employee_name) else employee_row.employee_name end,
      avatar_url = case when v_safe_employee ? 'avatar_url' then v_input.avatar_url else employee_row.avatar_url end,
      position_id = case when v_safe_employee ? 'position_id' then v_input.position_id else employee_row.position_id end,
      employment_status = case when v_safe_employee ? 'employment_status' then v_input.employment_status else employee_row.employment_status end,
      employment_type = case when v_safe_employee ? 'employment_type' then v_input.employment_type else employee_row.employment_type end,
      gender = case when v_safe_employee ? 'gender' then v_input.gender else employee_row.gender end,
      birth_date = case when v_safe_employee ? 'birth_date' then v_input.birth_date else employee_row.birth_date end,
      phone = case when v_safe_employee ? 'phone' then v_input.phone else employee_row.phone end,
      email = case when v_safe_employee ? 'email' then v_input.email else employee_row.email end,
      id_card_no = case when v_safe_employee ? 'id_card_no' then v_input.id_card_no else employee_row.id_card_no end,
      ethnicity = case when v_safe_employee ? 'ethnicity' then v_input.ethnicity else employee_row.ethnicity end,
      education_level = case when v_safe_employee ? 'education_level' then v_input.education_level else employee_row.education_level end,
      school_name = case when v_safe_employee ? 'school_name' then v_input.school_name else employee_row.school_name end,
      major_name = case when v_safe_employee ? 'major_name' then v_input.major_name else employee_row.major_name end,
      marital_status = case when v_safe_employee ? 'marital_status' then v_input.marital_status else employee_row.marital_status end,
      political_status = case when v_safe_employee ? 'political_status' then v_input.political_status else employee_row.political_status end,
      native_place = case when v_safe_employee ? 'native_place' then v_input.native_place else employee_row.native_place end,
      home_address = case when v_safe_employee ? 'home_address' then v_input.home_address else employee_row.home_address end,
      hire_date = case when v_safe_employee ? 'hire_date' then v_input.hire_date else employee_row.hire_date end,
      probation_end_date = case when v_safe_employee ? 'probation_end_date' then v_input.probation_end_date else employee_row.probation_end_date end,
      leave_date = case when v_safe_employee ? 'leave_date' then v_input.leave_date else employee_row.leave_date end,
      contract_start_date = case when v_safe_employee ? 'contract_start_date' then v_input.contract_start_date else employee_row.contract_start_date end,
      contract_end_date = case when v_safe_employee ? 'contract_end_date' then v_input.contract_end_date else employee_row.contract_end_date end,
      emergency_contact_name = case when v_safe_employee ? 'emergency_contact_name' then v_input.emergency_contact_name else employee_row.emergency_contact_name end,
      emergency_contact_relation = case when v_safe_employee ? 'emergency_contact_relation' then v_input.emergency_contact_relation else employee_row.emergency_contact_relation end,
      emergency_contact_phone = case when v_safe_employee ? 'emergency_contact_phone' then v_input.emergency_contact_phone else employee_row.emergency_contact_phone end,
      remark = case when v_safe_employee ? 'remark' then v_input.remark else employee_row.remark end
    where employee_row.id = v_employee_id
    returning employee_row.* into v_current;
  end if;

  v_tenant_id := v_current.tenant_id;
  v_owner_id := v_current.created_by_user_id;
  v_contact_access := app_private.resolve_field_access(
    'hr.employee', 'contactDetails', v_owner_id
  );
  v_compensation_access := app_private.resolve_field_access(
    'hr.employee', 'compensationDetails', v_owner_id
  );
  v_career_access := app_private.resolve_field_access(
    'hr.employee', 'careerRecords', v_owner_id
  );

  if p_payload ? 'contracts' then
    v_records := coalesce(p_payload -> 'contracts', '[]'::jsonb);
    if jsonb_typeof(v_records) <> 'array' then
      raise exception '劳动合同数据格式不正确';
    end if;

    if v_career_access = 'edit' then
      if exists (
        select 1 from jsonb_array_elements(v_records) record_row
        where nullif(record_row ->> 'id', '') is not null
          and not exists (
            select 1 from public.hr_employee_contract child_row
            where child_row.id = (record_row ->> 'id')::uuid
              and child_row.employee_id = v_employee_id
              and child_row.tenant_id = v_tenant_id
          )
      ) then raise exception '劳动合同包含不属于当前员工的记录'; end if;

      delete from public.hr_employee_contract child_row
      where child_row.employee_id = v_employee_id
        and child_row.tenant_id = v_tenant_id
        and child_row.id not in (
          select (record_row ->> 'id')::uuid
          from jsonb_array_elements(v_records) record_row
          where nullif(record_row ->> 'id', '') is not null
        );

      for v_item in select value from jsonb_array_elements(v_records) loop
        v_child_id := coalesce(nullif(v_item ->> 'id', '')::uuid, gen_random_uuid());
        insert into public.hr_employee_contract(
          id, tenant_id, employee_id, contract_no, contract_type, contract_status,
          sign_date, start_date, end_date, probation_end_date, work_location,
          monthly_salary, remark
        ) values (
          v_child_id, v_tenant_id, v_employee_id,
          btrim(v_item ->> 'contract_no'),
          coalesce(nullif(v_item ->> 'contract_type', ''), 'fixed_term'),
          coalesce(nullif(v_item ->> 'contract_status', ''), 'active'),
          nullif(v_item ->> 'sign_date', '')::date,
          nullif(v_item ->> 'start_date', '')::date,
          nullif(v_item ->> 'end_date', '')::date,
          nullif(v_item ->> 'probation_end_date', '')::date,
          nullif(v_item ->> 'work_location', ''),
          case when v_compensation_access = 'edit'
            then nullif(v_item ->> 'monthly_salary', '')::numeric else null end,
          nullif(v_item ->> 'remark', '')
        )
        on conflict (id) do update set
          contract_no = excluded.contract_no,
          contract_type = excluded.contract_type,
          contract_status = excluded.contract_status,
          sign_date = excluded.sign_date,
          start_date = excluded.start_date,
          end_date = excluded.end_date,
          probation_end_date = excluded.probation_end_date,
          work_location = excluded.work_location,
          monthly_salary = case when v_compensation_access = 'edit'
            then excluded.monthly_salary else hr_employee_contract.monthly_salary end,
          remark = excluded.remark;
      end loop;
    elsif v_compensation_access = 'edit' then
      for v_item in select value from jsonb_array_elements(v_records) loop
        if nullif(v_item ->> 'id', '') is not null and v_item ? 'monthly_salary' then
          update public.hr_employee_contract child_row
          set monthly_salary = nullif(v_item ->> 'monthly_salary', '')::numeric
          where child_row.id = (v_item ->> 'id')::uuid
            and child_row.employee_id = v_employee_id
            and child_row.tenant_id = v_tenant_id;
        end if;
      end loop;
    end if;
  end if;

  if p_payload ? 'educations' and v_career_access = 'edit' then
    v_records := coalesce(p_payload -> 'educations', '[]'::jsonb);
    if jsonb_typeof(v_records) <> 'array' then raise exception '教育经历数据格式不正确'; end if;
    if exists (
      select 1 from jsonb_array_elements(v_records) record_row
      where nullif(record_row ->> 'id', '') is not null
        and not exists (
          select 1 from public.hr_employee_education child_row
          where child_row.id = (record_row ->> 'id')::uuid
            and child_row.employee_id = v_employee_id
            and child_row.tenant_id = v_tenant_id
        )
    ) then raise exception '教育经历包含不属于当前员工的记录'; end if;

    delete from public.hr_employee_education child_row
    where child_row.employee_id = v_employee_id
      and child_row.tenant_id = v_tenant_id
      and child_row.id not in (
        select (record_row ->> 'id')::uuid
        from jsonb_array_elements(v_records) record_row
        where nullif(record_row ->> 'id', '') is not null
      );

    for v_item in select value from jsonb_array_elements(v_records) loop
      v_child_id := coalesce(nullif(v_item ->> 'id', '')::uuid, gen_random_uuid());
      insert into public.hr_employee_education(
        id, tenant_id, employee_id, school_name, major_name, education_level,
        degree, start_date, end_date, full_time, certificate_no, remark
      ) values (
        v_child_id, v_tenant_id, v_employee_id,
        btrim(v_item ->> 'school_name'), nullif(v_item ->> 'major_name', ''),
        btrim(v_item ->> 'education_level'), nullif(v_item ->> 'degree', ''),
        nullif(v_item ->> 'start_date', '')::date,
        nullif(v_item ->> 'end_date', '')::date,
        coalesce((v_item ->> 'full_time')::boolean, true),
        nullif(v_item ->> 'certificate_no', ''), nullif(v_item ->> 'remark', '')
      )
      on conflict (id) do update set
        school_name = excluded.school_name,
        major_name = excluded.major_name,
        education_level = excluded.education_level,
        degree = excluded.degree,
        start_date = excluded.start_date,
        end_date = excluded.end_date,
        full_time = excluded.full_time,
        certificate_no = excluded.certificate_no,
        remark = excluded.remark;
    end loop;
  end if;

  if p_payload ? 'work_experiences' and v_career_access = 'edit' then
    v_records := coalesce(p_payload -> 'work_experiences', '[]'::jsonb);
    if jsonb_typeof(v_records) <> 'array' then raise exception '工作经历数据格式不正确'; end if;
    if exists (
      select 1 from jsonb_array_elements(v_records) record_row
      where nullif(record_row ->> 'id', '') is not null
        and not exists (
          select 1 from public.hr_employee_work_experience child_row
          where child_row.id = (record_row ->> 'id')::uuid
            and child_row.employee_id = v_employee_id
            and child_row.tenant_id = v_tenant_id
        )
    ) then raise exception '工作经历包含不属于当前员工的记录'; end if;

    delete from public.hr_employee_work_experience child_row
    where child_row.employee_id = v_employee_id
      and child_row.tenant_id = v_tenant_id
      and child_row.id not in (
        select (record_row ->> 'id')::uuid
        from jsonb_array_elements(v_records) record_row
        where nullif(record_row ->> 'id', '') is not null
      );

    for v_item in select value from jsonb_array_elements(v_records) loop
      v_child_id := coalesce(nullif(v_item ->> 'id', '')::uuid, gen_random_uuid());
      insert into public.hr_employee_work_experience(
        id, tenant_id, employee_id, company_name, department_name, job_title,
        start_date, end_date, responsibilities, leaving_reason,
        reference_name, reference_phone
      ) values (
        v_child_id, v_tenant_id, v_employee_id,
        btrim(v_item ->> 'company_name'), nullif(v_item ->> 'department_name', ''),
        btrim(v_item ->> 'job_title'), nullif(v_item ->> 'start_date', '')::date,
        nullif(v_item ->> 'end_date', '')::date,
        nullif(v_item ->> 'responsibilities', ''),
        nullif(v_item ->> 'leaving_reason', ''),
        case when v_contact_access = 'edit'
          then nullif(v_item ->> 'reference_name', '') else null end,
        case when v_contact_access = 'edit'
          then nullif(v_item ->> 'reference_phone', '') else null end
      )
      on conflict (id) do update set
        company_name = excluded.company_name,
        department_name = excluded.department_name,
        job_title = excluded.job_title,
        start_date = excluded.start_date,
        end_date = excluded.end_date,
        responsibilities = excluded.responsibilities,
        leaving_reason = excluded.leaving_reason,
        reference_name = case when v_contact_access = 'edit'
          then excluded.reference_name else hr_employee_work_experience.reference_name end,
        reference_phone = case when v_contact_access = 'edit'
          then excluded.reference_phone else hr_employee_work_experience.reference_phone end;
    end loop;
  end if;

  if p_payload ? 'trainings' then
    v_records := coalesce(p_payload -> 'trainings', '[]'::jsonb);
    if jsonb_typeof(v_records) <> 'array' then raise exception '培训经历数据格式不正确'; end if;

    if v_career_access = 'edit' then
      if exists (
        select 1 from jsonb_array_elements(v_records) record_row
        where nullif(record_row ->> 'id', '') is not null
          and not exists (
            select 1 from public.hr_employee_training child_row
            where child_row.id = (record_row ->> 'id')::uuid
              and child_row.employee_id = v_employee_id
              and child_row.tenant_id = v_tenant_id
          )
      ) then raise exception '培训经历包含不属于当前员工的记录'; end if;

      delete from public.hr_employee_training child_row
      where child_row.employee_id = v_employee_id
        and child_row.tenant_id = v_tenant_id
        and child_row.id not in (
          select (record_row ->> 'id')::uuid
          from jsonb_array_elements(v_records) record_row
          where nullif(record_row ->> 'id', '') is not null
        );

      for v_item in select value from jsonb_array_elements(v_records) loop
        v_child_id := coalesce(nullif(v_item ->> 'id', '')::uuid, gen_random_uuid());
        insert into public.hr_employee_training(
          id, tenant_id, employee_id, training_name, training_type, provider_name,
          start_date, end_date, training_result, certificate_name, certificate_no,
          cost, remark
        ) values (
          v_child_id, v_tenant_id, v_employee_id,
          btrim(v_item ->> 'training_name'), btrim(v_item ->> 'training_type'),
          nullif(v_item ->> 'provider_name', ''),
          nullif(v_item ->> 'start_date', '')::date,
          nullif(v_item ->> 'end_date', '')::date,
          nullif(v_item ->> 'training_result', ''),
          nullif(v_item ->> 'certificate_name', ''),
          nullif(v_item ->> 'certificate_no', ''),
          case when v_compensation_access = 'edit'
            then nullif(v_item ->> 'cost', '')::numeric else null end,
          nullif(v_item ->> 'remark', '')
        )
        on conflict (id) do update set
          training_name = excluded.training_name,
          training_type = excluded.training_type,
          provider_name = excluded.provider_name,
          start_date = excluded.start_date,
          end_date = excluded.end_date,
          training_result = excluded.training_result,
          certificate_name = excluded.certificate_name,
          certificate_no = excluded.certificate_no,
          cost = case when v_compensation_access = 'edit'
            then excluded.cost else hr_employee_training.cost end,
          remark = excluded.remark;
      end loop;
    elsif v_compensation_access = 'edit' then
      for v_item in select value from jsonb_array_elements(v_records) loop
        if nullif(v_item ->> 'id', '') is not null and v_item ? 'cost' then
          update public.hr_employee_training child_row
          set cost = nullif(v_item ->> 'cost', '')::numeric
          where child_row.id = (v_item ->> 'id')::uuid
            and child_row.employee_id = v_employee_id
            and child_row.tenant_id = v_tenant_id;
        end if;
      end loop;
    end if;
  end if;

  if p_payload ? 'rewards' then
    v_records := coalesce(p_payload -> 'rewards', '[]'::jsonb);
    if jsonb_typeof(v_records) <> 'array' then raise exception '奖惩经历数据格式不正确'; end if;

    if v_career_access = 'edit' then
      if exists (
        select 1 from jsonb_array_elements(v_records) record_row
        where nullif(record_row ->> 'id', '') is not null
          and not exists (
            select 1 from public.hr_employee_reward child_row
            where child_row.id = (record_row ->> 'id')::uuid
              and child_row.employee_id = v_employee_id
              and child_row.tenant_id = v_tenant_id
          )
      ) then raise exception '奖惩经历包含不属于当前员工的记录'; end if;

      delete from public.hr_employee_reward child_row
      where child_row.employee_id = v_employee_id
        and child_row.tenant_id = v_tenant_id
        and child_row.id not in (
          select (record_row ->> 'id')::uuid
          from jsonb_array_elements(v_records) record_row
          where nullif(record_row ->> 'id', '') is not null
        );

      for v_item in select value from jsonb_array_elements(v_records) loop
        v_child_id := coalesce(nullif(v_item ->> 'id', '')::uuid, gen_random_uuid());
        insert into public.hr_employee_reward(
          id, tenant_id, employee_id, record_type, record_level, title,
          record_date, issuing_organization, amount, description
        ) values (
          v_child_id, v_tenant_id, v_employee_id,
          btrim(v_item ->> 'record_type'), nullif(v_item ->> 'record_level', ''),
          btrim(v_item ->> 'title'), nullif(v_item ->> 'record_date', '')::date,
          nullif(v_item ->> 'issuing_organization', ''),
          case when v_compensation_access = 'edit'
            then nullif(v_item ->> 'amount', '')::numeric else null end,
          nullif(v_item ->> 'description', '')
        )
        on conflict (id) do update set
          record_type = excluded.record_type,
          record_level = excluded.record_level,
          title = excluded.title,
          record_date = excluded.record_date,
          issuing_organization = excluded.issuing_organization,
          amount = case when v_compensation_access = 'edit'
            then excluded.amount else hr_employee_reward.amount end,
          description = excluded.description;
      end loop;
    elsif v_compensation_access = 'edit' then
      for v_item in select value from jsonb_array_elements(v_records) loop
        if nullif(v_item ->> 'id', '') is not null and v_item ? 'amount' then
          update public.hr_employee_reward child_row
          set amount = nullif(v_item ->> 'amount', '')::numeric
          where child_row.id = (v_item ->> 'id')::uuid
            and child_row.employee_id = v_employee_id
            and child_row.tenant_id = v_tenant_id;
        end if;
      end loop;
    end if;
  end if;

  return v_employee_id;
end;
$$;

create or replace function public.hr_delete_employee_secure(p_employee_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not app_private.can_execute_business_action(
    'HrEmployeeRoster', 'Hr:Employee:Delete', null, false
  ) then
    raise exception 'Missing employee delete permission' using errcode = '42501';
  end if;

  delete from public.hr_employee employee_row
  where employee_row.id = p_employee_id
    and (
      app_private.is_platform_super()
      or employee_row.tenant_id = app_private.current_user_tenant_id()
    );
  if not found then
    raise exception '员工档案不存在或无权删除' using errcode = 'P0002';
  end if;
end;
$$;

revoke all privileges on table public.hr_employee from anon, authenticated;
revoke all privileges on table public.hr_employee_contract from anon, authenticated;
revoke all privileges on table public.hr_employee_education from anon, authenticated;
revoke all privileges on table public.hr_employee_work_experience from anon, authenticated;
revoke all privileges on table public.hr_employee_training from anon, authenticated;
revoke all privileges on table public.hr_employee_reward from anon, authenticated;

revoke execute on function public.hr_create_employee_with_driver_secure(jsonb, jsonb)
  from public, anon, authenticated;

grant execute on function public.hr_list_employees_secure(
  integer, integer, uuid, uuid[], boolean, text, text, text, date, date, uuid
) to authenticated;
grant execute on function public.hr_get_employee_profile_secure(uuid) to authenticated;
grant execute on function public.hr_list_employee_organization_scope_secure(uuid) to authenticated;
grant execute on function public.hr_list_employee_selector_secure(integer, integer, uuid, text)
  to authenticated;
grant execute on function public.hr_save_employee_profile_secure(jsonb) to authenticated;
grant execute on function public.hr_delete_employee_secure(uuid) to authenticated;

revoke execute on function public.hr_list_employees_secure(
  integer, integer, uuid, uuid[], boolean, text, text, text, date, date, uuid
) from public, anon;
revoke execute on function public.hr_get_employee_profile_secure(uuid) from public, anon;
revoke execute on function public.hr_list_employee_organization_scope_secure(uuid)
  from public, anon;
revoke execute on function public.hr_list_employee_selector_secure(integer, integer, uuid, text)
  from public, anon;
revoke execute on function public.hr_save_employee_profile_secure(jsonb) from public, anon;
revoke execute on function public.hr_delete_employee_secure(uuid) from public, anon;

revoke execute on function app_private.set_hr_employee_creator_identity()
  from public, anon, authenticated;
revoke execute on function app_private.assert_hr_employee_readable()
  from public, anon, authenticated;
revoke execute on function app_private.hr_employee_to_secure_json(uuid, uuid)
  from public, anon, authenticated;
revoke execute on function app_private.hr_employee_histories_to_secure_json(uuid, uuid)
  from public, anon, authenticated;
revoke execute on function app_private.seed_field_permission_catalog_before_hr_employee(uuid)
  from public, anon, authenticated;
revoke execute on function app_private.seed_field_permission_catalog(uuid)
  from public, anon, authenticated;

do $$
begin
  if exists (
    select 1 from public.hr_employee employee_row
    where employee_row.created_by_user_id is null
      and not app_private.is_platform_super()
  ) then
    raise exception 'Unexpected unresolved HR employee creator';
  end if;

  if exists (
    select 1 from public.sys_tenant tenant_row
    where not exists (
      select 1 from public.sys_permission_resource resource_row
      where resource_row.tenant_id = tenant_row.id
        and resource_row.resource_key = 'hr.employee'
        and resource_row.owner_column = 'created_by_user_id'
    )
  ) then
    raise exception 'Missing hr.employee permission resource';
  end if;

  if exists (
    select 1 from public.sys_permission_resource resource_row
    where resource_row.resource_key = 'hr.employee'
      and (
        select count(*) from public.sys_permission_field field_row
        where field_row.resource_id = resource_row.id
          and field_row.enabled
          and field_row.field_key in (
            'contactDetails', 'identityDetails', 'compensationDetails',
            'careerRecords', 'maintenanceAudit'
          )
      ) <> 5
  ) then
    raise exception 'Unexpected hr.employee field catalog';
  end if;
end;
$$;

;
