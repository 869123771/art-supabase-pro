begin;

do $$
declare
  v_admin public.sys_user%rowtype;
  v_ordinary public.sys_user%rowtype;
  v_site_id uuid := gen_random_uuid();
  v_area_id uuid := gen_random_uuid();
  v_risk_point_id uuid := gen_random_uuid();
  v_case_id uuid := gen_random_uuid();
begin
  select * into v_admin from public.sys_user user_row
  where user_row.user_roles && array['R_ADMIN', 'R_SUPER']::text[]
    and user_row.auth_user_id is not null
    and user_row.deleted_at is null
  order by user_row.create_time
  limit 1;
  if not found then raise exception '测试环境缺少管理员用户'; end if;

  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_admin.auth_user_id, 'role', 'authenticated',
    'email', v_admin.user_email, 'tenant_id', v_admin.tenant_id
  )::text, true);

  insert into public.smis_site (id, tenant_id, site_code, site_name)
  values (v_site_id, v_admin.tenant_id, 'QA-AE-SITE', 'QA事故应急场所');
  insert into public.smis_area (id, tenant_id, site_id, area_code, area_name)
  values (v_area_id, v_admin.tenant_id, v_site_id, 'QA-AE-AREA', 'QA事故应急区域');
  insert into public.smis_risk_point (
    id, tenant_id, site_id, area_id, risk_point_no, risk_point_name, current_risk_level
  ) values (
    v_risk_point_id, v_admin.tenant_id, v_site_id, v_area_id,
    'QA-AE-RISK', 'QA事故应急风险点', 'major'
  );
  insert into public.smis_accident_case (
    id, tenant_id, risk_point_id, reporter_user_id, source_type, case_no,
    case_title, incident_type, severity, occurred_at, description,
    casualties, economic_loss, attachment_refs
  ) values (
    v_case_id, v_admin.tenant_id, v_risk_point_id, v_admin.id, 'manual',
    'QA-AE-CASE', 'QA事故闭环', 'accident', 'major', now(),
    '验证立案、整改、结案状态流转', 0, 100,
    jsonb_build_array(jsonb_build_object('id', 'qa-evidence'))
  );
  perform public.smis_transition_accident_case(
    v_case_id, 'investigate', v_admin.id, '立案调查', '[]'::jsonb
  );
  perform public.smis_transition_accident_case(
    v_case_id, 'rectify', null, '查明原因并落实纠正措施',
    jsonb_build_array(jsonb_build_object('id', 'qa-rectification'))
  );
  perform public.smis_transition_accident_case(
    v_case_id, 'close', null, '整改验证通过，同意结案', '[]'::jsonb
  );
  if (select status from public.smis_accident_case where id = v_case_id) <> 'closed' then
    raise exception '事故事件未完成结案';
  end if;
  if (select count(*) from public.smis_accident_case_event where accident_case_id = v_case_id) <> 4 then
    raise exception '事故事件审计时间线不完整';
  end if;

  select * into v_ordinary from public.sys_user user_row
  where not (user_row.user_roles && array['R_ADMIN', 'R_SUPER']::text[])
    and user_row.auth_user_id is not null
    and user_row.deleted_at is null
  order by user_row.create_time
  limit 1;
  if not found then raise exception '测试环境缺少普通用户'; end if;
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_ordinary.auth_user_id, 'role', 'authenticated',
    'email', v_ordinary.user_email, 'tenant_id', v_ordinary.tenant_id
  )::text, true);
end;
$$;

set local role authenticated;

do $$
declare v_blocked boolean := false;
begin
  begin
    insert into public.smis_accident_case (
      source_type, case_no, case_title, incident_type,
      severity, occurred_at, description
    ) values (
      'manual', 'QA-AE-BLOCKED', '普通用户不应写入',
      'unsafe_event', 'slight', now(), '验证只读边界'
    );
  exception when insufficient_privilege then
    v_blocked := true;
  end;
  if not v_blocked then raise exception '普通用户事故事件写入未被阻止'; end if;
end;
$$;

reset role;

rollback;
