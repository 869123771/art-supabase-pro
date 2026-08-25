create or replace function app_private.hr_add_compliance_event(
  p_tenant_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_event_type text,
  p_from_status text default null,
  p_to_status text default null,
  p_comment text default null,
  p_event_data jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  insert into public.hr_compliance_event(
    tenant_id, entity_type, entity_id, event_type, from_status, to_status,
    actor_employee_id, comment, event_data
  ) values (
    p_tenant_id, p_entity_type, p_entity_id, p_event_type, p_from_status, p_to_status,
    app_private.hr_current_employee_id(), nullif(btrim(p_comment), ''),
    coalesce(p_event_data, '{}'::jsonb)
  );
end
$function$;

revoke all on function app_private.hr_add_compliance_event(
  uuid, text, uuid, text, text, text, text, jsonb
) from public, anon, authenticated;

create or replace function public.hr_compliance_overview_secure(
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
begin
  if not app_private.can_execute_business_action(
    'HrCompliance', 'Hr:Compliance:View', null, false
  ) then
    raise exception '当前账号没有查看用工合规中心的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  return jsonb_build_object(
    'active_contract_count', (
      select count(*) from public.hr_employee_contract contract
      where (p_tenant_id is null or contract.tenant_id = p_tenant_id)
        and contract.contract_status in ('active', 'renewing')
    ),
    'contract_risk_count', (
      select count(*) from public.hr_employee_contract contract
      where (p_tenant_id is null or contract.tenant_id = p_tenant_id)
        and contract.contract_status in ('active', 'renewing')
        and contract.end_date is not null
        and contract.end_date <= current_date + contract.renewal_reminder_days
    ),
    'overdue_contract_count', (
      select count(*) from public.hr_employee_contract contract
      where (p_tenant_id is null or contract.tenant_id = p_tenant_id)
        and contract.contract_status in ('active', 'renewing')
        and contract.end_date < current_date
    ),
    'qualification_risk_count', (
      select count(*) from public.hr_employee_qualification qualification
      where (p_tenant_id is null or qualification.tenant_id = p_tenant_id)
        and qualification.status <> 'revoked'
        and qualification.expiry_date is not null
        and qualification.expiry_date <= current_date + qualification.reminder_days
    ),
    'expired_qualification_count', (
      select count(*) from public.hr_employee_qualification qualification
      where (p_tenant_id is null or qualification.tenant_id = p_tenant_id)
        and qualification.status <> 'revoked'
        and qualification.expiry_date < current_date
    ),
    'pending_verification_count', (
      select count(*) from public.hr_employee_qualification qualification
      where (p_tenant_id is null or qualification.tenant_id = p_tenant_id)
        and qualification.status <> 'revoked'
        and qualification.verification_status in ('pending', 'rejected')
    ),
    'verified_rate', (
      select coalesce(round(
        100 * count(*) filter (where qualification.verification_status = 'verified')::numeric
        / nullif(count(*) filter (where qualification.status <> 'revoked'), 0), 1
      ), 0)
      from public.hr_employee_qualification qualification
      where p_tenant_id is null or qualification.tenant_id = p_tenant_id
    )
  );
end
$function$;

create or replace function public.hr_list_compliance_records_secure(
  p_kind text,
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_status text default null,
  p_risk_status text default null,
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
  v_offset integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer := least(500,
    greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1));
  v_keyword text := nullif(btrim(p_keyword), '');
  v_result jsonb;
begin
  if p_kind not in ('risk', 'contract', 'qualification') then
    raise exception '不支持的用工合规记录类型';
  end if;
  if not app_private.can_execute_business_action(
    'HrCompliance', 'Hr:Compliance:View', null, false
  ) then
    raise exception '当前账号没有查看用工合规中心的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  if p_kind = 'contract' then
    with enriched as materialized (
      select contract.*,
        case
          when contract.contract_status in ('active', 'renewing')
            and contract.end_date < current_date then 'expired'
          else contract.contract_status
        end as effective_status,
        case
          when contract.contract_status not in ('active', 'renewing') or contract.end_date is null then 'clear'
          when contract.end_date < current_date then 'overdue'
          when contract.end_date <= current_date + 7 then 'critical'
          when contract.end_date <= current_date + 30 then 'due_soon'
          when contract.end_date <= current_date + contract.renewal_reminder_days then 'watch'
          else 'clear'
        end as risk_status,
        case when contract.end_date is null then null
          else contract.end_date - current_date end as days_remaining,
        previous.contract_no as previous_contract_no,
        jsonb_build_object(
          'id', employee.id, 'employee_no', employee.employee_no,
          'employee_name', employee.employee_name, 'job_title', employee.job_title,
          'organization_name', organization.organization_name,
          'position_name', position.position_name
        ) as employee,
        case when owner.id is null then null else jsonb_build_object(
          'id', owner.id, 'employee_no', owner.employee_no,
          'employee_name', owner.employee_name, 'job_title', owner.job_title
        ) end as renewal_owner
      from public.hr_employee_contract contract
      join public.hr_employee employee
        on employee.id = contract.employee_id and employee.tenant_id = contract.tenant_id
      left join public.sys_organization organization
        on organization.id = employee.organization_id
      left join public.hr_position position on position.id = employee.position_id
      left join public.hr_employee_contract previous
        on previous.id = contract.previous_contract_id and previous.tenant_id = contract.tenant_id
      left join public.hr_employee owner
        on owner.id = contract.renewal_owner_id and owner.tenant_id = contract.tenant_id
      where (p_tenant_id is null or contract.tenant_id = p_tenant_id)
    ), filtered as materialized (
      select * from enriched
      where (p_status is null or effective_status = p_status)
        and (p_risk_status is null or risk_status = p_risk_status)
        and (
          v_keyword is null
          or contract_no ilike '%' || v_keyword || '%'
          or employee->>'employee_name' ilike '%' || v_keyword || '%'
          or employee->>'employee_no' ilike '%' || v_keyword || '%'
          or employee->>'job_title' ilike '%' || v_keyword || '%'
        )
    ), paged as (
      select * from filtered
      order by case risk_status when 'overdue' then 1 when 'critical' then 2
        when 'due_soon' then 3 when 'watch' then 4 else 5 end,
        end_date nulls last, update_time desc
      offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg(
        (to_jsonb(paged) - 'effective_status')
          || jsonb_build_object('contract_status', paged.effective_status)
        order by case paged.risk_status when 'overdue' then 1 when 'critical' then 2
          when 'due_soon' then 3 when 'watch' then 4 else 5 end,
          paged.end_date nulls last, paged.update_time desc
      ), '[]'::jsonb),
      'total', (select count(*) from filtered)
    ) into v_result from paged;
    return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0));
  end if;

  if p_kind = 'qualification' then
    with enriched as materialized (
      select qualification.*,
        case
          when qualification.status <> 'revoked' and qualification.expiry_date < current_date
            then 'expired'
          when qualification.status <> 'revoked'
            and qualification.expiry_date <= current_date + qualification.reminder_days
            then 'expiring'
          else qualification.status
        end as effective_status,
        case
          when qualification.status = 'revoked' or qualification.expiry_date is null then 'clear'
          when qualification.expiry_date < current_date then 'overdue'
          when qualification.expiry_date <= current_date + 7 then 'critical'
          when qualification.expiry_date <= current_date + 30 then 'due_soon'
          when qualification.expiry_date <= current_date + qualification.reminder_days then 'watch'
          else 'clear'
        end as risk_status,
        case when qualification.expiry_date is null then null
          else qualification.expiry_date - current_date end as days_remaining,
        jsonb_build_object(
          'id', employee.id, 'employee_no', employee.employee_no,
          'employee_name', employee.employee_name, 'job_title', employee.job_title,
          'organization_name', organization.organization_name,
          'position_name', position.position_name
        ) as employee,
        case when responsible.id is null then null else jsonb_build_object(
          'id', responsible.id, 'employee_no', responsible.employee_no,
          'employee_name', responsible.employee_name, 'job_title', responsible.job_title
        ) end as responsible_employee,
        case when verifier.id is null then null else jsonb_build_object(
          'id', verifier.id, 'employee_no', verifier.employee_no,
          'employee_name', verifier.employee_name, 'job_title', verifier.job_title
        ) end as verified_by_employee
      from public.hr_employee_qualification qualification
      join public.hr_employee employee
        on employee.id = qualification.employee_id and employee.tenant_id = qualification.tenant_id
      left join public.sys_organization organization
        on organization.id = employee.organization_id
      left join public.hr_position position on position.id = employee.position_id
      left join public.hr_employee responsible
        on responsible.id = qualification.responsible_employee_id
        and responsible.tenant_id = qualification.tenant_id
      left join public.hr_employee verifier
        on verifier.id = qualification.verified_by_employee_id
        and verifier.tenant_id = qualification.tenant_id
      where (p_tenant_id is null or qualification.tenant_id = p_tenant_id)
    ), filtered as materialized (
      select * from enriched
      where (p_status is null or effective_status = p_status or verification_status = p_status)
        and (p_risk_status is null or risk_status = p_risk_status)
        and (
          v_keyword is null
          or qualification_name ilike '%' || v_keyword || '%'
          or certificate_no ilike '%' || v_keyword || '%'
          or issuer ilike '%' || v_keyword || '%'
          or employee->>'employee_name' ilike '%' || v_keyword || '%'
          or employee->>'employee_no' ilike '%' || v_keyword || '%'
        )
    ), paged as (
      select * from filtered
      order by case risk_status when 'overdue' then 1 when 'critical' then 2
        when 'due_soon' then 3 when 'watch' then 4 else 5 end,
        expiry_date nulls last, update_time desc
      offset v_offset limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce(jsonb_agg(
        (to_jsonb(paged) - 'effective_status')
          || jsonb_build_object('status', paged.effective_status)
        order by case paged.risk_status when 'overdue' then 1 when 'critical' then 2
          when 'due_soon' then 3 when 'watch' then 4 else 5 end,
          paged.expiry_date nulls last, paged.update_time desc
      ), '[]'::jsonb),
      'total', (select count(*) from filtered)
    ) into v_result from paged;
    return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0));
  end if;

  with risks as materialized (
    select 'contract'::text as entity_type, contract.id as record_id,
      contract.tenant_id, contract.contract_no as subject,
      contract.contract_status as status,
      contract.end_date as due_date,
      contract.end_date - current_date as days_remaining,
      case
        when contract.end_date < current_date then 'overdue'
        when contract.end_date <= current_date + 7 then 'critical'
        when contract.end_date <= current_date + 30 then 'due_soon'
        else 'watch'
      end as risk_status,
      '劳动合同到期处置'::text as risk_type,
      case when owner.id is null then null else jsonb_build_object(
        'id', owner.id, 'employee_no', owner.employee_no,
        'employee_name', owner.employee_name, 'job_title', owner.job_title
      ) end as owner,
      jsonb_build_object(
        'id', employee.id, 'employee_no', employee.employee_no,
        'employee_name', employee.employee_name, 'job_title', employee.job_title,
        'organization_name', organization.organization_name,
        'position_name', position.position_name
      ) as employee,
      concat(contract.contract_no, ' · ',
        case when contract.renewal_decision = 'pending' then '等待续签决策'
          else '尚未启动续签处置' end) as description
    from public.hr_employee_contract contract
    join public.hr_employee employee
      on employee.id = contract.employee_id and employee.tenant_id = contract.tenant_id
    left join public.sys_organization organization on organization.id = employee.organization_id
    left join public.hr_position position on position.id = employee.position_id
    left join public.hr_employee owner
      on owner.id = contract.renewal_owner_id and owner.tenant_id = contract.tenant_id
    where contract.contract_status in ('active', 'renewing')
      and contract.end_date is not null
      and contract.end_date <= current_date + contract.renewal_reminder_days
      and (p_tenant_id is null or contract.tenant_id = p_tenant_id)
    union all
    select 'qualification', qualification.id, qualification.tenant_id,
      qualification.qualification_name, qualification.status,
      qualification.expiry_date, qualification.expiry_date - current_date,
      case
        when qualification.expiry_date < current_date then 'overdue'
        when qualification.expiry_date <= current_date + 7 then 'critical'
        when qualification.expiry_date <= current_date + 30 then 'due_soon'
        else 'watch'
      end,
      '员工资质到期处置',
      case when responsible.id is null then null else jsonb_build_object(
        'id', responsible.id, 'employee_no', responsible.employee_no,
        'employee_name', responsible.employee_name, 'job_title', responsible.job_title
      ) end,
      jsonb_build_object(
        'id', employee.id, 'employee_no', employee.employee_no,
        'employee_name', employee.employee_name, 'job_title', employee.job_title,
        'organization_name', organization.organization_name,
        'position_name', position.position_name
      ),
      concat(coalesce(qualification.certificate_no, '无证书编号'), ' · ',
        case when qualification.verification_status = 'verified' then '已核验'
          else '待完成真实性核验' end)
    from public.hr_employee_qualification qualification
    join public.hr_employee employee
      on employee.id = qualification.employee_id and employee.tenant_id = qualification.tenant_id
    left join public.sys_organization organization on organization.id = employee.organization_id
    left join public.hr_position position on position.id = employee.position_id
    left join public.hr_employee responsible
      on responsible.id = qualification.responsible_employee_id
      and responsible.tenant_id = qualification.tenant_id
    where qualification.status <> 'revoked'
      and qualification.expiry_date is not null
      and qualification.expiry_date <= current_date + qualification.reminder_days
      and (p_tenant_id is null or qualification.tenant_id = p_tenant_id)
  ), filtered as materialized (
    select * from risks
    where (p_status is null or entity_type = p_status)
      and (p_risk_status is null or risk_status = p_risk_status)
      and (
        v_keyword is null
        or subject ilike '%' || v_keyword || '%'
        or risk_type ilike '%' || v_keyword || '%'
        or employee->>'employee_name' ilike '%' || v_keyword || '%'
        or employee->>'employee_no' ilike '%' || v_keyword || '%'
      )
  ), paged as (
    select * from filtered
    order by case risk_status when 'overdue' then 1 when 'critical' then 2
      when 'due_soon' then 3 else 4 end, due_date, subject
    offset v_offset limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce(jsonb_agg(to_jsonb(paged)
      order by case paged.risk_status when 'overdue' then 1 when 'critical' then 2
        when 'due_soon' then 3 else 4 end, paged.due_date, paged.subject), '[]'::jsonb),
    'total', (select count(*) from filtered)
  ) into v_result from paged;
  return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0));
