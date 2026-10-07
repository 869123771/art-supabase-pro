import{Dt as e,Ut as t}from"./icon-Bc0N772Q.js";import{Gn as n,Wt as r,Z as i,qt as a,tt as o}from"./framework-CQuaCGL1.js";var s={prefix:Math.floor(Math.random()*1e4),current:0},c=Symbol(`elIdInjection`),l=()=>r()?a(c,s):s,u=r=>{let a=l();!o&&a===s&&t(`IdInjection`,`Looks like you are using server rendering, you must provide a id provider to ensure the hydration process to be succeed
usage: app.provide(ID_INJECTION_KEY, {
  prefix: number,
  current: number,
})`);let c=e();return i(()=>n(r)||`${c.value}-id-${a.prefix}-${a.current++}`)};export{l as n,u as t};