import{Dt as e,Ut as t}from"./8uC-2hQl.js";import{Jt as n,Yn as r,Zt as i,et as a,it as o}from"./BCo0rLY3.js";var s={prefix:Math.floor(Math.random()*1e4),current:0},c=Symbol(`elIdInjection`),l=()=>n()?i(c,s):s,u=n=>{let i=l();!o&&i===s&&t(`IdInjection`,`Looks like you are using server rendering, you must provide a id provider to ensure the hydration process to be succeed
usage: app.provide(ID_INJECTION_KEY, {
  prefix: number,
  current: number,
})`);let c=e();return a(()=>r(n)||`${c.value}-id-${i.prefix}-${i.current++}`)};export{l as n,u as t};