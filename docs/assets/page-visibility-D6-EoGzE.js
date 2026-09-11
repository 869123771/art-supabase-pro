import"./rolldown-runtime-DAXXjFlN.js";import{At as e,Dt as t,Et as n,Ft as r,It as i,Rt as a,bn as o,in as s,tr as c,zn as l}from"./framework-ClRJ96jm.js";import{_t as u,t as d}from"./user-fgOPE8zV.js";import{t as f}from"./icon-Czp-2FrG.js";import{D as p,Q as m,j as h,tt as g}from"./style-DFvNC_CE.js";import{t as _}from"./style-b_mXnhPN2.js";import{t as v}from"./style-CuVqxBQS.js";import{n as y,t as b}from"./style-CjDm0euV.js";import{n as x,t as S}from"./style-DGDMOZAM.js";import"./style-xJcfdqHS.js";var C={class:`w-full py-2`},w={class:`mb-6`},T={class:`m-0 mb-2 text-xl font-medium`},E={class:`mb-6`},D={class:`flex-c gap-5`},O={class:`my-1 text-sm text-g-700`},k={class:`font-semibold`},A={class:`my-1 text-sm text-g-700`},j={class:`mb-6 last:mb-0`},M={class:`p-4 mt-3 mb-0 overflow-x-auto font-mono text-xs leading-[1.5] bg-g-200 border-full-d rounded-md`},N={class:``},P={class:`best-practices`},F={class:`practices-content`},I={class:`flex-c`},L={class:`size-10 bg-g-200 flex-cc rounded mr-2`},R={class:`flex-c`},z={class:`size-10 bg-g-200 flex-cc rounded mr-2`},B={class:`flex-c`},V={class:`size-10 bg-g-200 flex-cc rounded mr-2`},H={class:`flex-c`},U={class:`size-10 bg-g-200 flex-cc rounded mr-2`},W=a({name:`PermissionPageVisibility`,__name:`index`,setup(a){let W=d(),G=u.SUPER_ROLE_CODE,K=n(()=>W.info),q=e=>({[G]:`超级管理员`,R_ADMIN:`管理员`,R_USER:`普通用户`})[e]||`未知角色`;return(n,a)=>{let u=_,d=v,W=x,J=S,Y=f,X=b,Z=y;return s(),e(`div`,C,[t(`div`,w,[t(`h2`,T,c(n.$t(`menus.examples.permission.pageVisibility`)),1),a[0]||(a[0]=t(`p`,{class:`m-0 text-sm leading-[1.6] text-g-700`},[r(` 此页面仅对`),t(`strong`,{class:`font-semibold text-warning`},`超级管理员`),r(`用户可见，演示页面级别的权限控制。 如果您能看到此页面，说明您拥有相应的访问权限。 `)],-1))]),t(`div`,E,[i(d,{class:`art-card-xs`},{header:o(()=>[...a[1]||(a[1]=[t(`div`,{class:`flex-c gap-2 font-semibold`},[t(`span`,null,`权限验证成功`)],-1)])]),default:o(()=>[t(`div`,null,[t(`div`,D,[t(`div`,null,[a[4]||(a[4]=t(`h3`,{class:`m-0 mb-2 text-lg font-semibold`},`您拥有访问此页面的权限`,-1)),t(`p`,O,[a[2]||(a[2]=r(` 当前用户：`,-1)),t(`strong`,k,c(K.value.userName),1)]),t(`p`,A,[a[3]||(a[3]=r(` 用户角色： `,-1)),i(u,{type:`warning`},{default:o(()=>[r(c(q(K.value.userRoles?.[0]||``)),1)]),_:1})])])])])]),_:1})]),t(`div`,j,[i(d,{class:`art-card-xs`},{header:o(()=>[...a[5]||(a[5]=[t(`div`,{class:`flex-c font-semibold`},[t(`span`,null,`页面级权限控制说明`)],-1)])]),default:o(()=>[t(`div`,null,[i(J,null,{default:o(()=>[i(W,{timestamp:`前端控制模式`,type:`primary`,size:`large`},{default:o(()=>[i(d,null,{default:o(()=>[a[6]||(a[6]=t(`h4`,{class:`m-0 mb-2 text-base font-semibold`},`基于角色的权限控制`,-1)),a[7]||(a[7]=t(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},[r(` 在前端控制模式下，页面访问权限由路由配置文件中的 `),t(`code`,{class:`px-1.5 py-0.5 font-mono text-xs text-theme bg-theme/12 rounded`},`meta.roles`),r(` 字段定义，前端会根据用户接口所拥有的角色对路由和菜单进行过滤与控制 `)],-1)),t(`pre`,M,[t(`code`,N,`{
  path: 'page-visibility',
  name: 'PermissionPageVisibility',
  component: '/examples/permission/page-visibility',
  meta: {
    title: 'menus.permission.pageVisibility',
    roles: ['`+c(l(G))+`'], // 仅超级管理员可访问
    keepAlive: true
  }
}`,1)]),a[8]||(a[8]=t(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},[t(`strong`,null,`权限验证流程：`)],-1)),a[9]||(a[9]=t(`ul`,{class:`pl-5 my-2`},[t(`li`,{class:`my-1 leading-[1.5] text-g-700`},`用户登录后，接口返回用户角色信息`),t(`li`,{class:`my-1 leading-[1.5] text-g-700`},[r(` 在 `),t(`code`,{class:`px-1.5 py-0.5 font-mono text-xs text-theme bg-theme/12 rounded`},`beforeEach`),r(` 路由守卫中检查目标路由的 `),t(`code`,{class:`px-1.5 py-0.5 font-mono text-xs text-theme bg-theme/12 rounded`},`roles`),r(` 配置 `)]),t(`li`,{class:`my-1 leading-[1.5] text-g-700`},`比较用户角色是否包含在允许访问的角色列表中`),t(`li`,{class:`my-1 leading-[1.5] text-g-700`},`权限不足时跳转到 403 页面`)],-1))]),_:1})]),_:1}),i(W,{timestamp:`后端控制模式`,type:`warning`,size:`large`},{default:o(()=>[i(d,null,{default:o(()=>[...a[10]||(a[10]=[t(`h4`,{class:`m-0 mb-2 text-base font-semibold`},`基于菜单接口的权限控制`,-1),t(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},`在后端控制模式下，页面访问权限由后端统一管理，前端通过解析后端接口返回的菜单列表来生成可访问的路由，从而实现权限控制`,-1),t(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},`接口地址：src/api/menuApi.ts getMenuList`,-1),t(`pre`,{class:`p-4 mt-3 mb-0 overflow-x-auto font-mono text-xs leading-[1.5] bg-g-200 border-full-d rounded-md`},[t(`code`,{class:``},`
{
  "code": 200,
  "data": [
    {
      "id": 1,
      "path": "/permission",
      "name": "Permission",
      "component": "Layout",
      "meta": {
        "title": "menus.permission.title",
        "icon": ""
      },
      "children": [
        {
          "id": 11,
          "path": "page-visibility",
          "name": "PermissionPageVisibility",
          "component": "permission/page-visibility/index",
          "meta": {
            "title": "menus.permission.pageVisibility",
            "keepAlive": true
          }
        }
      ]
    }
  ]
}`)],-1),t(`p`,null,[t(`strong`,null,`权限验证流程：`)],-1),t(`ul`,null,[t(`li`,null,`用户登录成功后获取 Token`),t(`li`,null,`前端调用菜单接口获取用户可访问的菜单列表`),t(`li`,null,`前端根据菜单列表动态注册路由`),t(`li`,null,`菜单中存在的页面用户可以正常访问，不存在的页面会跳转到 404`)],-1)])]),_:1})]),_:1}),i(W,{timestamp:`菜单显示控制`,type:`success`,size:`large`},{default:o(()=>[i(d,null,{default:o(()=>[...a[11]||(a[11]=[t(`h4`,null,`侧边栏菜单可见性`,-1),t(`p`,null,[t(`strong`,null,`前端控制模式：`)],-1),t(`ul`,null,[t(`li`,null,`有权限的用户：菜单项正常显示，可以点击访问`),t(`li`,null,`无权限的用户：菜单项不显示，无法通过菜单导航到页面`),t(`li`,null,`即使通过直接输入URL尝试访问，也会被路由守卫拦截`)],-1),t(`p`,null,[t(`strong`,null,`后端控制模式：`)],-1),t(`ul`,null,[t(`li`,null,`侧边栏菜单根据后端返回的菜单列表进行渲染`),t(`li`,null,`后端应该根据用户权限过滤，只返回用户有权限访问的菜单项`),t(`li`,null,`前端只显示后端返回的菜单，确保用户只能看到和访问有权限的页面`)],-1)])]),_:1})]),_:1})]),_:1})])]),_:1})]),t(`div`,P,[i(d,{class:`art-card-xs`},{header:o(()=>[...a[12]||(a[12]=[t(`div`,{class:`card-header`},[t(`span`,null,`权限控制最佳实践`)],-1)])]),default:o(()=>[t(`div`,F,[i(Z,{gutter:24},{default:o(()=>[i(X,{span:12,class:`!mb-5`},{default:o(()=>[t(`div`,I,[t(`div`,L,[i(Y,{size:`20`,color:`#409EFF`},{default:o(()=>[i(l(h))]),_:1})]),a[13]||(a[13]=t(`div`,null,[t(`h4`,null,`多层权限验证`),t(`p`,{class:`text-g-700 text-sm`},`在前端路由、后端接口、UI组件等多个层面实施权限控制，确保安全性。`)],-1))])]),_:1}),i(X,{span:12},{default:o(()=>[t(`div`,R,[t(`div`,z,[i(Y,{size:`20`,color:`#67C23A`},{default:o(()=>[i(l(m))]),_:1})]),a[14]||(a[14]=t(`div`,null,[t(`h4`,null,`基于角色的访问控制`),t(`p`,{class:`text-g-700 text-sm`},`采用RBAC模型，通过角色分配权限，简化权限管理复杂度。`)],-1))])]),_:1}),i(X,{span:12},{default:o(()=>[t(`div`,B,[t(`div`,V,[i(Y,{size:`20`,color:`#E6A23C`},{default:o(()=>[i(l(p))]),_:1})]),a[15]||(a[15]=t(`div`,null,[t(`h4`,null,`细粒度权限控制`),t(`p`,{class:`text-g-700 text-sm`},`支持页面级、按钮级、数据级等多种粒度的权限控制。`)],-1))])]),_:1}),i(X,{span:12},{default:o(()=>[t(`div`,H,[t(`div`,U,[i(Y,{size:`20`,color:`#F56C6C`},{default:o(()=>[i(l(g))]),_:1})]),a[16]||(a[16]=t(`div`,null,[t(`h4`,null,`安全性优先原则`),t(`p`,{class:`text-g-700 text-sm`},`始终遵循最小权限原则，确保用户只能访问必要的功能和数据。`)],-1))])]),_:1})]),_:1})])]),_:1})])])}}});export{W as default};