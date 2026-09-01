
create or replace function app_private.search_platform_global_pending_workflow_tasks(
  p_keyword text default null,p_business_type text default null,p_tenant_id uuid default null,
  p_from integer default 0,p_to integer default 19
) returns jsonb
language plpgsql stable security definer set search_path=''
as $function$
declare
  v_from integer:=greatest(coalesce(p_from,0),0);
  v_limit integer:=least(greatest(coalesce(p_to,19)-greatest(coalesce(p_from,0),0)+1,1),100);
  v_keyword text:=nullif(btrim(coalesce(p_keyword,'')),'');
  v_result jsonb;
begin
  if (select auth.uid()) is null or not (select app_private.is_platform_super()) then
    raise exception '仅平台超级管理员可以查看全局待办' using errcode='42501';
  end if;
  with base as (
    select t.*,i.business_title,i.business_type,i.business_id,i.initiator_name_snapshot,
      i.definition_id,i.version_id,i.status instance_status,i.current_node_key,
      d.code definition_code,d.name definition_name,v.version_no,v.config,
      tenant.tenant_code,tenant.tenant_name
    from public.wf_task t
    join public.wf_instance i on i.id=t.instance_id
    join public.wf_definition d on d.id=i.definition_id
    join public.wf_version v on v.id=i.version_id
    join public.sys_tenant tenant on tenant.id=t.tenant_id
    where t.status='pending' and i.status='running' and i.current_node_key=t.node_key
      and (p_tenant_id is null or t.tenant_id=p_tenant_id)
      and (nullif(p_business_type,'') is null or i.business_type=p_business_type)
      and (v_keyword is null or i.business_title ilike '%'||v_keyword||'%'
        or i.business_id::text ilike '%'||v_keyword||'%'
        or i.initiator_name_snapshot ilike '%'||v_keyword||'%'
        or t.assignee_name_snapshot ilike '%'||v_keyword||'%'
        or tenant.tenant_name ilike '%'||v_keyword||'%' or d.name ilike '%'||v_keyword||'%')
  ), grouped as (
    select instance_id,node_key,min(id::text)::uuid representative_id,count(*)::integer assignee_count,
      count(*) filter(where status='pending')::integer pending_assignee_count,
      jsonb_agg(distinct assignee_name_snapshot order by assignee_name_snapshot) assignee_names,
      min(due_at) due_at,min(create_time) create_time,
      min(case when due_at is not null and due_at<now() then 0 else 1 end) urgency_order
    from base group by instance_id,node_key
  ), records as (
    select to_jsonb(b)-array['business_title','business_type','business_id','initiator_name_snapshot',
      'definition_id','version_id','instance_status','current_node_key','definition_code',
      'definition_name','version_no','config','tenant_code','tenant_name']
      ||jsonb_build_object(
        'assigneeCount',g.assignee_count,'pendingAssigneeCount',g.pending_assignee_count,
        'assigneeNames',g.assignee_names,
        'instance',jsonb_build_object('id',b.instance_id,'definitionId',b.definition_id,
          'versionId',b.version_id,'businessType',b.business_type,'businessId',b.business_id,
          'businessTitle',b.business_title,'initiatorNameSnapshot',b.initiator_name_snapshot,
          'status',b.instance_status,'currentNodeKey',b.current_node_key,
          'definition',jsonb_build_object('id',b.definition_id,'code',b.definition_code,
            'name',b.definition_name,'businessType',b.business_type),
          'version',jsonb_build_object('id',b.version_id,'versionNo',b.version_no,'config',b.config)),
        'tenant',jsonb_build_object('id',b.tenant_id,'tenantCode',b.tenant_code,'tenantName',b.tenant_name)
      ) record,g.urgency_order,g.due_at,g.create_time
    from grouped g join base b on b.id=g.representative_id
  ), page_rows as (
    select * from records order by urgency_order,due_at nulls last,create_time desc
    offset v_from limit v_limit
  )
  select jsonb_build_object(
    'records',coalesce((select jsonb_agg(record order by urgency_order,due_at nulls last,create_time desc) from page_rows),'[]'::jsonb),
    'total',(select count(*) from grouped),
    'taskTotal',(select coalesce(sum(assignee_count),0) from grouped)
  ) into v_result;
  return v_result;
end;$function$;
;
