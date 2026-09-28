import{Ct as e,zt as t}from"./icon-WyKc5IWZ.js";import{$ as n,Gt as r,Hn as i,Ht as a,X as o}from"./framework-CCD57Qi8.js";var s={prefix:Math.floor(Math.random()*1e4),current:0},c=Symbol(`elIdInjection`),l=()=>a()?r(c,s):s,u=r=>{let a=l();!n&&a===s&&t(`IdInjection`,`Looks like you are using server rendering, you must provide a id provider to ensure the hydration process to be succeed
usage: app.provide(ID_INJECTION_KEY, {
  prefix: number,
  current: number,
})`);let c=e();return o(()=>i(r)||`${c.value}-id-${a.prefix}-${a.current++}`)};export{l as n,u as t};