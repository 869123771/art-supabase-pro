import{Dn as e,H as t,Ot as n,V as r,jt as i}from"./framework-CEwusMeK.js";import{y as a}from"./icon-BjsvefcU.js";import{dt as o}from"./style-BqYjjhLm.js";var s={prefix:Math.floor(Math.random()*1e4),current:0},c=Symbol(`elIdInjection`),l=()=>n()?i(c,s):s,u=n=>{let i=l();!t&&i===s&&a(`IdInjection`,`Looks like you are using server rendering, you must provide a id provider to ensure the hydration process to be succeed
usage: app.provide(ID_INJECTION_KEY, {
  prefix: number,
  current: number,
})`);let c=o();return r(()=>e(n)||`${c.value}-id-${i.prefix}-${i.current++}`)};export{l as n,u as t};