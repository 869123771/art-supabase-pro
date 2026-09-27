import{f as e,n as t,v as n,x as r}from"./zoom-BqQd0rRP.js";import"./dist-a1jp10m4.js";import{n as i,r as a,t as o}from"./printLayout-cwq3dGGh.js";import{i as s,r as c,t as l}from"./viewer-CImeKObv.js";var u=`<span class="msdoc-page-break"></span>`,d=`<p class="msdoc-paragraph"><br></p>`,f={width:794,height:1123},p=.24,m=3,h=.15,g=`
.msdoc-stage{
  box-sizing:border-box;
  min-height:100%;
  padding:32px 24px 48px;
  background:var(--file-viewer-render-surface-background,#ececec);
  display:flex;
  flex-direction:column;
  align-items:center;
  gap:24px;
}
.msdoc-page{
  width:min(100%,794px);
  box-sizing:border-box;
}
.msdoc-page > .msdoc-root{
  box-sizing:border-box;
  width:100%;
  max-width:none;
  min-height:1123px;
  padding:clamp(24px,7%,96px) clamp(20px,6%,88px);
  background:#fff;
  border:1px solid #d9d9d9;
  box-shadow:0 1px 3px rgba(0,0,0,0.08), 0 12px 32px rgba(0,0,0,0.12);
  overflow-wrap:anywhere;
}
/* 表格不能沿用正文的 anywhere 断词，否则旧 DOC 的列宽和单元格内容会被过度压缩。 */
.msdoc-page .msdoc-table{
  display:table;
  width:auto;
  max-width:100%;
  table-layout:auto!important;
  border-collapse:collapse;
  border-spacing:0;
}
.msdoc-page .msdoc-table tbody,
.msdoc-page .msdoc-table tr{
  width:auto;
}
.msdoc-page .msdoc-cell{
  min-width:1.5em;
  padding:4px 6px;
  vertical-align:top;
  word-break:normal;
  overflow-wrap:normal;
  white-space:normal;
}
.msdoc-page .msdoc-cell .msdoc-paragraph{
  margin:0 0 4px;
  word-break:normal;
  overflow-wrap:break-word;
}
.msdoc-page .msdoc-cell .msdoc-paragraph:last-child{
  margin-bottom:0;
}
.msdoc-page .msdoc-cell span{
  white-space:normal!important;
}
.msdoc-page .msdoc-page-break{
  display:none;
}
[data-viewer-theme='dark'] .msdoc-stage{
  background:var(--file-viewer-render-surface-background,#111827);
}
[data-viewer-theme='dark'] .msdoc-page > .msdoc-root{
  color-scheme:dark;
  background:#161b22;
  border-color:rgba(139,148,158,.24);
  color:#e6edf3;
  box-shadow:0 18px 44px rgba(0,0,0,.36);
}
[data-viewer-theme='dark'] .msdoc-page > .msdoc-root span[style*='color:#000000']{
  color:#e6edf3!important;
}
[data-viewer-theme='dark'] .msdoc-page .msdoc-link{
  color:#58a6ff;
}
[data-viewer-theme='dark'] .msdoc-page .msdoc-attachment{
  border-color:rgba(139,148,158,.3);
  background:#21262d;
  color:#58a6ff;
}
@media (prefers-color-scheme:dark){
  [data-viewer-theme='system'] .msdoc-stage{
    background:var(--file-viewer-render-surface-background,#111827);
  }
  [data-viewer-theme='system'] .msdoc-page > .msdoc-root{
    color-scheme:dark;
    background:#161b22;
    border-color:rgba(139,148,158,.24);
    color:#e6edf3;
    box-shadow:0 18px 44px rgba(0,0,0,.36);
  }
  [data-viewer-theme='system'] .msdoc-page > .msdoc-root span[style*='color:#000000']{
    color:#e6edf3!important;
  }
  [data-viewer-theme='system'] .msdoc-page .msdoc-link{
    color:#58a6ff;
  }
  [data-viewer-theme='system'] .msdoc-page .msdoc-attachment{
    border-color:rgba(139,148,158,.3);
    background:#21262d;
    color:#58a6ff;
  }
}
@media (max-width: 860px){
  .msdoc-stage{
    padding:16px 12px 24px;
    gap:16px;
  }
  .msdoc-page{
    width:100%;
  }
  .msdoc-page > .msdoc-root{
    min-height:auto;
    padding:24px 20px;
    box-shadow:none;
  }
}
`,_=`
.msdoc-zoom-viewer{
  box-sizing:border-box;
  height:100%;
  overflow:auto;
  background:var(--file-viewer-render-surface-background,#ececec);
}
[data-viewer-theme='dark'] .msdoc-zoom-viewer{
  background:var(--file-viewer-render-surface-background,#111827);
}
@media (prefers-color-scheme:dark){
  [data-viewer-theme='system'] .msdoc-zoom-viewer{
    background:var(--file-viewer-render-surface-background,#111827);
  }
}
.msdoc-zoom-viewer .msdoc-stage{
  min-width:max-content;
}
.msdoc-zoom-viewer .msdoc-page{
  position:relative;
  max-width:none;
  overflow:visible;
}
.msdoc-zoom-viewer .msdoc-page > .msdoc-root{
  position:absolute;
  top:0;
  left:50%;
  width:${f.width}px;
  max-width:none;
  margin:0;
  transform-origin:top center;
}
`,v=e=>e.ownerDocument.defaultView;function y(e){return e.replace(/<(p|table|section)([^>]*?)style="([^"]*?\bbreak-before\s*:\s*page;?[^"]*?)"([^>]*)>/gi,e=>`${u}${e}`)}function b(e){return`<div class="msdoc-stage">${y(e).split(u).map(e=>`<section class="msdoc-page"><div class="msdoc-root">${e||d}</div></section>`).join(``)}</div>`}function x(e){let t=e.cloneNode(!0);return t.classList.remove(`msdoc-zoom-viewer`),t.querySelectorAll(`style[data-msdoc-zoom]`).forEach(e=>e.remove()),t.querySelectorAll(`.msdoc-stage, .msdoc-page, .msdoc-root`).forEach(e=>{e.style.height=`auto`,e.style.maxHeight=`none`,e.style.overflow=`visible`,e.style.transform=`none`}),t.querySelectorAll(`.msdoc-page`).forEach((e,t)=>{e.dataset.viewerPrintPageIndex=String(t),o(e,f,{heightMode:`min`}),e.style.position=`relative`,e.style.width=a(f.width),e.style.maxWidth=`none`,e.style.margin=`0 auto 18px`;let n=e.querySelector(`.msdoc-root`);n&&(n.style.position=`relative`,n.style.top=`auto`,n.style.left=`auto`,n.style.width=a(f.width),n.style.maxWidth=`none`,n.style.minHeight=a(f.height),n.style.height=`auto`,n.style.transform=`none`,n.style.transformOrigin=`top left`,n.style.boxShadow=`none`,n.style.border=`0`,n.style.overflow=`visible`)}),t.innerHTML}function S(){return i({selector:`.viewer-export-content .msdoc-page`,width:f.width,height:f.height,heightMode:`min`})}function C(i){let a=Array.from(i.querySelectorAll(`.msdoc-page`));if(!a.length)return()=>{};i.classList.add(`msdoc-zoom-viewer`);let o=v(i),s=o?.ResizeObserver,c=i.ownerDocument.createElement(`style`);c.dataset.msdocZoom=`true`,c.textContent=_,i.prepend(c);let l=t(),u=0,d=1,g=1,y=1,b=e=>Math.min(m,Math.max(p,Number(e.toFixed(2)))),x=()=>{let e=g,t=y,n=!1;a.forEach(r=>{let a=r.querySelector(`.msdoc-root`);if(!a)return;let o=a.offsetWidth||f.width,s=Math.max(a.scrollHeight,a.offsetHeight,f.height),c=Math.max(i.clientWidth-48,120),l=Math.min(1,Math.max(p,c/o)),u=b(l*d);n||(e=u,t=l,n=!0),a.style.transform=`translateX(-50%) scale(${u})`,r.style.width=`${Math.ceil(Math.max(o*u,120))}px`,r.style.height=`${Math.ceil(s*u)}px`}),n&&(g=e,y=t,l.emit())},S=()=>{if(!o){x();return}o.cancelAnimationFrame(u),u=o.requestAnimationFrame(()=>{x()})},C=()=>({scale:g,label:`${Math.round(g*100)}%`,canZoomIn:g<m,canZoomOut:g>p,canReset:d!==1,minScale:p,maxScale:m}),w=e=>(d=Math.min(6,Math.max(.2,Number(e.toFixed(2)))),o?.cancelAnimationFrame(u),x(),C()),T=e=>w(e/Math.max(y,.01)),E=()=>({width:a[0]?.querySelector(`.msdoc-root`)?.offsetWidth||f.width,height:f.height}),D=t=>{let n=E(),r=e({mode:t.mode===`auto`?`width`:t.mode,viewportWidth:Math.max(1,t.viewportWidth||i.clientWidth||0),viewportHeight:Math.max(1,t.viewportHeight||i.clientHeight||0),contentWidth:n.width,contentHeight:n.height,currentScale:g,minScale:t.minScale??p,maxScale:t.maxScale??m});if(!r)return{applied:!1,mode:t.mode,resize:t.resize,source:t.source,reason:`unmeasurable`,provider:`zoom`};let a=T(r);return{applied:!0,mode:t.mode,resize:t.resize,scale:a.scale,source:t.source,provider:`zoom`}};i.dataset.viewerZoomProvider=`doc`,n(i,{zoomIn:()=>w((g+h)/Math.max(y,.01)),zoomOut:()=>w((g-h)/Math.max(y,.01)),resetZoom:()=>w(1),setZoom:T,fit:D,getState:C,subscribe:l.subscribe});let O=s?new s(S):null;return O?.observe(i),a.forEach(e=>{let t=e.querySelector(`.msdoc-root`);t&&O?.observe(t)}),x(),()=>{o?.cancelAnimationFrame(u),O?.disconnect(),r(i),c.remove(),i.classList.remove(`msdoc-zoom-viewer`)}}async function w(e,t,n){var r,i;let a=await l(e,{renderOptions:{reviewMode:n?.options?.docx?.reviewMode??`all`,css:`${s()}\n${g}`,externalLinkPolicy:n?.options?.docx?.externalLinkPolicy??`block`,externalResourcePolicy:n?.options?.docx?.externalResourcePolicy??`block`}}),o=t.ownerDocument.defaultView;if(!o)throw Error(`The DOC target must belong to a browser document`);let u=t.ownerDocument.createElement(`style`);u.dataset.msdoc=``,u.textContent=a.css;let d=t.ownerDocument.createElement(`div`);d.append(c(b(a.html),o)),t.replaceChildren(u,...Array.from(d.childNodes));let f=C(t);return(r=n?.registerExportAdapter)==null||r.call(n,{includeDocumentStyles:!1,getPrintMaskPages:()=>Array.from(t.querySelectorAll(`.msdoc-page`)),printStyle:S,toHtml:()=>x(t)}),(i=n?.registerThumbnailAdapter)==null||i.call(n,{getTarget:()=>t.querySelector(`.msdoc-page`)||t}),{$el:t,unmount(){var e,r;(e=n?.registerExportAdapter)==null||e.call(n,null),(r=n?.registerThumbnailAdapter)==null||r.call(n,null),f(),t.replaceChildren()}}}export{w as default};