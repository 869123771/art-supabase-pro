import{w as e}from"./icon-C4SJeHIr.js";import{$ as t,Gt as n,Hn as r,Ht as i,X as a}from"./framework-CCD57Qi8.js";import{gt as o}from"./dist-CsJ0uY4E.js";var s={prefix:Math.floor(Math.random()*1e4),current:0},c=Symbol(`elIdInjection`),l=()=>i()?n(c,s):s,u=n=>{let i=l();!t&&i===s&&e(`IdInjection`,`Looks like you are using server rendering, you must provide a id provider to ensure the hydration process to be succeed
usage: app.provide(ID_INJECTION_KEY, {
  prefix: number,
  current: number,
})`);let c=o();return a(()=>r(n)||`${c.value}-id-${i.prefix}-${i.current++}`)};export{l as n,u as t};