import{Jr as e,Zr as t,en as n,qi as r,tn as i}from"./framework-D8pXWVr4.js";import{P as a,W as o}from"./style-uSaRqjVI.js";var s={prefix:Math.floor(Math.random()*1e4),current:0},c=Symbol(`elIdInjection`),l=()=>e()?t(c,s):s,u=e=>{let t=l();!i&&t===s&&o(`IdInjection`,`Looks like you are using server rendering, you must provide a id provider to ensure the hydration process to be succeed
usage: app.provide(ID_INJECTION_KEY, {
  prefix: number,
  current: number,
})`);let c=a();return n(()=>r(e)||`${c.value}-id-${t.prefix}-${t.current++}`)};export{l as n,u as t};