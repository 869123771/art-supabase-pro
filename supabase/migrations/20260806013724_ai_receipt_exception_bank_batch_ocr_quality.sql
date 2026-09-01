-- AI receipt exception workflow, bank statement batch matching and OCR quality operations.

create sequence if not exists public.tms_receipt_exception_work_order_no_seq;

create table if not exists public.tms_receipt_exception_work_order (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id() references public.sys_tenant(id),
  work_order_no text not null default ('RE' || to_char(current_date, 'YYYYMMDD') || '-' || lpad(nextval('public.tms_receipt_exception_work_order_no_seq')::text, 6, '0')),
  order_id uuid not null references public.tms_order(id),
  ai_artifact_review_id uuid not null unique references public.ai_artifact_review(id),
  order_no_snapshot text not null,
  severity text not null check (severity in ('low', 'medium', 'high', 'critical')),
  status text not null default 'pending' check (status in ('pending', 'in_progress', 'resolved', 'closed', 'cancelled')),
  exception_types text[] not null default '{}',
  summary text not null,
  evidence_urls jsonb not null default '[]'::jsonb check (jsonb_typeof(evidence_urls) = 'array'),
  assignee_id uuid references public.sys_user(id),
  started_at timestamptz,
  due_at timestamptz not null,
  resolution_note text,
  resolved_at timestamptz,
  resolved_by uuid references public.sys_user(id),
  closed_at timestamptz,
  closed_by uuid references public.sys_user(id),
  cancel_reason text,
  cancelled_at timestamptz,
  cancelled_by uuid references public.sys_user(id),
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  unique (tenant_id, work_order_no)
);

comment on table public.tms_receipt_exception_work_order is 'AI 签收回单异常人工处置工单';
create index if not exists idx_receipt_exception_tenant_status on public.tms_receipt_exception_work_order(tenant_id, status, due_at);
create index if not exists idx_receipt_exception_order on public.tms_receipt_exception_work_order(order_id, create_time desc);

create table if not exists public.ai_ocr_quality_threshold (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id() references public.sys_tenant(id),
  feature text not null check (feature in ('invoice_ocr', 'waybill_receipt_ocr', 'cash_voucher_ocr', 'bank_statement_batch_match')),
  review_confidence_threshold numeric(4,3) not null default 0.820 check (review_confidence_threshold between 0.500 and 0.990),
  change_reason text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  unique (tenant_id, feature)
);

comment on table public.ai_ocr_quality_threshold is '租户级 OCR 人工复核置信度阈值';

drop trigger if exists receipt_exception_create_audit on public.tms_receipt_exception_work_order;
create trigger receipt_exception_create_audit before insert on public.tms_receipt_exception_work_order
for each row execute function public.trg_set_create_time_and_by('true', 'true');
drop trigger if exists receipt_exception_update_audit on public.tms_receipt_exception_work_order;
create trigger receipt_exception_update_audit before update on public.tms_receipt_exception_work_order
for each row execute function public.trg_set_update_time_and_by();
drop trigger if exists ai_ocr_quality_threshold_create_audit on public.ai_ocr_quality_threshold;
create trigger ai_ocr_quality_threshold_create_audit before insert on public.ai_ocr_quality_threshold
for each row execute function public.trg_set_create_time_and_by('true', 'true');
drop trigger if exists ai_ocr_quality_threshold_update_audit on public.ai_ocr_quality_threshold;
create trigger ai_ocr_quality_threshold_update_audit before update on public.ai_ocr_quality_threshold
for each row execute function public.trg_set_update_time_and_by();

alter table public.tms_receipt_exception_work_order enable row level security;
alter table public.ai_ocr_quality_threshold enable row level security;

drop policy if exists receipt_exception_select on public.tms_receipt_exception_work_order;
create policy receipt_exception_select on public.tms_receipt_exception_work_order for select to authenticated
using (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());
drop policy if exists receipt_exception_controlled_write on public.tms_receipt_exception_work_order;
create policy receipt_exception_controlled_write on public.tms_receipt_exception_work_order for all to authenticated
using (app_private.is_platform_super()) with check (app_private.is_platform_super());

