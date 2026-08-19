import{F as e}from"./common-utils-DuvYmpmd.js";import{Wt as t}from"./user-BHm-7B54.js";import{t as n}from"./tree-BgtYkuXW.js";import{i as r}from"./query-B8aDij0r.js";var i=new n({idKey:`id`,parentKey:`parentId`,childrenKey:`children`}),{supabase:a,keysToSnakeDeep:o,responseHandle:s}=t(),c=`
  *,
  tenant:sys_tenant!hr_employee_tenant_fkey(id, tenant_code, tenant_name),
  organization:sys_organization!hr_employee_organization_fkey(
    id,
    organization_code,
    organization_name
  ),
  account:sys_user!sys_user_hr_employee_tenant_fkey(id, user_email, status)
`,l=e=>({...e,account:Array.isArray(e.account)?e.account[0]??null:e.account??null}),u=e=>e?.map(l)??null,d=(e,t)=>{let{tenantId:n,organizationId:r,organizationIds:i,organizationUnassigned:a,employmentStatus:o,employmentType:s,keyword:c,hireDateRange:l,recordId:u}=t;u&&(e=e.eq(`id`,u)),n&&(e=e.eq(`tenant_id`,n)),a?e=e.is(`organization_id`,null):i?.length?e=e.in(`organization_id`,i):r&&(e=e.eq(`organization_id`,r)),o&&(e=e.eq(`employment_status`,o)),s&&(e=e.eq(`employment_type`,s)),l?.[0]&&(e=e.gte(`hire_date`,l[0])),l?.[1]&&(e=e.lte(`hire_date`,l[1]));let d=c?.trim();return d&&(e=e.or(`employee_no.ilike.%${d}%,employee_name.ilike.%${d}%,phone.ilike.%${d}%,email.ilike.%${d}%,id_card_no.ilike.%${d}%,job_title.ilike.%${d}%`)),e};async function f(e,t){let{from:n=0,to:i=9}=e,o=a.from(`hr_employee`).select(c,{count:`exact`}).order(`employment_status`,{ascending:!0}).order(`hire_date`,{ascending:!1,nullsFirst:!1}).order(`create_time`,{ascending:!1}).range(n,i);o=d(o,e);let l=await s(()=>r(o,t),{ignoreCheck:!0,showErrorMessage:!0});return{...l,data:u(l.data)}}async function p(e,t){let{tenantId:n,keyword:i,from:o=0,to:c=9}=e,l=a.from(`hr_employee`).select(`
        id,
        tenant_id,
        organization_id,
        employee_no,
        employee_name,
        avatar_url,
        job_title,
        employment_status,
        gender,
        phone,
        email,
        organization:sys_organization!hr_employee_organization_fkey(
          id,
          organization_code,
          organization_name
        ),
        account:sys_user!sys_user_hr_employee_tenant_fkey()
      `,{count:`exact`}).in(`employment_status`,[`probation`,`active`]).is(`account`,null).order(`employee_name`,{ascending:!0}).range(o,c);n&&(l=l.eq(`tenant_id`,n));let u=i?.trim();return u&&(l=l.or(`employee_no.ilike.%${u}%,employee_name.ilike.%${u}%,phone.ilike.%${u}%,email.ilike.%${u}%,job_title.ilike.%${u}%`)),await s(()=>r(l,t),{ignoreCheck:!0,showErrorMessage:!0})}async function m(t){let n=e(t,[`id`,`tenant`,`organization`,`account`,`createBy`,`createTime`,`updateBy`,`updateTime`]);return await s(()=>a.from(`hr_employee`).insert(o(n)).select(`id`).single(),{showMessage:!0,message:`员工档案已创建`,breakReturn:!0})}async function h(t){let{id:n}=t;if(!n)throw Error(`未找到需要编辑的员工档案`);let r=e(t,[`id`,`tenantId`,`tenant`,`organization`,`account`,`createBy`,`createTime`,`updateBy`,`updateTime`]);return await s(()=>a.from(`hr_employee`).update(o(r),{count:`exact`}).eq(`id`,n),{showMessage:!0,message:`员工档案已更新`,breakReturn:!0,requireAffected:!0,noAffectedMessage:`员工档案不存在，或当前账号没有编辑权限`})}async function g(e){return await s(()=>a.from(`hr_employee`).delete({count:`exact`}).eq(`id`,e),{showMessage:!0,message:`员工档案已删除`,breakReturn:!0,requireAffected:!0,noAffectedMessage:`员工档案不存在，或当前账号没有删除权限`})}async function _(e={}){if(!e.tenantId)return{data:[],error:null};let t=a.from(`sys_organization`).select(`
        id, tenant_id, parent_id, organization_code, organization_name,
        organization_type, status, sort, is_system,
        employees:hr_employee!hr_employee_organization_fkey(id)
      `).eq(`tenant_id`,e.tenantId).eq(`status`,`1`).order(`sort`,{ascending:!0}).order(`organization_name`,{ascending:!0}),n=await s(()=>t,{ignoreCheck:!0,showErrorMessage:!0});return{...n,data:i.listToTree((n.data??[]).map(({employees:e,...t})=>({...t,scopeCount:e?.length??0})),(e,t)=>(e.sort??0)-(t.sort??0)||e.organizationName.localeCompare(t.organizationName,`zh-CN`))}}var v=async(e,t,n)=>(await s(()=>a.from(e).select(`*`).eq(`employee_id`,t).order(n,{ascending:!1,nullsFirst:!1}).order(`create_time`,{ascending:!1}),{ignoreCheck:!0,showErrorMessage:!0})).data??[];async function y(e){let t=(await f({recordId:e,from:0,to:0})).data?.[0];if(!t)return null;let[n,r,i,a,o]=await Promise.all([v(`hr_employee_contract`,e,`start_date`),v(`hr_employee_education`,e,`start_date`),v(`hr_employee_work_experience`,e,`start_date`),v(`hr_employee_training`,e,`start_date`),v(`hr_employee_reward`,e,`record_date`)]);return{...t,contracts:n,educations:r,workExperiences:i,trainings:a,rewards:o}}var b=async(t,n,r,i)=>{if(await s(()=>a.from(t).delete().eq(`employee_id`,n),{breakReturn:!0}),!i.length)return;let c=i.map(t=>o({...e(t,[`id`,`tenantId`,`employeeId`,`employee`,`createBy`,`createTime`,`updateBy`,`updateTime`]),employeeId:n,...r?{tenantId:r}:{}}));await s(()=>a.from(t).insert(c),{breakReturn:!0})};async function x(e){let t=e.employee.id;if(t?await h(e.employee):t=(await m(e.employee)).data?.id,!t)throw Error(`保存员工基础档案后未返回员工 ID`);return await b(`hr_employee_contract`,t,e.employee.tenantId,e.contracts),await b(`hr_employee_education`,t,e.employee.tenantId,e.educations),await b(`hr_employee_work_experience`,t,e.employee.tenantId,e.workExperiences),await b(`hr_employee_training`,t,e.employee.tenantId,e.trainings),await b(`hr_employee_reward`,t,e.employee.tenantId,e.rewards),t}export{p as a,y as i,f as n,x as o,_ as r,g as t};