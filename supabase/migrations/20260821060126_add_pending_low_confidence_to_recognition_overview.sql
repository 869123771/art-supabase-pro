create or replace function public.ai_ocr_recognition_overview()
returns jsonb
language sql
stable
set search_path = ''
as $function$
  with visible_reviews as materialized (
    select
      review.feature,
      review.status,
      review.confidence,
      review.create_time
    from public.ai_artifact_review review
    where review.feature in (
      'invoice_ocr',
      'waybill_receipt_ocr',
      'cash_voucher_ocr',
      'waybill_expense_ocr'
    )
  ),
  summary as (
    select
      count(*) as total,
      count(*) filter (where status = 'pending') as pending,
      count(*) filter (where status = 'applied') as applied,
      count(*) filter (where status = 'rejected') as rejected,
      count(*) filter (where coalesce(confidence, 0) < 0.65) as low_confidence,
      count(*) filter (
        where status = 'pending' and coalesce(confidence, 0) < 0.65
      ) as pending_low_confidence,
      count(*) filter (where create_time >= date_trunc('day', now())) as today,
      coalesce(round(avg(confidence), 4), 0) as avg_confidence
    from visible_reviews
  ),
  feature_stats as (
    select feature, count(*) as feature_count
    from visible_reviews
    group by feature
  )
  select jsonb_build_object(
    'total', summary.total,
    'pending', summary.pending,
    'applied', summary.applied,
    'rejected', summary.rejected,
    'low_confidence', summary.low_confidence,
    'pending_low_confidence', summary.pending_low_confidence,
    'today', summary.today,
    'avg_confidence', summary.avg_confidence,
    'by_feature', coalesce(
      (select jsonb_object_agg(feature, feature_count) from feature_stats),
      '{}'::jsonb
    )
  )
  from summary;
$function$;

comment on function public.ai_ocr_recognition_overview() is
  'Returns tenant- and owner-scoped OCR recognition metrics, including the pending low-confidence workload.';;
