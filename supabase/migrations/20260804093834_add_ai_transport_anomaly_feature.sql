do $$
declare
  v_tenant_id uuid;
  v_type_id uuid;
begin
  select id
  into v_tenant_id
  from public.sys_tenant
  where tenant_code = 'platform'
  limit 1;

  if v_tenant_id is null then
    raise exception 'Platform tenant is required before adding AI transport anomaly dictionaries';
  end if;

  select id
  into v_type_id
  from public.sys_dict_type
  where tenant_id = v_tenant_id
    and code = 'aiRunFeature'
  limit 1;

  if v_type_id is null then
    raise exception 'Dictionary type aiRunFeature is required before adding AI transport anomaly dictionaries';
  end if;

  insert into public.sys_dictionary (
    tenant_id, type_id, parent_id, label, code, value, i18n_scope, status, sort,
    color, tag_type, remark, create_by, update_by
  )
  select
    v_tenant_id, v_type_id, null, 'AI 运输异常研判', 'transport_anomaly_advisor',
    'transport_anomaly_advisor', '1', '1', 45, '#E6A23C', 'warning',
    '基于计划时间、配载和业务状态进行只读风险研判；不自动改变订单或运单状态。',
    '624944977@qq.com', '624944977@qq.com'
  where not exists (
    select 1
    from public.sys_dictionary dictionary
    where dictionary.tenant_id = v_tenant_id
      and dictionary.type_id = v_type_id
      and dictionary.code = 'transport_anomaly_advisor'
  );
end
$$;;
