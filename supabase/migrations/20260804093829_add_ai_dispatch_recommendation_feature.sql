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
    raise exception 'Platform tenant is required before adding AI dispatch dictionaries';
  end if;

  select id
  into v_type_id
  from public.sys_dict_type
  where tenant_id = v_tenant_id
    and code = 'aiRunFeature'
  limit 1;

  if v_type_id is null then
    raise exception 'Dictionary type aiRunFeature is required before adding AI dispatch dictionaries';
  end if;

  insert into public.sys_dictionary (
    tenant_id, type_id, parent_id, label, code, value, i18n_scope, status, sort,
    color, tag_type, remark, create_by, update_by
  )
  select
    v_tenant_id, v_type_id, null, 'AI 调度推荐', 'dispatch_recommendation',
    'dispatch_recommendation', '1', '1', 40, '#409EFF', 'primary',
    '只读车辆与司机候选排序；推荐结果不自动改变订单调度状态。',
    '624944977@qq.com', '624944977@qq.com'
  where not exists (
    select 1
    from public.sys_dictionary dictionary
    where dictionary.tenant_id = v_tenant_id
      and dictionary.type_id = v_type_id
      and dictionary.code = 'dispatch_recommendation'
  );
end
$$;;
