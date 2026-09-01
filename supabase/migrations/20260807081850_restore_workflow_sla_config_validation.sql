-- Preserve the existing SLA contract while extending node decision semantics.

create or replace function app_private.validate_workflow_config(p_config jsonb)
returns void
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  v_node jsonb;
  v_count integer;
  v_mode text;
  v_threshold integer;
  v_due_hours integer;
  v_reminder_minutes integer;
  v_escalate_hours integer;
begin
  if p_config is null or jsonb_typeof(p_config) <> 'object'
     or jsonb_typeof(p_config -> 'nodes') <> 'array' then
    raise exception '流程配置必须包含 nodes 数组';
  end if;

  v_count := jsonb_array_length(p_config -> 'nodes');
  if v_count < 1 or v_count > 30 then
    raise exception '审批节点数量必须在 1 到 30 之间';
  end if;

  if (select count(distinct node ->> 'key') from jsonb_array_elements(p_config -> 'nodes') node) <> v_count then
    raise exception '审批节点标识不能重复';
  end if;

  if (select count(distinct (node ->> 'order')::integer) from jsonb_array_elements(p_config -> 'nodes') node) <> v_count then
    raise exception '审批节点顺序不能重复';
  end if;

  for v_node in select value from jsonb_array_elements(p_config -> 'nodes') loop
    if btrim(coalesce(v_node ->> 'key', '')) = ''
       or (v_node ->> 'key') !~ '^[A-Za-z][A-Za-z0-9_-]{1,39}$'
       or btrim(coalesce(v_node ->> 'name', '')) = '' then
      raise exception '节点标识或名称不正确';
    end if;

    v_mode := coalesce(v_node ->> 'approvalMode', '');
    if v_mode not in ('any', 'all', 'percentage') then
      raise exception '节点 % 的审批方式不正确', v_node ->> 'name';
    end if;

    if v_mode = 'percentage' then
      if coalesce(v_node ->> 'approvalThresholdPercent', '') !~ '^[0-9]+$' then
        raise exception '节点 % 的通过比例必须是 1 到 100 的整数', v_node ->> 'name';
      end if;
      v_threshold := (v_node ->> 'approvalThresholdPercent')::integer;
      if v_threshold < 1 or v_threshold > 100 then
        raise exception '节点 % 的通过比例必须是 1 到 100 的整数', v_node ->> 'name';
      end if;
    end if;

    if v_node ? 'rejectVetoEnabled'
       and jsonb_typeof(v_node -> 'rejectVetoEnabled') <> 'boolean' then
      raise exception '节点 % 的一票否决配置必须是布尔值', v_node ->> 'name';
    end if;

    if coalesce(v_node #>> '{assignee,type}', '') not in ('users', 'roles', 'initiator') then
      raise exception '节点 % 的审批人类型不正确', v_node ->> 'name';
    end if;
    if (v_node #>> '{assignee,type}') = 'users'
       and coalesce(jsonb_array_length(v_node #> '{assignee,userIds}'), 0) = 0 then
      raise exception '节点 % 必须选择审批人', v_node ->> 'name';
    end if;
    if (v_node #>> '{assignee,type}') = 'roles'
       and coalesce(jsonb_array_length(v_node #> '{assignee,roleCodes}'), 0) = 0 then
      raise exception '节点 % 必须选择审批角色', v_node ->> 'name';
    end if;

    if coalesce(v_node #>> '{condition,operator}', 'always') not in
       ('always', 'eq', 'ne', 'gt', 'gte', 'lt', 'lte', 'in', 'contains', 'not_empty') then
      raise exception '节点 % 的条件运算符不受支持', v_node ->> 'name';
    end if;

    if coalesce(v_node ->> 'dueHours', '') !~ '^[0-9]+$' then
      raise exception '节点 % 的审批时限必须是整数小时', v_node ->> 'name';
    end if;
    v_due_hours := (v_node ->> 'dueHours')::integer;
    if v_due_hours < 1 or v_due_hours > 720 then
      raise exception '节点 % 的审批时限必须在 1 到 720 小时之间', v_node ->> 'name';
    end if;

    if coalesce(v_node ->> 'reminderBeforeMinutes', '60') !~ '^[0-9]+$' then
      raise exception '节点 % 的到期前提醒必须是整数分钟', v_node ->> 'name';
    end if;
    v_reminder_minutes := coalesce((v_node ->> 'reminderBeforeMinutes')::integer, 60);
    if v_reminder_minutes < 0 or v_reminder_minutes > v_due_hours * 60 then
      raise exception '节点 % 的到期前提醒不能超过审批时限', v_node ->> 'name';
    end if;

    if coalesce(v_node ->> 'escalationEnabled', 'true') not in ('true', 'false') then
      raise exception '节点 % 的超时升级开关不正确', v_node ->> 'name';
    end if;
    if coalesce(v_node ->> 'escalateAfterHours', '4') !~ '^[0-9]+$' then
      raise exception '节点 % 的升级时间必须是整数小时', v_node ->> 'name';
    end if;
    v_escalate_hours := coalesce((v_node ->> 'escalateAfterHours')::integer, 4);
    if v_escalate_hours < 1 or v_escalate_hours > 720 then
      raise exception '节点 % 的升级时间必须在 1 到 720 小时之间', v_node ->> 'name';
    end if;
  end loop;
end;
$$;

revoke all on function app_private.validate_workflow_config(jsonb)
  from public, anon, authenticated;
grant execute on function app_private.validate_workflow_config(jsonb) to service_role;

;
