begin;

create or replace function public.smis_save_exam_draft(
  p_attempt_id uuid,
  p_answers jsonb
)
returns public.smis_exam_attempt
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := app_private.smis_current_user_id();
  v_tenant_id uuid := app_private.smis_current_tenant_id();
  v_result public.smis_exam_attempt;
begin
  if v_user_id is null or v_tenant_id is null then
    raise exception 'Authentication and an active tenant are required';
  end if;
  if not app_private.smis_has_permission('SmisCatalog:TakeExam') then
    raise exception 'Missing permission: SmisCatalog:TakeExam';
  end if;
  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then
    raise exception 'Exam answers must be a JSON object';
  end if;

  update public.smis_exam_attempt target
  set answers = p_answers
  where target.id = p_attempt_id
    and target.tenant_id = v_tenant_id
    and target.user_id = v_user_id
    and target.status = 'in_progress'
  returning * into v_result;

  if v_result.id is null then
    raise exception 'The active exam attempt was not found';
  end if;
  return v_result;
end;
$$;

revoke all on function public.smis_save_exam_draft(uuid, jsonb) from public, anon;
grant execute on function public.smis_save_exam_draft(uuid, jsonb) to authenticated, service_role;

commit;;
