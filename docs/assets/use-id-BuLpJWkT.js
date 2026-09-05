import{H as e,Mt as t,On as n,U as r,kt as i}from"./framework-DJQMI0NS.js";import{w as a}from"./icon-BjYXIeJn.js";import{dt as o}from"./style-nJerGBDB.js";var s={prefix:Math.floor(Math.random()*1e4),current:0},c=Symbol(`elIdInjection`),l=()=>i()?t(c,s):s,u=t=>{let i=l();!r&&i===s&&a(`IdInjection`,`Looks like you are using server rendering, you must provide a id provider to ensure the hydration process to be succeed
usage: app.provide(ID_INJECTION_KEY, {
  prefix: number,
  current: number,
})`);let c=o();return e(()=>n(t)||`${c.value}-id-${i.prefix}-${i.current++}`)};export{l as n,u as t};