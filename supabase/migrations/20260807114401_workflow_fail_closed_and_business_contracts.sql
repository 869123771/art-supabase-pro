
create or replace function app_private.validate_workflow_business_config(
  p_business_type text,
  p_config jsonb
) returns void
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_node jsonb;
  v_operator text;
  v_field text;
  v_allowed_fields text[];
begin
  perform app_private.validate_workflow_config(p_config);

  if p_config ? 'allowAutoApprove'
     and jsonb_typeof(p_config -> 'allowAutoApprove') <> 'boolean' then
    raise exception '全条件未命中策略必须是布尔值';
  end if;

  v_allowed_fields := case p_business_type
    when 'tms_waybill_cost' then array['amount','costType','payeeName','waybillNo','occurredOn']
    when 'tms_invoice' then array['direction','invoiceType','invoiceNo','totalAmount','taxRate','counterpartyName']
    when 'tms_carrier_statement' then array['statementNo','statementAmount','carrierId','carrierName','costCount','settledAmount']
    when 'tms_customer_statement' then array['statementNo','statementAmount','customerId','customerName','waybillCount','settledAmount']
    when 'tms_contract' then array['contractNo','contractAmount','carrierId','billingMethod','signTime','handler']
    when 'vehicle_archive' then array['plateNo','companyName','vehicleType','approvedLoadMass','operationType','isNewEnergy']
    else null
  end;

  for v_node in select value from jsonb_array_elements(p_config -> 'nodes')
  loop
    v_operator := coalesce(v_node #>> '{condition,operator}', 'always');
    if v_operator <> 'always' then
      v_field := btrim(coalesce(v_node #>> '{condition,field}', ''));
      if v_field = '' then
        raise exception '节点“%”必须选择条件字段', v_node ->> 'name';
      end if;
      if v_allowed_fields is not null and not (v_field = any(v_allowed_fields)) then
        raise exception '节点“%”使用了业务类型 % 不支持的条件字段 %',
          v_node ->> 'name', p_business_type, v_field;
      end if;
      if v_operator = 'in' and jsonb_typeof(v_node #> '{condition,value}') <> 'array' then
        raise exception '节点“%”的“属于”比较值必须是非空数组', v_node ->> 'name';
      end if;
      if v_operator = 'in' and jsonb_array_length(v_node #> '{condition,value}') = 0 then
        raise exception '节点“%”的“属于”比较值不能为空', v_node ->> 'name';
      end if;
    end if;
  end loop;
end;
$function$;

create or replace function app_private.trg_validate_workflow_version_business_config()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_business_type text;
begin
  select d.business_type into v_business_type
  from public.wf_definition d
  where d.id = new.definition_id;

  if v_business_type is null then
    raise exception '流程定义不存在';
  end if;

  perform app_private.validate_workflow_business_config(v_business_type, new.config);
  return new;
end;
$function$;

drop trigger if exists wf_version_validate_business_config on public.wf_version;
create trigger wf_version_validate_business_config
before insert or update of config on public.wf_version
for each row execute function app_private.trg_validate_workflow_version_business_config();

create or replace function app_private.activate_next_workflow_node(
  p_instance_id uuid,
  p_after_order integer
) returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_instance public.wf_instance;
  v_config jsonb;
  v_node jsonb;
  v_assignee record;
  v_assignee_count integer;
  v_mode text;
  v_candidate_count integer := 0;
begin
  select i.* into v_instance
  from public.wf_instance i
  where i.id = p_instance_id
  for update;

  if not found then raise exception '流程实例不存在'; end if;

  select v.config into v_config
  from public.wf_version v
  where v.id = v_instance.version_id;

  for v_node in
    select value
    from jsonb_array_elements(v_config -> 'nodes')
    where (value ->> 'order')::integer > p_after_order
    order by (value ->> 'order')::integer
  loop
    v_candidate_count := v_candidate_count + 1;

    if not app_private.workflow_condition_matches(v_instance.context_snapshot, v_node) then
      insert into public.wf_action(
        instance_id, node_key, node_name, action, actor_name_snapshot, comment, tenant_id
      ) values (
        v_instance.id, v_node ->> 'key', v_node ->> 'name', 'auto_skip',
        '系统', '条件不满足，自动跳过', v_instance.tenant_id
      );
      continue;
    end if;

    v_mode := v_node ->> 'approvalMode';
    v_assignee_count := 0;

    for v_assignee in
      select * from app_private.resolve_workflow_assignees(
        v_instance.tenant_id, v_node, v_instance.initiator_user_id
      )
    loop
      insert into public.wf_task(
        instance_id, node_key, node_name, node_order, approval_mode,
        approval_threshold_percent, reject_veto_enabled, assignee_user_id,
        assignee_name_snapshot, due_at, tenant_id
      ) values (
        v_instance.id, v_node ->> 'key', v_node ->> 'name',
        (v_node ->> 'order')::integer, v_mode,
        case when v_mode = 'any' then 1 when v_mode = 'all' then 100
          else (v_node ->> 'approvalThresholdPercent')::integer end,
        coalesce((v_node ->> 'rejectVetoEnabled')::boolean, true),
        v_assignee.user_id, v_assignee.user_name,
        case when coalesce((v_node ->> 'dueHours')::integer, 0) > 0
          then now() + make_interval(hours => (v_node ->> 'dueHours')::integer) end,
        v_instance.tenant_id
      );
      v_assignee_count := v_assignee_count + 1;
    end loop;

    if v_assignee_count = 0 then
      raise exception '节点“%”没有可用审批人，请检查角色、人员或自审配置', v_node ->> 'name';
    end if;

    update public.wf_instance
    set current_node_key = v_node ->> 'key',
        current_node_name = v_node ->> 'name',
        row_version = row_version + 1
    where id = v_instance.id;
    return;
  end loop;

  if v_candidate_count > 0
     and not coalesce((v_config ->> 'allowAutoApprove')::boolean, false) then
    raise exception '后续审批条件全部未命中，流程已安全阻断；请检查业务上下文或显式开启自动通过策略';
  end if;

  update public.wf_instance
  set status = 'approved', current_node_key = null, current_node_name = null,
      finished_at = now(), row_version = row_version + 1
  where id = v_instance.id;

  perform app_private.apply_workflow_business_status(
    v_instance.business_type, v_instance.business_id, 'approved', '系统', '流程全部节点已通过'
  );
end;
$function$;

revoke all on function app_private.validate_workflow_business_config(text,jsonb) from public, anon, authenticated;
revoke all on function app_private.trg_validate_workflow_version_business_config() from public, anon, authenticated;
;
