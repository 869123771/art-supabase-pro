import"./rolldown-runtime-DAXXjFlN.js";import{Br as e,Gr as t,Ir as n,Lr as r,Oi as i,Wr as a,fi as o,la as s,qi as c,qr as l}from"./framework-D8pXWVr4.js";import{nt as u,t as d}from"./user-DDaBeciv.js";import{t as f}from"./icon-B7LQxGa7.js";import{D as p,Q as m,j as h,tt as g}from"./style-DNNKwLAh.js";import{t as _}from"./style-CcrjKbPv.js";import{t as v}from"./style-BmIwlLR8.js";import{n as y,t as b}from"./style-Vp42gByL.js";import{n as x,t as S}from"./style-Bt0gQtci.js";import"./style-Cz7i-eCw.js";var C={class:`w-full py-2`},w={class:`mb-6`},T={class:`m-0 mb-2 text-xl font-medium`},E={class:`mb-6`},D={class:`flex-c gap-5`},O={class:`my-1 text-sm text-g-700`},k={class:`font-semibold`},A={class:`my-1 text-sm text-g-700`},j={class:`mb-6 last:mb-0`},M={class:`p-4 mt-3 mb-0 overflow-x-auto font-mono text-xs leading-[1.5] bg-g-200 border-full-d rounded-md`},N={class:``},P={class:`best-practices`},F={class:`practices-content`},I={class:`flex-c`},L={class:`size-10 bg-g-200 flex-cc rounded mr-2`},R={class:`flex-c`},z={class:`size-10 bg-g-200 flex-cc rounded mr-2`},B={class:`flex-c`},V={class:`size-10 bg-g-200 flex-cc rounded mr-2`},H={class:`flex-c`},U={class:`size-10 bg-g-200 flex-cc rounded mr-2`},W=l({name:`PermissionPageVisibility`,__name:`index`,setup(l){let W=d(),G=u.SUPER_ROLE_CODE,K=n(()=>W.info),q=e=>({[G]:`超级管理员`,R_ADMIN:`管理员`,R_USER:`普通用户`})[e]||`未知角色`;return(n,l)=>{let u=_,d=v,W=x,J=S,Y=f,X=b,Z=y;return o(),e(`div`,C,[r(`div`,w,[r(`h2`,T,s(n.$t(`menus.examples.permission.pageVisibility`)),1),l[0]||(l[0]=r(`p`,{class:`m-0 text-sm leading-[1.6] text-g-700`},[a(` 此页面仅对`),r(`strong`,{class:`font-semibold text-warning`},`超级管理员`),a(`用户可见，演示页面级别的权限控制。 如果您能看到此页面，说明您拥有相应的访问权限。 `)],-1))]),r(`div`,E,[t(d,{class:`art-card-xs`},{header:i(()=>[...l[1]||(l[1]=[r(`div`,{class:`flex-c gap-2 font-semibold`},[r(`span`,null,`权限验证成功`)],-1)])]),default:i(()=>[r(`div`,null,[r(`div`,D,[r(`div`,null,[l[4]||(l[4]=r(`h3`,{class:`m-0 mb-2 text-lg font-semibold`},`您拥有访问此页面的权限`,-1)),r(`p`,O,[l[2]||(l[2]=a(` 当前用户：`,-1)),r(`strong`,k,s(K.value.userName),1)]),r(`p`,A,[l[3]||(l[3]=a(` 用户角色： `,-1)),t(u,{type:`warning`},{default:i(()=>[a(s(q(K.value.userRoles?.[0]||``)),1)]),_:1})])])])])]),_:1})]),r(`div`,j,[t(d,{class:`art-card-xs`},{header:i(()=>[...l[5]||(l[5]=[r(`div`,{class:`flex-c font-semibold`},[r(`span`,null,`页面级权限控制说明`)],-1)])]),default:i(()=>[r(`div`,null,[t(J,null,{default:i(()=>[t(W,{timestamp:`前端控制模式`,type:`primary`,size:`large`},{default:i(()=>[t(d,null,{default:i(()=>[l[6]||(l[6]=r(`h4`,{class:`m-0 mb-2 text-base font-semibold`},`基于角色的权限控制`,-1)),l[7]||(l[7]=r(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},[a(` 在前端控制模式下，页面访问权限由路由配置文件中的 `),r(`code`,{class:`px-1.5 py-0.5 font-mono text-xs text-theme bg-theme/12 rounded`},`meta.roles`),a(` 字段定义，前端会根据用户接口所拥有的角色对路由和菜单进行过滤与控制 `)],-1)),r(`pre`,M,[r(`code`,N,`{
  path: 'page-visibility',
  name: 'PermissionPageVisibility',
  component: '/examples/permission/page-visibility',
  meta: {
    title: 'menus.permission.pageVisibility',
    roles: ['`+s(c(G))+`'], // 仅超级管理员可访问
    keepAlive: true
  }
}`,1)]),l[8]||(l[8]=r(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},[r(`strong`,null,`权限验证流程：`)],-1)),l[9]||(l[9]=r(`ul`,{class:`pl-5 my-2`},[r(`li`,{class:`my-1 leading-[1.5] text-g-700`},`用户登录后，接口返回用户角色信息`),r(`li`,{class:`my-1 leading-[1.5] text-g-700`},[a(` 在 `),r(`code`,{class:`px-1.5 py-0.5 font-mono text-xs text-theme bg-theme/12 rounded`},`beforeEach`),a(` 路由守卫中检查目标路由的 `),r(`code`,{class:`px-1.5 py-0.5 font-mono text-xs text-theme bg-theme/12 rounded`},`roles`),a(` 配置 `)]),r(`li`,{class:`my-1 leading-[1.5] text-g-700`},`比较用户角色是否包含在允许访问的角色列表中`),r(`li`,{class:`my-1 leading-[1.5] text-g-700`},`权限不足时跳转到 403 页面`)],-1))]),_:1})]),_:1}),t(W,{timestamp:`后端控制模式`,type:`warning`,size:`large`},{default:i(()=>[t(d,null,{default:i(()=>[...l[10]||(l[10]=[r(`h4`,{class:`m-0 mb-2 text-base font-semibold`},`基于菜单接口的权限控制`,-1),r(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},`在后端控制模式下，页面访问权限由后端统一管理，前端通过解析后端接口返回的菜单列表来生成可访问的路由，从而实现权限控制`,-1),r(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},`接口地址：src/api/menuApi.ts getMenuList`,-1),r(`pre`,{class:`p-4 mt-3 mb-0 overflow-x-auto font-mono text-xs leading-[1.5] bg-g-200 border-full-d rounded-md`},[r(`code`,{class:``},`
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
}`)],-1),r(`p`,null,[r(`strong`,null,`权限验证流程：`)],-1),r(`ul`,null,[r(`li`,null,`用户登录成功后获取 Token`),r(`li`,null,`前端调用菜单接口获取用户可访问的菜单列表`),r(`li`,null,`前端根据菜单列表动态注册路由`),r(`li`,null,`菜单中存在的页面用户可以正常访问，不存在的页面会跳转到 404`)],-1)])]),_:1})]),_:1}),t(W,{timestamp:`菜单显示控制`,type:`success`,size:`large`},{default:i(()=>[t(d,null,{default:i(()=>[...l[11]||(l[11]=[r(`h4`,null,`侧边栏菜单可见性`,-1),r(`p`,null,[r(`strong`,null,`前端控制模式：`)],-1),r(`ul`,null,[r(`li`,null,`有权限的用户：菜单项正常显示，可以点击访问`),r(`li`,null,`无权限的用户：菜单项不显示，无法通过菜单导航到页面`),r(`li`,null,`即使通过直接输入URL尝试访问，也会被路由守卫拦截`)],-1),r(`p`,null,[r(`strong`,null,`后端控制模式：`)],-1),r(`ul`,null,[r(`li`,null,`侧边栏菜单根据后端返回的菜单列表进行渲染`),r(`li`,null,`后端应该根据用户权限过滤，只返回用户有权限访问的菜单项`),r(`li`,null,`前端只显示后端返回的菜单，确保用户只能看到和访问有权限的页面`)],-1)])]),_:1})]),_:1})]),_:1})])]),_:1})]),r(`div`,P,[t(d,{class:`art-card-xs`},{header:i(()=>[...l[12]||(l[12]=[r(`div`,{class:`card-header`},[r(`span`,null,`权限控制最佳实践`)],-1)])]),default:i(()=>[r(`div`,F,[t(Z,{gutter:24},{default:i(()=>[t(X,{span:12,class:`!mb-5`},{default:i(()=>[r(`div`,I,[r(`div`,L,[t(Y,{size:`20`,color:`#409EFF`},{default:i(()=>[t(c(h))]),_:1})]),l[13]||(l[13]=r(`div`,null,[r(`h4`,null,`多层权限验证`),r(`p`,{class:`text-g-700 text-sm`},`在前端路由、后端接口、UI组件等多个层面实施权限控制，确保安全性。`)],-1))])]),_:1}),t(X,{span:12},{default:i(()=>[r(`div`,R,[r(`div`,z,[t(Y,{size:`20`,color:`#67C23A`},{default:i(()=>[t(c(m))]),_:1})]),l[14]||(l[14]=r(`div`,null,[r(`h4`,null,`基于角色的访问控制`),r(`p`,{class:`text-g-700 text-sm`},`采用RBAC模型，通过角色分配权限，简化权限管理复杂度。`)],-1))])]),_:1}),t(X,{span:12},{default:i(()=>[r(`div`,B,[r(`div`,V,[t(Y,{size:`20`,color:`#E6A23C`},{default:i(()=>[t(c(p))]),_:1})]),l[15]||(l[15]=r(`div`,null,[r(`h4`,null,`细粒度权限控制`),r(`p`,{class:`text-g-700 text-sm`},`支持页面级、按钮级、数据级等多种粒度的权限控制。`)],-1))])]),_:1}),t(X,{span:12},{default:i(()=>[r(`div`,H,[r(`div`,U,[t(Y,{size:`20`,color:`#F56C6C`},{default:i(()=>[t(c(g))]),_:1})]),l[16]||(l[16]=r(`div`,null,[r(`h4`,null,`安全性优先原则`),r(`p`,{class:`text-g-700 text-sm`},`始终遵循最小权限原则，确保用户只能访问必要的功能和数据。`)],-1))])]),_:1})]),_:1})])]),_:1})])])}}});export{W as default};