end
$function$;

create or replace function public.hr_get_compliance_detail_secure(
  p_kind text,
  p_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_record jsonb;
  v_record_tenant uuid;
begin
  if p_kind not in ('contract', 'qualification') then
    raise exception '不支持的用工合规记录类型';
  end if;
  if not app_private.can_execute_business_action(
    'HrCompliance', 'Hr:Compliance:View', p_id, false
  ) then
    raise exception '当前账号没有查看用工合规详情的权限' using errcode = '42501';
  end if;

  if p_kind = 'contract' then
    select contract.tenant_id,
      to_jsonb(contract) || jsonb_build_object(
        'employee', jsonb_build_object(
          'id', employee.id, 'employee_no', employee.employee_no,
          'employee_name', employee.employee_name, 'job_title', employee.job_title,
          'organization_name', organization.organization_name,
          'position_name', position.position_name
        ),
        'renewal_owner', case when owner.id is null then null else jsonb_build_object(
          'id', owner.id, 'employee_no', owner.employee_no,
          'employee_name', owner.employee_name, 'job_title', owner.job_title
        ) end,
        'previous_contract_no', previous.contract_no
      ) into v_record_tenant, v_record
    from public.hr_employee_contract contract
    join public.hr_employee employee
      on employee.id = contract.employee_id and employee.tenant_id = contract.tenant_id
    left join public.sys_organization organization on organization.id = employee.organization_id
    left join public.hr_position position on position.id = employee.position_id
    left join public.hr_employee owner
      on owner.id = contract.renewal_owner_id and owner.tenant_id = contract.tenant_id
    left join public.hr_employee_contract previous
      on previous.id = contract.previous_contract_id and previous.tenant_id = contract.tenant_id
    where contract.id = p_id;
  else
    select qualification.tenant_id,
      to_jsonb(qualification) || jsonb_build_object(
        'employee', jsonb_build_object(
          'id', employee.id, 'employee_no', employee.employee_no,
          'employee_name', employee.employee_name, 'job_title', employee.job_title,
          'organization_name', organization.organization_name,
          'position_name', position.position_name
        ),
        'responsible_employee', case when responsible.id is null then null else jsonb_build_object(
          'id', responsible.id, 'employee_no', responsible.employee_no,
          'employee_name', responsible.employee_name, 'job_title', responsible.job_title
        ) end,
        'verified_by_employee', case when verifier.id is null then null else jsonb_build_object(
          'id', verifier.id, 'employee_no', verifier.employee_no,
          'employee_name', verifier.employee_name, 'job_title', verifier.job_title
        ) end
      ) into v_record_tenant, v_record
    from public.hr_employee_qualification qualification
    join public.hr_employee employee
      on employee.id = qualification.employee_id and employee.tenant_id = qualification.tenant_id
    left join public.sys_organization organization on organization.id = employee.organization_id
    left join public.hr_position position on position.id = employee.position_id
    left join public.hr_employee responsible
      on responsible.id = qualification.responsible_employee_id
      and responsible.tenant_id = qualification.tenant_id
    left join public.hr_employee verifier
      on verifier.id = qualification.verified_by_employee_id
      and verifier.tenant_id = qualification.tenant_id
    where qualification.id = p_id;
  end if;

  if v_record is null
    or (not app_private.is_platform_super() and v_record_tenant <> v_tenant_id) then
    raise exception '用工合规记录不存在或无权查看' using errcode = '42501';
  end if;

  return v_record || jsonb_build_object(
    'events', coalesce((
      select jsonb_agg(to_jsonb(event) || jsonb_build_object(
        'actor', case when actor.id is null then null else jsonb_build_object(
          'id', actor.id, 'employee_no', actor.employee_no,
          'employee_name', actor.employee_name, 'job_title', actor.job_title
        ) end
      ) order by event.create_time desc)
      from public.hr_compliance_event event
      left join public.hr_employee actor
        on actor.id = event.actor_employee_id and actor.tenant_id = event.tenant_id
      where event.tenant_id = v_record_tenant
        and event.entity_type = p_kind and event.entity_id = p_id
    ), '[]'::jsonb)
  );
end
$function$;

create or replace function public.hr_save_compliance_record_secure(
  p_kind text,
  p_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_id uuid := nullif(p_payload->>'id', '')::uuid;
  v_tenant_id uuid := coalesce(nullif(p_payload->>'tenant_id', '')::uuid,
    app_private.current_user_tenant_id());
  v_employee_id uuid := nullif(p_payload->>'employee_id', '')::uuid;
  v_existing_contract public.hr_employee_contract;
  v_existing_qualification public.hr_employee_qualification;
  v_core_changed boolean := false;
  v_status text;
begin
  if p_kind not in ('contract', 'qualification') then
    raise exception '不支持的用工合规记录类型';
  end if;
  if not app_private.is_platform_super() then
    v_tenant_id := app_private.current_user_tenant_id();
  end if;
  if v_employee_id is null or not exists (
    select 1 from public.hr_employee employee
    where employee.id = v_employee_id and employee.tenant_id = v_tenant_id
  ) then
    raise exception '请选择当前租户内的有效员工';
  end if;

  if v_id is null then
    if not app_private.can_execute_business_action(
      'HrCompliance', 'Hr:Compliance:Add', null, false
    ) then
      raise exception '当前账号没有新增合同或资质的权限' using errcode = '42501';
    end if;
  elsif not app_private.can_execute_business_action(
    'HrCompliance', 'Hr:Compliance:Edit', v_id, false
  ) then
    raise exception '当前账号没有编辑合同或资质的权限' using errcode = '42501';
  end if;

  if p_kind = 'contract' then
    if nullif(btrim(p_payload->>'contract_no'), '') is null then raise exception '请输入合同编号'; end if;
    if nullif(p_payload->>'start_date', '') is null then raise exception '请选择合同开始日期'; end if;
    if nullif(btrim(p_payload->>'contract_type'), '') is null then raise exception '请选择合同类型'; end if;
    if nullif(p_payload->>'end_date', '') is not null
      and (p_payload->>'end_date')::date < (p_payload->>'start_date')::date then
      raise exception '合同结束日期不能早于开始日期';
    end if;

    if v_id is null then
      v_status := coalesce(nullif(p_payload->>'contract_status', ''), 'draft');
      if v_status not in ('draft', 'active') then v_status := 'draft'; end if;
      insert into public.hr_employee_contract(
        tenant_id, employee_id, contract_no, contract_type, contract_status,
        sign_date, start_date, end_date, probation_end_date, work_location,
        monthly_salary, renewal_reminder_days, renewal_owner_id,
        attachment_url, remark
      ) values (
        v_tenant_id, v_employee_id, btrim(p_payload->>'contract_no'),
        p_payload->>'contract_type', v_status,
        nullif(p_payload->>'sign_date', '')::date,
        (p_payload->>'start_date')::date, nullif(p_payload->>'end_date', '')::date,
        nullif(p_payload->>'probation_end_date', '')::date,
        nullif(btrim(p_payload->>'work_location'), ''),
        nullif(p_payload->>'monthly_salary', '')::numeric,
        coalesce(nullif(p_payload->>'renewal_reminder_days', '')::integer, 30),
        nullif(p_payload->>'renewal_owner_id', '')::uuid,
        nullif(btrim(p_payload->>'attachment_url'), ''),
        nullif(btrim(p_payload->>'remark'), '')
      ) returning id into v_id;
      perform app_private.hr_add_compliance_event(
        v_tenant_id, 'contract', v_id, 'created', null, v_status,
        '创建劳动合同记录', '{}'::jsonb
      );
    else
      select * into v_existing_contract from public.hr_employee_contract contract
      where contract.id = v_id and contract.tenant_id = v_tenant_id for update;
      if not found then raise exception '劳动合同不存在或无权编辑' using errcode = '42501'; end if;
      if v_existing_contract.contract_status in ('renewed', 'terminated', 'expired') then
        raise exception '已续签、已终止或已到期合同不能直接编辑';
      end if;
      v_status := case when v_existing_contract.contract_status = 'renewing' then 'renewing'
        when p_payload->>'contract_status' in ('draft', 'active')
          then p_payload->>'contract_status'
        else v_existing_contract.contract_status end;
      update public.hr_employee_contract set
        employee_id = v_employee_id,
        contract_no = btrim(p_payload->>'contract_no'),
        contract_type = p_payload->>'contract_type',
        contract_status = v_status,
        sign_date = nullif(p_payload->>'sign_date', '')::date,
        start_date = (p_payload->>'start_date')::date,
        end_date = nullif(p_payload->>'end_date', '')::date,
        probation_end_date = nullif(p_payload->>'probation_end_date', '')::date,
        work_location = nullif(btrim(p_payload->>'work_location'), ''),
        monthly_salary = nullif(p_payload->>'monthly_salary', '')::numeric,
        renewal_reminder_days = coalesce(
          nullif(p_payload->>'renewal_reminder_days', '')::integer, 30),
        renewal_owner_id = nullif(p_payload->>'renewal_owner_id', '')::uuid,
        attachment_url = nullif(btrim(p_payload->>'attachment_url'), ''),
        remark = nullif(btrim(p_payload->>'remark'), '')
      where id = v_id;
      perform app_private.hr_add_compliance_event(
        v_tenant_id, 'contract', v_id, 'updated',
        v_existing_contract.contract_status, v_status,
        '更新劳动合同资料', '{}'::jsonb
      );
    end if;
  else
    if nullif(btrim(p_payload->>'qualification_name'), '') is null then raise exception '请输入资质名称'; end if;
    if nullif(btrim(p_payload->>'qualification_type'), '') is null then raise exception '请选择资质类型'; end if;
    if nullif(p_payload->>'expiry_date', '') is not null
      and nullif(p_payload->>'issue_date', '') is not null
      and (p_payload->>'expiry_date')::date < (p_payload->>'issue_date')::date then
      raise exception '资质到期日期不能早于发证日期';
    end if;
    v_status := case
      when nullif(p_payload->>'expiry_date', '') is null then 'valid'
      when (p_payload->>'expiry_date')::date < current_date then 'expired'
      when (p_payload->>'expiry_date')::date <= current_date
        + coalesce(nullif(p_payload->>'reminder_days', '')::integer, 30) then 'expiring'
      else 'valid' end;

    if v_id is null then
      insert into public.hr_employee_qualification(
        tenant_id, employee_id, qualification_type, qualification_name,
        certificate_no, issuer, issue_date, expiry_date, status,
        attachment_url, reminder_days, responsible_employee_id,
        verification_status, next_review_date, remark
      ) values (
        v_tenant_id, v_employee_id, p_payload->>'qualification_type',
        btrim(p_payload->>'qualification_name'),
        nullif(btrim(p_payload->>'certificate_no'), ''),
        nullif(btrim(p_payload->>'issuer'), ''),
        nullif(p_payload->>'issue_date', '')::date,
        nullif(p_payload->>'expiry_date', '')::date, v_status,
        nullif(btrim(p_payload->>'attachment_url'), ''),
        coalesce(nullif(p_payload->>'reminder_days', '')::integer, 30),
        nullif(p_payload->>'responsible_employee_id', '')::uuid,
        'pending', nullif(p_payload->>'next_review_date', '')::date,
        nullif(btrim(p_payload->>'remark'), '')
      ) returning id into v_id;
      perform app_private.hr_add_compliance_event(
        v_tenant_id, 'qualification', v_id, 'created', null, v_status,
        '创建员工资质记录', '{}'::jsonb
      );
    else
      select * into v_existing_qualification from public.hr_employee_qualification qualification
      where qualification.id = v_id and qualification.tenant_id = v_tenant_id for update;
      if not found then raise exception '员工资质不存在或无权编辑' using errcode = '42501'; end if;
      if v_existing_qualification.status = 'revoked' then raise exception '已撤销资质不能直接编辑'; end if;
      v_core_changed := v_existing_qualification.qualification_type is distinct from p_payload->>'qualification_type'
        or v_existing_qualification.qualification_name is distinct from btrim(p_payload->>'qualification_name')
        or v_existing_qualification.certificate_no is distinct from nullif(btrim(p_payload->>'certificate_no'), '')
        or v_existing_qualification.issuer is distinct from nullif(btrim(p_payload->>'issuer'), '')
        or v_existing_qualification.issue_date is distinct from nullif(p_payload->>'issue_date', '')::date
        or v_existing_qualification.expiry_date is distinct from nullif(p_payload->>'expiry_date', '')::date;
      update public.hr_employee_qualification set
        employee_id = v_employee_id,
        qualification_type = p_payload->>'qualification_type',
        qualification_name = btrim(p_payload->>'qualification_name'),
        certificate_no = nullif(btrim(p_payload->>'certificate_no'), ''),
        issuer = nullif(btrim(p_payload->>'issuer'), ''),
        issue_date = nullif(p_payload->>'issue_date', '')::date,
        expiry_date = nullif(p_payload->>'expiry_date', '')::date,
        status = v_status,
        attachment_url = nullif(btrim(p_payload->>'attachment_url'), ''),
        reminder_days = coalesce(nullif(p_payload->>'reminder_days', '')::integer, 30),
        responsible_employee_id = nullif(p_payload->>'responsible_employee_id', '')::uuid,
        next_review_date = nullif(p_payload->>'next_review_date', '')::date,
        remark = nullif(btrim(p_payload->>'remark'), ''),
        verification_status = case when v_core_changed then 'pending'
          else verification_status end,
        verified_by_employee_id = case when v_core_changed then null
          else verified_by_employee_id end,
        verified_at = case when v_core_changed then null else verified_at end
      where id = v_id;
      perform app_private.hr_add_compliance_event(
        v_tenant_id, 'qualification', v_id, 'updated',
        v_existing_qualification.status, v_status,
        case when v_core_changed then '更新资质核心资料并重新进入核验' else '更新员工资质资料' end,
        jsonb_build_object('verification_reset', v_core_changed)
      );
    end if;
  end if;
  return v_id;
exception
  when unique_violation then
    raise exception '合同编号已存在，请检查后重试';
end
$function$;

create or replace function public.hr_transition_compliance_record_secure(
  p_kind text,
  p_id uuid,
  p_action text,
  p_payload jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_contract public.hr_employee_contract;
  v_qualification public.hr_employee_qualification;
  v_new_contract_id uuid;
  v_comment text := nullif(btrim(p_payload->>'comment'), '');
  v_new_status text;
begin
  if p_kind = 'contract' then
    select * into v_contract from public.hr_employee_contract contract
    where contract.id = p_id
      and (app_private.is_platform_super() or contract.tenant_id = v_tenant_id)
    for update;
    if not found then raise exception '劳动合同不存在或无权处理' using errcode = '42501'; end if;

    if p_action = 'activate' then
      if not app_private.can_execute_business_action(
        'HrCompliance', 'Hr:Compliance:Edit', p_id, false
      ) then raise exception '当前账号没有使合同生效的权限' using errcode = '42501'; end if;
      if v_contract.contract_status <> 'draft' then raise exception '只有待签署合同可以生效'; end if;
      update public.hr_employee_contract set contract_status = 'active' where id = p_id;
      perform app_private.hr_add_compliance_event(
        v_contract.tenant_id, 'contract', p_id, 'activated', 'draft', 'active',
        coalesce(v_comment, '劳动合同已确认生效'), '{}'::jsonb
      );
      return p_id;
    elsif p_action = 'start_renewal' then
      if not app_private.can_execute_business_action(
        'HrCompliance', 'Hr:Compliance:Contract:Renew', p_id, false
      ) then raise exception '当前账号没有启动合同续签的权限' using errcode = '42501'; end if;
      if v_contract.contract_status <> 'active' or v_contract.end_date is null then
        raise exception '只有存在结束日期的生效中合同可以启动续签';
      end if;
      if nullif(p_payload->>'renewal_owner_id', '') is not null and not exists (
        select 1 from public.hr_employee employee
        where employee.id = (p_payload->>'renewal_owner_id')::uuid
          and employee.tenant_id = v_contract.tenant_id
      ) then raise exception '请选择当前租户内的续签负责人'; end if;
      update public.hr_employee_contract set
        contract_status = 'renewing', renewal_decision = 'pending',
        renewal_started_at = now(),
        renewal_owner_id = coalesce(nullif(p_payload->>'renewal_owner_id', '')::uuid,
          renewal_owner_id)
      where id = p_id;
      perform app_private.hr_add_compliance_event(
        v_contract.tenant_id, 'contract', p_id, 'renewal_started', 'active', 'renewing',
        coalesce(v_comment, '已启动合同续签决策'), '{}'::jsonb
      );
      return p_id;
    elsif p_action = 'renew' then
      if not app_private.can_execute_business_action(
        'HrCompliance', 'Hr:Compliance:Contract:Renew', p_id, false
      ) then raise exception '当前账号没有完成合同续签的权限' using errcode = '42501'; end if;
      if v_contract.contract_status not in ('active', 'renewing') then
        raise exception '当前合同状态不能办理续签';
      end if;
      if nullif(btrim(p_payload->>'contract_no'), '') is null
        or nullif(p_payload->>'start_date', '') is null
        or nullif(btrim(p_payload->>'contract_type'), '') is null then
        raise exception '请完整填写新合同编号、类型和开始日期';
      end if;
      if (p_payload->>'start_date')::date <= v_contract.start_date then
        raise exception '新合同开始日期必须晚于原合同开始日期';
      end if;
      if nullif(p_payload->>'end_date', '') is not null
        and (p_payload->>'end_date')::date < (p_payload->>'start_date')::date then
        raise exception '新合同结束日期不能早于开始日期';
      end if;
      insert into public.hr_employee_contract(
        tenant_id, employee_id, contract_no, contract_type, contract_status,
        sign_date, start_date, end_date, probation_end_date, work_location,
        monthly_salary, renewal_reminder_days, renewal_owner_id,
        previous_contract_id, attachment_url, remark
      ) values (
        v_contract.tenant_id, v_contract.employee_id, btrim(p_payload->>'contract_no'),
        p_payload->>'contract_type',
        case when p_payload->>'contract_status' = 'draft' then 'draft' else 'active' end,
        nullif(p_payload->>'sign_date', '')::date,
        (p_payload->>'start_date')::date, nullif(p_payload->>'end_date', '')::date,
        nullif(p_payload->>'probation_end_date', '')::date,
        coalesce(nullif(btrim(p_payload->>'work_location'), ''), v_contract.work_location),
        coalesce(nullif(p_payload->>'monthly_salary', '')::numeric, v_contract.monthly_salary),
        coalesce(nullif(p_payload->>'renewal_reminder_days', '')::integer,
          v_contract.renewal_reminder_days),
        coalesce(nullif(p_payload->>'renewal_owner_id', '')::uuid, v_contract.renewal_owner_id),
        v_contract.id, nullif(btrim(p_payload->>'attachment_url'), ''),
        nullif(btrim(p_payload->>'remark'), '')
      ) returning id, contract_status into v_new_contract_id, v_new_status;
      update public.hr_employee_contract set
        contract_status = 'renewed', renewal_decision = 'completed', renewed_at = now()
      where id = p_id;
      perform app_private.hr_add_compliance_event(
        v_contract.tenant_id, 'contract', p_id, 'renewed',
        v_contract.contract_status, 'renewed', coalesce(v_comment, '已创建续签合同'),
        jsonb_build_object('new_contract_id', v_new_contract_id)
      );
      perform app_private.hr_add_compliance_event(
        v_contract.tenant_id, 'contract', v_new_contract_id, 'created', null, v_new_status,
        '由合同续签创建', jsonb_build_object('previous_contract_id', p_id)
      );
      return v_new_contract_id;
    elsif p_action = 'terminate' then
      if not app_private.can_execute_business_action(
        'HrCompliance', 'Hr:Compliance:Contract:Terminate', p_id, false
      ) then raise exception '当前账号没有终止合同的权限' using errcode = '42501'; end if;
      if v_contract.contract_status not in ('draft', 'active', 'renewing') then
        raise exception '当前合同状态不能终止';
      end if;
      if nullif(p_payload->>'termination_date', '') is null or v_comment is null then
        raise exception '终止合同必须填写终止日期和原因';
      end if;
      if (p_payload->>'termination_date')::date < v_contract.start_date then
        raise exception '终止日期不能早于合同开始日期';
      end if;
      update public.hr_employee_contract set
        contract_status = 'terminated', renewal_decision = 'completed',
        termination_date = (p_payload->>'termination_date')::date,
        termination_reason = v_comment
      where id = p_id;
      perform app_private.hr_add_compliance_event(
        v_contract.tenant_id, 'contract', p_id, 'terminated',
        v_contract.contract_status, 'terminated', v_comment,
        jsonb_build_object('termination_date', p_payload->>'termination_date')
      );
      return p_id;
    elsif p_action = 'comment' then
      if not app_private.can_execute_business_action(
        'HrCompliance', 'Hr:Compliance:Edit', p_id, false
      ) then raise exception '当前账号没有补充合同说明的权限' using errcode = '42501'; end if;
      if v_comment is null then raise exception '请输入补充说明'; end if;
      perform app_private.hr_add_compliance_event(
        v_contract.tenant_id, 'contract', p_id, 'commented',
        v_contract.contract_status, v_contract.contract_status, v_comment, '{}'::jsonb
      );
      return p_id;
    end if;
  elsif p_kind = 'qualification' then
    select * into v_qualification from public.hr_employee_qualification qualification
    where qualification.id = p_id
      and (app_private.is_platform_super() or qualification.tenant_id = v_tenant_id)
    for update;
    if not found then raise exception '员工资质不存在或无权处理' using errcode = '42501'; end if;

    if p_action in ('verify', 'reject') then
      if not app_private.can_execute_business_action(
        'HrCompliance', 'Hr:Compliance:Qualification:Verify', p_id, false
      ) then raise exception '当前账号没有核验员工资质的权限' using errcode = '42501'; end if;
      if v_qualification.status = 'revoked' then raise exception '已撤销资质不能核验'; end if;
      if p_action = 'reject' and v_comment is null then raise exception '核验驳回必须填写原因'; end if;
      update public.hr_employee_qualification set
        verification_status = case when p_action = 'verify' then 'verified' else 'rejected' end,
        verified_by_employee_id = case when p_action = 'verify'
          then app_private.hr_current_employee_id() else null end,
        verified_at = case when p_action = 'verify' then now() else null end,
        verification_note = v_comment
      where id = p_id;
      perform app_private.hr_add_compliance_event(
        v_qualification.tenant_id, 'qualification', p_id,
        case when p_action = 'verify' then 'verified' else 'verification_rejected' end,
        v_qualification.verification_status,
        case when p_action = 'verify' then 'verified' else 'rejected' end,
        coalesce(v_comment, '员工资质核验通过'), '{}'::jsonb
      );
      return p_id;
    elsif p_action = 'revoke' then
      if not app_private.can_execute_business_action(
        'HrCompliance', 'Hr:Compliance:Qualification:Revoke', p_id, false
      ) then raise exception '当前账号没有撤销员工资质的权限' using errcode = '42501'; end if;
      if v_qualification.status = 'revoked' then raise exception '员工资质已经撤销'; end if;
      if v_comment is null then raise exception '撤销资质必须填写原因'; end if;
      update public.hr_employee_qualification set
        status = 'revoked', revoked_at = now(), revocation_reason = v_comment
      where id = p_id;
      perform app_private.hr_add_compliance_event(
        v_qualification.tenant_id, 'qualification', p_id, 'revoked',
        v_qualification.status, 'revoked', v_comment, '{}'::jsonb
      );
      return p_id;
    elsif p_action = 'comment' then
      if not app_private.can_execute_business_action(
        'HrCompliance', 'Hr:Compliance:Edit', p_id, false
      ) then raise exception '当前账号没有补充资质说明的权限' using errcode = '42501'; end if;
      if v_comment is null then raise exception '请输入补充说明'; end if;
      perform app_private.hr_add_compliance_event(
        v_qualification.tenant_id, 'qualification', p_id, 'commented',
        v_qualification.status, v_qualification.status, v_comment, '{}'::jsonb
      );
      return p_id;
    end if;
  else
    raise exception '不支持的用工合规记录类型';
  end if;
  raise exception '当前记录不支持此操作';
exception
  when unique_violation then raise exception '续签合同编号已存在，请检查后重试';
end
$function$;

create or replace function public.hr_delete_compliance_record_secure(
  p_kind text,
  p_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_status text;
  v_verification_status text;
  v_record_tenant uuid;
begin
  if not app_private.can_execute_business_action(
    'HrCompliance', 'Hr:Compliance:Delete', p_id, false
  ) then raise exception '当前账号没有删除合同或资质的权限' using errcode = '42501'; end if;

  if p_kind = 'contract' then
    select tenant_id, contract_status into v_record_tenant, v_status
    from public.hr_employee_contract where id = p_id for update;
    if not found or (not app_private.is_platform_super() and v_record_tenant <> v_tenant_id) then
      raise exception '劳动合同不存在或无权删除' using errcode = '42501';
    end if;
    if v_status <> 'draft' then raise exception '只有待签署合同可以删除'; end if;
    delete from public.hr_compliance_event
    where tenant_id = v_record_tenant and entity_type = 'contract' and entity_id = p_id;
    delete from public.hr_employee_contract where id = p_id;
  elsif p_kind = 'qualification' then
    select tenant_id, status, verification_status
      into v_record_tenant, v_status, v_verification_status
    from public.hr_employee_qualification where id = p_id for update;
    if not found or (not app_private.is_platform_super() and v_record_tenant <> v_tenant_id) then
      raise exception '员工资质不存在或无权删除' using errcode = '42501';
    end if;
    if v_status = 'revoked' or v_verification_status = 'verified' then
      raise exception '已核验或已撤销资质必须保留审计记录，不能删除';
    end if;
    delete from public.hr_compliance_event
    where tenant_id = v_record_tenant and entity_type = 'qualification' and entity_id = p_id;
    delete from public.hr_employee_qualification where id = p_id;
  else
    raise exception '不支持的用工合规记录类型';
  end if;
end
$function$;

revoke all on function public.hr_compliance_overview_secure(uuid) from public, anon;
revoke all on function public.hr_list_compliance_records_secure(
  text, integer, integer, text, text, text, uuid
) from public, anon;
revoke all on function public.hr_get_compliance_detail_secure(text, uuid) from public, anon;
revoke all on function public.hr_save_compliance_record_secure(text, jsonb) from public, anon;
revoke all on function public.hr_transition_compliance_record_secure(
  text, uuid, text, jsonb
) from public, anon;
revoke all on function public.hr_delete_compliance_record_secure(text, uuid) from public, anon;

grant execute on function public.hr_compliance_overview_secure(uuid) to authenticated;
grant execute on function public.hr_list_compliance_records_secure(
  text, integer, integer, text, text, text, uuid
) to authenticated;
grant execute on function public.hr_get_compliance_detail_secure(text, uuid) to authenticated;
grant execute on function public.hr_save_compliance_record_secure(text, jsonb) to authenticated;
grant execute on function public.hr_transition_compliance_record_secure(
  text, uuid, text, jsonb
) to authenticated;
grant execute on function public.hr_delete_compliance_record_secure(text, uuid) to authenticated;
