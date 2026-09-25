import{w as e}from"./icon-BZsin8Ge.js";import{Q as t,Vn as n,Vt as r,Wt as i,Y as a}from"./framework-x7XoaZj-.js";import{gt as o}from"./dist-DHiWXbO9.js";var s={prefix:Math.floor(Math.random()*1e4),current:0},c=Symbol(`elIdInjection`),l=()=>r()?i(c,s):s,u=r=>{let i=l();!t&&i===s&&e(`IdInjection`,`Looks like you are using server rendering, you must provide a id provider to ensure the hydration process to be succeed
usage: app.provide(ID_INJECTION_KEY, {
  prefix: number,
  current: number,
})`);let c=o();return a(()=>n(r)||`${c.value}-id-${i.prefix}-${i.current++}`)};export{l as n,u as t};