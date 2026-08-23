import{Br as e,Oi as t,Ti as n,wa as r,zr as i}from"./framework-zmx8ZOtz.js";import{N as a}from"./icon-Ds7H3eYK.js";import{rt as o}from"./style-DT-Q-OBS.js";var s={prefix:Math.floor(Math.random()*1e4),current:0},c=Symbol(`elIdInjection`),l=()=>n()?t(c,s):s,u=t=>{let n=l();!e&&n===s&&a(`IdInjection`,`Looks like you are using server rendering, you must provide a id provider to ensure the hydration process to be succeed
usage: app.provide(ID_INJECTION_KEY, {
  prefix: number,
  current: number,
})`);let c=o();return i(()=>r(t)||`${c.value}-id-${n.prefix}-${n.current++}`)};export{l as n,u as t};