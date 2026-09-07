import{o as e}from"./rolldown-runtime-DAXXjFlN.js";import{an as t}from"./user-DPUaGI2L.js";import{L as n,_ as r}from"./common-utils-BqyWzPML.js";var i=e(r(),1),{supabase:a,keysToSnakeDeep:o,responseHandle:s}=t(),c=`
  id, tenant_id, equipment_code, equipment_name, production_department_id,
  operation_status, status,
  department:mdm_production_department!mdm_equipment_production_department_fkey(
    id, tenant_id, parent_id, department_code:code, department_name:name
  )
`,l=`
  id, tenant_id, task_no, planned_date, shift_name, status, completed_at, execution_summary,
  plan:pmis_plan!pmis_task_plan_fkey!inner(
    id, plan_kind, plan_name, required_days,
    items:pmis_plan_item(id,item_name,requirement,judgment_rule,require_photo,sort)
  ),
  equipment:mdm_equipment!pmis_task_equipment_fkey!inner(${c}),
  responsible:mdm_employee!pmis_task_employee_fkey(id, employee_no, employee_name),
  results:pmis_task_result(
    id, result_status, result_value, photo_files, inspected_at, remark,
    item:pmis_plan_item!pmis_task_result_item_fkey(id, item_name, requirement, judgment_rule, require_photo, sort),
    inspector:mdm_employee!pmis_task_result_employee_fkey(id, employee_no, employee_name)
  )
`,u=e=>e.status===`pending`&&(0,i.default)(e.plannedDate).isBefore((0,i.default)(),`day`)?`overdue`:e.status,d=e=>({...e,displayStatus:u(e)});async function f(){return(await s(()=>a.from(`mdm_production_department`).select(`id,tenant_id,parent_id,department_code:code,department_name:name`).eq(`enabled`,!0).order(`sort`).order(`name`),{showErrorMessage:!0,errorMessage:`部门与产线加载失败，请重试`})).data??[]}async function p(e={}){let t=Math.max(((e.current??1)-1)*(e.size??20),0),n=t+(e.size??20)-1,r=a.from(`mdm_equipment`).select(c,{count:`exact`}).eq(`status`,`enabled`).order(`equipment_code`).range(t,n);e.keyword?.trim()&&(r=r.or(`equipment_code.ilike.%${e.keyword.trim()}%,equipment_name.ilike.%${e.keyword.trim()}%`)),e.departmentId&&(r=r.eq(`production_department_id`,e.departmentId)),e.tenantId&&(r=r.eq(`tenant_id`,e.tenantId));let i=await s(()=>r,{showErrorMessage:!0,errorMessage:`设备列表加载失败，请重试`});return{data:i.data??[],total:i.total??0}}async function m(e,t={}){let n=Math.max(((t.current??1)-1)*(t.size??20),0),r=n+(t.size??20)-1,i=a.from(`pmis_plan`).select(`
        *,
        items:pmis_plan_item(id,item_name,requirement,judgment_rule,require_photo,sort),
        equipment_bindings:pmis_plan_equipment(
          equipment:mdm_equipment!pmis_plan_equipment_equipment_fkey(${c})
        ),
        responsible_bindings:pmis_plan_responsible(
          employee:mdm_employee!pmis_plan_responsible_employee_fkey(
            id, tenant_id, employee_no, employee_name
          )
        )
      `,{count:`exact`}).eq(`plan_kind`,e).order(`update_time`,{ascending:!1}).range(n,r);t.keyword?.trim()&&(i=i.ilike(`plan_name`,`%${t.keyword.trim()}%`)),t.status&&(i=i.eq(`status`,t.status));let o=await s(()=>i,{showErrorMessage:!0,errorMessage:`${e===`inspection`?`点检`:`巡检`}方案加载失败，请重试`});return{data:o.data??[],total:o.total??0}}async function h(e,t){await s(()=>a.rpc(`pmis_save_plan_secure`,{p_id:t??null,p_payload:o(n(e,[`id`]))}),{breakReturn:!0,showMessage:!0,showErrorMessage:!0,message:t?`方案已更新`:`方案已创建`,errorMessage:`方案保存失败，请检查名称、项目和适用设备`})}async function g(e,t){await s(()=>a.rpc(`pmis_delete_plans_secure`,{p_ids:e,p_kind:t}),{breakReturn:!0,showMessage:!0,showErrorMessage:!0,message:`方案已删除`,errorMessage:`方案删除失败，请先解除适用设备或保留已有执行记录`})}async function _(e,t={}){let n=Math.max(((t.current??1)-1)*(t.size??20),0),r=n+(t.size??20)-1,o=a.from(`pmis_task`).select(l,{count:`exact`}).eq(`plan.plan_kind`,e).order(`planned_date`,{ascending:!1}).order(`task_no`).range(n,r);t.keyword?.trim()&&(o=o.ilike(`task_no`,`%${t.keyword.trim()}%`)),t.equipmentId&&(o=o.eq(`equipment_id`,t.equipmentId)),t.departmentIds?.length&&(o=o.in(`equipment.production_department_id`,t.departmentIds)),t.planId&&(o=o.eq(`plan_id`,t.planId)),t.dateFrom&&(o=o.gte(`planned_date`,t.dateFrom)),t.dateTo&&(o=o.lte(`planned_date`,t.dateTo)),t.status===`overdue`?o=o.eq(`status`,`pending`).lt(`planned_date`,(0,i.default)().format(`YYYY-MM-DD`)):t.status===`pending`?o=o.eq(`status`,`pending`).gte(`planned_date`,(0,i.default)().format(`YYYY-MM-DD`)):t.status&&(o=o.eq(`status`,t.status));let c=await s(()=>o,{showErrorMessage:!0,errorMessage:`${e===`inspection`?`点检`:`巡检`}任务加载失败，请重试`}),u=(c.data??[]).map(d);return t.departmentId&&(u=u.filter(e=>e.equipment?.productionDepartmentId===t.departmentId)),{data:u,total:t.departmentId?u.length:c.total??0}}async function v(e,t={}){return(await _(e,{...t,current:1,size:5e3})).data}function y(e){let t=e.filter(e=>e.displayStatus===`completed`).length,n=e.filter(e=>e.displayStatus===`pending`).length,r=e.filter(e=>e.displayStatus===`overdue`).length,i=e.filter(e=>e.displayStatus===`exempt`).length,a=Math.max(e.length-i,0);return{total:e.length,completed:t,pending:n,overdue:r,exempt:i,completionRate:a?Math.round(t/a*1e3)/10:0}}function b(e,t){let n=new Map;return e.forEach(e=>{let r=t===`department`?e.equipment.department?.id||`unassigned`:e.equipment.id;n.set(r,[...n.get(r)??[],e])}),[...n.entries()].map(([e,n])=>{let r=y(n),i=n[0]?.equipment;return{id:e,label:t===`department`?i?.department?.departmentName||`未分配产线`:i?.equipmentName||`未知设备`,description:t===`department`?`${new Set(n.map(e=>e.equipment.id)).size} 台设备`:i?.equipmentCode,...r}}).sort((e,t)=>t.overdue-e.overdue||e.completionRate-t.completionRate)}export{m as a,h as c,p as i,y as l,g as n,v as o,f as r,_ as s,b as t};