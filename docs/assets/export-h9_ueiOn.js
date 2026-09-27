import{t as e}from"./purify.es-DpfiG7v6.js";import{i as t,n,r,t as i}from"./printMask-BLGRbUDN.js";import{i as a,n as o,r as s,t as c}from"./export-BdvKDp-_.js";var l=e=>e.replace(/&/g,`&amp;`).replace(/"/g,`&quot;`).replace(/</g,`&lt;`).replace(/>/g,`&gt;`),u={WHOLE_DOCUMENT:!0,USE_PROFILES:{html:!0,svg:!0,svgFilters:!0,mathMl:!0},ADD_TAGS:[`use`],ADD_ATTR:[`target`,`rel`,`download`],FORBID_TAGS:[`script`,`iframe`,`object`,`embed`,`base`,`form`,`link`],FORBID_ATTR:[`srcdoc`]},d=e=>e||globalThis.document||null,f=e=>/[A-Za-z0-9_-]/.test(e),p=(e,t)=>{let n=t+1,r=e[n]||``;if(!r)return{value:``,nextIndex:n};if(r===`\r`||r===`
`||r===`\f`)return r===`\r`&&e[n+1]===`
`&&(n+=1),{value:``,nextIndex:n+1};let i=``;for(;n<e.length&&i.length<6&&/[0-9a-f]/i.test(e[n]||``);)i+=e[n],n+=1;if(i){/\s/.test(e[n]||``)&&(n+=1);let t=Number.parseInt(i,16);return{value:t===0||t>1114111?`�`:String.fromCodePoint(t),nextIndex:n}}return{value:r,nextIndex:n+1}},m=e=>{let t=``,n=``,r=0;for(;r<e.length;){let i=e[r]||``;if(n){if(t+=i,i===`\\`){t+=e[r+1]||``,r+=2;continue}i===n&&(n=``),r+=1;continue}if(i===`/`&&e[r+1]===`*`){let t=e.indexOf(`*/`,r+2);r=t<0?e.length:t+2;continue}if(i===`"`||i===`'`){n=i,t+=i,r+=1;continue}if(i===`\\`){let n=p(e,r);t+=n.value,r=n.nextIndex;continue}let a=i.charCodeAt(0);t+=a<32&&i!==`	`&&i!==`
`&&i!==`\r`?` `:i,r+=1}return t},h=/^data:(?:image\/(?:avif|bmp|gif|jpeg|png|webp|x-icon)|font\/(?:collection|otf|sfnt|ttf|woff2?)|application\/(?:font-sfnt|font-woff|vnd\.ms-fontobject|x-font-opentype|x-font-ttf|x-font-woff));/i,g=e=>{let t=/^data:image\/svg\+xml(?:;charset=[A-Za-z0-9._-]+)?,([\s\S]*)$/i.exec(e);if(!t||t[1].length>1024*1024)return!1;let n;try{n=decodeURIComponent(t[1])}catch{return!1}if(!/^\s*<svg(?:\s|>)/i.test(n)||/<\/?(?:script|style|foreignObject|iframe|object|embed|form|link)\b/i.test(n)||/<!\s*(?:doctype|entity)\b/i.test(n)||/\son[a-z0-9_-]+\s*=/i.test(n)||/@import\b/i.test(n)||/url\s*\(\s*(?!["']?#)/i.test(n))return!1;for(let e of n.matchAll(/\s(?:href|xlink:href|src)\s*=\s*(["'])([\s\S]*?)\1/gi)){let t=v(e[2]||``);if(!/^#[A-Za-z0-9_.:-]+$/.test(t)&&!h.test(t))return!1}return!0},_=e=>{let t=``;for(let n of e){let e=n.charCodeAt(0);e<=32||e>=127&&e<=159||(t+=n)}return t.trim()},v=_,y=/^data:(?:image\/(?:avif|bmp|gif|jpeg|png|webp|x-icon)|audio\/[a-z0-9.+-]+|video\/[a-z0-9.+-]+|text\/vtt)(?:;[^,]*)?,/i,b=e=>{let t=_(e);return t?t.startsWith(`#`)||/^blob:/i.test(t)?!0:y.test(t):!1},x=(e,t,n={})=>{if(!e.hasAttribute(t))return;let r=_(e.getAttribute(t)||``);(n.fragmentOnly?/^#[A-Za-z0-9_.:-]+$/.test(r):b(r))?e.setAttribute(t,r):e.removeAttribute(t)},S=e=>{let t=e.trim(),n=t[0];return(n===`"`||n===`'`)&&t[t.length-1]===n&&(t=t.slice(1,-1).trim()),_(t)},C=e=>{let t=S(e);return t?t.startsWith(`#`)||/^blob:/i.test(t)?!0:h.test(t)||g(t):!1},w=(e,t)=>{let n=``;for(let r=t;r<e.length;r+=1){let t=e[r]||``;if(n){t===`\\`?r+=1:t===n&&(n=``);continue}if(t===`"`||t===`'`)n=t;else if(t===`)`)return r}return-1},T=e=>{let t=!1,n=!1,r=``,i=0;for(;i<e.length;){let a=e[i]||``;if(r){if(a===`\\`){i+=2;continue}a===r&&(r=``),i+=1;continue}if(a===`/`&&e[i+1]===`*`){let t=e.indexOf(`*/`,i+2);i=t<0?e.length:t+2;continue}if(a===`"`||a===`'`){r=a,i+=1;continue}if(a===`\\`){i+=2;continue}if(a===`@`&&e.slice(i+1,i+7).toLowerCase()===`import`){let n=e[i+7]||``;(!n||!f(n))&&(t=!0)}if(e.slice(i,i+3).toLowerCase()===`url`&&!f(e[i-1]||``)){let t=i+3;for(;/\s/.test(e[t]||``);)t+=1;e[t]===`(`&&(n=!0)}i+=1}return{hasImport:t,hasUrl:n}},E=e=>{let t=T(m(e)),n=T(e);if(t.hasImport||t.hasUrl&&!n.hasUrl)return``;if(!n.hasUrl)return e;let r=``,i=``,a=0;for(;a<e.length;){let t=e[a]||``;if(i){if(r+=t,t===`\\`){r+=e[a+1]||``,a+=2;continue}t===i&&(i=``),a+=1;continue}if(t===`"`||t===`'`){i=t,r+=t,a+=1;continue}if(t===`/`&&e[a+1]===`*`){let t=e.indexOf(`*/`,a+2);if(t<0){r+=e.slice(a);break}r+=e.slice(a,t+2),a=t+2;continue}if(t===`\\`){r+=t,r+=e[a+1]||``,a+=2;continue}if(e.slice(a,a+3).toLowerCase()===`url`&&!f(e[a-1]||``)){let t=a+3;for(;/\s/.test(e[t]||``);)t+=1;if(e[t]===`(`){let n=w(e,t+1);if(n<0)return``;let i=e.slice(t+1,n);r+=C(i)?e.slice(a,n+1):`none`,a=n+1;continue}}r+=t,a+=1}return r},D=t=>{let n=t.defaultView;if(!n)return null;let r=e(n);return r.isSupported?(r.addHook(`afterSanitizeElements`,e=>{let t=e;if(t.localName?.toLowerCase()!==`style`)return;let n=E(t.textContent||``);n?t.textContent=n:t.remove()}),r.addHook(`afterSanitizeAttributes`,e=>{let t=e,n=t.localName?.toLowerCase();if(n===`a`&&(t.getAttribute(`target`)||``).trim().toLowerCase()===`_blank`&&t.setAttribute(`rel`,`noopener noreferrer`),(n===`a`||n===`area`)&&t.removeAttribute(`ping`),t.hasAttribute(`srcset`)&&t.removeAttribute(`srcset`),[`img`,`audio`,`video`,`source`,`track`,`input`].includes(n||``)&&x(t,`src`),n===`video`&&x(t,`poster`),t.hasAttribute(`background`)&&x(t,`background`),t.namespaceURI===`http://www.w3.org/2000/svg`&&n!==`a`){let e=n===`use`||n===`mpath`;x(t,`href`,{fragmentOnly:e}),x(t,`xlink:href`,{fragmentOnly:e})}if(t.hasAttribute(`style`)){let e=E(t.getAttribute(`style`)||``);e?t.setAttribute(`style`,e):t.removeAttribute(`style`)}}),r):null},O=[`<meta charset="utf-8" />`,`<meta name="viewport" content="width=device-width,initial-scale=1" />`].join(`
  `),k=(e,t)=>{let n=d(t),r=n?D(n):null;return r?`<!doctype html>\n${String(r.sanitize(e,u)).replace(`<head>`,`<head>\n  ${O}`)}`:`<!doctype html>
<html lang="en"><head><meta charset="utf-8" /></head><body></body></html>`},A=e=>{let t=e.createElement(`html`);t.lang=`en`;let n=e.createElement(`head`),r=e.createElement(`meta`);return r.setAttribute(`charset`,`utf-8`),n.append(r),t.append(n,e.createElement(`body`)),t},j=e=>{let t=e.querySelector(`:scope > head`);if(!t)return e;if(!t.querySelector(`meta[charset]`)){let n=e.ownerDocument.createElement(`meta`);n.setAttribute(`charset`,`utf-8`),t.prepend(n)}if(!t.querySelector(`meta[name="viewport"]`)){let n=e.ownerDocument.createElement(`meta`);n.setAttribute(`name`,`viewport`),n.setAttribute(`content`,`width=device-width,initial-scale=1`),t.querySelector(`meta[charset]`)?.after(n)}return e},M=(e,t)=>{let n=d(t);if(!n)throw Error(`A browser document is required to build printable DOM.`);let r=D(n);if(!r)return A(n);let i=r.sanitize(e,{...u,RETURN_DOM:!0});return!i||i.nodeType!==1||i.localName.toLowerCase()!==`html`?A(n):j(i)},N=`
  * { box-sizing: border-box; }
  html, body { margin: 0; min-height: 100%; background: #f2f4f7; color: #172033; font-family: Aptos, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif; print-color-adjust: exact; -webkit-print-color-adjust: exact; }
  body { padding: 24px; }
  .viewer-export-shell { position: relative; min-height: calc(100vh - 48px); overflow: visible; background: #f2f4f7; }
  .viewer-export-content { position: relative; z-index: 1; contain: none; width: 100%; min-height: 100%; overflow: visible; }
  .viewer-export-watermark { position: absolute; inset: 0; pointer-events: none; z-index: 20; background-repeat: repeat; print-color-adjust: exact; -webkit-print-color-adjust: exact; }
  .viewer-export-content .file-render,
  .viewer-export-content .file-viewer,
  .viewer-export-content .viewer-stage,
  .viewer-export-content .content,
  .viewer-export-content .pdf-shell,
  .viewer-export-content .pdf-content,
  .viewer-export-content .pdf-viewport,
  .viewer-export-content .pdf-wrapper,
  .viewer-export-content .docx-fit-viewer,
  .viewer-export-content .docx-wrapper,
  .viewer-export-content .docx-canvas-wrapper,
  .viewer-export-content .msdoc-stage,
  .viewer-export-content .msdoc-paged-view,
  .viewer-export-content .code-viewer,
  .viewer-export-content .markdown-viewer,
  .viewer-export-content .email-shell,
  .viewer-export-content .archive-shell,
  .viewer-export-content .eda-shell,
  .viewer-export-content .ebook-shell,
  .viewer-export-content .umd-shell,
  .viewer-export-content .drawing-shell,
  .viewer-export-content .audio-shell,
  .viewer-export-content .cad-shell,
  .viewer-export-content .cad-body,
  .viewer-export-content .cad-canvas-wrap,
  .viewer-export-content .dwg-preview-frame {
    position: relative !important;
    inset: auto !important;
    contain: none !important;
    width: 100% !important;
    height: auto !important;
    min-height: 0 !important;
    max-height: none !important;
    overflow: visible !important;
  }
  .viewer-export-content .docx-wrapper {
    display: block !important;
    padding: 0 !important;
    background: transparent !important;
  }
  .viewer-export-content .docx-canvas-wrapper {
    display: block !important;
    padding: 0 !important;
    background: transparent !important;
  }
  .viewer-export-content .docx-print-document {
    display: block !important;
    width: fit-content !important;
    max-width: 100% !important;
    height: auto !important;
    overflow: visible !important;
    margin: 0 auto !important;
  }
  .viewer-export-content .docx-page-frame {
    position: relative !important;
    width: var(--viewer-print-page-width, fit-content) !important;
    height: var(--viewer-print-page-height, auto) !important;
    min-height: var(--viewer-print-page-height, 0) !important;
    max-width: 100% !important;
    margin: 0 auto 18px !important;
    overflow: hidden !important;
    break-inside: avoid;
    page-break-inside: avoid;
    break-after: page;
    page-break-after: always;
  }
  .viewer-export-content .docx-canvas-sheet {
    position: relative !important;
    contain: none !important;
    width: var(--viewer-print-page-width, 794px) !important;
    height: var(--viewer-print-page-height, 1123px) !important;
    min-height: var(--viewer-print-page-height, 1123px) !important;
    max-width: 100% !important;
    margin: 0 auto 18px !important;
    overflow: hidden !important;
    box-shadow: none !important;
    break-inside: avoid;
    page-break-inside: avoid;
    break-after: page;
    page-break-after: always;
  }
  .viewer-export-content .docx-canvas-sheet > img {
    display: block !important;
    width: 100% !important;
    height: 100% !important;
    max-width: none !important;
    object-fit: fill;
  }
  .viewer-export-content .msdoc-page {
    position: relative !important;
    width: var(--viewer-print-page-width, 794px) !important;
    min-height: var(--viewer-print-page-height, 1123px) !important;
    max-width: 100% !important;
    height: auto !important;
    margin: 0 auto 18px !important;
    overflow: visible !important;
    break-after: page;
    page-break-after: always;
  }
  .viewer-export-content .docx-page-frame:last-child,
  .viewer-export-content .docx-canvas-sheet:last-child,
  .viewer-export-content .msdoc-page:last-child {
    break-after: auto;
    page-break-after: auto;
  }
  .viewer-export-content .docx-page-frame > section.docx {
    position: relative !important;
    top: auto !important;
    left: auto !important;
    width: var(--viewer-print-page-width, auto) !important;
    min-height: var(--viewer-print-page-height, auto) !important;
    max-width: none !important;
    margin: 0 auto !important;
    overflow: visible !important;
    transform: none !important;
    box-shadow: none !important;
    break-inside: avoid;
    page-break-inside: avoid;
  }
  .viewer-export-content .msdoc-stage {
    display: block !important;
    padding: 0 !important;
    background: transparent !important;
  }
  .viewer-export-content .msdoc-paged-view {
    display: block !important;
    gap: 0 !important;
    padding: 0 !important;
    background: transparent !important;
  }
  .viewer-export-content .msdoc-page > .msdoc-root {
    margin: 0 auto !important;
    box-shadow: none !important;
    overflow: visible !important;
  }
  .viewer-export-content .pdf-toolbar,
  .viewer-export-content .pdf-nav-pane,
  .viewer-export-content .viewer-actions,
  .viewer-export-content .code-toolbar,
  .viewer-export-content .umd-toolbar,
  .viewer-export-content .drawing-toolbar,
  .viewer-export-content .cad-toolbar {
    display: none !important;
  }
  .viewer-export-content .pdf-content,
  .viewer-export-content .pdf-shell--nav-hidden .pdf-content,
  .viewer-export-content .cad-body.without-layers {
    display: block !important;
    grid-template-columns: none !important;
  }
  .viewer-export-content .pdfViewer { padding: 0 !important; }
  .viewer-export-content .pdfViewer .page {
    margin: 0 auto 16px !important;
    border: 0 !important;
    box-shadow: none !important;
    break-after: page;
    page-break-after: always;
  }
  .viewer-export-content .pdfViewer .page:last-child {
    break-after: auto;
    page-break-after: auto;
  }
  .viewer-export-content .pdf-export-document {
    display: grid;
    justify-items: center;
    gap: 18px;
    padding: 4px 0;
  }
  .viewer-export-content .pdf-export-page {
    width: var(--viewer-print-page-width, auto);
    height: var(--viewer-print-page-height, auto);
    max-width: 100%;
    overflow: hidden;
    background: #ffffff;
    box-shadow: 0 12px 32px rgba(15, 23, 42, 0.12);
    break-inside: avoid;
    page-break-inside: avoid;
    break-after: page;
    page-break-after: always;
  }
  .viewer-export-content .pdf-export-page:last-child {
    break-after: auto;
    page-break-after: auto;
  }
  .viewer-export-content .pdf-export-page img {
    display: block;
    width: 100%;
    height: 100%;
    object-fit: contain;
  }
  .viewer-export-content .pptx-wrapper {
    width: 100% !important;
    max-width: 100% !important;
    height: auto !important;
    overflow: visible !important;
    transform: none !important;
  }
  .viewer-export-content .pptx-wrapper .slide {
    margin: 0 auto 18px !important;
    break-inside: avoid;
    page-break-inside: avoid;
    break-after: page;
    page-break-after: always;
    box-shadow: none !important;
  }
  .viewer-export-content .pptx-wrapper .slide:last-child {
    break-after: auto;
    page-break-after: auto;
  }
  .viewer-export-content .ofd-stage {
    padding: 0 !important;
    overflow: visible !important;
  }
  .viewer-export-content .ofd-page,
  .viewer-export-content .drawing-svg,
  .viewer-export-content .cad-canvas-wrap,
  .viewer-export-content .dwg-preview-frame {
    break-inside: avoid;
    page-break-inside: avoid;
    break-after: page;
    page-break-after: always;
    box-shadow: none !important;
  }
  .viewer-export-content .ofd-page:last-child,
  .viewer-export-content .drawing-svg:last-child,
  .viewer-export-content .cad-canvas-wrap:last-child,
  .viewer-export-content .dwg-preview-frame:last-child {
    break-after: auto;
    page-break-after: auto;
  }
  .viewer-export-content .code-area {
    overflow: visible !important;
    white-space: pre-wrap !important;
    word-break: break-word !important;
  }
  .viewer-export-content .umd-body,
  .viewer-export-content .umd-stage-wrap,
  .viewer-export-content .umd-stage {
    display: block !important;
    height: auto !important;
    max-height: none !important;
    overflow: visible !important;
  }
  .viewer-export-content .umd-toc {
    display: none !important;
  }
  img, canvas, svg, video { max-width: 100%; }
  @media print {
    @page { margin: 12mm; }
    html, body { min-height: auto; background: #ffffff; }
    body { padding: 0; }
    .viewer-export-shell,
    .viewer-export-content {
      min-height: 0;
      overflow: visible;
      background: #ffffff;
    }
    .viewer-export-content .pdf-export-document {
      display: block;
      padding: 0;
    }
    .viewer-export-content .pdf-export-page {
      width: var(--viewer-print-page-width, auto) !important;
      height: var(--viewer-print-page-height, auto) !important;
      max-width: none !important;
      margin: 0;
      overflow: hidden;
      box-shadow: none;
    }
    .viewer-export-content .docx-page-frame {
      width: var(--viewer-print-page-width, auto) !important;
      height: var(--viewer-print-page-height, auto) !important;
      min-height: var(--viewer-print-page-height, 0) !important;
      max-width: none !important;
      margin: 0 !important;
      overflow: hidden !important;
    }
    .viewer-export-content .docx-canvas-sheet {
      contain: none !important;
      width: var(--viewer-print-page-width, 794px) !important;
      height: var(--viewer-print-page-height, 1123px) !important;
      min-height: var(--viewer-print-page-height, 1123px) !important;
      max-width: none !important;
      margin: 0 !important;
      overflow: hidden !important;
      box-shadow: none !important;
    }
    .viewer-export-content .msdoc-page {
      width: var(--viewer-print-page-width, 794px) !important;
      min-height: var(--viewer-print-page-height, 1123px) !important;
      max-width: none !important;
      margin: 0 !important;
      overflow: visible !important;
    }
    .viewer-export-content .docx-page-frame > section.docx,
    .viewer-export-content .msdoc-page > .msdoc-root {
      width: var(--viewer-print-page-width, 100%) !important;
      max-width: none !important;
      border: 0 !important;
    }
    .viewer-export-content .pptx-wrapper .slide,
    .viewer-export-content .ofd-page,
    .viewer-export-content .drawing-svg,
    .viewer-export-content .cad-canvas-wrap,
    .viewer-export-content .dwg-preview-frame {
      box-shadow: none !important;
    }
  }
`,P=e=>{let t=d(e);return t?Array.from(t.querySelectorAll(`style, link[rel="stylesheet"]`)).map(e=>{if(e.localName.toLowerCase()===`style`)return`<style>${e.textContent||``}</style>`;let t=e;try{let e=Array.from(t.sheet?.cssRules||[]).map(e=>e.cssText).join(`
`);return e?`<style data-viewer-inlined-stylesheet>${e}</style>`:``}catch{return``}}).filter(Boolean).join(`
`):``},F=({contentHtml:e,includeDocumentStyles:a=!0,printStyle:o=``,title:s,watermarkInlineStyle:c=``,mask:u=null,documentRef:d})=>{let f=c?`<div class="viewer-export-watermark" style="${l(c)}"></div>`:``,p=t(u),m=r(p?{...p,regions:p.regions?.filter(e=>e.pageIndex===void 0),stamps:p.stamps?.filter(e=>e.pageIndex===void 0)}:null),h=n(e,p),g=a?P(d):``,_=o?`<style data-viewer-print-style>${o}</style>`:``,v=p?`<style data-viewer-print-mask-style>${i}</style>`:``;return`<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>${l(s)}</title>
  ${g}
  <style>${N}</style>
  ${v}
</head>
<body>
  <main class="viewer-export-shell">
    <div class="viewer-export-content">${h}</div>
    ${m}
    ${f}
  </main>
  ${_}
</body>
</html>`},I=e=>k(F(e),e.documentRef),L=e=>M(F(e),e.documentRef),R=async({source:e,mode:n=`export`,title:r,adapter:i=null,watermarkInlineStyle:l=``,mask:u=null})=>{let d={mode:n,title:r},f=i?.toHtml,p=t(u);if(f){await o(e,i);let t=await c(await f(d)),n=await a(i,d);return{contentHtml:t,includeDocumentStyles:i.includeDocumentStyles!==!1,printStyle:n,title:r,watermarkInlineStyle:l,mask:p,documentRef:e.ownerDocument}}await o(e,i);let m=e.cloneNode(!0);m.querySelectorAll(`.viewer-watermark`).forEach(e=>e.remove()),s(e,m);let h=await a(i,d);return{contentHtml:await c(m.innerHTML),printStyle:h,title:r,watermarkInlineStyle:l,mask:p,documentRef:e.ownerDocument}},z=async e=>I(await R(e)),B=async e=>L(await R(e));export{B as buildFileViewerRenderedDomDocument,z as buildFileViewerRenderedHtmlDocument};