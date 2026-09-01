-- Align composite foreign-key indexes with their constraint column order.
-- Existing names are retained where the index also serves the primary read path.

drop index if exists public.smis_violation_record_site_idx;
create index smis_violation_record_site_idx
  on public.smis_violation_record(site_id, tenant_id);
drop index if exists public.smis_violation_record_checker_idx;
create index smis_violation_record_checker_idx
  on public.smis_violation_record(checker_employee_id, tenant_id);
drop index if exists public.smis_violation_record_employee_parent_idx;
create index smis_violation_record_employee_parent_idx
  on public.smis_violation_record_employee(record_id, tenant_id, sort);
drop index if exists public.smis_violation_record_employee_employee_idx;
create index smis_violation_record_employee_employee_idx
  on public.smis_violation_record_employee(employee_id, tenant_id, record_id);
create index if not exists smis_violation_record_employee_tenant_idx
  on public.smis_violation_record_employee(tenant_id);
drop index if exists public.smis_violation_record_item_parent_idx;
create index smis_violation_record_item_parent_idx
  on public.smis_violation_record_item(record_id, tenant_id, sort);
drop index if exists public.smis_violation_record_item_standard_idx;
create index smis_violation_record_item_standard_idx
  on public.smis_violation_record_item(standard_id, tenant_id, record_id);
create index if not exists smis_violation_record_item_tenant_idx
  on public.smis_violation_record_item(tenant_id);
drop index if exists public.smis_announcement_category_idx;
create index smis_announcement_category_idx
  on public.smis_announcement(category_id, tenant_id, lifecycle_status);
create index if not exists smis_announcement_publisher_idx
  on public.smis_announcement(published_by_user_id)
  where published_by_user_id is not null;
create index if not exists smis_announcement_withdrawer_idx
  on public.smis_announcement(withdrawn_by_user_id)
  where withdrawn_by_user_id is not null;
drop index if exists public.smis_announcement_audience_employee_parent_idx;
create index smis_announcement_audience_employee_parent_idx
  on public.smis_announcement_audience_employee(announcement_id, tenant_id, sort);
drop index if exists public.smis_announcement_audience_employee_employee_idx;
create index smis_announcement_audience_employee_employee_idx
  on public.smis_announcement_audience_employee(employee_id, tenant_id, announcement_id);
create index if not exists smis_announcement_audience_employee_tenant_idx
  on public.smis_announcement_audience_employee(tenant_id);
drop index if exists public.smis_announcement_audience_org_parent_idx;
create index smis_announcement_audience_org_parent_idx
  on public.smis_announcement_audience_organization(announcement_id, tenant_id, sort);
drop index if exists public.smis_announcement_audience_org_org_idx;
create index smis_announcement_audience_org_org_idx
  on public.smis_announcement_audience_organization(tenant_id, organization_id, announcement_id);
drop index if exists public.smis_announcement_receipt_parent_idx;
create index smis_announcement_receipt_parent_idx
  on public.smis_announcement_read_receipt(announcement_id, tenant_id, read_at desc);
create index if not exists smis_announcement_receipt_tenant_idx
  on public.smis_announcement_read_receipt(tenant_id);
