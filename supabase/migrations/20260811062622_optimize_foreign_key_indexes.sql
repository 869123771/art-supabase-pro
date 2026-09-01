
create index if not exists idx_ai_run_conversation_id
  on public.ai_run (conversation_id);
create index if not exists idx_tms_waybill_cargo_id
  on public.tms_waybill (cargo_id);
create index if not exists idx_tms_contract_carrier_id
  on public.tms_contract (carrier_id);
create index if not exists idx_tms_waybill_cost_expense_payment_id
  on public.tms_waybill_cost (expense_payment_id);
create index if not exists idx_tms_waybill_cost_reimbursement_id
  on public.tms_waybill_cost (reimbursement_id);
create index if not exists idx_ai_message_auth_user_id
  on public.ai_message (auth_user_id);
create index if not exists idx_sys_document_number_rule_rule_key
  on public.sys_document_number_rule (rule_key);
create index if not exists idx_ai_conversation_auth_user_id
  on public.ai_conversation (auth_user_id);
create index if not exists idx_ai_feedback_resolution_resolved_by
  on public.ai_feedback_resolution (resolved_by);
create index if not exists idx_ai_tool_call_auth_user_id
  on public.ai_tool_call (auth_user_id);
create index if not exists idx_tms_waybill_proof_attachment_id
  on public.tms_waybill_proof (attachment_id);
create index if not exists idx_ai_feedback_auth_user_id
  on public.ai_feedback (auth_user_id);
create index if not exists idx_tms_in_transit_expense_cost_id
  on public.tms_in_transit_expense (cost_id);
create index if not exists idx_tms_in_transit_expense_driver_id
  on public.tms_in_transit_expense (driver_id);
create index if not exists idx_tms_in_transit_expense_latest_ocr_run_id
  on public.tms_in_transit_expense (latest_ocr_run_id);
create index if not exists idx_tms_in_transit_expense_ocr_artifact_id
  on public.tms_in_transit_expense (ocr_artifact_id);
create index if not exists idx_tms_in_transit_expense_order_id
  on public.tms_in_transit_expense (order_id);
create index if not exists idx_tms_in_transit_expense_waybill_id
  on public.tms_in_transit_expense (waybill_id);
create index if not exists idx_tms_expense_reimbursement_applicant_user_id
  on public.tms_expense_reimbursement (applicant_user_id);
create index if not exists idx_tms_expense_reimbursement_item_tenant_id
  on public.tms_expense_reimbursement_item (tenant_id);
create index if not exists idx_tms_expense_reimbursement_item_waybill_id
  on public.tms_expense_reimbursement_item (waybill_id);

drop index if exists public.idx_sys_user_auth_user_id;
;
