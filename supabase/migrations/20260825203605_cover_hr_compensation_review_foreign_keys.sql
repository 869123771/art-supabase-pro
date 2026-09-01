-- Cover every compensation review foreign key with a matching leading index.

create index hr_compensation_review_budget_tenant_idx
  on public.hr_compensation_review_budget(tenant_id);

create index hr_compensation_review_item_tenant_idx
  on public.hr_compensation_review_item(tenant_id);

create index hr_compensation_review_item_grade_idx
  on public.hr_compensation_review_item(current_grade_id, tenant_id)
  where current_grade_id is not null;

create index hr_compensation_review_item_new_compensation_idx
  on public.hr_compensation_review_item(new_compensation_id, tenant_id)
  where new_compensation_id is not null;

create index hr_employee_compensation_source_review_item_idx
  on public.hr_employee_compensation(source_review_item_id, tenant_id)
  where source_review_item_id is not null;


;
