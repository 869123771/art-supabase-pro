
insert into public.sys_dictionary(
  type_id,code,status,value,label,i18n_scope,sort,tenant_id,tag_type,create_by,update_by
)
select t.id,'workflowBusinessType_tms_customer_statement','1','tms_customer_statement',
       '客户结算','1',5,t.tenant_id,'success','workflow-migration','workflow-migration'
from public.sys_dict_type t
where t.code='workflowBusinessType'
  and not exists(select 1 from public.sys_dictionary d
    where d.type_id=t.id and d.value='tms_customer_statement');

do $block$
declare
  v_tenant uuid := '6675a0d6-3ff6-4ab7-bb09-232d85ae96ad'::uuid;
  v_type text;
  v_code text;
  v_name text;
  v_node_name text;
  v_definition_id uuid;
  v_version_id uuid;
  v_config jsonb;
begin
  foreach v_type in array array['tms_customer_statement','tms_contract','vehicle_archive']
  loop
    if exists(select 1 from public.wf_definition d
      where d.tenant_id=v_tenant and d.business_type=v_type and d.status='published') then
      continue;
    end if;
    v_code:=case v_type when 'tms_customer_statement' then 'tms-customer-statement-review'
      when 'tms_contract' then 'tms-contract-review' else 'vehicle-archive-review' end;
    v_name:=case v_type when 'tms_customer_statement' then '客户结算审批'
      when 'tms_contract' then '运输合同审批' else '车辆档案审批' end;
    v_node_name:=case v_type when 'vehicle_archive' then '档案管理员审核' else '业务负责人审核' end;
    v_config:=jsonb_build_object(
      'allowAutoApprove',false,
      'nodes',jsonb_build_array(jsonb_build_object(
        'key','business_review','name',v_node_name,'order',1,
        'approvalMode','any','approvalThresholdPercent',100,'rejectVetoEnabled',true,
        'allowSelfApproval',false,'dueHours',24,'reminderBeforeMinutes',120,
        'escalationEnabled',true,'escalateAfterHours',4,
        'assignee',jsonb_build_object('type','roles','roleCodes',jsonb_build_array('R_ADMIN'),'userIds','[]'::jsonb),
        'condition',jsonb_build_object('operator','always')
      ))
    );
    insert into public.wf_definition(
      code,name,business_type,description,status,tenant_id,create_by,update_by
    ) values (
      v_code,v_name,v_type,'系统预置基础审批流，可在审批中心创建新版本后调整审批人和条件。',
      'draft',v_tenant,'workflow-migration','workflow-migration'
    ) returning id into v_definition_id;
    insert into public.wf_version(
      definition_id,version_no,status,config,change_note,published_at,published_by,
      tenant_id,create_by,update_by
    ) values (
      v_definition_id,1,'published',v_config,'接入统一审批中心',now(),'workflow-migration',
      v_tenant,'workflow-migration','workflow-migration'
    ) returning id into v_version_id;
    update public.wf_definition set status='published',current_version_id=v_version_id,
      published_at=now(),published_by='workflow-migration',update_by='workflow-migration'
    where id=v_definition_id;
  end loop;
end;
$block$;
;