drop policy if exists ai_ocr_quality_threshold_select on public.ai_ocr_quality_threshold;
create policy ai_ocr_quality_threshold_select on public.ai_ocr_quality_threshold for select to authenticated
using (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id());
drop policy if exists ai_ocr_quality_threshold_controlled_write on public.ai_ocr_quality_threshold;
create policy ai_ocr_quality_threshold_controlled_write on public.ai_ocr_quality_threshold for all to authenticated
using (app_private.is_platform_super()) with check (app_private.is_platform_super());

revoke all on table public.tms_receipt_exception_work_order from anon;
revoke all on table public.ai_ocr_quality_threshold from anon;
grant select, insert, update on table public.tms_receipt_exception_work_order to authenticated;
grant select, insert, update on table public.ai_ocr_quality_threshold to authenticated;
grant usage, select on sequence public.tms_receipt_exception_work_order_no_seq to authenticated;

insert into public.ai_ocr_quality_threshold (tenant_id, feature, review_confidence_threshold, change_reason, create_by, update_by)
select tenant.id, feature.value, 0.820, '初始化 OCR 人工复核阈值', '624944977@qq.com', '624944977@qq.com'
from public.sys_tenant tenant
cross join (values ('invoice_ocr'), ('waybill_receipt_ocr'), ('cash_voucher_ocr'), ('bank_statement_batch_match')) feature(value)
on conflict (tenant_id, feature) do nothing;

create or replace function public.create_ai_receipt_exception_work_order(
  p_artifact_id uuid,
  p_order_id uuid,
  p_evidence_urls jsonb default '[]'::jsonb
) returns public.tms_receipt_exception_work_order
language plpgsql
set search_path = ''
as $$
declare
  v_artifact public.ai_artifact_review%rowtype;
  v_order public.tms_order%rowtype;
  v_existing public.tms_receipt_exception_work_order%rowtype;
  v_signals jsonb;
  v_risk text;
  v_types text[];
  v_summary text;
  v_result public.tms_receipt_exception_work_order%rowtype;
begin
  if not app_private.is_platform_super() then raise exception '仅平台超级管理员可生成异常工单'; end if;
  if jsonb_typeof(coalesce(p_evidence_urls, '[]'::jsonb)) <> 'array' then raise exception '回单凭证格式无效'; end if;

  select * into v_existing from public.tms_receipt_exception_work_order where ai_artifact_review_id = p_artifact_id;
  if found then return v_existing; end if;

  select * into v_artifact from public.ai_artifact_review
  where id = p_artifact_id and feature = 'waybill_receipt_ocr' and status = 'pending';
  if not found then raise exception 'AI 回单识别记录不存在或已处理'; end if;
  select * into v_order from public.tms_order where id = p_order_id and tenant_id = v_artifact.tenant_id;
  if not found then raise exception '关联运单不存在或无权访问'; end if;
  if coalesce(v_artifact.metadata->>'orderId', '') <> p_order_id::text then raise exception 'AI 回单与运单不匹配'; end if;

  v_signals := coalesce(v_artifact.metadata->'assessment'->'signals', '[]'::jsonb);
  if jsonb_array_length(v_signals) = 0 then raise exception '当前识别结果没有可转工单的异常'; end if;
  v_risk := coalesce(v_artifact.metadata->'assessment'->>'riskLevel', 'medium');
  if v_risk not in ('low','medium','high','critical') then v_risk := 'medium'; end if;
  select coalesce(array_agg(distinct item->>'type') filter (where coalesce(item->>'type','') <> ''), '{}')
  into v_types from jsonb_array_elements(v_signals) item;
  v_summary := coalesce(nullif(v_artifact.metadata->>'summary',''), nullif(v_artifact.proposed_payload->>'exceptionNote',''), 'AI 检测到签收异常，请核对原始回单与运单信息');

  insert into public.tms_receipt_exception_work_order (
    tenant_id, order_id, ai_artifact_review_id, order_no_snapshot, severity, exception_types,
    summary, evidence_urls, due_at
  ) values (
    v_artifact.tenant_id, v_order.id, v_artifact.id, v_order.order_no, v_risk, v_types,
    left(v_summary, 1000), coalesce(p_evidence_urls, '[]'::jsonb), now() + case v_risk
      when 'critical' then interval '4 hours' when 'high' then interval '12 hours'
      when 'medium' then interval '24 hours' else interval '48 hours' end
  ) returning * into v_result;
  return v_result;
