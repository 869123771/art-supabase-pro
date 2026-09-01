alter table public.hr_candidate_stage_history
  add column sequence_no integer;

select pg_catalog.set_config('app.hr_recruitment_erasure', 'on', true);
with numbered as (
  select id,
    row_number() over (
      partition by candidate_id order by changed_at, create_time, id
    )::integer as sequence_no
  from public.hr_candidate_stage_history
)
update public.hr_candidate_stage_history history
set sequence_no = numbered.sequence_no
from numbered
where numbered.id = history.id;
select pg_catalog.set_config('app.hr_recruitment_erasure', 'off', true);

alter table public.hr_candidate_stage_history
  alter column sequence_no set not null;
alter table public.hr_candidate_stage_history
  add constraint hr_candidate_stage_history_sequence_unique
  unique (tenant_id, candidate_id, sequence_no);

create or replace function app_private.hr_set_candidate_stage_sequence()
returns trigger language plpgsql security definer set search_path = '' as $function$
begin
  if new.sequence_no is null then
    select coalesce(max(history.sequence_no), 0) + 1
    into new.sequence_no
    from public.hr_candidate_stage_history history
    where history.candidate_id = new.candidate_id;
  end if;
  return new;
end
$function$;

create trigger hr_candidate_stage_history_sequence
before insert on public.hr_candidate_stage_history
for each row execute function app_private.hr_set_candidate_stage_sequence();

revoke all on function app_private.hr_set_candidate_stage_sequence()
from public, anon, authenticated;

;
