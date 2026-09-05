begin;

create or replace function public.list_menu_management_nodes(
  p_parent_id uuid default null,
  p_name text default null,
  p_path text default null,
  p_record_id uuid default null,
  p_root_only boolean default false,
  p_include_child_state boolean default true
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
  select coalesce(
    jsonb_agg(
      to_jsonb(menu_row)
      || case
        when p_include_child_state then jsonb_build_object(
          'has_children',
          exists (
            select 1
            from public.sys_menu child_row
            where child_row.parent_id = menu_row.id
          )
        )
        else '{}'::jsonb
      end
      order by menu_row.sort nulls last, menu_row.id
    ),
    '[]'::jsonb
  )
  from public.sys_menu menu_row
  where case
      when p_parent_id is not null then menu_row.parent_id = p_parent_id
      when p_root_only then menu_row.parent_id is null
      else true
    end
    and (
      nullif(btrim(p_name), '') is null
      or coalesce(menu_row.meta ->> 'title', '') ilike '%' || btrim(p_name) || '%'
    )
    and (
      nullif(btrim(p_path), '') is null
      or menu_row.path = btrim(p_path)
    )
    and (p_record_id is null or menu_row.id = p_record_id);
$function$;

comment on function public.list_menu_management_nodes(uuid, text, text, uuid, boolean, boolean)
is 'Returns compact menu-management nodes with server-side child state; RLS remains the authorization boundary.';

revoke all on function public.list_menu_management_nodes(uuid, text, text, uuid, boolean, boolean)
from public, anon;
grant execute on function public.list_menu_management_nodes(uuid, text, text, uuid, boolean, boolean)
to authenticated, service_role;

commit;
