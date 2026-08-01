var e=e=>!Number.isFinite(e)||e<=0?0:Number(e.toFixed(3)),t=t=>`${e(t)}px`,n=t=>`${Number((e(t)/96).toFixed(4))}in`,r=e=>{let t=Number.parseFloat(e);return Number.isFinite(t)&&t>0?t:0},i=(t,n={})=>{let i=window.getComputedStyle(t),a=r(i.width)||t.offsetWidth||n.width||t.getBoundingClientRect().width,o=r(i.height)||r(i.minHeight)||t.offsetHeight||n.height||t.getBoundingClientRect().height;return{width:e(a),height:e(o)}},a=(e,n,r={})=>{let i=t(n.width),a=t(n.height),o=r.heightMode||`fixed`;e.classList.add(`viewer-print-page`),e.style.setProperty(`--viewer-print-page-width`,i),e.style.setProperty(`--viewer-print-page-height`,a),e.style.width=i,e.style.maxWidth=`none`,e.style.minHeight=a,o===`fixed`?(e.style.height=a,e.style.overflow=`hidden`):(e.style.height=`auto`,e.style.overflow=`visible`)},o=({selector:e,width:r,height:i,heightMode:a=`fixed`})=>{let o=t(r),s=t(i),c=a===`fixed`?`height:${s}!important;min-height:${s}!important;overflow:hidden!important;`:`height:auto!important;min-height:${s}!important;overflow:visible!important;`;return`
    @page { size: ${n(r)} ${n(i)}; margin: 0; }
    @media print {
      html, body {
        width: ${o};
        min-width: ${o};
        background: #ffffff !important;
      }
      ${e} {
        width: ${o}!important;
        max-width: none!important;
        ${c}
        margin: 0!important;
        box-shadow: none!important;
        border: 0!important;
        break-after: page;
        page-break-after: always;
      }
      ${e}:last-child {
        break-after: auto;
        page-break-after: auto;
      }
    }
  `};export{i,o as n,t as r,a as t};