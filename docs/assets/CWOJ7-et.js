import{ht as e}from"./CWsmOlGP.js";import{bt as t}from"./DSJSvGY3.js";import{a as n}from"./BBHSAUCh.js";import{r}from"./CokjUxmi.js";import{t as i}from"./g3B5Y6Cb.js";import{t as a}from"./BAAH54b_.js";import{Nr as o,zn as s}from"./Cv9SvrRq.js";function c(e,i){let c=t(),l=a(async t=>(await n(r,{tenantId:e,keyword:t,from:0})).filter(n=>n.tenantId===e&&n.employeeNo===t)),u=a(async t=>(await n(s,{keyword:t,status:`enabled`,from:0})).filter(n=>n.tenantId===e&&n.locationCode===t)),d=a(async t=>(await n(o,{materialCode:t,materialType:i,status:`enabled`,from:0})).filter(n=>n.tenantId===e&&n.materialCode===t));return async e=>{c();let[t,n,r,a]=await Promise.all([l(e.employeeNo,`员工工号：${e.employeeNo}`),l(e.issuerEmployeeNo,`员工工号：${e.issuerEmployeeNo}`),u(e.warehouseCode,`启用仓库编码：${e.warehouseCode}`),d(e.materialCode,`${i===`tool`?`工器具`:`防护用品`}编码：${e.materialCode}`)]);return c(),{employee:t,issuer:n,warehouse:r,material:a}}}function l(t,n,r){let i=t.items.map((t,n)=>`<tr><td>${n+1}</td><td>${e(t.materialName)}</td><td>${e(t.specificationModel||`—`)}</td><td>${e(String(t.issueQuantity))}</td><td>${e(r(t.unit))}</td><td>${e(t.remark||``)}</td></tr>`).join(``);return`<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <title>${e(t.issuanceNo)}</title>
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
    <span>单据编号：${e(t.issuanceNo)}</span>
    <span>领用人：${e(t.employeeName)}</span>
    <span>员工工号：${e(t.employeeNo)}</span>
    <span>所属组织：${e(t.organizationName||`—`)}</span>
    <span>发放仓库：${e(t.warehouseName)}</span>
    <span>发放日期：${e(t.issueDate)}</span>
  </div>
  <table>
    <thead><tr><th>序号</th><th>${n}</th><th>规格型号</th><th>发放数量</th><th>单位</th><th>备注</th></tr></thead>
    <tbody>${i}</tbody>
  </table>
  <div class="sign">
    <span>领用人签字：____________</span>
    <span>发放人：${e(t.issuerName)}</span>
    <span>日期：____________</span>
  </div>
</body>
</html>`}function u(e,t,n){i(l(e,t,n),`width=980,height=760`)}export{c as n,u as t};