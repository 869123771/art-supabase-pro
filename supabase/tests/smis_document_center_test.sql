begin;

create temporary table smis_document_center_test_context (
  user_id uuid not null,
  auth_user_id uuid not null,
  tenant_id uuid not null,
  category_id uuid,
  document_id uuid
) on commit drop;

create temporary table smis_document_center_test_result (
  check_name text primary key,
  passed boolean not null,
  detail text not null
) on commit drop;

insert into smis_document_center_test_context(user_id, auth_user_id, tenant_id)
select user_row.id, user_row.auth_user_id, user_row.tenant_id
from public.sys_user user_row
join public.sys_tenant tenant on tenant.id = user_row.tenant_id and tenant.status = '1'
where user_row.auth_user_id is not null
  and user_row.status = '1'
  and user_row.deleted_at is null
  and exists (
    select 1
    from public.sys_role role_row
    join public.sys_role_menu role_menu
      on role_menu.role_id = role_row.id
     and role_menu.tenant_id = role_row.tenant_id
    join public.sys_menu menu_row on menu_row.id = role_menu.menu_id
    where role_row.tenant_id = user_row.tenant_id
      and role_row.role_code = any(coalesce(user_row.user_roles, array[]::text[]))
      and role_row.enabled is true
      and menu_row.name = 'SmisAllDocuments:Upload'
  )
order by user_row.create_time
limit 1;

do $fixture$
begin
  if not exists (select 1 from smis_document_center_test_context) then
    raise exception 'No enabled user with document-center permissions';
  end if;
end;
$fixture$;

grant select, update on smis_document_center_test_context to authenticated;
grant select, insert on smis_document_center_test_result to authenticated;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', (select auth_user_id from smis_document_center_test_context),
    'role', 'authenticated'
  )::text,
  true
);
set local role authenticated;

do $test$
declare
  v_user_id uuid;
  v_category_id uuid;
  v_document_id uuid;
  v_first_result jsonb;
  v_second_result jsonb;
  v_duplicate jsonb;
  v_list jsonb;
  v_delete_blocked boolean := false;
begin
  select user_id into v_user_id
  from smis_document_center_test_context;

  v_category_id := public.smis_save_document_category_secure(
    null,
    jsonb_build_object(
      'category_name', '文档中心自动化测试分类',
      'sort', 999,
      'status', 'enabled',
      'description', '事务内测试数据，结束后回滚'
    )
  );
  update smis_document_center_test_context set category_id = v_category_id;
  insert into smis_document_center_test_result values (
    'category_created_in_current_tenant',
    exists (
      select 1 from public.smis_document_category category
      where category.id = v_category_id
        and category.tenant_id = (select tenant_id from smis_document_center_test_context)
    ),
    '分类通过受控 RPC 创建并绑定当前租户'
  );

  v_first_result := public.smis_save_document_secure(
    null,
    jsonb_build_object(
      'category_id', v_category_id,
      'title', '文档中心自动化测试',
      'status', 'published',
      'summary', '事务内测试数据，结束后回滚',
      'file_name', 'document-center-regression.pdf',
      'file_url', 'https://example.invalid/document-center-regression-v1.pdf',
      'file_type', 'pdf',
      'file_size', 1024,
      'effective_date', current_date,
      'duplicate_action', 'none'
    )
  );
  v_document_id := (v_first_result->>'id')::uuid;
  update smis_document_center_test_context set document_id = v_document_id;

  v_duplicate := public.smis_find_document_duplicate_secure(
    v_category_id,
    'document-center-regression.pdf',
    null
  );
  insert into smis_document_center_test_result values (
    'duplicate_filename_detected',
    v_duplicate->>'id' = v_document_id::text,
    '同一分类下同名文件在上传前可被准确识别'
  );

  v_second_result := public.smis_save_document_secure(
    v_document_id,
    jsonb_build_object(
      'category_id', v_category_id,
      'title', '文档中心自动化测试',
      'status', 'published',
      'summary', '包含未来实施版本',
      'file_name', 'document-center-regression.pdf',
      'file_url', 'https://example.invalid/document-center-regression-v2.pdf',
      'file_type', 'pdf',
      'file_size', 2048,
      'effective_date', current_date + 10,
      'replacement_note', '未来日期自动切换',
      'duplicate_action', 'none'
    )
  );
  insert into smis_document_center_test_result values (
    'immutable_version_incremented',
    (v_first_result->>'versionNo')::integer = 1
      and (v_second_result->>'versionNo')::integer = 2
      and (select count(*) from public.smis_document_version version
        where version.document_id = v_document_id) = 2,
    '上传新版本保留旧版本并按文档递增版本号'
  );

  v_list := public.smis_list_documents_secure(
    0, 19, null, null, v_category_id, 'created', array[v_document_id], 'list'
  );
  insert into smis_document_center_test_result values (
    'scheduled_version_keeps_current_effective',
    exists (
      select 1
      from jsonb_array_elements(v_list->'records') record_row
      where record_row->>'id' = v_document_id::text
        and (record_row->>'versionNo')::integer = 1
        and (record_row->>'latestVersionNo')::integer = 2
        and record_row->>'implementationState' = 'scheduled'
    ),
    '未来实施版本展示为待实施，当前有效文件仍指向上一版本'
  );

  perform public.smis_toggle_document_follow_secure(v_document_id, true);
  v_list := public.smis_list_documents_secure(
    0, 19, null, null, null, 'following', null, 'list'
  );
  insert into smis_document_center_test_result values (
    'following_scope_is_user_specific',
    exists (
      select 1 from jsonb_array_elements(v_list->'records') record_row
      where record_row->>'id' = v_document_id::text
        and (record_row->>'isFollowing')::boolean
    ),
    '关注操作与“我关注的”范围使用系统用户主键'
  );

  begin
    perform public.smis_delete_documents_secure(array[v_document_id]);
  exception when raise_exception then
    v_delete_blocked := true;
  end;
  insert into smis_document_center_test_result values (
    'published_document_delete_blocked',
    v_delete_blocked,
    '已发布文档不能物理删除，只能作废或归档'
  );

  perform public.smis_save_document_secure(
    v_document_id,
    jsonb_build_object(
      'category_id', v_category_id,
      'title', '文档中心自动化测试',
      'status', 'draft',
      'summary', '删除回归验证'
    )
  );
  perform public.smis_delete_documents_secure(array[v_document_id]);
  insert into smis_document_center_test_result values (
    'draft_delete_cascades_versions',
    not exists (select 1 from public.smis_document where id = v_document_id)
      and not exists (select 1 from public.smis_document_version where document_id = v_document_id),
    '草稿删除同时清理版本并终止关联提醒'
  );
end;
$test$;

reset role;

insert into smis_document_center_test_result values (
  'future_effective_notification_created',
  exists (
    select 1
    from public.sys_notification_subject subject
    where subject.tenant_id = (select tenant_id from smis_document_center_test_context)
      and subject.business_type = 'smis_document'
      and subject.business_id = (select document_id from smis_document_center_test_context)
      and subject.subject_key = 'version-2'
      and subject.status = 'cancelled'
  ),
  '未来实施日期写入统一提醒主题，删除草稿时提醒被正确终止'
);

select check_name, passed, detail
from smis_document_center_test_result
order by check_name;

do $verify$
declare
  v_failures text;
begin
  select string_agg(check_name || ': ' || detail, '; ' order by check_name)
  into v_failures
  from smis_document_center_test_result
  where not passed;
  if v_failures is not null then
    raise exception 'SMIS document center verification failed: %', v_failures;
  end if;
end;
$verify$;

rollback;
