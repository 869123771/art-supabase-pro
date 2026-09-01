create index if not exists idx_receipt_exception_assignee on public.tms_receipt_exception_work_order(assignee_id) where assignee_id is not null;
create index if not exists idx_receipt_exception_resolved_by on public.tms_receipt_exception_work_order(resolved_by) where resolved_by is not null;
create index if not exists idx_receipt_exception_closed_by on public.tms_receipt_exception_work_order(closed_by) where closed_by is not null;
create index if not exists idx_receipt_exception_cancelled_by on public.tms_receipt_exception_work_order(cancelled_by) where cancelled_by is not null;

drop policy if exists receipt_exception_controlled_write on public.tms_receipt_exception_work_order;
drop policy if exists receipt_exception_select on public.tms_receipt_exception_work_order;
create policy receipt_exception_select on public.tms_receipt_exception_work_order for select to authenticated
using ((select app_private.is_platform_super()) or tenant_id = (select app_private.current_user_tenant_id()));
create policy receipt_exception_insert on public.tms_receipt_exception_work_order for insert to authenticated
with check ((select app_private.is_platform_super()));
create policy receipt_exception_update on public.tms_receipt_exception_work_order for update to authenticated
using ((select app_private.is_platform_super())) with check ((select app_private.is_platform_super()));
create policy receipt_exception_delete on public.tms_receipt_exception_work_order for delete to authenticated
using ((select app_private.is_platform_super()));

drop policy if exists ai_ocr_quality_threshold_controlled_write on public.ai_ocr_quality_threshold;
drop policy if exists ai_ocr_quality_threshold_select on public.ai_ocr_quality_threshold;
create policy ai_ocr_quality_threshold_select on public.ai_ocr_quality_threshold for select to authenticated
using ((select app_private.is_platform_super()) or tenant_id = (select app_private.current_user_tenant_id()));
create policy ai_ocr_quality_threshold_insert on public.ai_ocr_quality_threshold for insert to authenticated
with check ((select app_private.is_platform_super()));
create policy ai_ocr_quality_threshold_update on public.ai_ocr_quality_threshold for update to authenticated
using ((select app_private.is_platform_super())) with check ((select app_private.is_platform_super()));
create policy ai_ocr_quality_threshold_delete on public.ai_ocr_quality_threshold for delete to authenticated
using ((select app_private.is_platform_super()));

;
