import{n as e,r as t}from"./objectSpread2-BADuQQie.js";import{a as n,c as r,i,l as a,n as o,o as s,r as c,s as l,t as u}from"./export-BHuNh29X.js";import{n as d,o as f,r as p,t as ee}from"./printMask-A-0eATiv.js";function te(e,t){(t==null||t>e.length)&&(t=e.length);for(var n=0,r=Array(t);n<t;n++)r[n]=e[n];return r}function m(e){if(Array.isArray(e))return e}function h(e,t){var n=e==null?null:typeof Symbol<`u`&&e[Symbol.iterator]||e[`@@iterator`];if(n!=null){var r,i,a,o,s=[],c=!0,l=!1;try{if(a=(n=n.call(e)).next,t!==0)for(;!(c=(r=a.call(n)).done)&&(s.push(r.value),s.length!==t);c=!0);}catch(e){l=!0,i=e}finally{try{if(!c&&n.return!=null&&(o=n.return(),Object(o)!==o))return}finally{if(l)throw i}}return s}}function ne(){throw TypeError(`Invalid attempt to destructure non-iterable instance.
In order to be iterable, non-array objects must have a [Symbol.iterator]() method.`)}function re(e,t){return m(e)||h(e,t)||g(e,t)||ne()}function g(e,t){if(e){if(typeof e==`string`)return te(e,t);var n={}.toString.call(e).slice(8,-1);return n===`Object`&&e.constructor&&(n=e.constructor.name),n===`Map`||n===`Set`?Array.from(e):n===`Arguments`||/^(?:Ui|I)nt(?:8|16|32)(?:Clamped)?Array$/.test(n)?te(e,t):void 0}}var ie=Object.entries,_=Object.setPrototypeOf,ae=Object.isFrozen,v=Object.getPrototypeOf,oe=Object.getOwnPropertyDescriptor,y=Object.freeze,b=Object.seal,se=Object.create,x=typeof Reflect<`u`&&Reflect,S=x.apply,C=x.construct;y||(y=function(e){return e}),b||(b=function(e){return e}),S||(S=function(e,t){var n=[...arguments].slice(2);return e.apply(t,n)}),C||(C=function(e){return new e(...[...arguments].slice(1))});var w=M(Array.prototype.forEach),ce=M(Array.prototype.lastIndexOf),le=M(Array.prototype.pop),ue=M(Array.prototype.push),de=M(Array.prototype.splice),T=Array.isArray,fe=M(String.prototype.toLowerCase),pe=M(String.prototype.toString),me=M(String.prototype.match),he=M(String.prototype.replace),ge=M(String.prototype.indexOf),_e=M(String.prototype.trim),ve=M(Number.prototype.toString),E=M(Boolean.prototype.toString),ye=typeof BigInt>`u`?null:M(BigInt.prototype.toString),D=typeof Symbol>`u`?null:M(Symbol.prototype.toString),O=M(Object.prototype.hasOwnProperty),k=M(Object.prototype.toString),A=M(RegExp.prototype.test),j=be(TypeError);function M(e){return function(t){t instanceof RegExp&&(t.lastIndex=0);var n=[...arguments].slice(1);return S(e,t,n)}}function be(e){return function(){return C(e,[...arguments])}}function N(e,t){let n=arguments.length>2&&arguments[2]!==void 0?arguments[2]:fe;if(_&&_(e,null),!T(t))return e;let r=t.length;for(;r--;){let i=t[r];if(typeof i==`string`){let e=n(i);e!==i&&(ae(t)||(t[r]=e),i=e)}e[i]=!0}return e}function xe(e){for(let t=0;t<e.length;t++)O(e,t)||(e[t]=null);return e}function P(e){let t=se(null);for(let r of ie(e)){var n=re(r,2);let i=n[0],a=n[1];O(e,i)&&(t[i]=T(a)?xe(a):a&&typeof a==`object`&&a.constructor===Object?P(a):a)}return t}function Se(e){switch(typeof e){case`string`:return e;case`number`:return ve(e);case`boolean`:return E(e);case`bigint`:return ye?ye(e):`0`;case`symbol`:return D?D(e):`Symbol()`;case`undefined`:return k(e);case`function`:case`object`:{if(e===null)return k(e);let t=e,n=F(t,`toString`);if(typeof n==`function`){let e=n(t);return typeof e==`string`?e:k(e)}return k(e)}default:return k(e)}}function F(e,t){for(;e!==null;){let n=oe(e,t);if(n){if(n.get)return M(n.get);if(typeof n.value==`function`)return M(n.value)}e=v(e)}function n(){return null}return n}function Ce(e){try{return A(e,``),!0}catch{return!1}}var we=y(`a.abbr.acronym.address.area.article.aside.audio.b.bdi.bdo.big.blink.blockquote.body.br.button.canvas.caption.center.cite.code.col.colgroup.content.data.datalist.dd.decorator.del.details.dfn.dialog.dir.div.dl.dt.element.em.fieldset.figcaption.figure.font.footer.form.h1.h2.h3.h4.h5.h6.head.header.hgroup.hr.html.i.img.input.ins.kbd.label.legend.li.main.map.mark.marquee.menu.menuitem.meter.nav.nobr.ol.optgroup.option.output.p.picture.pre.progress.q.rp.rt.ruby.s.samp.search.section.select.shadow.slot.small.source.spacer.span.strike.strong.style.sub.summary.sup.table.tbody.td.template.textarea.tfoot.th.thead.time.tr.track.tt.u.ul.var.video.wbr`.split(`.`)),Te=y(`svg.a.altglyph.altglyphdef.altglyphitem.animatecolor.animatemotion.animatetransform.circle.clippath.defs.desc.ellipse.enterkeyhint.exportparts.filter.font.g.glyph.glyphref.hkern.image.inputmode.line.lineargradient.marker.mask.metadata.mpath.part.path.pattern.polygon.polyline.radialgradient.rect.stop.style.switch.symbol.text.textpath.title.tref.tspan.view.vkern`.split(`.`)),Ee=y([`feBlend`,`feColorMatrix`,`feComponentTransfer`,`feComposite`,`feConvolveMatrix`,`feDiffuseLighting`,`feDisplacementMap`,`feDistantLight`,`feDropShadow`,`feFlood`,`feFuncA`,`feFuncB`,`feFuncG`,`feFuncR`,`feGaussianBlur`,`feImage`,`feMerge`,`feMergeNode`,`feMorphology`,`feOffset`,`fePointLight`,`feSpecularLighting`,`feSpotLight`,`feTile`,`feTurbulence`]),De=y([`animate`,`color-profile`,`cursor`,`discard`,`font-face`,`font-face-format`,`font-face-name`,`font-face-src`,`font-face-uri`,`foreignobject`,`hatch`,`hatchpath`,`mesh`,`meshgradient`,`meshpatch`,`meshrow`,`missing-glyph`,`script`,`set`,`solidcolor`,`unknown`,`use`]),Oe=y(`math.menclose.merror.mfenced.mfrac.mglyph.mi.mlabeledtr.mmultiscripts.mn.mo.mover.mpadded.mphantom.mroot.mrow.ms.mspace.msqrt.mstyle.msub.msup.msubsup.mtable.mtd.mtext.mtr.munder.munderover.mprescripts`.split(`.`)),ke=y([`maction`,`maligngroup`,`malignmark`,`mlongdiv`,`mscarries`,`mscarry`,`msgroup`,`mstack`,`msline`,`msrow`,`semantics`,`annotation`,`annotation-xml`,`mprescripts`,`none`]),Ae=y([`#text`]),je=y(`accept.action.align.alt.autocapitalize.autocomplete.autopictureinpicture.autoplay.background.bgcolor.border.capture.cellpadding.cellspacing.checked.cite.class.clear.color.cols.colspan.command.commandfor.controls.controlslist.coords.crossorigin.datetime.decoding.default.dir.disabled.disablepictureinpicture.disableremoteplayback.download.draggable.enctype.enterkeyhint.exportparts.face.for.headers.height.hidden.high.href.hreflang.id.inert.inputmode.integrity.ismap.kind.label.lang.list.loading.loop.low.max.maxlength.media.method.min.minlength.multiple.muted.name.nonce.noshade.novalidate.nowrap.open.optimum.part.pattern.placeholder.playsinline.popover.popovertarget.popovertargetaction.poster.preload.pubdate.radiogroup.readonly.rel.required.rev.reversed.role.rows.rowspan.spellcheck.scope.selected.shape.size.sizes.slot.span.srclang.start.src.srcset.step.style.summary.tabindex.title.translate.type.usemap.valign.value.width.wrap.xmlns`.split(`.`)),Me=y(`accent-height.accumulate.additive.alignment-baseline.amplitude.ascent.attributename.attributetype.azimuth.basefrequency.baseline-shift.begin.bias.by.class.clip.clippathunits.clip-path.clip-rule.color.color-interpolation.color-interpolation-filters.color-profile.color-rendering.cx.cy.d.dx.dy.diffuseconstant.direction.display.divisor.dominant-baseline.dur.edgemode.elevation.end.exponent.fill.fill-opacity.fill-rule.filter.filterunits.flood-color.flood-opacity.font-family.font-size.font-size-adjust.font-stretch.font-style.font-variant.font-weight.fx.fy.g1.g2.glyph-name.glyphref.gradientunits.gradienttransform.height.href.id.image-rendering.in.in2.intercept.k.k1.k2.k3.k4.kerning.keypoints.keysplines.keytimes.lang.lengthadjust.letter-spacing.kernelmatrix.kernelunitlength.lighting-color.local.marker-end.marker-mid.marker-start.markerheight.markerunits.markerwidth.maskcontentunits.maskunits.max.mask.mask-type.media.method.mode.min.name.numoctaves.offset.operator.opacity.order.orient.orientation.origin.overflow.paint-order.path.pathlength.patterncontentunits.patterntransform.patternunits.pointer-events.points.preservealpha.preserveaspectratio.primitiveunits.r.rx.ry.radius.refx.refy.repeatcount.repeatdur.restart.result.rotate.scale.seed.shape-rendering.slope.specularconstant.specularexponent.spreadmethod.startoffset.stddeviation.stitchtiles.stop-color.stop-opacity.stroke-dasharray.stroke-dashoffset.stroke-linecap.stroke-linejoin.stroke-miterlimit.stroke-opacity.stroke.stroke-width.style.surfacescale.systemlanguage.tabindex.tablevalues.targetx.targety.transform.transform-origin.text-anchor.text-decoration.text-orientation.text-rendering.textlength.type.u1.u2.unicode.values.vector-effect.viewbox.visibility.version.vert-adv-y.vert-origin-x.vert-origin-y.width.word-spacing.wrap.writing-mode.xchannelselector.ychannelselector.x.x1.x2.xmlns.y.y1.y2.z.zoomandpan`.split(`.`)),Ne=y(`accent.accentunder.align.bevelled.close.columnalign.columnlines.columnspacing.columnspan.denomalign.depth.dir.display.displaystyle.encoding.fence.frame.height.href.id.largeop.length.linethickness.lquote.lspace.mathbackground.mathcolor.mathsize.mathvariant.maxsize.minsize.movablelimits.notation.numalign.open.rowalign.rowlines.rowspacing.rowspan.rspace.rquote.scriptlevel.scriptminsize.scriptsizemultiplier.selection.separator.separators.stretchy.subscriptshift.supscriptshift.symmetric.voffset.width.xmlns`.split(`.`)),Pe=y([`xlink:href`,`xml:id`,`xlink:title`,`xml:space`,`xmlns:xlink`]),Fe=b(/{{[\w\W]*|^[\w\W]*}}/g),Ie=b(/<%[\w\W]*|^[\w\W]*%>/g),Le=b(/\${[\w\W]*/g),Re=b(/^data-[\-\w.\u00B7-\uFFFF]+$/),ze=b(/^aria-[\-\w]+$/),Be=b(/^(?:(?:(?:f|ht)tps?|mailto|tel|callto|sms|cid|xmpp|matrix):|[^a-z]|[a-z+.\-]+(?:[^a-z+.\-:]|$))/i),Ve=b(/^(?:\w+script|data):/i),He=b(/[\u0000-\u0020\u00A0\u1680\u180E\u2000-\u2029\u205F\u3000]/g),Ue=b(/^html$/i),We=b(/^[a-z][.\w]*(-[.\w]+)+$/i),Ge=b(/<[/\w!]/g),Ke=b(/<[/\w]/g),qe=b(/<\/no(script|embed|frames)/i),Je=b(/\/>/i),I={element:1,attribute:2,text:3,cdataSection:4,entityReference:5,entityNode:6,processingInstruction:7,comment:8,document:9,documentType:10,documentFragment:11,notation:12},Ye=[`style`,`script`,`xmp`,`iframe`,`noembed`,`noframes`,`plaintext`,`noscript`],Xe=y(N({},Ye)),Ze=function(){let e={};return w(Ye,t=>{e[t]=b(RegExp(`</`+t+`(?=[\\t\\n\\f\\r />])`,`i`))}),y(e)}(),Qe=function(){return typeof window>`u`?null:window},$e=function(e,t){if(typeof e!=`object`||typeof e.createPolicy!=`function`)return null;let n=null,r=`data-tt-policy-suffix`;t&&t.hasAttribute(r)&&(n=t.getAttribute(r));let i=`dompurify`+(n?`#`+n:``);try{return e.createPolicy(i,{createHTML(e){return e},createScriptURL(e){return e}})}catch{return console.warn(`TrustedTypes policy `+i+` could not be created.`),null}},et=function(){return{afterSanitizeAttributes:[],afterSanitizeElements:[],afterSanitizeShadowDOM:[],beforeSanitizeAttributes:[],beforeSanitizeElements:[],beforeSanitizeShadowDOM:[],uponSanitizeAttribute:[],uponSanitizeElement:[],uponSanitizeShadowNode:[]}},L=function(e,t,n,r){return O(e,t)&&T(e[t])?N(r.base?P(r.base):{},e[t],r.transform):n},tt=function(e,t,n){let r=O(e,t)?e[t]:void 0;return r&&typeof r==`object`?P(r):n()};function nt(){let e=arguments.length>0&&arguments[0]!==void 0?arguments[0]:Qe(),t=e=>nt(e);if(t.version=`3.4.15`,t.removed=[],!e||!e.document||e.document.nodeType!==I.document||!e.Element)return t.isSupported=!1,t;let n=e.document,r=n,i=r.currentScript;e.DocumentFragment;let a=e.HTMLTemplateElement,o=e.Node,s=e.Element,c=e.NodeFilter;e.NamedNodeMap===void 0&&(e.NamedNodeMap||e.MozNamedAttrMap),e.HTMLFormElement;let l=e.DOMParser,u=e.trustedTypes,d=s.prototype,f=F(d,`cloneNode`),p=F(d,`remove`),ee=F(d,`removeAttributeNode`),te=F(d,`nextSibling`),m=F(d,`childNodes`),h=F(d,`parentNode`),ne=F(d,`shadowRoot`),re=F(d,`attributes`),g=o&&o.prototype?F(o.prototype,`nodeType`):null,_=o&&o.prototype?F(o.prototype,`nodeName`):null,ae=o&&o.prototype?F(o.prototype,`ownerDocument`):null,v=function(e){return g?g(e):e.nodeType},oe=function(e){return _?_(e):e.nodeName};if(typeof a==`function`){let e=n.createElement(`template`);e.content&&e.content.ownerDocument&&(n=e.content.ownerDocument)}let x,S=``,C,ve=!1,E=0,ye=function(){if(E>0)throw j(`A configured TRUSTED_TYPES_POLICY callback (createHTML or createScriptURL) must not call DOMPurify.sanitize, as that causes infinite recursion. Do not pass a policy whose callbacks wrap DOMPurify as TRUSTED_TYPES_POLICY; see the "DOMPurify and Trusted Types" section of the README.`)},D=function(e){ye(),E++;try{return x.createHTML(e)}finally{E--}},k=function(e){ye(),E++;try{return x.createScriptURL(e)}finally{E--}},M=function(){return ve||(C=$e(u,i),ve=!0),C},be=n,xe=be.implementation,Ye=be.createNodeIterator,rt=be.createDocumentFragment,it=be.getElementsByTagName,at=r.importNode,R=et();t.isSupported=typeof ie==`function`&&typeof h==`function`&&xe&&xe.createHTMLDocument!==void 0;let ot=Fe,st=Ie,ct=Le,lt=Re,ut=ze,dt=Ve,ft=He,pt=We,mt=Be,z=null,ht=N({},[...we,...Te,...Ee,...Oe,...Ae]),B=null,gt=N({},[...je,...Me,...Ne,...Pe]),V=Object.seal(se(null,{tagNameCheck:{writable:!0,configurable:!1,enumerable:!0,value:null},attributeNameCheck:{writable:!0,configurable:!1,enumerable:!0,value:null},allowCustomizedBuiltInElements:{writable:!0,configurable:!1,enumerable:!0,value:!1}})),H=null,_t=null,U=Object.seal(se(null,{tagCheck:{writable:!0,configurable:!1,enumerable:!0,value:null},attributeCheck:{writable:!0,configurable:!1,enumerable:!0,value:null}})),vt=!0,yt=!0,bt=!1,xt=!0,W=!1,G=!0,K=!1,St=!1,q=null,Ct=null,wt=!1,J=!1,Tt=!1,Et=!1,Dt=!0,Ot=!1,kt=`user-content-`,At=!0,jt=!1,Mt={},Nt=null,Pt=N({},`annotation-xml.audio.colgroup.desc.foreignobject.head.iframe.math.mi.mn.mo.ms.mtext.noembed.noframes.noscript.plaintext.script.selectedcontent.style.svg.template.thead.title.video.xmp`.split(`.`)),Ft=null,It=N({},[`audio`,`video`,`img`,`source`,`image`,`track`]),Lt=null,Rt=N({},[`alt`,`class`,`for`,`id`,`label`,`name`,`pattern`,`placeholder`,`role`,`summary`,`title`,`value`,`style`,`xmlns`]),zt=`http://www.w3.org/1998/Math/MathML`,Bt=`http://www.w3.org/2000/svg`,Y=`http://www.w3.org/1999/xhtml`,Vt=Y,Ht=!1,Ut=null,Wt=N({},[zt,Bt,Y],pe),Gt=y([`mi`,`mo`,`mn`,`ms`,`mtext`]),Kt=N({},Gt),qt=y([`annotation-xml`]),Jt=N({},qt),Yt=N({},[`title`,`style`,`font`,`a`,`script`]),Xt=null,Zt=[`application/xhtml+xml`,`text/html`],X=null,Qt=null,$t=n.createElement(`form`),en=function(e){return e instanceof RegExp||e instanceof Function},tn=function(){let e=arguments.length>0&&arguments[0]!==void 0?arguments[0]:{};if(Qt&&Qt===e)return;(!e||typeof e!=`object`)&&(e={}),e=P(e),Xt=Zt.indexOf(e.PARSER_MEDIA_TYPE)===-1?`text/html`:e.PARSER_MEDIA_TYPE,X=Xt===`application/xhtml+xml`?pe:fe,z=L(e,`ALLOWED_TAGS`,ht,{transform:X}),B=L(e,`ALLOWED_ATTR`,gt,{transform:X}),Ut=L(e,`ALLOWED_NAMESPACES`,Wt,{transform:pe}),Lt=L(e,`ADD_URI_SAFE_ATTR`,Rt,{transform:X,base:Rt}),Ft=L(e,`ADD_DATA_URI_TAGS`,It,{transform:X,base:It}),Nt=L(e,`FORBID_CONTENTS`,Pt,{transform:X}),H=L(e,`FORBID_TAGS`,P({}),{transform:X}),_t=L(e,`FORBID_ATTR`,P({}),{transform:X}),Mt=O(e,`USE_PROFILES`)?e.USE_PROFILES&&typeof e.USE_PROFILES==`object`?P(e.USE_PROFILES):e.USE_PROFILES:!1,vt=e.ALLOW_ARIA_ATTR!==!1,yt=e.ALLOW_DATA_ATTR!==!1,bt=e.ALLOW_UNKNOWN_PROTOCOLS||!1,xt=e.ALLOW_SELF_CLOSE_IN_ATTR!==!1,W=e.SAFE_FOR_TEMPLATES||!1,G=e.SAFE_FOR_XML!==!1,K=e.WHOLE_DOCUMENT||!1,J=e.RETURN_DOM||!1,Tt=e.RETURN_DOM_FRAGMENT||!1,Et=e.RETURN_TRUSTED_TYPE||!1,wt=e.FORCE_BODY||!1,Dt=e.SANITIZE_DOM!==!1,Ot=e.SANITIZE_NAMED_PROPS||!1,At=e.KEEP_CONTENT!==!1,jt=e.IN_PLACE||!1,mt=Ce(e.ALLOWED_URI_REGEXP)?e.ALLOWED_URI_REGEXP:Be,Vt=typeof e.NAMESPACE==`string`?e.NAMESPACE:Y,Kt=tt(e,`MATHML_TEXT_INTEGRATION_POINTS`,()=>N({},Gt)),Jt=tt(e,`HTML_INTEGRATION_POINTS`,()=>N({},qt));let t=tt(e,`CUSTOM_ELEMENT_HANDLING`,()=>se(null));if(V=se(null),O(t,`tagNameCheck`)&&en(t.tagNameCheck)&&(V.tagNameCheck=t.tagNameCheck),O(t,`attributeNameCheck`)&&en(t.attributeNameCheck)&&(V.attributeNameCheck=t.attributeNameCheck),O(t,`allowCustomizedBuiltInElements`)&&typeof t.allowCustomizedBuiltInElements==`boolean`&&(V.allowCustomizedBuiltInElements=t.allowCustomizedBuiltInElements),b(V),W&&(yt=!1),Tt&&(J=!0),Mt&&(z=N({},Ae),B=se(null),Mt.html===!0&&(N(z,we),N(B,je)),Mt.svg===!0&&(N(z,Te),N(B,Me),N(B,Pe)),Mt.svgFilters===!0&&(N(z,Ee),N(B,Me),N(B,Pe)),Mt.mathMl===!0&&(N(z,Oe),N(B,Ne),N(B,Pe))),U.tagCheck=null,U.attributeCheck=null,O(e,`ADD_TAGS`)&&(typeof e.ADD_TAGS==`function`?U.tagCheck=e.ADD_TAGS:T(e.ADD_TAGS)&&(z===ht&&(z=P(z)),N(z,e.ADD_TAGS,X))),O(e,`ADD_ATTR`)&&(typeof e.ADD_ATTR==`function`?U.attributeCheck=e.ADD_ATTR:T(e.ADD_ATTR)&&(B===gt&&(B=P(B)),N(B,e.ADD_ATTR,X))),O(e,`ADD_FORBID_CONTENTS`)&&T(e.ADD_FORBID_CONTENTS)&&(Nt===Pt&&(Nt=P(Nt)),N(Nt,e.ADD_FORBID_CONTENTS,X)),At&&(z[`#text`]=!0),K&&N(z,[`html`,`head`,`body`]),z.table&&(N(z,[`tbody`]),delete H.tbody),e.TRUSTED_TYPES_POLICY){if(typeof e.TRUSTED_TYPES_POLICY.createHTML!=`function`)throw j(`TRUSTED_TYPES_POLICY configuration option must provide a "createHTML" hook.`);if(typeof e.TRUSTED_TYPES_POLICY.createScriptURL!=`function`)throw j(`TRUSTED_TYPES_POLICY configuration option must provide a "createScriptURL" hook.`);let t=x;x=e.TRUSTED_TYPES_POLICY;try{S=D(``)}catch(e){throw x=t,e}}else e.TRUSTED_TYPES_POLICY===null?(x=void 0,S=``):(x===void 0&&(x=M()),x&&typeof S==`string`&&(S=D(``)));y&&y(e),Qt=e},nn=N({},[...Te,...Ee,...De]),rn=N({},[...Oe,...ke]),an=function(e,t,n){return t.namespaceURI===Y?e===`svg`:t.namespaceURI===zt?e===`svg`&&(n===`annotation-xml`||Kt[n]):!!nn[e]},on=function(e,t,n){return t.namespaceURI===Y?e===`math`:t.namespaceURI===Bt?e===`math`&&Jt[n]:!!rn[e]},sn=function(e,t,n){return t.namespaceURI===Bt&&!Jt[n]||t.namespaceURI===zt&&!Kt[n]?!1:!rn[e]&&(Yt[e]||!nn[e])},cn=function(e){let t=h(e);(!t||!t.tagName)&&(t={namespaceURI:Vt,tagName:`template`});let n=fe(e.tagName),r=fe(t.tagName);return Ut[e.namespaceURI]?e.namespaceURI===Bt?an(n,t,r):e.namespaceURI===zt?on(n,t,r):e.namespaceURI===Y?sn(n,t,r):!!(Xt===`application/xhtml+xml`&&Ut[e.namespaceURI]):!1},Z=function(e){ue(t.removed,{element:e});try{h(e).removeChild(e)}catch{if(p(e),!h(e))throw j(`a node selected for removal could not be detached from its tree and cannot be safely returned; refusing to sanitize in place`)}},ln=function(e,t,n){try{ee(e,t)}catch{try{e.removeAttribute(n)}catch{}}},un=function(e){fn(e);let t=m(e);if(t){let e=[];w(t,t=>{ue(e,t)}),w(e,e=>{try{p(e)}catch{}})}let n=re(e);if(n)for(let t=n.length-1;t>=0;--t){let r=n[t],i=r&&r.name;typeof i==`string`&&ln(e,r,i)}},Q=function(e,n,r){if(!r)try{r=n.getAttributeNode(e)}catch{r=null}ue(t.removed,{attribute:r||null,from:n});try{r?ee(n,r):n.removeAttribute(e)}catch{try{n.removeAttribute(e)}catch{}}if(e===`is`)if(J||Tt)try{Z(n)}catch{}else try{n.setAttribute(e,``)}catch{}},dn=function(e){let t=re(e);if(t)for(let n=t.length-1;n>=0;--n){let r=t[n],i=r&&r.name;typeof i!=`string`||B[X(i)]||ln(e,r,i)}},fn=function(e){let t=[e];for(;t.length>0;){let e=t.pop();v(e)===I.element&&dn(e);let n=m(e);if(n)for(let e=n.length-1;e>=0;--e)t.push(n[e])}},pn=function(e,t){return G?e===`patchsrc`||e===`for`&&t!==`label`&&t!==`output`:!1},mn=function(e){if(!G)return;let t=[e];for(;t.length>0;){let e=t.pop(),n=v(e);if(n===I.processingInstruction||n===I.comment&&A(Ke,e.data)){try{p(e)}catch{}continue}if(n===I.element){let t=e,n=X(oe(e));try{t.hasAttribute&&t.hasAttribute(`patchsrc`)&&t.removeAttribute(`patchsrc`),t.hasAttribute&&t.hasAttribute(`for`)&&pn(`for`,n)&&t.removeAttribute(`for`)}catch{}}let r=m(e);if(r)for(let e=r.length-1;e>=0;--e)t.push(r[e])}},hn=function(e){let t=null,r=null;if(wt)e=`<remove></remove>`+e;else{let t=me(e,/^[\r\n\t ]+/);r=t&&t[0]}Xt===`application/xhtml+xml`&&Vt===Y&&(e=`<html xmlns="http://www.w3.org/1999/xhtml"><head></head><body>`+e+`</body></html>`);let i=x?D(e):e;if(Vt===Y)try{t=new l().parseFromString(i,Xt)}catch{}if(!t||!t.documentElement){t=xe.createDocument(Vt,`template`,null);try{t.documentElement.innerHTML=Ht?S:i}catch{}}let a=t.body||t.documentElement;return e&&r&&a.insertBefore(n.createTextNode(r),a.childNodes[0]||null),Vt===Y?it.call(t,K?`html`:`body`)[0]:K?t.documentElement:a},gn=function(e){let t=ae?ae(e):e.ownerDocument;return Ye.call(t||e,e,c.SHOW_ELEMENT|c.SHOW_COMMENT|c.SHOW_TEXT|c.SHOW_PROCESSING_INSTRUCTION|c.SHOW_CDATA_SECTION,null)},_n=function(e){return e=he(e,ot,` `),e=he(e,st,` `),e=he(e,ct,` `),e},vn=function(e){e.normalize();let t=ae?ae(e):e.ownerDocument,n=Ye.call(t||e,e,c.SHOW_TEXT|c.SHOW_COMMENT|c.SHOW_CDATA_SECTION|c.SHOW_PROCESSING_INSTRUCTION,null),r=n.nextNode();for(;r;)r.data=_n(r.data),r=n.nextNode();let i=e.querySelectorAll?.call(e,`template`);i&&w(i,e=>{bn(e.content)&&vn(e.content)})},yn=function(e){let t=_?_(e):null;return typeof t!=`string`||X(t)!==`form`?!1:typeof e.nodeName!=`string`||typeof e.textContent!=`string`||typeof e.removeChild!=`function`||e.attributes!==re(e)||typeof e.removeAttribute!=`function`||typeof e.removeAttributeNode!=`function`||typeof e.getAttributeNode!=`function`||typeof e.setAttribute!=`function`||typeof e.namespaceURI!=`string`||typeof e.insertBefore!=`function`||typeof e.hasChildNodes!=`function`||e.nodeType!==g(e)||e.childNodes!==m(e)},bn=function(e){if(!g||typeof e!=`object`||!e)return!1;try{return g(e)===I.documentFragment}catch{return!1}},xn=function(e){if(!g||typeof e!=`object`||!e)return!1;try{return typeof g(e)==`number`}catch{return!1}};function $(e,n,r){e.length!==0&&w(e,e=>{e.call(t,n,r,Qt)})}let Sn=function(e,t){return!!(G&&e.hasChildNodes()&&!xn(e.firstElementChild)&&A(Ge,e.textContent)&&A(Ge,e.innerHTML)||G&&e.namespaceURI===Y&&Xe[t]&&(xn(e.firstElementChild)||typeof e.textContent==`string`&&A(Ze[t],e.textContent))||e.nodeType===I.processingInstruction||G&&e.nodeType===I.comment&&A(Ke,e.data))},Cn=function(e,t){return e instanceof RegExp?A(e,t):e instanceof Function&&!!e(t,...[...arguments].slice(2))},wn=function(e,t,n){if(!H[t]&&An(t)&&Cn(V.tagNameCheck,t))return!1;if(At&&!Nt[t]){let t=h(e),r=m(e);if(r&&t){let i=r.length;for(let a=i-1;a>=0;--a){let i=e===n?f(r[a],!0):r[a];t.insertBefore(i,te(e))}}}return Z(e),!0},Tn=function(e,t,n,r){return e.length===0?t:t===n||t===r?P(t):t},En=function(e,t){return e===t||h(e)!==null?!1:(jt&&fn(e),!0)},Dn=function(e,n){if($(R.beforeSanitizeElements,e,null),En(e,n))return!0;if(yn(e))return Z(e),!0;let r=X(oe(e));if(z=Tn(R.uponSanitizeElement,z,ht,q),$(R.uponSanitizeElement,e,{tagName:r,allowedTags:z}),En(e,n))return!0;if(Sn(e,r))return Z(e),!0;if(H[r]||!(U.tagCheck instanceof Function&&U.tagCheck(r))&&!z[r]){let t=wn(e,r,n);return t===!1&&$(R.afterSanitizeElements,e,null),t}if(v(e)===I.element&&!cn(e)||(r===`noscript`||r===`noembed`||r===`noframes`)&&A(qe,e.innerHTML))return Z(e),!0;if(W&&e.nodeType===I.text){let n=_n(e.textContent);e.textContent!==n&&(ue(t.removed,{element:e.cloneNode()}),e.textContent=n)}return $(R.afterSanitizeElements,e,null),!1},On=function(e,t,r){if(_t[t]||pn(t,e)||Dt&&(t===`id`||t===`name`)&&(r in n||r in $t))return!1;let i=B[t]||U.attributeCheck instanceof Function&&U.attributeCheck(t,e);return yt&&A(lt,t)||vt&&A(ut,t)?!0:i?Lt[t]||A(mt,he(r,ft,``))||(t===`src`||t===`xlink:href`||t===`href`)&&e!==`script`&&ge(r,`data:`)===0&&Ft[e]||bt&&!A(dt,he(r,ft,``))?!0:!r:An(e)&&Cn(V.tagNameCheck,e)&&Cn(V.attributeNameCheck,t,e)||t===`is`&&V.allowCustomizedBuiltInElements&&Cn(V.tagNameCheck,r)},kn=N({},[`annotation-xml`,`color-profile`,`font-face`,`font-face-format`,`font-face-name`,`font-face-src`,`font-face-uri`,`missing-glyph`]),An=function(e){return!kn[fe(e)]&&A(pt,e)},jn=function(e,t,n,r){if(x&&typeof u==`object`&&typeof u.getAttributeType==`function`&&!n)switch(u.getAttributeType(e,t)){case`TrustedHTML`:return D(r);case`TrustedScriptURL`:return k(r)}return r},Mn=function(e,t,n,r){try{return n?e.setAttributeNS(n,t,r):e.setAttribute(t,r),!yn(e)||(Z(e),!1)}catch{return Q(t,e),!1}},Nn=function(e){$(R.beforeSanitizeAttributes,e,null);let n=e.attributes;if(!n||yn(e))return;B=Tn(R.uponSanitizeAttribute,B,gt,Ct);let r={attrName:``,attrValue:``,keepAttr:!0,allowedAttributes:B,forceKeepAttr:void 0},i=n.length,a=X(e.nodeName);for(;i--;){let o=n[i],s=o.name,c=o.namespaceURI,l=o.value,u=X(s),d=l,f=s===`value`?d:_e(d),p=!1;if(r.attrName=u,r.attrValue=f,r.keepAttr=!0,r.forceKeepAttr=void 0,$(R.uponSanitizeAttribute,e,r),f=r.attrValue,Ot&&(u===`id`||u===`name`)&&ge(f,kt)!==0&&(Q(s,e,o),f=kt+f,p=!0),G&&A(/((--!?|])>)|<\/(style|script|title|xmp|textarea|noscript|iframe|noembed|noframes)/i,f)){Q(s,e,o);continue}if(u===`attributename`&&me(f,`href`)){Q(s,e,o);continue}if(!r.forceKeepAttr){if(!r.keepAttr){Q(s,e,o);continue}if(!xt&&A(Je,f)){Q(s,e,o);continue}if(W&&(f=_n(f)),!On(a,u,f)){Q(s,e,o);continue}f=jn(a,u,c,f),f!==d&&Mn(e,s,c,f)&&p&&le(t.removed)}}$(R.afterSanitizeAttributes,e,null)},Pn=function(e){let t=null,n=gn(e);for($(R.beforeSanitizeShadowDOM,e,null);t=n.nextNode();)if($(R.uponSanitizeShadowNode,t,null),Dn(t,e),Nn(t),bn(t.content)&&Pn(t.content),v(t)===I.element){let e=ne(t);bn(e)&&(Fn(e),Pn(e))}$(R.afterSanitizeShadowDOM,e,null)},Fn=function(e){let t=[{node:e,shadow:null}];for(;t.length>0;){let e=t.pop();if(e.shadow){Pn(e.shadow);continue}let n=e.node,r=v(n)===I.element,i=m(n);if(i)for(let e=i.length-1;e>=0;--e)t.push({node:i[e],shadow:null});if(r){let e=_?_(n):null;if(typeof e==`string`&&X(e)===`template`){let e=n.content;bn(e)&&t.push({node:e,shadow:null})}}if(r){let e=ne(n);bn(e)&&t.push({node:null,shadow:e},{node:e,shadow:null})}}};return t.sanitize=function(e){let n=arguments.length>1&&arguments[1]!==void 0?arguments[1]:{},i=null,a=null,o=null,s=null;if(Ht=!e,Ht&&(e=`<!-->`),typeof e!=`string`&&!xn(e)&&(e=Se(e),typeof e!=`string`))throw j(`dirty is not a string, aborting`);if(!t.isSupported)return e;St?(z=q,B=Ct):tn(n),(R.uponSanitizeElement.length>0||R.uponSanitizeAttribute.length>0)&&(z=P(z)),R.uponSanitizeAttribute.length>0&&(B=P(B)),t.removed=[];let c=jt&&typeof e!=`string`&&xn(e);if(c){mn(e);let t=oe(e);if(typeof t==`string`){let n=X(t);if(!z[n]||H[n])throw un(e),j(`root node is forbidden and cannot be sanitized in-place`)}if(yn(e))throw un(e),j(`root node is clobbered and cannot be sanitized in-place`);try{Fn(e)}catch(t){throw un(e),t}}else if(xn(e))i=hn(`<!---->`),a=i.ownerDocument.importNode(e,!0),a.nodeType===I.element&&a.nodeName===`BODY`||a.nodeName===`HTML`?i=a:i.appendChild(a),Fn(i);else{if(!J&&!W&&!K&&e.indexOf(`<`)===-1)return x&&Et?D(e):e;if(i=hn(e),!i)return J?null:Et?S:``}i&&wt&&Z(i.firstChild);let l=c?e:i;try{let e=gn(l);for(;o=e.nextNode();)Dn(o,l),Nn(o),bn(o.content)&&Pn(o.content)}catch(n){throw c&&(un(e),w(t.removed,e=>{e.element&&fn(e.element)})),n}if(c)return w(t.removed,e=>{e.element&&fn(e.element)}),W&&vn(e),e;if(J){if(W&&vn(i),Tt)for(s=rt.call(i.ownerDocument);i.firstChild;)s.appendChild(i.firstChild);else s=i;return(B.shadowroot||B.shadowrootmode)&&(s=at.call(r,s,!0)),s}let u=K?i.outerHTML:i.innerHTML;return K&&z[`!doctype`]&&i.ownerDocument&&i.ownerDocument.doctype&&i.ownerDocument.doctype.name&&A(Ue,i.ownerDocument.doctype.name)&&(u=`<!DOCTYPE `+i.ownerDocument.doctype.name+`>
`+u),W&&(u=_n(u)),x&&Et?D(u):u},t.setConfig=function(){let e=arguments.length>0&&arguments[0]!==void 0?arguments[0]:{};tn(e),St=!0,q=z,Ct=B},t.clearConfig=function(){Qt=null,St=!1,q=null,Ct=null,x=C,S=``},t.isValidAttribute=function(e,t,n){Qt||tn({});let r=X(e),i=X(t);return On(r,i,n)},t.addHook=function(e,t){typeof t==`function`&&O(R,e)&&ue(R[e],t)},t.removeHook=function(e,t){if(O(R,e)){if(t!==void 0){let n=ce(R[e],t);return n===-1?void 0:de(R[e],n,1)[0]}return le(R[e])}},t.removeHooks=function(e){O(R,e)&&(R[e]=[])},t.removeAllHooks=function(){R=et()},t}var rt=nt(),it=e=>e.replace(/&/g,`&amp;`).replace(/"/g,`&quot;`).replace(/</g,`&lt;`).replace(/>/g,`&gt;`),at={WHOLE_DOCUMENT:!0,USE_PROFILES:{html:!0,svg:!0,svgFilters:!0,mathMl:!0},ADD_TAGS:[`use`],ADD_ATTR:[`target`,`rel`,`download`],FORBID_TAGS:[`script`,`iframe`,`object`,`embed`,`base`,`form`,`link`],FORBID_ATTR:[`srcdoc`]},R=e=>e||globalThis.document||null,ot=e=>/[A-Za-z0-9_-]/.test(e),st=(e,t)=>{let n=t+1,r=e[n]||``;if(!r)return{value:``,nextIndex:n};if(r===`\r`||r===`
`||r===`\f`)return r===`\r`&&e[n+1]===`
`&&(n+=1),{value:``,nextIndex:n+1};let i=``;for(;n<e.length&&i.length<6&&/[0-9a-f]/i.test(e[n]||``);)i+=e[n],n+=1;if(i){/\s/.test(e[n]||``)&&(n+=1);let t=Number.parseInt(i,16);return{value:t===0||t>1114111?`�`:String.fromCodePoint(t),nextIndex:n}}return{value:r,nextIndex:n+1}},ct=e=>{let t=``,n=``,r=0;for(;r<e.length;){let i=e[r]||``;if(n){if(t+=i,i===`\\`){t+=e[r+1]||``,r+=2;continue}i===n&&(n=``),r+=1;continue}if(i===`/`&&e[r+1]===`*`){let t=e.indexOf(`*/`,r+2);r=t<0?e.length:t+2;continue}if(i===`"`||i===`'`){n=i,t+=i,r+=1;continue}if(i===`\\`){let n=st(e,r);t+=n.value,r=n.nextIndex;continue}let a=i.charCodeAt(0);t+=a<32&&i!==`	`&&i!==`
`&&i!==`\r`?` `:i,r+=1}return t},lt=/^data:(?:image\/(?:avif|bmp|gif|jpeg|png|webp|x-icon)|font\/(?:collection|otf|sfnt|ttf|woff2?)|application\/(?:font-sfnt|font-woff|vnd\.ms-fontobject|x-font-opentype|x-font-ttf|x-font-woff));/i,ut=e=>{let t=/^data:image\/svg\+xml(?:;charset=[A-Za-z0-9._-]+)?,([\s\S]*)$/i.exec(e);if(!t||t[1].length>1048576)return!1;let n;try{n=decodeURIComponent(t[1])}catch{return!1}if(!/^\s*<svg(?:\s|>)/i.test(n)||/<\/?(?:script|style|foreignObject|iframe|object|embed|form|link)\b/i.test(n)||/<!\s*(?:doctype|entity)\b/i.test(n)||/\son[a-z0-9_-]+\s*=/i.test(n)||/@import\b/i.test(n)||/url\s*\(\s*(?!["']?#)/i.test(n))return!1;for(let e of n.matchAll(/\s(?:href|xlink:href|src)\s*=\s*(["'])([\s\S]*?)\1/gi)){let t=ft(e[2]||``);if(!/^#[A-Za-z0-9_.:-]+$/.test(t)&&!lt.test(t))return!1}return!0},dt=e=>{let t=``;for(let n of e){let e=n.charCodeAt(0);e<=32||e>=127&&e<=159||(t+=n)}return t.trim()},ft=dt,pt=/^data:(?:image\/(?:avif|bmp|gif|jpeg|png|webp|x-icon)|audio\/[a-z0-9.+-]+|video\/[a-z0-9.+-]+|text\/vtt)(?:;[^,]*)?,/i,mt=e=>{let t=dt(e);return t?t.startsWith(`#`)||/^blob:/i.test(t)?!0:pt.test(t):!1},z=(e,t,n={})=>{if(!e.hasAttribute(t))return;let r=dt(e.getAttribute(t)||``);(n.fragmentOnly?/^#[A-Za-z0-9_.:-]+$/.test(r):mt(r))?e.setAttribute(t,r):e.removeAttribute(t)},ht=e=>{let t=e.trim(),n=t[0];return(n===`"`||n===`'`)&&t[t.length-1]===n&&(t=t.slice(1,-1).trim()),dt(t)},B=e=>{let t=ht(e);return t?t.startsWith(`#`)||/^blob:/i.test(t)?!0:lt.test(t)||ut(t):!1},gt=(e,t)=>{let n=``;for(let r=t;r<e.length;r+=1){let t=e[r]||``;if(n){t===`\\`?r+=1:t===n&&(n=``);continue}if(t===`"`||t===`'`)n=t;else if(t===`)`)return r}return-1},V=e=>{let t=!1,n=!1,r=``,i=0;for(;i<e.length;){let a=e[i]||``;if(r){if(a===`\\`){i+=2;continue}a===r&&(r=``),i+=1;continue}if(a===`/`&&e[i+1]===`*`){let t=e.indexOf(`*/`,i+2);i=t<0?e.length:t+2;continue}if(a===`"`||a===`'`){r=a,i+=1;continue}if(a===`\\`){i+=2;continue}if(a===`@`&&e.slice(i+1,i+7).toLowerCase()===`import`){let n=e[i+7]||``;(!n||!ot(n))&&(t=!0)}if(e.slice(i,i+3).toLowerCase()===`url`&&!ot(e[i-1]||``)){let t=i+3;for(;/\s/.test(e[t]||``);)t+=1;e[t]===`(`&&(n=!0)}i+=1}return{hasImport:t,hasUrl:n}},H=e=>{let t=V(ct(e)),n=V(e);if(t.hasImport||t.hasUrl&&!n.hasUrl)return``;if(!n.hasUrl)return e;let r=``,i=``,a=0;for(;a<e.length;){let t=e[a]||``;if(i){if(r+=t,t===`\\`){r+=e[a+1]||``,a+=2;continue}t===i&&(i=``),a+=1;continue}if(t===`"`||t===`'`){i=t,r+=t,a+=1;continue}if(t===`/`&&e[a+1]===`*`){let t=e.indexOf(`*/`,a+2);if(t<0){r+=e.slice(a);break}r+=e.slice(a,t+2),a=t+2;continue}if(t===`\\`){r+=t,r+=e[a+1]||``,a+=2;continue}if(e.slice(a,a+3).toLowerCase()===`url`&&!ot(e[a-1]||``)){let t=a+3;for(;/\s/.test(e[t]||``);)t+=1;if(e[t]===`(`){let n=gt(e,t+1);if(n<0)return``;let i=e.slice(t+1,n);r+=B(i)?e.slice(a,n+1):`none`,a=n+1;continue}}r+=t,a+=1}return r},_t=e=>{let t=e.defaultView;if(!t)return null;let n=rt(t);return n.isSupported?(n.addHook(`afterSanitizeElements`,e=>{let t=e;if(t.localName?.toLowerCase()!==`style`)return;let n=H(t.textContent||``);n?t.textContent=n:t.remove()}),n.addHook(`afterSanitizeAttributes`,e=>{let t=e,n=t.localName?.toLowerCase();if(n===`a`&&(t.getAttribute(`target`)||``).trim().toLowerCase()===`_blank`&&t.setAttribute(`rel`,`noopener noreferrer`),(n===`a`||n===`area`)&&t.removeAttribute(`ping`),t.hasAttribute(`srcset`)&&t.removeAttribute(`srcset`),[`img`,`audio`,`video`,`source`,`track`,`input`].includes(n||``)&&z(t,`src`),n===`video`&&z(t,`poster`),t.hasAttribute(`background`)&&z(t,`background`),t.namespaceURI===`http://www.w3.org/2000/svg`&&n!==`a`){let e=n===`use`||n===`mpath`;z(t,`href`,{fragmentOnly:e}),z(t,`xlink:href`,{fragmentOnly:e})}if(t.hasAttribute(`style`)){let e=H(t.getAttribute(`style`)||``);e?t.setAttribute(`style`,e):t.removeAttribute(`style`)}}),n):null},U=[`<meta charset="utf-8" />`,`<meta name="viewport" content="width=device-width,initial-scale=1" />`].join(`
  `),vt=(e,t)=>{let n=R(t),r=n?_t(n):null;return r?`<!doctype html>\n${String(r.sanitize(e,at)).replace(`<head>`,`<head>\n  ${U}`)}`:`<!doctype html>
<html lang="en"><head><meta charset="utf-8" /></head><body></body></html>`},yt=e=>{let t=e.createElement(`html`);t.lang=`en`;let n=e.createElement(`head`),r=e.createElement(`meta`);return r.setAttribute(`charset`,`utf-8`),n.append(r),t.append(n,e.createElement(`body`)),t},bt=e=>{let t=e.querySelector(`:scope > head`);if(!t)return e;if(!t.querySelector(`meta[charset]`)){let n=e.ownerDocument.createElement(`meta`);n.setAttribute(`charset`,`utf-8`),t.prepend(n)}if(!t.querySelector(`meta[name="viewport"]`)){let n=e.ownerDocument.createElement(`meta`);n.setAttribute(`name`,`viewport`),n.setAttribute(`content`,`width=device-width,initial-scale=1`),t.querySelector(`meta[charset]`)?.after(n)}return e},xt=(t,n)=>{let r=R(n);if(!r)throw Error(`A browser document is required to build printable DOM.`);let i=_t(r);if(!i)return yt(r);let a=i.sanitize(t,e(e({},at),{},{RETURN_DOM:!0}));return!a||a.nodeType!==1||a.localName.toLowerCase()!==`html`?yt(r):bt(a)},W=`
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
`,G=e=>{let t=R(e);return t?Array.from(t.querySelectorAll(`style, link[rel="stylesheet"]`)).map(e=>{if(e.localName.toLowerCase()===`style`)return`<style>${e.textContent||``}</style>`;let t=e;try{let e=Array.from(t.sheet?.cssRules||[]).map(e=>e.cssText).join(`
`);return e?`<style data-viewer-inlined-stylesheet>${e}</style>`:``}catch{return``}}).filter(Boolean).join(`
`):``},K=({contentHtml:t,includeDocumentStyles:n=!0,printStyle:r=``,title:i,watermarkInlineStyle:a=``,mask:o=null,documentRef:s})=>{let c=a?`<div class="viewer-export-watermark" style="${it(a)}"></div>`:``,l=d(o),u=f(l?e(e({},l),{},{regions:l.regions?.filter(e=>e.pageIndex===void 0),stamps:l.stamps?.filter(e=>e.pageIndex===void 0)}):null),te=ee(t,l),m=n?G(s):``,h=r?`<style data-viewer-print-style>${r}</style>`:``,ne=l?`<style data-viewer-print-mask-style>${p}</style>`:``;return`<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>${it(i)}</title>
  ${m}
  <style>${W}</style>
  ${ne}
</head>
<body>
  <main class="viewer-export-shell">
    <div class="viewer-export-content">${te}</div>
    ${u}
    ${c}
  </main>
  ${h}
</body>
</html>`},St=e=>vt(K(e),e.documentRef),q=e=>xt(K(e),e.documentRef),Ct=function(){var e=t(function*({source:e,mode:t=`export`,title:r,adapter:i=null,watermarkInlineStyle:a=``,mask:s=null}){let u={mode:t,title:r},f=i?.toHtml,p=d(s);if(f){yield c(e,i);let t=yield n(yield f(u)),s=yield o(i,u);return{contentHtml:t,includeDocumentStyles:i.includeDocumentStyles!==!1,printStyle:s,title:r,watermarkInlineStyle:a,mask:p,documentRef:e.ownerDocument}}yield c(e,i);let ee=e.cloneNode(!0);ee.querySelectorAll(`.viewer-watermark`).forEach(e=>e.remove()),l(e,ee);let te=yield o(i,u);return{contentHtml:yield n(ee.innerHTML),printStyle:te,title:r,watermarkInlineStyle:a,mask:p,documentRef:e.ownerDocument}});return function(t){return e.apply(this,arguments)}}(),wt=function(){var e=t(function*(e){return St(yield Ct(e))});return function(t){return e.apply(this,arguments)}}(),J=function(){var e=t(function*(e){return q(yield Ct(e))});return function(t){return e.apply(this,arguments)}}();export{q as buildExportDomDocument,St as buildExportHtmlDocument,J as buildFileViewerRenderedDomDocument,wt as buildFileViewerRenderedHtmlDocument,G as collectDocumentStyles,n as inlineFileViewerBlobUrlsInHtml,c as prepareFileViewerRenderedContentForSnapshot,l as replaceFileViewerCanvasWithImages,o as resolveFileViewerPrintStyle,xt as sanitizeFileViewerExportDocumentDom,vt as sanitizeFileViewerExportDocumentHtml,r as triggerFileViewerBlobDownload,s as triggerFileViewerUrlDownload,u as waitForFileViewerImages,i as waitForFileViewerNextPaint,a as waitForFileViewerPrintWindowReady};