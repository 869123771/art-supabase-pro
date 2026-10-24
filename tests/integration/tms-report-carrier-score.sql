BEGIN;
DO $test$
DECLARE actor uuid; rows jsonb;
BEGIN
 SELECT auth_user_id INTO actor FROM public.sys_user WHERE user_roles @> ARRAY['R_SUPER'] AND auth_user_id IS NOT NULL LIMIT 1;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
 PERFORM set_config('request.headers','{}',true);
 rows:=public.tms_management_report('carrier-performance','2026-09-01','2026-09-30','报表验收',0,200)->'records';
 IF jsonb_array_length(rows)<>2 THEN RAISE EXCEPTION 'Carrier acceptance scenarios missing'; END IF;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(rows) j WHERE (j->>'score')::numeric=100 AND (j->>'receipt_rate')::numeric=100 AND j->>'rating'='A') THEN RAISE EXCEPTION 'Good carrier score incorrect'; END IF;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(rows) j WHERE (j->>'score')::numeric=10 AND (j->>'receipt_rate')::numeric=0 AND j->>'rating'='D') THEN RAISE EXCEPTION 'Late carrier score incorrect'; END IF;
 UPDATE public.tms_waybill SET arrived_at=null WHERE id='a9fc0006-1023-4620-9220-000000000001';
 rows:=public.tms_management_report('carrier-performance','2026-09-01','2026-09-30','报表验收',0,200)->'records';
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(rows) j WHERE j->>'carrier_id'='a9fc0002-1023-4620-9220-000000000001' AND j->>'score' IS NULL AND j->>'rating'='待核算') THEN RAISE EXCEPTION 'Missing source incorrectly graded'; END IF;
END $test$;
ROLLBACK;
