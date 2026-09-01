create index if not exists hr_experience_question_tenant_fk_idx
  on public.hr_experience_question(tenant_id);

create index if not exists hr_experience_response_organization_fk_idx
  on public.hr_experience_response(tenant_id, cohort_organization_id);

create index if not exists hr_experience_answer_tenant_fk_idx
  on public.hr_experience_answer(tenant_id);;