end;
$$;

create or replace function public.transition_ai_receipt_exception_work_order(
  p_work_order_id uuid,
  p_next_status text,
  p_note text default null
) returns public.tms_receipt_exception_work_order
language plpgsql
set search_path = ''
as $$
declare
  v_row public.tms_receipt_exception_work_order%rowtype;
  v_user_id uuid := app_private.current_app_user_id();
begin
  if not app_private.is_platform_super() then raise exception '仅平台超级管理员可流转异常工单'; end if;
  select * into v_row from public.tms_receipt_exception_work_order where id = p_work_order_id for update;
  if not found then raise exception '异常工单不存在'; end if;
  if not (
    (v_row.status = 'pending' and p_next_status in ('in_progress','cancelled')) or
    (v_row.status = 'in_progress' and p_next_status in ('resolved','cancelled')) or
    (v_row.status = 'resolved' and p_next_status in ('closed','in_progress'))
  ) then raise exception '不允许的工单状态流转：% -> %', v_row.status, p_next_status; end if;
  if p_next_status in ('resolved','cancelled') and coalesce(length(trim(p_note)),0) < 2 then
    raise exception '解决或取消时必须填写处理说明';
  end if;

  update public.tms_receipt_exception_work_order set
    status = p_next_status,
    assignee_id = case when p_next_status = 'in_progress' then v_user_id else assignee_id end,
    started_at = case when p_next_status = 'in_progress' then coalesce(started_at, now()) else started_at end,
    resolution_note = case when p_next_status = 'resolved' then trim(p_note) else resolution_note end,
    resolved_at = case when p_next_status = 'resolved' then now() when p_next_status = 'in_progress' then null else resolved_at end,
    resolved_by = case when p_next_status = 'resolved' then v_user_id when p_next_status = 'in_progress' then null else resolved_by end,
    closed_at = case when p_next_status = 'closed' then now() else closed_at end,
    closed_by = case when p_next_status = 'closed' then v_user_id else closed_by end,
    cancel_reason = case when p_next_status = 'cancelled' then trim(p_note) else cancel_reason end,
    cancelled_at = case when p_next_status = 'cancelled' then now() else cancelled_at end,
    cancelled_by = case when p_next_status = 'cancelled' then v_user_id else cancelled_by end
  where id = p_work_order_id returning * into v_row;
  return v_row;
end;
$$;

create or replace function public.commit_ai_bank_statement_batch(
  p_artifact_id uuid,
  p_rows jsonb
) returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_artifact public.ai_artifact_review%rowtype;
  v_row jsonb;
  v_transaction_id uuid;
  v_ids uuid[] := '{}';
  v_count integer := 0;
  v_direction text;
  v_reference text;
