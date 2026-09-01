create or replace function public.ai_operations_overview(p_days integer default 30)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with params as (
    select least(greatest(coalesce(p_days, 30), 1), 90) as days
  ),
  scoped_runs as (
    select run.*
    from public.ai_run run
    cross join params
    where run.started_at >= current_timestamp - make_interval(days => params.days)
  ),
  totals as (
    select
      count(*)::bigint as total_runs,
      count(*) filter (where status = 'succeeded')::bigint as succeeded_runs,
      count(*) filter (where status = 'failed')::bigint as failed_runs,
      count(*) filter (where status = 'running')::bigint as running_runs,
      coalesce(round(avg(latency_ms) filter (where latency_ms is not null)), 0)::bigint
        as average_latency_ms,
      coalesce(
        round(percentile_cont(0.95) within group (order by latency_ms)
          filter (where latency_ms is not null)),
        0
      )::bigint as p95_latency_ms,
      coalesce(sum(input_tokens), 0)::bigint as input_tokens,
      coalesce(sum(output_tokens), 0)::bigint as output_tokens
    from scoped_runs
  ),
  feedback_totals as (
    select
      count(*) filter (where feedback.rating = 1)::bigint as positive_feedback,
      count(*) filter (where feedback.rating = -1)::bigint as negative_feedback
    from public.ai_feedback feedback
    join scoped_runs run on run.id = feedback.run_id
  ),
  scoped_artifacts as (
    select artifact.*
    from public.ai_artifact_review artifact
    cross join params
    where artifact.create_time >= current_timestamp - make_interval(days => params.days)
  ),
  quality_totals as (
    select
      count(*)::bigint as total_artifacts,
      count(*) filter (where status = 'pending')::bigint as pending_artifacts,
      count(*) filter (where status <> 'pending')::bigint as reviewed_artifacts,
      count(*) filter (where status = 'applied')::bigint as applied_artifacts,
      count(*) filter (where status = 'rejected')::bigint as rejected_artifacts,
      count(*) filter (where status = 'superseded')::bigint as superseded_artifacts,
      coalesce(sum(cardinality(accepted_fields)), 0)::bigint as accepted_fields,
      coalesce(sum(cardinality(corrected_fields)), 0)::bigint as corrected_fields,
      coalesce(round(avg(confidence) filter (where confidence is not null) * 100, 1), 0)
        as average_confidence
    from scoped_artifacts
  ),
  field_events as (
    select field, true as accepted
    from scoped_artifacts artifact
    cross join lateral unnest(artifact.accepted_fields) as field
    where artifact.status = 'applied'
    union all
    select field, false as accepted
    from scoped_artifacts artifact
    cross join lateral unnest(artifact.corrected_fields) as field
    where artifact.status = 'applied'
  ),
  day_series as (
    select generate_series(
      current_date - ((select days from params) - 1),
      current_date,
      interval '1 day'
    )::date as day
  ),
  daily_counts as (
    select
      started_at::date as day,
      count(*)::bigint as total,
      count(*) filter (where status = 'succeeded')::bigint as succeeded,
      count(*) filter (where status = 'failed')::bigint as failed
    from scoped_runs
    group by started_at::date
  ),
  daily_quality as (
    select
      artifact.create_time::date as day,
      count(*)::bigint as total,
      count(*) filter (where artifact.status = 'applied')::bigint as applied,
      count(*) filter (where artifact.status = 'rejected')::bigint as rejected,
      coalesce(sum(cardinality(artifact.accepted_fields)), 0)::bigint as accepted_fields,
      coalesce(sum(cardinality(artifact.corrected_fields)), 0)::bigint as corrected_fields
    from scoped_artifacts artifact
    group by artifact.create_time::date
  )
  select jsonb_build_object(
    'days', params.days,
    'totalRuns', totals.total_runs,
    'succeededRuns', totals.succeeded_runs,
    'failedRuns', totals.failed_runs,
    'runningRuns', totals.running_runs,
    'successRate', case
      when totals.total_runs = 0 then 0
      else round(totals.succeeded_runs::numeric * 100 / totals.total_runs, 1)
    end,
    'averageLatencyMs', totals.average_latency_ms,
    'p95LatencyMs', totals.p95_latency_ms,
    'inputTokens', totals.input_tokens,
    'outputTokens', totals.output_tokens,
    'positiveFeedback', feedback_totals.positive_feedback,
    'negativeFeedback', feedback_totals.negative_feedback,
    'dailyTrend', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'date', day_series.day,
          'total', coalesce(daily_counts.total, 0),
          'succeeded', coalesce(daily_counts.succeeded, 0),
          'failed', coalesce(daily_counts.failed, 0)
        )
        order by day_series.day
      )
      from day_series
      left join daily_counts on daily_counts.day = day_series.day
    ), '[]'::jsonb),
    'featureBreakdown', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'feature', feature_stats.feature,
          'total', feature_stats.total,
          'succeeded', feature_stats.succeeded,
          'failed', feature_stats.failed,
          'averageLatencyMs', feature_stats.average_latency_ms
        )
        order by feature_stats.total desc, feature_stats.feature
      )
      from (
        select
          feature,
          count(*)::bigint as total,
          count(*) filter (where status = 'succeeded')::bigint as succeeded,
          count(*) filter (where status = 'failed')::bigint as failed,
          coalesce(round(avg(latency_ms) filter (where latency_ms is not null)), 0)::bigint
            as average_latency_ms
        from scoped_runs
        group by feature
      ) feature_stats
    ), '[]'::jsonb),
    'topErrors', coalesce((
      select jsonb_agg(
        jsonb_build_object('code', error_stats.error_code, 'count', error_stats.total)
        order by error_stats.total desc, error_stats.error_code
      )
      from (
        select coalesce(error_code, 'unknown_error') as error_code, count(*)::bigint as total
        from scoped_runs
        where status = 'failed'
        group by coalesce(error_code, 'unknown_error')
        order by total desc
        limit 5
      ) error_stats
    ), '[]'::jsonb),
    'quality', jsonb_build_object(
      'totalArtifacts', quality_totals.total_artifacts,
      'pendingArtifacts', quality_totals.pending_artifacts,
      'reviewedArtifacts', quality_totals.reviewed_artifacts,
      'appliedArtifacts', quality_totals.applied_artifacts,
      'rejectedArtifacts', quality_totals.rejected_artifacts,
      'supersededArtifacts', quality_totals.superseded_artifacts,
      'reviewCompletionRate', case
        when quality_totals.total_artifacts = 0 then 0
        else round(
          quality_totals.reviewed_artifacts::numeric * 100 / quality_totals.total_artifacts,
          1
        )
      end,
      'applicationRate', case
        when quality_totals.total_artifacts = 0 then 0
        else round(
          quality_totals.applied_artifacts::numeric * 100 / quality_totals.total_artifacts,
          1
        )
      end,
      'acceptedFields', quality_totals.accepted_fields,
      'correctedFields', quality_totals.corrected_fields,
      'fieldAcceptanceRate', case
        when quality_totals.accepted_fields + quality_totals.corrected_fields = 0 then 0
        else round(
          quality_totals.accepted_fields::numeric * 100
            / (quality_totals.accepted_fields + quality_totals.corrected_fields),
          1
        )
      end,
      'averageConfidence', quality_totals.average_confidence,
      'dailyTrend', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'date', day_series.day,
            'total', coalesce(daily_quality.total, 0),
            'applied', coalesce(daily_quality.applied, 0),
            'rejected', coalesce(daily_quality.rejected, 0),
            'acceptedFields', coalesce(daily_quality.accepted_fields, 0),
            'correctedFields', coalesce(daily_quality.corrected_fields, 0)
          )
          order by day_series.day
        )
        from day_series
        left join daily_quality on daily_quality.day = day_series.day
      ), '[]'::jsonb),
      'fieldQuality', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'field', field_stats.field,
            'total', field_stats.total,
            'accepted', field_stats.accepted,
            'corrected', field_stats.corrected,
            'acceptanceRate', case
              when field_stats.total = 0 then 0
              else round(field_stats.accepted::numeric * 100 / field_stats.total, 1)
            end
          )
          order by field_stats.corrected desc, field_stats.total desc, field_stats.field
        )
        from (
          select
            field,
            count(*)::bigint as total,
            count(*) filter (where accepted)::bigint as accepted,
            count(*) filter (where not accepted)::bigint as corrected
          from field_events
          group by field
          order by corrected desc, total desc, field
          limit 12
        ) field_stats
      ), '[]'::jsonb)
    )
  )
  from params
  cross join totals
  cross join feedback_totals
  cross join quality_totals;
$$;

comment on function public.ai_operations_overview(integer) is
  'Returns RLS-scoped AI operations and human-reviewed artifact quality metrics.';

revoke all on function public.ai_operations_overview(integer) from public, anon;
grant execute on function public.ai_operations_overview(integer) to authenticated, service_role;;
