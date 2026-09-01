create or replace function public.ai_ocr_recognition_overview()
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'total', count(*),
    'pending', count(*) filter (where review.status = 'pending'),
    'applied', count(*) filter (where review.status = 'applied'),
    'rejected', count(*) filter (where review.status = 'rejected'),
    'low_confidence', count(*) filter (where coalesce(review.confidence, 0) < 0.65),
    'today', count(*) filter (where review.create_time >= date_trunc('day', now())),
    'avg_confidence', coalesce(round(avg(review.confidence), 4), 0),
    'by_feature', coalesce((
      select jsonb_object_agg(feature_stats.feature, feature_stats.feature_count)
      from (
        select feature, count(*) as feature_count
        from public.ai_artifact_review
        where feature in ('invoice_ocr', 'waybill_receipt_ocr', 'cash_voucher_ocr')
        group by feature
      ) feature_stats
    ), '{}'::jsonb)
  )
  from public.ai_artifact_review review
  where review.feature in ('invoice_ocr', 'waybill_receipt_ocr', 'cash_voucher_ocr');
$$;

revoke all on function public.ai_ocr_recognition_overview() from public, anon;
grant execute on function public.ai_ocr_recognition_overview() to authenticated;

do $$
declare
  v_platform_tenant_id uuid;
  v_type_id uuid;
  v_root_menu_id uuid;
  v_child record;
  v_child_menu_id uuid;
begin
  select id into v_platform_tenant_id
  from public.sys_tenant
  where tenant_code = 'platform'
  limit 1;

  if v_platform_tenant_id is null then
    raise exception 'Platform tenant is required for intelligent recognition dictionaries';
  end if;

  insert into public.sys_dict_type (
    name, code, status, create_by, update_by, tenant_id, node_type, sort, remark
  ) values (
    '智能识别类型', 'aiOcrFeature', '1', '624944977@qq.com', '624944977@qq.com',
    v_platform_tenant_id, 'dictionary', 71, '统一智能识别中心业务类型'
  )
  on conflict (code) do update set
    name = excluded.name,
    status = excluded.status,
    update_by = excluded.update_by,
    update_time = now(),
    tenant_id = excluded.tenant_id,
    remark = excluded.remark
  returning id into v_type_id;

  insert into public.sys_dictionary (
    type_id, code, status, create_by, update_by, value, label, sort, tenant_id, tag_type
  )
  select v_type_id, item.value, '1', '624944977@qq.com', '624944977@qq.com',
         item.value, item.label, item.sort, v_platform_tenant_id, item.tag_type
  from (values
    ('invoice_ocr', '发票识别', 1::bigint, 'primary'),
    ('waybill_receipt_ocr', '回单识别', 2::bigint, 'success'),
    ('cash_voucher_ocr', '收付款凭证', 3::bigint, 'warning')
  ) item(value, label, sort, tag_type)
  where not exists (
    select 1 from public.sys_dictionary dictionary
    where dictionary.type_id = v_type_id and dictionary.value = item.value
  );

  insert into public.sys_dict_type (
    name, code, status, create_by, update_by, tenant_id, node_type, sort, remark
  ) values (
    '识别复核状态', 'aiArtifactStatus', '1', '624944977@qq.com', '624944977@qq.com',
    v_platform_tenant_id, 'dictionary', 72, 'AI 识别产物的业务复核状态'
  )
  on conflict (code) do update set
    name = excluded.name,
    status = excluded.status,
    update_by = excluded.update_by,
    update_time = now(),
    tenant_id = excluded.tenant_id,
    remark = excluded.remark
  returning id into v_type_id;

  insert into public.sys_dictionary (
    type_id, code, status, create_by, update_by, value, label, sort, tenant_id, tag_type
  )
  select v_type_id, item.value, '1', '624944977@qq.com', '624944977@qq.com',
         item.value, item.label, item.sort, v_platform_tenant_id, item.tag_type
  from (values
    ('pending', '待业务复核', 1::bigint, 'warning'),
    ('applied', '已应用', 2::bigint, 'success'),
    ('rejected', '已驳回', 3::bigint, 'danger'),
    ('superseded', '已失效', 4::bigint, 'info')
  ) item(value, label, sort, tag_type)
  where not exists (
    select 1 from public.sys_dictionary dictionary
    where dictionary.type_id = v_type_id and dictionary.value = item.value
  );

  select id into v_root_menu_id
  from public.sys_menu
  where name = 'IntelligentRecognition' and parent_id is null
  limit 1;

  if v_root_menu_id is null then
    v_root_menu_id := gen_random_uuid();
    insert into public.sys_menu (
      id, name, path, component, meta, sort, parent_id, type, create_by, update_by
    ) values (
      v_root_menu_id, 'IntelligentRecognition', '/intelligent-recognition', '/index/index',
      '{"icon":"ri:scan-2-line","roles":[],"title":"智能识别","is_enable":true,"keep_alive":true}'::jsonb,
      6, null, 'folder', '624944977@qq.com', '624944977@qq.com'
    );
  else
    update public.sys_menu
    set path = '/intelligent-recognition', component = '/index/index', sort = 6,
        type = 'folder',
        meta = meta || '{"icon":"ri:scan-2-line","title":"智能识别","is_enable":true,"keep_alive":true}'::jsonb,
        update_by = '624944977@qq.com', update_time = now()
    where id = v_root_menu_id;
  end if;

  for v_child in
    select * from (values
      ('RecognitionWorkbench', 'workbench', '/intelligent-recognition/workbench', '识别工作台', 'ri:sparkling-2-line', 1),
      ('RecognitionReview', 'review', '/intelligent-recognition/review', '待复核', 'ri:shield-check-line', 2),
      ('RecognitionRecords', 'records', '/intelligent-recognition/records', '识别记录', 'ri:file-history-line', 3)
    ) children(name, path, component, title, icon, sort)
  loop
    select id into v_child_menu_id
    from public.sys_menu
    where name = v_child.name and parent_id = v_root_menu_id
    limit 1;

    if v_child_menu_id is null then
      insert into public.sys_menu (
        name, path, component, meta, sort, parent_id, type, create_by, update_by
      ) values (
        v_child.name, v_child.path, v_child.component,
        jsonb_build_object('icon', v_child.icon, 'roles', jsonb_build_array(), 'title', v_child.title,
          'is_enable', true, 'keep_alive', true),
        v_child.sort, v_root_menu_id, 'menu', '624944977@qq.com', '624944977@qq.com'
      );
    else
      update public.sys_menu
      set path = v_child.path, component = v_child.component, sort = v_child.sort, type = 'menu',
          meta = meta || jsonb_build_object('icon', v_child.icon, 'title', v_child.title,
            'is_enable', true, 'keep_alive', true),
          update_by = '624944977@qq.com', update_time = now()
      where id = v_child_menu_id;
    end if;
    v_child_menu_id := null;
  end loop;

  insert into public.sys_role_menu (
    tenant_id, role_id, menu_id, permission, create_by, update_by
  )
  select role.tenant_id, role.id, menu.id, '{}'::jsonb,
         '624944977@qq.com', '624944977@qq.com'
  from public.sys_role role
  join public.sys_menu menu on menu.id = v_root_menu_id or menu.parent_id = v_root_menu_id
  where role.enabled is true
  on conflict (role_id, menu_id) do nothing;
end;
$$;;
