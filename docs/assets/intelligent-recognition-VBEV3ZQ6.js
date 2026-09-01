import{en as e}from"./user-CeudZSXX.js";import{t}from"./query-B8aDij0r.js";var{supabase:n,responseHandle:r}=e(),i=`
  *,
  run:ai_run!ai_artifact_review_ai_run_id_fkey(
    id,
    model,
    status,
    latency_ms,
    error_code,
    error_message,
    metadata,
    started_at,
    finished_at
  )
`;function a(e,n){return n.artifactId&&(e=e.eq(`id`,n.artifactId)),n.feature&&(e=e.eq(`feature`,n.feature)),n.status&&(e=e.eq(`status`,n.status)),n.creator&&(e=e.ilike(`create_by`,`%${n.creator.trim()}%`)),n.confidenceLevel===`low`&&(e=e.lt(`confidence`,.65)),n.confidenceLevel===`medium`&&(e=e.gte(`confidence`,.65).lt(`confidence`,.85)),n.confidenceLevel===`high`&&(e=e.gte(`confidence`,.85)),t(e,n.createTimeRange)}async function o(e){let{from:t=0,to:o=9}=e,s=n.from(`ai_artifact_review`).select(i,{count:`exact`}).in(`feature`,[`invoice_ocr`,`waybill_receipt_ocr`,`cash_voucher_ocr`,`waybill_expense_ocr`]);e.sort===`risk`&&(s=s.order(`confidence`,{ascending:!0,nullsFirst:!0})),s=s.order(`create_time`,{ascending:!1}).range(t,o);let c=a(s,e);return await r(()=>c,{ignoreCheck:!0,showErrorMessage:!0})}async function s(e){return await r(()=>n.from(`ai_artifact_review`).select(i).eq(`id`,e).single(),{ignoreCheck:!0,showErrorMessage:!0})}async function c(){return await r(()=>n.rpc(`ai_ocr_recognition_overview`),{ignoreCheck:!0,showErrorMessage:!0,convertToCamelShadow:!0})}export{o as n,c as r,s as t};