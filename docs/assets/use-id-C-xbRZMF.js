import{Dt as e,Ut as t}from"./icon-CplFS_U0.js";import{Gn as n,Wt as r,X as i,et as a,qt as o}from"./framework-D3WzblCr.js";var s={prefix:Math.floor(Math.random()*1e4),current:0},c=Symbol(`elIdInjection`),l=()=>r()?o(c,s):s,u=r=>{let o=l();!a&&o===s&&t(`IdInjection`,`Looks like you are using server rendering, you must provide a id provider to ensure the hydration process to be succeed
usage: app.provide(ID_INJECTION_KEY, {
  prefix: number,
  current: number,
})`);let c=e();return i(()=>n(r)||`${c.value}-id-${o.prefix}-${o.current++}`)};export{l as n,u as t};