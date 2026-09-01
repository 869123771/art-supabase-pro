create or replace function public.create_ai_order_master_data(p_tasks jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_task jsonb;
  v_payload jsonb;
  v_kind text;
  v_key text;
  v_customer_id uuid;
  v_record_id uuid;
  v_station public.tms_station;
  v_address jsonb;
  v_result jsonb := '[]'::jsonb;
begin
  if not (select app_private.is_platform_super()) then
    raise exception '仅平台超级管理员可执行 AI 主数据建档';
  end if;

  if p_tasks is null or jsonb_typeof(p_tasks) <> 'array' or jsonb_array_length(p_tasks) = 0 then
    raise exception '请选择需要创建的主数据';
  end if;

  if jsonb_array_length(p_tasks) > 20 then
    raise exception '单次最多创建 20 项主数据';
  end if;

  for v_task in select value from jsonb_array_elements(p_tasks)
  loop
    if jsonb_typeof(v_task) <> 'object' then
      raise exception 'AI 主数据任务格式不正确';
    end if;

    v_kind := btrim(coalesce(v_task ->> 'kind', ''));
    v_key := btrim(coalesce(v_task ->> 'key', ''));
    v_payload := coalesce(v_task -> 'payload', '{}'::jsonb);

    if v_key = '' or jsonb_typeof(v_payload) <> 'object' then
      raise exception 'AI 主数据任务缺少标识或载荷';
    end if;

    if v_kind = 'station' then
      select *
        into v_station
      from public.save_tms_station(
        coalesce(v_payload -> 'station', '{}'::jsonb),
        array(
          select jsonb_array_elements_text(coalesce(v_payload -> 'role_types', '[]'::jsonb))
        )
      );
      v_record_id := v_station.id;

    elsif v_kind = 'customer' then
      if btrim(coalesce(v_payload #>> '{customer,customer_name}', '')) = '' then
        raise exception '客户名称不能为空';
      end if;

      insert into public.tms_customer (
        customer_name,
        tags,
        region,
        address_detail,
        enabled,
        contact_name,
        contact_phone,
        coordinate_system,
        coordinate_status
      )
      values (
        btrim(v_payload #>> '{customer,customer_name}'),
        array(
          select jsonb_array_elements_text(
            case
              when jsonb_typeof(v_payload #> '{customer,tags}') = 'array'
              then v_payload #> '{customer,tags}'
              else '[]'::jsonb
            end
          )
        ),
        nullif(btrim(coalesce(v_payload #>> '{customer,region}', '')), ''),
        nullif(btrim(coalesce(v_payload #>> '{customer,address_detail}', '')), ''),
        coalesce((v_payload #>> '{customer,enabled}')::boolean, true),
        nullif(btrim(coalesce(v_payload #>> '{customer,contact_name}', '')), ''),
        nullif(btrim(coalesce(v_payload #>> '{customer,contact_phone}', '')), ''),
        coalesce(nullif(v_payload #>> '{customer,coordinate_system}', ''), 'gcj02'),
        coalesce(nullif(v_payload #>> '{customer,coordinate_status}', ''), 'pending')
      )
      returning id into v_customer_id;

      v_record_id := v_customer_id;
      v_address := v_payload -> 'address';
      if v_address is not null and jsonb_typeof(v_address) = 'object' then
        if btrim(coalesce(v_address ->> 'contact_name', '')) = ''
           or btrim(coalesce(v_address ->> 'contact_phone', '')) = ''
           or btrim(coalesce(v_address ->> 'region', '')) = ''
           or btrim(coalesce(v_address ->> 'address_detail', '')) = '' then
          raise exception '客户默认地址资料不完整';
        end if;

        insert into public.tms_customer_address (
          customer_id,
          address_type,
          contact_name,
          contact_phone,
          region,
          address_detail,
          is_default,
          coordinate_system,
          coordinate_status
        )
        values (
          v_customer_id,
          v_address ->> 'address_type',
          btrim(v_address ->> 'contact_name'),
          btrim(v_address ->> 'contact_phone'),
          btrim(v_address ->> 'region'),
          btrim(v_address ->> 'address_detail'),
          coalesce((v_address ->> 'is_default')::boolean, true),
          coalesce(nullif(v_address ->> 'coordinate_system', ''), 'gcj02'),
          coalesce(nullif(v_address ->> 'coordinate_status', ''), 'pending')
        );
      end if;

    elsif v_kind = 'address' then
      begin
        v_customer_id := nullif(v_payload ->> 'customer_id', '')::uuid;
      exception
        when invalid_text_representation then
          raise exception '客户编号格式不正确';
      end;

      if v_customer_id is null or not exists (
        select 1
        from public.tms_customer c
        where c.id = v_customer_id
          and c.tenant_id = (select app_private.current_user_tenant_id())
      ) then
        raise exception '客户不存在或当前用户无权访问';
      end if;

      v_address := coalesce(v_payload -> 'address', '{}'::jsonb);
      if btrim(coalesce(v_address ->> 'contact_name', '')) = ''
         or btrim(coalesce(v_address ->> 'contact_phone', '')) = ''
         or btrim(coalesce(v_address ->> 'region', '')) = ''
         or btrim(coalesce(v_address ->> 'address_detail', '')) = '' then
        raise exception '客户地址资料不完整';
      end if;

      insert into public.tms_customer_address (
        customer_id,
        address_type,
        contact_name,
        contact_phone,
        region,
        address_detail,
        is_default,
        coordinate_system,
        coordinate_status
      )
      values (
        v_customer_id,
        v_address ->> 'address_type',
        btrim(v_address ->> 'contact_name'),
        btrim(v_address ->> 'contact_phone'),
        btrim(v_address ->> 'region'),
        btrim(v_address ->> 'address_detail'),
        coalesce((v_address ->> 'is_default')::boolean, true),
        coalesce(nullif(v_address ->> 'coordinate_system', ''), 'gcj02'),
        coalesce(nullif(v_address ->> 'coordinate_status', ''), 'pending')
      )
      returning id into v_record_id;

    elsif v_kind = 'cargo' then
      if btrim(coalesce(v_payload #>> '{cargo,cargo_name}', '')) = '' then
        raise exception '货物名称不能为空';
      end if;

      insert into public.tms_cargo (cargo_name, unit, enabled, remark)
      values (
        btrim(v_payload #>> '{cargo,cargo_name}'),
        coalesce(nullif(btrim(v_payload #>> '{cargo,unit}'), ''), 'item'),
        coalesce((v_payload #>> '{cargo,enabled}')::boolean, true),
        nullif(btrim(coalesce(v_payload #>> '{cargo,remark}', '')), '')
      )
      returning id into v_record_id;

    else
      raise exception '不支持的 AI 主数据任务类型：%', v_kind;
    end if;

    v_result := v_result || jsonb_build_array(
      jsonb_build_object('key', v_key, 'kind', v_kind, 'id', v_record_id)
    );
  end loop;

  return v_result;
end;
$$;
revoke execute on function public.create_ai_order_master_data(jsonb)
  from public, anon, service_role;
grant execute on function public.create_ai_order_master_data(jsonb)
  to authenticated;