begin
  if not app_private.is_platform_super() then raise exception '仅平台超级管理员可执行批量入账'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) < 1 or jsonb_array_length(p_rows) > 300 then
    raise exception '请选择 1 至 300 条可入账流水';
  end if;
  select * into v_artifact from public.ai_artifact_review
  where id = p_artifact_id and feature = 'bank_statement_batch_match' and status = 'pending'
    and auth_user_id = auth.uid();
  if not found then raise exception '批量匹配记录不存在、已处理或不属于当前用户'; end if;

  for v_row in select value from jsonb_array_elements(p_rows)
  loop
    v_direction := v_row->>'direction';
    v_reference := nullif(trim(v_row->>'bankReference'), '');
    if v_direction not in ('receipt','payment') or coalesce((v_row->>'amount')::numeric,0) <= 0
      or nullif(v_row->>'counterpartyId','') is null or nullif(v_row->>'transactionDate','') is null then
      raise exception '批次中存在缺少方向、往来单位、日期或金额的流水';
    end if;
    if v_reference is not null and exists (
      select 1 from public.tms_cash_transaction t
      where t.tenant_id = v_artifact.tenant_id and t.direction = v_direction and t.bank_reference = v_reference
    ) then raise exception '银行流水号已入账：%', v_reference; end if;

    if v_direction = 'receipt' then
      v_transaction_id := public.create_tms_customer_receipt(
        (v_row->>'counterpartyId')::uuid, (v_row->>'transactionDate')::date, (v_row->>'amount')::numeric,
        coalesce(nullif(v_row->>'paymentMethod',''),'bank_transfer'), v_reference,
        coalesce(v_row->'voucherUrls','[]'::jsonb), nullif(v_row->>'remark',''), coalesce(v_row->'allocations','[]'::jsonb)
      );
    else
      v_transaction_id := public.create_tms_carrier_payment(
        (v_row->>'counterpartyId')::uuid, (v_row->>'transactionDate')::date, (v_row->>'amount')::numeric,
        coalesce(nullif(v_row->>'paymentMethod',''),'bank_transfer'), v_reference,
        coalesce(v_row->'voucherUrls','[]'::jsonb), nullif(v_row->>'remark',''), coalesce(v_row->'allocations','[]'::jsonb)
      );
    end if;
    v_ids := array_append(v_ids, v_transaction_id);
    v_count := v_count + 1;
  end loop;

  update public.ai_artifact_review set
    status = 'applied', final_payload = jsonb_build_object('transactionIds', to_jsonb(v_ids), 'committedRows', p_rows),
    accepted_fields = array['rows'], corrected_fields = '{}', entity_type = 'tms_cash_transaction_batch',
    review_note = format('批量入账 %s 条银行流水', v_count), reviewed_at = now()
  where id = v_artifact.id;
  return jsonb_build_object('artifactId', v_artifact.id, 'committedCount', v_count, 'transactionIds', to_jsonb(v_ids));
end;
$$;

create or replace function public.ai_ocr_quality_overview(p_days integer default 30)
returns jsonb
language sql
stable
set search_path = ''
as $$
with features(feature, label) as (values
  ('invoice_ocr','发票 OCR'), ('waybill_receipt_ocr','签收回单 OCR'),
  ('cash_voucher_ocr','收付款凭证 OCR'), ('bank_statement_batch_match','银行流水批量匹配')
), scoped as (
  select a.* from public.ai_artifact_review a
  where a.feature in (select feature from features)
    and a.create_time >= now() - make_interval(days => least(greatest(coalesce(p_days,30),1),90))
), stats as (
  select f.feature, f.label,
    count(s.id)::int artifacts,
    count(s.id) filter (where s.status <> 'pending')::int reviewed,
    count(s.id) filter (where s.status = 'applied')::int applied,
    coalesce(round(avg(s.confidence) * 100,1),0) average_confidence,
    coalesce(sum(cardinality(s.accepted_fields)),0)::int accepted_fields,
    coalesce(sum(cardinality(s.corrected_fields)),0)::int corrected_fields
  from features f left join scoped s on s.feature=f.feature group by f.feature,f.label
), enriched as (
  select stats.*, coalesce(t.review_confidence_threshold,0.820) threshold,
    count(s.id) filter (where s.confidence < coalesce(t.review_confidence_threshold,0.820))::int low_confidence
  from stats left join public.ai_ocr_quality_threshold t on t.feature=stats.feature
    and (t.tenant_id=app_private.current_user_tenant_id() or app_private.is_platform_super())
  left join scoped s on s.feature=stats.feature
  group by stats.feature,stats.label,stats.artifacts,stats.reviewed,stats.applied,stats.average_confidence,
    stats.accepted_fields,stats.corrected_fields,t.review_confidence_threshold
)
select jsonb_build_object(
  'days', least(greatest(coalesce(p_days,30),1),90),
  'canManage', app_private.is_platform_super(),
  'totalArtifacts', sum(artifacts),
  'reviewedArtifacts', sum(reviewed),
  'lowConfidenceArtifacts', sum(low_confidence),
  'acceptedFields', sum(accepted_fields),
  'correctedFields', sum(corrected_fields),
  'features', coalesce(jsonb_agg(jsonb_build_object(
    'feature',feature,'label',label,'artifacts',artifacts,'reviewed',reviewed,'applied',applied,
    'averageConfidence',average_confidence,'acceptedFields',accepted_fields,'correctedFields',corrected_fields,
    'acceptanceRate',case when accepted_fields+corrected_fields=0 then 0 else round(accepted_fields*100.0/(accepted_fields+corrected_fields),1) end,
    'threshold',round(threshold*100,1),'lowConfidence',low_confidence,
    'recommendedThreshold',round((case
      when reviewed < 5 then threshold
      when accepted_fields+corrected_fields > 0 and accepted_fields*1.0/(accepted_fields+corrected_fields) < .80 then least(.95,threshold+.05)
      when accepted_fields+corrected_fields > 0 and accepted_fields*1.0/(accepted_fields+corrected_fields) > .95 then greatest(.65,threshold-.03)
      else threshold end)*100,1)
  ) order by feature), '[]'::jsonb)
) from enriched;
$$;

