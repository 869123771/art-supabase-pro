import{Ht as e,X as t,q as n,zn as r,zt as i}from"./framework-ClRJ96jm.js";import{w as a}from"./icon-Czp-2FrG.js";import{dt as o}from"./style-DFvNC_CE.js";var s={prefix:Math.floor(Math.random()*1e4),current:0},c=Symbol(`elIdInjection`),l=()=>i()?e(c,s):s,u=e=>{let i=l();!t&&i===s&&a(`IdInjection`,`Looks like you are using server rendering, you must provide a id provider to ensure the hydration process to be succeed
usage: app.provide(ID_INJECTION_KEY, {
  prefix: number,
  current: number,
})`);let c=o();return n(()=>r(e)||`${c.value}-id-${i.prefix}-${i.current++}`)};export{l as n,u as t};