-- Model-backed OCR features must be explicitly enabled per tenant after pilot acceptance.
-- Existing tenant settings are authoritative and are never overwritten by this seed.
with feature_defaults (
  feature,
  description,
  max_tokens
) as (
  values
    ('invoice_ocr', '发票图片识别并生成待人工确认草稿', 1200),
    ('waybill_receipt_ocr', '签收回单识别、异常提示并生成待人工确认草稿', 1400),
    ('cash_voucher_ocr', '收付款凭证识别并推荐待人工确认的对账单', 1400)
),
platform_model as (
  select
    config.provider,
    config.model,
    coalesce(config.vision_model, config.model) as vision_model,
    config.fallback_model
  from public.ai_feature_config config
  join public.sys_tenant tenant on tenant.id = config.tenant_id
  where tenant.tenant_code = 'platform'
    and config.feature = 'order_extraction'
  limit 1
),
tenant_models as (
  select
    tenant.id as tenant_id,
    coalesce(tenant_config.provider, platform_model.provider, 'openai_compatible') as provider,
    coalesce(tenant_config.model, platform_model.model, 'gpt-4.1-mini') as model,
    coalesce(
      tenant_config.vision_model,
      tenant_config.model,
      platform_model.vision_model,
      platform_model.model,
      'gpt-4.1-mini'
    ) as vision_model,
    coalesce(tenant_config.fallback_model, platform_model.fallback_model) as fallback_model
  from public.sys_tenant tenant
  left join public.ai_feature_config tenant_config
    on tenant_config.tenant_id = tenant.id
   and tenant_config.feature = 'order_extraction'
  left join platform_model on true
  where tenant.status = '1'
)
insert into public.ai_feature_config (
  tenant_id,
  feature,
  enabled,
  provider,
  model,
  vision_model,
  fallback_model,
  timeout_ms,
  max_retries,
  temperature,
  max_tokens,
  rate_limit_per_minute,
  rate_limit_per_day,
  prompt_version,
  metadata,
  create_by,
  update_by
)
select
  tenant_models.tenant_id,
  feature_defaults.feature,
  false,
  tenant_models.provider,
  tenant_models.model,
  tenant_models.vision_model,
  tenant_models.fallback_model,
  60000,
  0,
  0,
  feature_defaults.max_tokens,
  6,
  100,
  'v1',
  jsonb_build_object(
    'description', feature_defaults.description,
    'rollout', 'pilot',
    'requires_human_review', true,
    'write_mode', 'draft_only',
    'seeded_by', '20260806023036_seed_controlled_ai_ocr_feature_configs'
  ),
  'codex',
  'codex'
from tenant_models
cross join feature_defaults
on conflict (tenant_id, feature) do nothing;;
