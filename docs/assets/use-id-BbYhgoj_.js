import{Ht as e,Rn as t,X as n,q as r,zt as i}from"./framework-CYzF-5kq.js";import{w as a}from"./icon-BYQt9vQ_.js";import{dt as o}from"./style-C0gLILkt.js";var s={prefix:Math.floor(Math.random()*1e4),current:0},c=Symbol(`elIdInjection`),l=()=>i()?e(c,s):s,u=e=>{let i=l();!n&&i===s&&a(`IdInjection`,`Looks like you are using server rendering, you must provide a id provider to ensure the hydration process to be succeed
usage: app.provide(ID_INJECTION_KEY, {
  prefix: number,
  current: number,
})`);let c=o();return r(()=>t(e)||`${c.value}-id-${i.prefix}-${i.current++}`)};export{l as n,u as t};