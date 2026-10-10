import{Ft as e,ht as t}from"./common-utils-CsmQQMly.js";import{gt as n}from"./sys-BHP3a-WC.js";import{a as r}from"./document-detail-list-DbVuGu-b.js";import{n as i}from"./employees-CW8BgXQj.js";import{Nr as a,zn as o}from"./api-CEKU269C.js";import{t as s}from"./print-document-R2-6iKJq.js";function c(e,t){let[n]=e;if(!n?.id)throw Error(`未找到${t}`);if(e.length!==1)throw Error(`${t}存在多个匹配记录，请核对编号后重新导入`);return n}function l(t,s){let l=n(),u=e(async e=>c((await r(i,{tenantId:t,keyword:e,from:0})).filter(n=>n.tenantId===t&&n.employeeNo===e),`员工工号：${e}`)),d=e(async e=>c((await r(o,{keyword:e,status:`enabled`,from:0})).filter(n=>n.tenantId===t&&n.locationCode===e),`启用仓库编码：${e}`)),f=e(async e=>c((await r(a,{materialCode:e,materialType:s,status:`enabled`,from:0})).filter(n=>n.tenantId===t&&n.materialCode===e),`${s===`tool`?`工器具`:`防护用品`}编码：${e}`));return async e=>{l();let[t,n,r,i]=await Promise.all([u(e.employeeNo),u(e.issuerEmployeeNo),d(e.warehouseCode),f(e.materialCode)]);return l(),{employee:t,issuer:n,warehouse:r,material:i}}}function u(e,n,r){let i=e.items.map((e,n)=>`<tr><td>${n+1}</td><td>${t(e.materialName)}</td><td>${t(e.specificationModel||`—`)}</td><td>${t(String(e.issueQuantity))}</td><td>${t(r(e.unit))}</td><td>${t(e.remark||``)}</td></tr>`).join(``);return`<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <title>${t(e.issuanceNo)}</title>
  <style>
    body { padding: 32px; color: #1f2937; font: 14px/1.5 sans-serif; }
    h1 { text-align: center; font-size: 22px; }
    .meta { display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px 24px; margin: 24px 0; }
    table { width: 100%; border-collapse: collapse; }
    th, td { padding: 9px; border: 1px solid #9ca3af; text-align: left; }
    .sign { display: flex; justify-content: space-between; margin-top: 48px; }
    @media screen and (max-width: 640px) {
      body { padding: 12px; }
      .meta { grid-template-columns: 1fr; }
      table { table-layout: fixed; font-size: 11px; }
      th, td { padding: 4px; overflow-wrap: anywhere; }
      .sign { flex-wrap: wrap; gap: 12px 24px; }
    }
    @media print { body { padding: 0; } }
  </style>
</head>
<body>
  <h1>${n}发放单</h1>
  <div class="meta">
    <span>单据编号：${t(e.issuanceNo)}</span>
    <span>领用人：${t(e.employeeName)}</span>
    <span>员工工号：${t(e.employeeNo)}</span>
    <span>所属组织：${t(e.organizationName||`—`)}</span>
    <span>发放仓库：${t(e.warehouseName)}</span>
    <span>发放日期：${t(e.issueDate)}</span>
  </div>
  <table>
    <thead><tr><th>序号</th><th>${n}</th><th>规格型号</th><th>发放数量</th><th>单位</th><th>备注</th></tr></thead>
    <tbody>${i}</tbody>
  </table>
  <div class="sign">
    <span>领用人签字：____________</span>
    <span>发放人：${t(e.issuerName)}</span>
    <span>日期：____________</span>
  </div>
</body>
</html>`}function d(e,t,n){s(u(e,t,n),`width=980,height=760`)}export{l as n,d as t};