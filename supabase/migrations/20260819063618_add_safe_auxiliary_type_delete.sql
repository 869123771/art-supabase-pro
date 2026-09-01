create or replace function public.delete_fms_auxiliary_type(p_id uuid)
returns public.fms_auxiliary_type
language plpgsql
set search_path = ''
as $function$
declare
  v_type public.fms_auxiliary_type%rowtype;
  v_item_count integer;
  v_subject_count integer;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可删除辅助核算维度';
  end if;

  select *
    into v_type
  from public.fms_auxiliary_type
  where id = p_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = '辅助核算维度不存在或已被删除';
  end if;

  if v_type.is_system or v_type.source_type <> 'manual' then
    raise exception using errcode = '23514', message = '系统维度和业务主数据维度受保护，不能删除';
  end if;

  select count(*)::integer
    into v_item_count
  from public.fms_auxiliary_item
  where auxiliary_type_id = v_type.id;

  if v_item_count > 0 then
    raise exception using
      errcode = '23514',
      message = format('该维度已有 %s 个核算项目，请先清理核算项目后再删除', v_item_count);
  end if;

  select count(*)::integer
    into v_subject_count
  from public.fms_subject_auxiliary_type
  where auxiliary_type_id = v_type.id;

  if v_subject_count > 0 then
    raise exception using
      errcode = '23514',
      message = format('该维度已被 %s 个会计科目引用，请先解除科目辅助核算配置', v_subject_count);
  end if;

  delete from public.fms_auxiliary_type
  where id = v_type.id;

  return v_type;
end;
$function$;

revoke all on function public.delete_fms_auxiliary_type(uuid) from public;
grant execute on function public.delete_fms_auxiliary_type(uuid) to authenticated;

comment on function public.delete_fms_auxiliary_type(uuid)
is '安全删除未被核算项目或会计科目引用的手工辅助核算维度；系统与业务主数据维度受保护。';;
