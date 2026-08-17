const __vite__mapDeps=(i,m=__vite__mapDeps,d=(m.f||(m.f=["assets/docx-preview-_0j8R57G.js","assets/rolldown-runtime-DAXXjFlN.js","assets/lib-CC8b0Sep.js","assets/build-runtime-CKdosLtJ.js"])))=>i.map(i=>d[i]);
import{_ as e}from"./build-runtime-CKdosLtJ.js";import{a as t,o as n}from"./assets-D4_1pr-L.js";import{n as r}from"./dist-NzBD-XT3.js";import{a as i,g as a,p as o,r as s}from"./fit-D5xl58Tb.js";import{i as c,n as l,r as u,t as d}from"./printLayout-B9g6jJOI.js";import{t as f}from"./messages-Br38nP9c.js";var p={width:794,height:1123},m=new Set([`file:`,`about:`,`data:`]),h=.24,g=3,_=.15,v=`0.3.20`,y=20555,b=(()=>{let t={module:null,async load(){return this.module||(this.module=e(()=>import(`./docx-preview-_0j8R57G.js`),__vite__mapDeps([0,1,2,3]))),this.module}};return async()=>await t.load()})(),x=(e,t)=>{if((e.byteLength>=4?new DataView(e).getUint16(0,!1):0)!==y)throw Error(f(t?.options)(`word.error.invalidDocx`))},S=e=>e.ownerDocument.defaultView,C=e=>{let t=[e.ownerDocument.URL,S(e)?.location?.href,globalThis.location?.href].filter(Boolean);for(let e of t)try{return new URL(e).protocol}catch{}return``},w=(e,t)=>t?.worker===!1?!1:t?.worker===!0?!0:S(e)?.Worker??globalThis.Worker?!m.has(C(e)):!1,T=e=>{let t=S(e)?.matchMedia??globalThis.matchMedia;return typeof t==`function`&&t(`(prefers-color-scheme: dark)`).matches},E=(e,t,n)=>{if(n?.darkMode!==void 0)return n.darkMode;let i=r(t?.options?.theme);return i===`dark`||i!==`light`&&T(e)},D=(e,t)=>!e||t?e:`${e}${e.includes(`?`)?`&`:`?`}file-viewer-docx=${v}`,O=(e,r,i)=>{let a=r?.options?.docx,o=e.ownerDocument.URL||void 0,s=w(e,a),c=a?.visualPagination===!0,l=E(e,r,a),u={useWorker:s,breakPages:c,ignoreLastRenderedPageBreak:a?.ignoreLastRenderedPageBreak??!c,darkMode:l,progress:e=>{(e.phase===`render`||e.phase===`layout`||e.phase===`done`)&&i()}};return s&&(u.workerUrl=D(n(a,o),!!a?.workerUrl),u.workerJsZipUrl=D(t(a,o),!!a?.workerJsZipUrl)),a?.workerTimeout!==void 0&&(u.workerTimeout=a.workerTimeout),a?.renderPageBatchSize===void 0?a?.progressive===!1&&(u.renderPageBatchSize=2**53-1):u.renderPageBatchSize=a.renderPageBatchSize,a?.renderYieldEveryMs!==void 0&&(u.renderYieldEveryMs=a.renderYieldEveryMs),a?.strictWordCompatibility!==void 0&&(u.strictWordCompatibility=a.strictWordCompatibility),a?.paginationTolerance!==void 0&&(u.paginationTolerance=a.paginationTolerance),a?.maxDynamicPaginationPasses!==void 0&&(u.maxDynamicPaginationPasses=a.maxDynamicPaginationPasses),a?.awaitLayout!==void 0&&(u.awaitLayout=a.awaitLayout),a?.preserveComplexFieldResults!==void 0&&(u.preserveComplexFieldResults=a.preserveComplexFieldResults),a?.updatePageReferences!==void 0&&(u.updatePageReferences=a.updatePageReferences),a?.hideWebHiddenContent!==void 0&&(u.hideWebHiddenContent=a.hideWebHiddenContent),u},k=(e,t)=>{let n=S(t)?.HTMLElement;return n?e instanceof n:e instanceof HTMLElement},A=`
.docx-fit-viewer {
  box-sizing: border-box;
  height: 100%;
  overflow: auto;
  background: #ececec;
  color-scheme: light;
}
.docx-fit-viewer[data-docx-dark-mode='true'] {
  background: #242424;
  color-scheme: dark;
}
.docx-fit-viewer .docx-wrapper {
  box-sizing: border-box;
  min-width: 0 !important;
  width: 100% !important;
  padding: 24px 14px 40px !important;
  background: #e7e9ec !important;
}
.docx-fit-viewer[data-docx-dark-mode='true'] .docx-wrapper {
  background: #242424 !important;
}
.docx-fit-viewer .docx-page-frame {
  position: relative;
  width: 100%;
  min-width: 0;
  margin: 0 auto 24px;
  overflow: visible;
}
.docx-fit-viewer .docx-flow-frame {
  position: relative;
  width: 100%;
  min-width: 0;
  margin: 0 auto 28px;
  overflow: visible;
}
.docx-fit-viewer .docx-page-frame > section.docx,
.docx-fit-viewer .docx-flow-frame > section.docx {
  position: absolute;
  top: 0;
  left: 50%;
  margin: 0 !important;
  background: #ffffff !important;
  box-shadow: 0 2px 14px rgba(25, 35, 48, 0.18);
  box-sizing: border-box;
  overflow: hidden;
  transform-origin: top center;
}
.docx-fit-viewer[data-docx-dark-mode='true'] .docx-page-frame > section.docx,
.docx-fit-viewer[data-docx-dark-mode='true'] .docx-flow-frame > section.docx {
  background: rgb(51, 51, 51) !important;
  box-shadow: 0 0 10px rgba(0, 0, 0, 0.8);
  outline: 1px solid rgba(255, 255, 255, 0.15);
  outline-offset: -1px;
}
.docx-fit-viewer .docx-flow-frame > section.docx {
  height: auto !important;
  min-height: var(--docx-page-height, auto) !important;
  overflow: visible !important;
}
.docx-fit-viewer .docx-page-frame > section.docx > article,
.docx-fit-viewer .docx-flow-frame > section.docx > article {
  position: relative;
  z-index: 1;
}
`;function j(e){let t=e.ownerDocument.createElement(`style`);return t.textContent=A,e.prepend(t),t}function M(e,t){let n=e.querySelector(`.docx-wrapper`);return n?Array.from(n.children).flatMap(n=>{if(!k(n,e)||!n.matches(`section.docx`))return[];let r=e.ownerDocument.createElement(`div`);return r.className=t?`docx-page-frame`:`docx-flow-frame`,n.before(r),r.appendChild(n),[r]}):[]}function N(e,t){e.classList.add(`docx-fit-viewer`);let n=j(e),r=t?.options?.docx?.visualPagination===!0,l=M(e,r),u=S(e),d=u?.ResizeObserver,f=0,m=1,v=1,y=1,b=i(),x=e=>Math.min(g,Math.max(h,Number(e.toFixed(2)))),C=()=>{let t=v,n=y,i=!1;l.forEach(a=>{let o=a.firstElementChild;if(!k(o,e))return;o.style.transform=`translateX(-50%)`;let s=o.offsetWidth,c=r?o.offsetHeight:Math.max(o.scrollHeight,o.offsetHeight);if(!s||!c)return;let l=Math.max(e.clientWidth-28,120),u=Math.min(1,Math.max(h,l/s)),d=x(u*m);i||(t=d,n=u,i=!0),o.style.transform=`translateX(-50%) scale(${d})`,a.style.width=`${Math.ceil(Math.max(s*d,e.clientWidth-28,120))}px`,a.style.maxWidth=`none`,a.style.height=`${Math.ceil(c*d)}px`}),i&&(v=t,y=n,b.emit())},w=()=>{if(!u){C();return}u.cancelAnimationFrame(f),f=u.requestAnimationFrame(()=>{C()})},T=()=>({scale:v,label:`${Math.round(v*100)}%`,canZoomIn:v<g,canZoomOut:v>h,canReset:m!==1,minScale:h,maxScale:g}),E=e=>(m=Math.min(6,Math.max(.2,Number(e.toFixed(2)))),u?.cancelAnimationFrame(f),C(),T()),D=e=>E(e/Math.max(y,.01)),O=()=>{for(let e of l){let t=P(e);if(!t)continue;let n=c(t,p);return{width:t.offsetWidth||n.width||p.width,height:F(e)?p.height:t.offsetHeight||n.height||p.height}}return null},A=t=>{let n=O();if(!n)return{applied:!1,mode:t.mode,resize:t.resize,source:t.source,reason:`unmeasurable`,provider:`zoom`};let r=s({mode:t.mode===`auto`?`width`:t.mode,viewportWidth:Math.max(1,t.viewportWidth||e.clientWidth||0),viewportHeight:Math.max(1,t.viewportHeight||e.clientHeight||0),contentWidth:n.width,contentHeight:n.height,currentScale:v,minScale:t.minScale??h,maxScale:t.maxScale??g});if(!r)return{applied:!1,mode:t.mode,resize:t.resize,source:t.source,reason:`unmeasurable`,provider:`zoom`};let i=D(r);return{applied:!0,mode:t.mode,resize:t.resize,scale:i.scale,source:t.source,provider:`zoom`}};e.dataset.viewerZoomProvider=`docx`,o(e,{zoomIn:()=>E((v+_)/Math.max(y,.01)),zoomOut:()=>E((v-_)/Math.max(y,.01)),resetZoom:()=>E(1),setZoom:D,fit:A,getState:T,subscribe:b.subscribe});let N=d?new d(w):null;return N?.observe(e),l.forEach(e=>{let t=P(e);t&&N?.observe(t)}),C(),()=>{u?.cancelAnimationFrame(f),N?.disconnect(),a(e),n.remove(),e.classList.remove(`docx-fit-viewer`)}}function P(e){let t=e.firstElementChild,n=e.ownerDocument.defaultView?.HTMLElement;return n&&t instanceof n?t:null}function F(e){return!!e?.classList.contains(`docx-flow-frame`)}function I(e){let t=e?P(e):null;if(!t)return p;let n=c(t,p);return F(e)?{width:n.width,height:Math.max(t.scrollHeight||0,t.offsetHeight||0,p.height)}:n}function L(e,t){let n=F(e),r=u(t.width),i=u(t.height);d(e,t,{heightMode:n?`min`:`fixed`}),e.style.margin=`0 auto 18px`;let a=P(e);a&&(a.style.position=`relative`,a.style.top=`auto`,a.style.left=`auto`,a.style.width=r,a.style.maxWidth=`none`,a.style.minHeight=n?`0`:i,a.style.height=n?`auto`:i,a.style.margin=`0 auto`,a.style.transform=`none`,a.style.transformOrigin=`top left`,a.style.overflow=n?`visible`:`hidden`,a.style.boxShadow=`none`)}function R(e){let t=e.querySelector(`.docx-page-frame, .docx-flow-frame`),n=I(t||void 0);return l({selector:t?.classList.contains(`docx-flow-frame`)?`.viewer-export-content .docx-flow-frame`:`.viewer-export-content .docx-page-frame`,width:n.width,height:t?.classList.contains(`docx-flow-frame`)?p.height:n.height,heightMode:t?.classList.contains(`docx-flow-frame`)?`min`:`fixed`})}function z(e){let t=Array.from(e.querySelectorAll(`.docx-page-frame, .docx-flow-frame`)),n=e.cloneNode(!0),r=e.ownerDocument.createElement(`div`);r.className=`docx-print-document`;let i=Array.from(n.querySelectorAll(`style`)).filter(e=>!e.textContent?.includes(`.docx-fit-viewer`)).map(e=>e.outerHTML).join(``);return n.querySelectorAll(`.docx-page-frame, .docx-flow-frame`).forEach((e,n)=>{L(e,I(t[n])),r.appendChild(e.cloneNode(!0))}),r.childElementCount?`${i}${r.outerHTML}`:n.innerHTML}async function B(e,t,n){var r,i;x(e,n),t.innerHTML=``;let a=!1,o=()=>{var e;a||(a=!0,(e=n?.onProgressiveRender)==null||e.call(n))},s=O(t,n,o),{defaultOptions:c,renderAsync:l}=await b();t.dataset.docxWorker=s.useWorker?`self`:`false`,t.dataset.docxDarkMode=s.darkMode?`true`:`false`,await l(e,t,void 0,{...c,...s}),o();let u=N(t,n);return(r=n?.registerExportAdapter)==null||r.call(n,{includeDocumentStyles:!1,beforeSnapshot:()=>{let e=S(t);e&&e.dispatchEvent(new e.Event(`resize`))},printStyle:()=>R(t),toHtml:()=>z(t)}),(i=n?.registerThumbnailAdapter)==null||i.call(n,{getTarget:()=>t.querySelector(`.docx-page-frame, .docx-flow-frame`)||t}),{$el:t,unmount(){var e,r;(e=n?.registerExportAdapter)==null||e.call(n,null),(r=n?.registerThumbnailAdapter)==null||r.call(n,null),u(),delete t.dataset.docxWorker,delete t.dataset.docxDarkMode,t.innerHTML=``}}}export{B as default};