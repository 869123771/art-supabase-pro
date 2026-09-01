-- Secure policy versioning, audience delivery and acknowledgement APIs.

create or replace function public.hr_policy_acknowledgement_overview_secure(
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql stable security definer
set search_path=''
set timezone='Asia/Shanghai'
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_total integer;
  v_acknowledged integer;
begin
  if auth.uid() is null or not app_private.can_execute_business_action(
    'HrPolicyAcknowledgement','Hr:PolicyAcknowledgement:View',null,false
  ) then raise exception '当前账号没有查看政策与签收的权限' using errcode='42501'; end if;
  if not app_private.is_platform_super() then p_tenant_id:=v_tenant_id; end if;

  select count(*)::integer,
    count(*) filter(where receipt.status in ('acknowledged','waived'))::integer
  into v_total,v_acknowledged
  from public.hr_policy_receipt receipt
  join public.hr_policy_document policy on policy.id=receipt.policy_id
  where (p_tenant_id is null or receipt.tenant_id=p_tenant_id)
    and policy.status='published';

  return jsonb_build_object(
    'draft_policy_count',(select count(*) from public.hr_policy_document policy where (p_tenant_id is null or policy.tenant_id=p_tenant_id) and policy.status='draft'),
    'published_policy_count',(select count(*) from public.hr_policy_document policy where (p_tenant_id is null or policy.tenant_id=p_tenant_id) and policy.status='published'),
    'scheduled_policy_count',(select count(*) from public.hr_policy_document policy where (p_tenant_id is null or policy.tenant_id=p_tenant_id) and policy.status='published' and policy.effective_date>current_date),
    'receipt_count',v_total,
    'acknowledged_count',v_acknowledged,
    'pending_count',greatest(v_total-v_acknowledged,0),
    'overdue_count',(select count(*) from public.hr_policy_receipt receipt join public.hr_policy_document policy on policy.id=receipt.policy_id where (p_tenant_id is null or receipt.tenant_id=p_tenant_id) and policy.status='published' and receipt.status='pending' and receipt.due_date<current_date),
    'completion_rate',case when v_total=0 then 0 else round(v_acknowledged*100.0/v_total,1) end,
    'evidence_access',app_private.can_execute_business_action('HrPolicyAcknowledgement','Hr:PolicyAcknowledgement:Evidence:View',null,false)
  );
end;
$function$;

create or replace function public.hr_list_policy_acknowledgement_records_secure(
  p_kind text,
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_status text default null,
  p_policy_id uuid default null,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql stable security definer
set search_path=''
set timezone='Asia/Shanghai'
as $function$
declare
  v_tenant_id uuid:=app_private.current_user_tenant_id();
  v_offset integer:=greatest(coalesce(p_from,0),0);
  v_limit integer:=least(500,greatest(coalesce(p_to,19)-greatest(coalesce(p_from,0),0)+1,1));
  v_keyword text:=nullif(btrim(p_keyword),'');
  v_evidence_access boolean;
  v_total integer:=0;
  v_records jsonb:='[]'::jsonb;
begin
  if p_kind not in ('policy','receipt') then raise exception '不支持的政策签收记录类型'; end if;
  if auth.uid() is null or not app_private.can_execute_business_action(
    'HrPolicyAcknowledgement','Hr:PolicyAcknowledgement:View',null,false
  ) then raise exception '当前账号没有查看政策与签收的权限' using errcode='42501'; end if;
  if not app_private.is_platform_super() then p_tenant_id:=v_tenant_id; end if;
  v_evidence_access:=app_private.can_execute_business_action(
    'HrPolicyAcknowledgement','Hr:PolicyAcknowledgement:Evidence:View',null,false
  );

  if p_kind='policy' then
    select count(*)::integer into v_total
    from public.hr_policy_document policy
    left join public.sys_organization organization on organization.id=policy.audience_organization_id
    where (p_tenant_id is null or policy.tenant_id=p_tenant_id)
      and (p_status is null or p_status='' or policy.status=p_status)
      and (v_keyword is null or policy.policy_code ilike '%'||v_keyword||'%'
        or policy.policy_title ilike '%'||v_keyword||'%'
        or policy.category ilike '%'||v_keyword||'%'
        or organization.organization_name ilike '%'||v_keyword||'%');

    select coalesce(jsonb_agg(row_data order by effective_date desc,version_no desc),'[]'::jsonb)
    into v_records from (
      select policy.effective_date,policy.version_no,
        jsonb_build_object(
          'id',policy.id,'tenant_id',policy.tenant_id,'policy_code',policy.policy_code,
          'policy_title',policy.policy_title,'category',policy.category,'version_no',policy.version_no,
          'effective_date',policy.effective_date,'acknowledgement_due_days',policy.acknowledgement_due_days,
          'audience_type',policy.audience_type,'audience_organization_id',policy.audience_organization_id,
          'audience_organization_name',organization.organization_name,
          'audience_employment_type',policy.audience_employment_type,
          'document_reference',policy.document_reference,'content_summary',policy.content_summary,
          'status',policy.status,'supersedes_policy_id',policy.supersedes_policy_id,
          'supersedes_policy_title',supersedes.policy_title,'published_at',policy.published_at,
          'published_by',policy.published_by,'decision_note',policy.decision_note,
          'receipt_count',(select count(*) from public.hr_policy_receipt receipt where receipt.policy_id=policy.id),
          'acknowledged_count',(select count(*) from public.hr_policy_receipt receipt where receipt.policy_id=policy.id and receipt.status='acknowledged'),
          'waived_count',(select count(*) from public.hr_policy_receipt receipt where receipt.policy_id=policy.id and receipt.status='waived'),
          'overdue_count',(select count(*) from public.hr_policy_receipt receipt where receipt.policy_id=policy.id and receipt.status='pending' and receipt.due_date<current_date),
          'create_time',policy.create_time,'update_time',policy.update_time
        ) row_data
      from public.hr_policy_document policy
      left join public.sys_organization organization on organization.id=policy.audience_organization_id
      left join public.hr_policy_document supersedes on supersedes.id=policy.supersedes_policy_id
      where (p_tenant_id is null or policy.tenant_id=p_tenant_id)
        and (p_status is null or p_status='' or policy.status=p_status)
        and (v_keyword is null or policy.policy_code ilike '%'||v_keyword||'%'
          or policy.policy_title ilike '%'||v_keyword||'%'
          or policy.category ilike '%'||v_keyword||'%'
          or organization.organization_name ilike '%'||v_keyword||'%')
      order by policy.effective_date desc,policy.version_no desc
      offset v_offset limit v_limit
    ) rows;
  else
    select count(*)::integer into v_total
    from public.hr_policy_receipt receipt
    join public.hr_policy_document policy on policy.id=receipt.policy_id
    join public.hr_employee employee on employee.id=receipt.employee_id
    left join public.sys_organization organization on organization.id=employee.organization_id
    where (p_tenant_id is null or receipt.tenant_id=p_tenant_id)
      and (p_policy_id is null or receipt.policy_id=p_policy_id)
      and (p_status is null or p_status='' or receipt.status=p_status
        or (p_status='overdue' and receipt.status='pending' and receipt.due_date<current_date))
      and (v_keyword is null or policy.policy_code ilike '%'||v_keyword||'%'
        or policy.policy_title ilike '%'||v_keyword||'%'
        or employee.employee_no ilike '%'||v_keyword||'%'
        or employee.employee_name ilike '%'||v_keyword||'%'
        or organization.organization_name ilike '%'||v_keyword||'%');

    select coalesce(jsonb_agg(row_data order by overdue desc,due_date,employee_name),'[]'::jsonb)
    into v_records from (
      select receipt.due_date,employee.employee_name,
        receipt.status='pending' and receipt.due_date<current_date overdue,
        jsonb_build_object(
          'id',receipt.id,'tenant_id',receipt.tenant_id,'policy_id',receipt.policy_id,
          'policy_code',policy.policy_code,'policy_title',policy.policy_title,
          'policy_version_no',policy.version_no,'policy_status',policy.status,
          'document_reference',policy.document_reference,'employee_id',receipt.employee_id,
          'employee_no',employee.employee_no,'employee_name',employee.employee_name,
          'organization_name',organization.organization_name,'job_title',employee.job_title,
          'delivered_at',receipt.delivered_at,'due_date',receipt.due_date,
          'status',case when receipt.status='pending' and receipt.due_date<current_date then 'overdue' else receipt.status end,
          'stored_status',receipt.status,'acknowledged_at',receipt.acknowledged_at,
          'acknowledged_by',receipt.acknowledged_by,'acknowledgement_note',receipt.acknowledgement_note,
          'evidence_reference',case when v_evidence_access then receipt.evidence_reference else null end,
          'waived_at',receipt.waived_at,'waived_by',receipt.waived_by,
          'waiver_reason',case when v_evidence_access then receipt.waiver_reason else null end,
          'create_time',receipt.create_time,'update_time',receipt.update_time
        ) row_data
      from public.hr_policy_receipt receipt
      join public.hr_policy_document policy on policy.id=receipt.policy_id
      join public.hr_employee employee on employee.id=receipt.employee_id
      left join public.sys_organization organization on organization.id=employee.organization_id
      where (p_tenant_id is null or receipt.tenant_id=p_tenant_id)
        and (p_policy_id is null or receipt.policy_id=p_policy_id)
        and (p_status is null or p_status='' or receipt.status=p_status
          or (p_status='overdue' and receipt.status='pending' and receipt.due_date<current_date))
        and (v_keyword is null or policy.policy_code ilike '%'||v_keyword||'%'
          or policy.policy_title ilike '%'||v_keyword||'%'
          or employee.employee_no ilike '%'||v_keyword||'%'
          or employee.employee_name ilike '%'||v_keyword||'%'
          or organization.organization_name ilike '%'||v_keyword||'%')
      order by overdue desc,receipt.due_date,employee.employee_name
      offset v_offset limit v_limit
    ) rows;
  end if;

  return jsonb_build_object('records',v_records,'total',v_total,'evidence_access',v_evidence_access);
end;
$function$;

create or replace function public.hr_list_policy_acknowledgement_options_secure(
  p_kind text,p_tenant_id uuid default null
)
returns jsonb
language plpgsql stable security definer set search_path=''
as $function$
declare v_tenant_id uuid:=app_private.current_user_tenant_id(); v_result jsonb:='[]'::jsonb;
begin
  if p_kind not in ('organization','policy') then raise exception '不支持的政策签收选项类型'; end if;
  if auth.uid() is null or not app_private.can_execute_business_action(
    'HrPolicyAcknowledgement','Hr:PolicyAcknowledgement:View',null,false
  ) then raise exception '当前账号没有查看政策与签收的权限' using errcode='42501'; end if;
  if not app_private.is_platform_super() then p_tenant_id:=v_tenant_id; end if;
  if p_kind='organization' then
    select coalesce(jsonb_agg(jsonb_build_object('id',organization.id,'tenant_id',organization.tenant_id,'code',organization.organization_code,'name',organization.organization_name,'status',organization.status) order by organization.sort,organization.organization_name),'[]'::jsonb)
    into v_result from public.sys_organization organization
    where p_tenant_id is null or organization.tenant_id=p_tenant_id;
  else
    select coalesce(jsonb_agg(jsonb_build_object('id',policy.id,'tenant_id',policy.tenant_id,'code',policy.policy_code,'name',policy.policy_title||' v'||policy.version_no,'status',policy.status,'effective_date',policy.effective_date) order by policy.policy_code,policy.version_no desc),'[]'::jsonb)
    into v_result from public.hr_policy_document policy
    where (p_tenant_id is null or policy.tenant_id=p_tenant_id) and policy.status in ('published','retired');
  end if;
  return v_result;
end;
$function$;

create or replace function public.hr_save_policy_document_secure(p_id uuid,p_payload jsonb)
returns uuid
language plpgsql security definer set search_path=''
as $function$
declare
  v_current_tenant uuid:=app_private.current_user_tenant_id();
  v_tenant_id uuid:=case when app_private.is_platform_super() and nullif(p_payload->>'tenant_id','') is not null then (p_payload->>'tenant_id')::uuid else v_current_tenant end;
  v_id uuid:=coalesce(p_id,gen_random_uuid());
  v_existing public.hr_policy_document%rowtype;
  v_supersedes public.hr_policy_document%rowtype;
begin
  if auth.uid() is null or not app_private.can_execute_business_action(
    'HrPolicyAcknowledgement','Hr:PolicyAcknowledgement:Policy:Manage',null,false
  ) then raise exception '当前账号没有管理政策草稿的权限' using errcode='42501'; end if;
  if nullif(p_payload->>'supersedes_policy_id','') is not null then
    select * into v_supersedes from public.hr_policy_document
    where id=(p_payload->>'supersedes_policy_id')::uuid and tenant_id=v_tenant_id;
    if not found then raise exception '被替代政策不存在或不属于当前租户'; end if;
    if lower(v_supersedes.policy_code)<>lower(btrim(p_payload->>'policy_code')) then
      raise exception '新版本与被替代政策的编码必须一致';
    end if;
  end if;
  if p_id is null then
    insert into public.hr_policy_document(
      id,tenant_id,policy_code,policy_title,category,version_no,effective_date,
      acknowledgement_due_days,audience_type,audience_organization_id,
      audience_employment_type,document_reference,content_summary,status,
      supersedes_policy_id,decision_note
    ) values (
      v_id,v_tenant_id,btrim(p_payload->>'policy_code'),btrim(p_payload->>'policy_title'),
      btrim(p_payload->>'category'),coalesce(nullif(p_payload->>'version_no','')::integer,1),
      (p_payload->>'effective_date')::date,
      coalesce(nullif(p_payload->>'acknowledgement_due_days','')::integer,7),
      coalesce(nullif(p_payload->>'audience_type',''),'all'),
      nullif(p_payload->>'audience_organization_id','')::uuid,
      nullif(btrim(p_payload->>'audience_employment_type'),''),
      btrim(p_payload->>'document_reference'),btrim(p_payload->>'content_summary'),
      'draft',nullif(p_payload->>'supersedes_policy_id','')::uuid,
      nullif(btrim(p_payload->>'decision_note'),'')
    );
  else
    select * into v_existing from public.hr_policy_document
    where id=p_id and (app_private.is_platform_super() or tenant_id=v_tenant_id) for update;
    if not found then raise exception '政策不存在或不属于当前租户'; end if;
    if v_existing.status<>'draft' then raise exception '已发布政策不可修改，请创建新版本'; end if;
    update public.hr_policy_document set
      policy_code=btrim(p_payload->>'policy_code'),policy_title=btrim(p_payload->>'policy_title'),
      category=btrim(p_payload->>'category'),version_no=(p_payload->>'version_no')::integer,
      effective_date=(p_payload->>'effective_date')::date,
      acknowledgement_due_days=(p_payload->>'acknowledgement_due_days')::integer,
      audience_type=p_payload->>'audience_type',
      audience_organization_id=nullif(p_payload->>'audience_organization_id','')::uuid,
      audience_employment_type=nullif(btrim(p_payload->>'audience_employment_type'),''),
      document_reference=btrim(p_payload->>'document_reference'),
      content_summary=btrim(p_payload->>'content_summary'),
      supersedes_policy_id=nullif(p_payload->>'supersedes_policy_id','')::uuid,
      decision_note=nullif(btrim(p_payload->>'decision_note'),'')
    where id=p_id;
  end if;
  return v_id;
end;
$function$;

create or replace function public.hr_transition_policy_acknowledgement_secure(
  p_kind text,p_id uuid,p_action text,p_comment text default null,p_evidence_reference text default null
)
returns boolean
language plpgsql security definer set search_path='' set timezone='Asia/Shanghai'
as $function$
declare
  v_tenant_id uuid:=app_private.current_user_tenant_id();
  v_policy public.hr_policy_document%rowtype;
  v_receipt public.hr_policy_receipt%rowtype;
  v_actor text:=coalesce(public.get_app_user_display_name(),app_private.current_user_email(),auth.uid()::text);
  v_permission text;
  v_inserted integer;
begin
  if p_kind not in ('policy','receipt') then raise exception '不支持的政策签收流转类型'; end if;
  v_permission:=case when p_kind='policy' then 'Hr:PolicyAcknowledgement:Publish' else 'Hr:PolicyAcknowledgement:Receipt:Manage' end;
  if auth.uid() is null or not app_private.can_execute_business_action(
    'HrPolicyAcknowledgement',v_permission,null,false
  ) then raise exception '当前账号没有执行政策签收流转的权限' using errcode='42501'; end if;

  if p_kind='policy' then
    select * into v_policy from public.hr_policy_document
    where id=p_id and (app_private.is_platform_super() or tenant_id=v_tenant_id) for update;
    if not found then raise exception '政策不存在或不属于当前租户'; end if;
    if p_action='publish' and v_policy.status='draft' then
      with recursive org_scope as (
        select organization.id from public.sys_organization organization
        where organization.id=v_policy.audience_organization_id and organization.tenant_id=v_policy.tenant_id
        union all
        select child.id from public.sys_organization child
        join org_scope parent_scope on child.parent_id=parent_scope.id
        where child.tenant_id=v_policy.tenant_id
      )
      insert into public.hr_policy_receipt(tenant_id,policy_id,employee_id,due_date)
      select v_policy.tenant_id,v_policy.id,employee.id,
        greatest(current_date,v_policy.effective_date)+v_policy.acknowledgement_due_days
      from public.hr_employee employee
      where employee.tenant_id=v_policy.tenant_id
        and employee.employment_status in ('probation','active','leave')
        and (v_policy.audience_type='all'
          or (v_policy.audience_type='organization' and employee.organization_id in (select id from org_scope))
          or (v_policy.audience_type='employment_type' and employee.employment_type=v_policy.audience_employment_type))
      on conflict(policy_id,employee_id) do nothing;
      get diagnostics v_inserted=row_count;
      if v_inserted=0 then raise exception '当前适用人群没有可送达员工，请检查范围后再发布'; end if;
      update public.hr_policy_document set status='published',published_at=now(),published_by=v_actor,
        decision_note=coalesce(nullif(btrim(p_comment),''),decision_note) where id=p_id;
    elsif p_action='retire' and v_policy.status='published' then
      if nullif(btrim(p_comment),'') is null then raise exception '退役政策必须填写原因'; end if;
      update public.hr_policy_document set status='retired',retired_at=now(),retired_by=v_actor,
        decision_note=btrim(p_comment) where id=p_id;
    elsif p_action='cancel' and v_policy.status='draft' then
      update public.hr_policy_document set status='cancelled',decision_note=nullif(btrim(p_comment),'') where id=p_id;
    else raise exception '政策当前状态不支持此操作'; end if;
  else
    select * into v_receipt from public.hr_policy_receipt
    where id=p_id and (app_private.is_platform_super() or tenant_id=v_tenant_id) for update;
    if not found then raise exception '签收记录不存在或不属于当前租户'; end if;
    if p_action='acknowledge' and v_receipt.status='pending' then
      if nullif(btrim(p_comment),'') is null then raise exception '确认签收必须记录确认说明'; end if;
      update public.hr_policy_receipt set status='acknowledged',acknowledged_at=now(),
        acknowledged_by=v_actor,acknowledgement_note=btrim(p_comment),
        evidence_reference=nullif(btrim(p_evidence_reference),'') where id=p_id;
    elsif p_action='waive' and v_receipt.status='pending' then
      if nullif(btrim(p_comment),'') is null then raise exception '豁免签收必须填写原因'; end if;
      update public.hr_policy_receipt set status='waived',waived_at=now(),waived_by=v_actor,
        waiver_reason=btrim(p_comment),evidence_reference=nullif(btrim(p_evidence_reference),'') where id=p_id;
    elsif p_action='reopen' and v_receipt.status in ('acknowledged','waived') then
      if nullif(btrim(p_comment),'') is null then raise exception '重新打开签收必须填写原因'; end if;
      update public.hr_policy_receipt set status='pending',acknowledged_at=null,acknowledged_by=null,
        acknowledgement_note=null,waived_at=null,waived_by=null,waiver_reason=null,
        evidence_reference=null where id=p_id;
    else raise exception '签收记录当前状态不支持此操作'; end if;
  end if;
  return true;
end;
$function$;

create or replace function public.hr_delete_policy_document_secure(p_id uuid)
returns boolean language plpgsql security definer set search_path=''
as $function$
declare v_tenant_id uuid:=app_private.current_user_tenant_id();
begin
  if auth.uid() is null or not app_private.can_execute_business_action(
    'HrPolicyAcknowledgement','Hr:PolicyAcknowledgement:Policy:Manage',null,false
  ) then raise exception '当前账号没有删除政策草稿的权限' using errcode='42501'; end if;
  delete from public.hr_policy_document where id=p_id
    and (app_private.is_platform_super() or tenant_id=v_tenant_id) and status='draft';
  if not found then raise exception '政策不存在、已进入流程或不允许删除'; end if;
  return true;
end;
$function$;

revoke all on function public.hr_policy_acknowledgement_overview_secure(uuid) from public,anon,authenticated;
revoke all on function public.hr_list_policy_acknowledgement_records_secure(text,integer,integer,text,text,uuid,uuid) from public,anon,authenticated;
revoke all on function public.hr_list_policy_acknowledgement_options_secure(text,uuid) from public,anon,authenticated;
revoke all on function public.hr_save_policy_document_secure(uuid,jsonb) from public,anon,authenticated;
revoke all on function public.hr_transition_policy_acknowledgement_secure(text,uuid,text,text,text) from public,anon,authenticated;
revoke all on function public.hr_delete_policy_document_secure(uuid) from public,anon,authenticated;
grant execute on function public.hr_policy_acknowledgement_overview_secure(uuid) to authenticated;
grant execute on function public.hr_list_policy_acknowledgement_records_secure(text,integer,integer,text,text,uuid,uuid) to authenticated;
grant execute on function public.hr_list_policy_acknowledgement_options_secure(text,uuid) to authenticated;
grant execute on function public.hr_save_policy_document_secure(uuid,jsonb) to authenticated;
grant execute on function public.hr_transition_policy_acknowledgement_secure(text,uuid,text,text,text) to authenticated;
grant execute on function public.hr_delete_policy_document_secure(uuid) to authenticated;

;
