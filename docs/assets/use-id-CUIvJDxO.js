import{Dt as e,Ut as t}from"./icon-CTrSPg3F.js";import{Gt as n,Jt as r,Kn as i,Z as a,tt as o}from"./framework-DZqGOvEn.js";var s={prefix:Math.floor(Math.random()*1e4),current:0},c=Symbol(`elIdInjection`),l=()=>n()?r(c,s):s,u=n=>{let r=l();!o&&r===s&&t(`IdInjection`,`Looks like you are using server rendering, you must provide a id provider to ensure the hydration process to be succeed
usage: app.provide(ID_INJECTION_KEY, {
  prefix: number,
  current: number,
})`);let c=e();return a(()=>i(n)||`${c.value}-id-${r.prefix}-${r.current++}`)};export{l as n,u as t};