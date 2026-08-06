import"./rolldown-runtime-DAXXjFlN.js";import{$t as e,Ft as t,Q as n,St as r,Z as i,g as a,h as o,lt as s,nn as c,ot as l,zt as u}from"./element-plus-dRGO7Zkd.js";import{Bt as d,Pn as f,St as p,bt as m,ft as h,gt as g,pt as _,tn as v,vn as y,yt as b}from"./framework-BFjC6kHl.js";import{Y as x,t as S}from"./user-DWYn2klO.js";var C={class:`w-full py-2`},w={class:`mb-6`},T={class:`m-0 mb-2 text-xl font-medium`},E={class:`mb-6`},D={class:`flex-c gap-5`},O={class:`my-1 text-sm text-g-700`},k={class:`font-semibold`},A={class:`my-1 text-sm text-g-700`},j={class:`mb-6 last:mb-0`},M={class:`p-4 mt-3 mb-0 overflow-x-auto font-mono text-xs leading-[1.5] bg-g-200 border-full-d rounded-md`},N={class:``},P={class:`best-practices`},F={class:`practices-content`},I={class:`flex-c`},L={class:`size-10 bg-g-200 flex-cc rounded mr-2`},R={class:`flex-c`},z={class:`size-10 bg-g-200 flex-cc rounded mr-2`},B={class:`flex-c`},V={class:`size-10 bg-g-200 flex-cc rounded mr-2`},H={class:`flex-c`},U={class:`size-10 bg-g-200 flex-cc rounded mr-2`},W=p({name:`PermissionPageVisibility`,__name:`index`,setup(p){let W=S(),G=x.SUPER_ROLE_CODE,K=h(()=>W.info),q=e=>({[G]:`超级管理员`,R_ADMIN:`管理员`,R_USER:`普通用户`})[e]||`未知角色`;return(p,h)=>{let x=s,S=l,W=a,J=o,Y=r,X=i,Z=n;return d(),g(`div`,C,[_(`div`,w,[_(`h2`,T,f(p.$t(`menus.examples.permission.pageVisibility`)),1),h[0]||(h[0]=_(`p`,{class:`m-0 text-sm leading-[1.6] text-g-700`},[b(` 此页面仅对`),_(`strong`,{class:`font-semibold text-warning`},`超级管理员`),b(`用户可见，演示页面级别的权限控制。 如果您能看到此页面，说明您拥有相应的访问权限。 `)],-1))]),_(`div`,E,[m(S,{class:`art-card-xs`},{header:v(()=>[...h[1]||(h[1]=[_(`div`,{class:`flex-c gap-2 font-semibold`},[_(`span`,null,`权限验证成功`)],-1)])]),default:v(()=>[_(`div`,null,[_(`div`,D,[_(`div`,null,[h[4]||(h[4]=_(`h3`,{class:`m-0 mb-2 text-lg font-semibold`},`您拥有访问此页面的权限`,-1)),_(`p`,O,[h[2]||(h[2]=b(` 当前用户：`,-1)),_(`strong`,k,f(K.value.userName),1)]),_(`p`,A,[h[3]||(h[3]=b(` 用户角色： `,-1)),m(x,{type:`warning`},{default:v(()=>[b(f(q(K.value.userRoles?.[0]||``)),1)]),_:1})])])])])]),_:1})]),_(`div`,j,[m(S,{class:`art-card-xs`},{header:v(()=>[...h[5]||(h[5]=[_(`div`,{class:`flex-c font-semibold`},[_(`span`,null,`页面级权限控制说明`)],-1)])]),default:v(()=>[_(`div`,null,[m(J,null,{default:v(()=>[m(W,{timestamp:`前端控制模式`,type:`primary`,size:`large`},{default:v(()=>[m(S,null,{default:v(()=>[h[6]||(h[6]=_(`h4`,{class:`m-0 mb-2 text-base font-semibold`},`基于角色的权限控制`,-1)),h[7]||(h[7]=_(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},[b(` 在前端控制模式下，页面访问权限由路由配置文件中的 `),_(`code`,{class:`px-1.5 py-0.5 font-mono text-xs text-theme bg-theme/12 rounded`},`meta.roles`),b(` 字段定义，前端会根据用户接口所拥有的角色对路由和菜单进行过滤与控制 `)],-1)),_(`pre`,M,[_(`code`,N,`{
  path: 'page-visibility',
  name: 'PermissionPageVisibility',
  component: '/examples/permission/page-visibility',
  meta: {
    title: 'menus.permission.pageVisibility',
    roles: ['`+f(y(G))+`'], // 仅超级管理员可访问
    keepAlive: true
  }
}`,1)]),h[8]||(h[8]=_(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},[_(`strong`,null,`权限验证流程：`)],-1)),h[9]||(h[9]=_(`ul`,{class:`pl-5 my-2`},[_(`li`,{class:`my-1 leading-[1.5] text-g-700`},`用户登录后，接口返回用户角色信息`),_(`li`,{class:`my-1 leading-[1.5] text-g-700`},[b(` 在 `),_(`code`,{class:`px-1.5 py-0.5 font-mono text-xs text-theme bg-theme/12 rounded`},`beforeEach`),b(` 路由守卫中检查目标路由的 `),_(`code`,{class:`px-1.5 py-0.5 font-mono text-xs text-theme bg-theme/12 rounded`},`roles`),b(` 配置 `)]),_(`li`,{class:`my-1 leading-[1.5] text-g-700`},`比较用户角色是否包含在允许访问的角色列表中`),_(`li`,{class:`my-1 leading-[1.5] text-g-700`},`权限不足时跳转到 403 页面`)],-1))]),_:1})]),_:1}),m(W,{timestamp:`后端控制模式`,type:`warning`,size:`large`},{default:v(()=>[m(S,null,{default:v(()=>[...h[10]||(h[10]=[_(`h4`,{class:`m-0 mb-2 text-base font-semibold`},`基于菜单接口的权限控制`,-1),_(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},`在后端控制模式下，页面访问权限由后端统一管理，前端通过解析后端接口返回的菜单列表来生成可访问的路由，从而实现权限控制`,-1),_(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},`接口地址：src/api/menuApi.ts getMenuList`,-1),_(`pre`,{class:`p-4 mt-3 mb-0 overflow-x-auto font-mono text-xs leading-[1.5] bg-g-200 border-full-d rounded-md`},[_(`code`,{class:``},`
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
}`)],-1),_(`p`,null,[_(`strong`,null,`权限验证流程：`)],-1),_(`ul`,null,[_(`li`,null,`用户登录成功后获取 Token`),_(`li`,null,`前端调用菜单接口获取用户可访问的菜单列表`),_(`li`,null,`前端根据菜单列表动态注册路由`),_(`li`,null,`菜单中存在的页面用户可以正常访问，不存在的页面会跳转到 404`)],-1)])]),_:1})]),_:1}),m(W,{timestamp:`菜单显示控制`,type:`success`,size:`large`},{default:v(()=>[m(S,null,{default:v(()=>[...h[11]||(h[11]=[_(`h4`,null,`侧边栏菜单可见性`,-1),_(`p`,null,[_(`strong`,null,`前端控制模式：`)],-1),_(`ul`,null,[_(`li`,null,`有权限的用户：菜单项正常显示，可以点击访问`),_(`li`,null,`无权限的用户：菜单项不显示，无法通过菜单导航到页面`),_(`li`,null,`即使通过直接输入URL尝试访问，也会被路由守卫拦截`)],-1),_(`p`,null,[_(`strong`,null,`后端控制模式：`)],-1),_(`ul`,null,[_(`li`,null,`侧边栏菜单根据后端返回的菜单列表进行渲染`),_(`li`,null,`后端应该根据用户权限过滤，只返回用户有权限访问的菜单项`),_(`li`,null,`前端只显示后端返回的菜单，确保用户只能看到和访问有权限的页面`)],-1)])]),_:1})]),_:1})]),_:1})])]),_:1})]),_(`div`,P,[m(S,{class:`art-card-xs`},{header:v(()=>[...h[12]||(h[12]=[_(`div`,{class:`card-header`},[_(`span`,null,`权限控制最佳实践`)],-1)])]),default:v(()=>[_(`div`,F,[m(Z,{gutter:24},{default:v(()=>[m(X,{span:12,class:`!mb-5`},{default:v(()=>[_(`div`,I,[_(`div`,L,[m(Y,{size:`20`,color:`#409EFF`},{default:v(()=>[m(y(u))]),_:1})]),h[13]||(h[13]=_(`div`,null,[_(`h4`,null,`多层权限验证`),_(`p`,{class:`text-g-700 text-sm`},`在前端路由、后端接口、UI组件等多个层面实施权限控制，确保安全性。`)],-1))])]),_:1}),m(X,{span:12},{default:v(()=>[_(`div`,R,[_(`div`,z,[m(Y,{size:`20`,color:`#67C23A`},{default:v(()=>[m(y(e))]),_:1})]),h[14]||(h[14]=_(`div`,null,[_(`h4`,null,`基于角色的访问控制`),_(`p`,{class:`text-g-700 text-sm`},`采用RBAC模型，通过角色分配权限，简化权限管理复杂度。`)],-1))])]),_:1}),m(X,{span:12},{default:v(()=>[_(`div`,B,[_(`div`,V,[m(Y,{size:`20`,color:`#E6A23C`},{default:v(()=>[m(y(t))]),_:1})]),h[15]||(h[15]=_(`div`,null,[_(`h4`,null,`细粒度权限控制`),_(`p`,{class:`text-g-700 text-sm`},`支持页面级、按钮级、数据级等多种粒度的权限控制。`)],-1))])]),_:1}),m(X,{span:12},{default:v(()=>[_(`div`,H,[_(`div`,U,[m(Y,{size:`20`,color:`#F56C6C`},{default:v(()=>[m(y(c))]),_:1})]),h[16]||(h[16]=_(`div`,null,[_(`h4`,null,`安全性优先原则`),_(`p`,{class:`text-g-700 text-sm`},`始终遵循最小权限原则，确保用户只能访问必要的功能和数据。`)],-1))])]),_:1})]),_:1})])]),_:1})])])}}});export{W as default};