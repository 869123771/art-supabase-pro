begin;

-- The RPC performs its own platform-super check and strict scope validation.
-- Definer rights are required because the account-number masker is intentionally
-- private and must not be executable directly by authenticated clients.
alter function public.save_fms_fund_account(jsonb) security definer;

commit;

;
