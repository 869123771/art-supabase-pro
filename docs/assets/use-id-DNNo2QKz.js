import{Mn as e,Nn as t,Oi as n,Ti as r,wa as i}from"./framework-zmx8ZOtz.js";import{P as a,W as o}from"./style-CIXPBBet.js";var s={prefix:Math.floor(Math.random()*1e4),current:0},c=Symbol(`elIdInjection`),l=()=>r()?n(c,s):s,u=n=>{let r=l();!t&&r===s&&o(`IdInjection`,`Looks like you are using server rendering, you must provide a id provider to ensure the hydration process to be succeed
usage: app.provide(ID_INJECTION_KEY, {
  prefix: number,
  current: number,
})`);let c=a();return e(()=>i(n)||`${c.value}-id-${r.prefix}-${r.current++}`)};export{l as n,u as t};