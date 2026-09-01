-- The RBAC policies include platform-super through app_private.has_permission(),
-- so the former parallel super-only policies are redundant.

drop policy if exists fms_subject_platform_insert on public.fms_subject;
drop policy if exists fms_subject_platform_update on public.fms_subject;

drop policy if exists fms_auxiliary_type_platform_insert on public.fms_auxiliary_type;
drop policy if exists fms_auxiliary_type_platform_update on public.fms_auxiliary_type;
drop policy if exists fms_auxiliary_type_platform_delete on public.fms_auxiliary_type;

drop policy if exists fms_auxiliary_item_platform_insert on public.fms_auxiliary_item;
drop policy if exists fms_auxiliary_item_platform_update on public.fms_auxiliary_item;

drop policy if exists fms_currency_platform_insert on public.fms_currency;
drop policy if exists fms_currency_platform_update on public.fms_currency;

drop policy if exists fms_exchange_rate_platform_insert on public.fms_exchange_rate;
drop policy if exists fms_exchange_rate_platform_update on public.fms_exchange_rate;

drop policy if exists fms_opening_balance_platform_delete on public.fms_opening_balance;

;
