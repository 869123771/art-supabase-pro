begin;

create index if not exists smis_personnel_certificate_employee_fk_idx
  on public.smis_personnel_certificate (employee_id, tenant_id);

create index if not exists smis_certificate_item_catalog_fk_idx
  on public.smis_personnel_certificate_item (catalog_id, tenant_id);

create index if not exists smis_certificate_item_parent_fk_idx
  on public.smis_personnel_certificate_item (certificate_id, tenant_id);

create index if not exists smis_certificate_review_item_fk_idx
  on public.smis_personnel_certificate_review_history (certificate_item_id, tenant_id);

create index if not exists smis_certificate_review_parent_fk_idx
  on public.smis_personnel_certificate_review_history (certificate_id, tenant_id);

create index if not exists smis_certificate_review_tenant_fk_idx
  on public.smis_personnel_certificate_review_history (tenant_id);

create index if not exists smis_qualification_catalog_parent_fk_idx
  on public.smis_qualification_catalog (parent_id, tenant_id);

commit;;
