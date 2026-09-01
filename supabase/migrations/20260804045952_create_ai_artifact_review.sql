begin;

create table public.ai_artifact_review (
  id uuid primary key default gen_random_uuid(),
  ai_run_id uuid not null references public.ai_run(id) on delete restrict,
  auth_user_id uuid not null,
  feature text not null,
  artifact_type text not null,
  status text not null default 'pending',
  proposed_payload jsonb not null,
  final_payload jsonb not null default '{}'::jsonb,
  confidence numeric(5, 4),
  field_confidence jsonb not null default '{}'::jsonb,
  warnings text[] not null default '{}'::text[],
  accepted_fields text[] not null default '{}'::text[],
  corrected_fields text[] not null default '{}'::text[],
  entity_type text,
  entity_id uuid,
  review_note text,
  reviewed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  constraint ai_artifact_review_run_unique unique (ai_run_id),
  constraint ai_artifact_review_feature_check check (feature <> ''),
  constraint ai_artifact_review_type_check check (artifact_type <> ''),
  constraint ai_artifact_review_status_check check (
    status in ('pending', 'applied', 'rejected', 'superseded')
  ),
  constraint ai_artifact_review_confidence_check check (
    confidence is null or confidence between 0 and 1
  ),
  constraint ai_artifact_review_applied_entity_check check (
    status <> 'applied'
    or (entity_type is not null and entity_id is not null and final_payload <> '{}'::jsonb)
  )
);

comment on table public.ai_artifact_review is
  'Tenant-scoped AI proposal and human final-result comparison used for quality evaluation.';
comment on column public.ai_artifact_review.proposed_payload is
  'Normalized AI proposal. It is immutable after creation and is not the authoritative business record.';
comment on column public.ai_artifact_review.final_payload is
  'Human-confirmed comparable payload captured only after the authoritative business write succeeds.';

create index ai_artifact_review_pending_idx
  on public.ai_artifact_review (tenant_id, auth_user_id, feature, artifact_type, create_time desc)
  where status = 'pending';
create index ai_artifact_review_user_status_created_idx
  on public.ai_artifact_review (tenant_id, auth_user_id, status, create_time desc);
create index ai_artifact_review_entity_idx
  on public.ai_artifact_review (tenant_id, entity_type, entity_id)
  where entity_id is not null;

create or replace function app_private.trg_validate_ai_artifact_review_transition()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.ai_run_id is distinct from old.ai_run_id
    or new.auth_user_id is distinct from old.auth_user_id
    or new.tenant_id is distinct from old.tenant_id
    or new.feature is distinct from old.feature
    or new.artifact_type is distinct from old.artifact_type
    or new.proposed_payload is distinct from old.proposed_payload
    or new.confidence is distinct from old.confidence
    or new.field_confidence is distinct from old.field_confidence
    or new.warnings is distinct from old.warnings
    or new.metadata is distinct from old.metadata then
    raise exception 'AI artifact proposal fields are immutable';
  end if;

  if old.status <> new.status then
    if old.status <> 'pending' or new.status not in ('applied', 'rejected', 'superseded') then
      raise exception 'Invalid AI artifact review transition: % -> %', old.status, new.status;
    end if;
  elsif old.status = 'pending' and (
    new.final_payload is distinct from old.final_payload
    or new.accepted_fields is distinct from old.accepted_fields
    or new.corrected_fields is distinct from old.corrected_fields
    or new.entity_type is distinct from old.entity_type
    or new.entity_id is distinct from old.entity_id
    or new.review_note is distinct from old.review_note
    or new.reviewed_at is distinct from old.reviewed_at
  ) then
    raise exception 'Review fields can only change while completing a pending AI artifact';
  elsif old.status <> 'pending' and (
    new.final_payload is distinct from old.final_payload
    or new.accepted_fields is distinct from old.accepted_fields
    or new.corrected_fields is distinct from old.corrected_fields
    or new.entity_type is distinct from old.entity_type
    or new.entity_id is distinct from old.entity_id
    or new.review_note is distinct from old.review_note
    or new.reviewed_at is distinct from old.reviewed_at
  ) then
    raise exception 'Completed AI artifact reviews are immutable';
  end if;

  if new.status in ('applied', 'rejected') and new.reviewed_at is null then
    new.reviewed_at := now();
  end if;

  return new;
end;
$$;

revoke all on function app_private.trg_validate_ai_artifact_review_transition() from public;

create trigger ai_artifact_review_validate_transition
before update on public.ai_artifact_review
for each row
execute function app_private.trg_validate_ai_artifact_review_transition();

create trigger ai_artifact_review_create_audit
before insert on public.ai_artifact_review
for each row
execute function public.trg_set_create_time_and_by('true', 'true');

create trigger ai_artifact_review_update_audit
before update on public.ai_artifact_review
for each row
execute function public.trg_set_update_time_and_by();

alter table public.ai_artifact_review enable row level security;

create policy ai_artifact_review_tenant_select
on public.ai_artifact_review
for select
to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and auth_user_id = (select auth.uid())
  )
);

-- Writes are intentionally service-managed by the authenticated AI Edge Function.
-- Authenticated clients only receive SELECT; no INSERT/UPDATE/DELETE policy is created.
revoke all on table public.ai_artifact_review from anon, authenticated;
grant select on table public.ai_artifact_review to authenticated;

commit;;
