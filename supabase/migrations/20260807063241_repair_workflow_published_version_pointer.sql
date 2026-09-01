-- Data-modifying CTEs share one snapshot, so the initial seed update could not see
-- definitions inserted earlier in the same statement. Repair the published pointer
-- and assert that every published definition is executable.
with latest_published as (
  select distinct on (v.definition_id)
    v.definition_id,
    v.id as version_id,
    v.published_at,
    v.published_by
  from public.wf_version v
  where v.status = 'published'
  order by v.definition_id, v.version_no desc
)
update public.wf_definition d
set current_version_id = latest_published.version_id,
    published_at = coalesce(d.published_at, latest_published.published_at, now()),
    published_by = coalesce(d.published_by, latest_published.published_by)
from latest_published
where d.id = latest_published.definition_id
  and d.status = 'published'
  and d.current_version_id is null;
do $$
begin
  if exists (
    select 1
    from public.wf_definition d
    where d.status = 'published' and d.current_version_id is null
  ) then
    raise exception '存在缺少当前版本的已发布审批流程';
  end if;
end;
$$;