create or replace function public.apply_ai_ocr_quality_threshold(
  p_feature text,
  p_threshold numeric,
  p_reason text
) returns integer
language plpgsql
set search_path = ''
as $$
declare v_count integer;
begin
  if not app_private.is_platform_super() then raise exception '仅平台超级管理员可调整 OCR 阈值'; end if;
  if p_feature not in ('invoice_ocr','waybill_receipt_ocr','cash_voucher_ocr','bank_statement_batch_match') then raise exception '不支持的 OCR 能力'; end if;
  if p_threshold < .5 or p_threshold > .99 then raise exception '阈值必须在 50%% 至 99%% 之间'; end if;
  if coalesce(length(trim(p_reason)),0) < 2 then raise exception '请填写阈值调整原因'; end if;
  insert into public.ai_ocr_quality_threshold(tenant_id,feature,review_confidence_threshold,change_reason)
  select id,p_feature,p_threshold,trim(p_reason) from public.sys_tenant where status='1'
  on conflict (tenant_id,feature) do update set review_confidence_threshold=excluded.review_confidence_threshold,
    change_reason=excluded.change_reason, update_time=now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.create_ai_receipt_exception_work_order(uuid,uuid,jsonb) from public, anon;
revoke all on function public.transition_ai_receipt_exception_work_order(uuid,text,text) from public, anon;
revoke all on function public.commit_ai_bank_statement_batch(uuid,jsonb) from public, anon;
revoke all on function public.ai_ocr_quality_overview(integer) from public, anon;
revoke all on function public.apply_ai_ocr_quality_threshold(text,numeric,text) from public, anon;
grant execute on function public.create_ai_receipt_exception_work_order(uuid,uuid,jsonb) to authenticated;
grant execute on function public.transition_ai_receipt_exception_work_order(uuid,text,text) to authenticated;
grant execute on function public.commit_ai_bank_statement_batch(uuid,jsonb) to authenticated;
grant execute on function public.ai_ocr_quality_overview(integer) to authenticated;
grant execute on function public.apply_ai_ocr_quality_threshold(text,numeric,text) to authenticated;

with feature_type as (
  select id, tenant_id from public.sys_dict_type
  where code='aiRunFeature' and tenant_id=app_private.platform_tenant_id() limit 1
), feature_row(code,value,label,remark,sort,tag_type) as (values
  ('bank_statement_batch_match','bank_statement_batch_match','AI 银行流水批量匹配','批量解析银行流水并推荐往来单位与待核销对账单',79::bigint,'success')
)
insert into public.sys_dictionary(id,type_id,code,status,create_by,update_by,remark,value,label,i18n_scope,sort,tenant_id,tag_type)
select gen_random_uuid(),f.id,r.code,'1','624944977@qq.com','624944977@qq.com',r.remark,r.value,r.label,'1',r.sort,f.tenant_id,r.tag_type
from feature_type f cross join feature_row r
where not exists(select 1 from public.sys_dictionary d where d.type_id=f.id and d.value=r.value and d.tenant_id=f.tenant_id);

;
