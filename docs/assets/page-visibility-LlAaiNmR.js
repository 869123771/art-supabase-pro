import"./rolldown-runtime-DAXXjFlN.js";import{$ as e,Ct as t,Lt as n,Q as r,Vt as i,g as a,h as o,in as s,st as c,tn as l,ut as u}from"./element-plus-e6gcqm0z.js";import{A as d,B as f,L as p,P as m,R as h,Un as g,Vt as _,at as v,bt as y,j as b}from"./file-viewer-CCM9jSgy.js";import{Q as x,t as S}from"./user-Bku_ltwS.js";var C={class:`w-full py-2`},w={class:`mb-6`},T={class:`m-0 mb-2 text-xl font-medium`},E={class:`mb-6`},D={class:`flex-c gap-5`},O={class:`my-1 text-sm text-g-700`},k={class:`font-semibold`},A={class:`my-1 text-sm text-g-700`},j={class:`mb-6 last:mb-0`},M={class:`p-4 mt-3 mb-0 overflow-x-auto font-mono text-xs leading-[1.5] bg-g-200 border-full-d rounded-md`},N={class:``},P={class:`best-practices`},F={class:`practices-content`},I={class:`flex-c`},L={class:`size-10 bg-g-200 flex-cc rounded mr-2`},R={class:`flex-c`},z={class:`size-10 bg-g-200 flex-cc rounded mr-2`},B={class:`flex-c`},V={class:`size-10 bg-g-200 flex-cc rounded mr-2`},H={class:`flex-c`},U={class:`size-10 bg-g-200 flex-cc rounded mr-2`},W=f({name:`PermissionPageVisibility`,__name:`index`,setup(f){let W=S(),G=x.SUPER_ROLE_CODE,K=d(()=>W.info),q=e=>({[G]:`超级管理员`,R_ADMIN:`管理员`,R_USER:`普通用户`})[e]||`未知角色`;return(d,f)=>{let x=u,S=c,W=a,J=o,Y=t,X=r,Z=e;return v(),m(`div`,C,[b(`div`,w,[b(`h2`,T,g(d.$t(`menus.examples.permission.pageVisibility`)),1),f[0]||(f[0]=b(`p`,{class:`m-0 text-sm leading-[1.6] text-g-700`},[p(` 此页面仅对`),b(`strong`,{class:`font-semibold text-warning`},`超级管理员`),p(`用户可见，演示页面级别的权限控制。 如果您能看到此页面，说明您拥有相应的访问权限。 `)],-1))]),b(`div`,E,[h(S,{class:`art-card-xs`},{header:y(()=>[...f[1]||(f[1]=[b(`div`,{class:`flex-c gap-2 font-semibold`},[b(`span`,null,`权限验证成功`)],-1)])]),default:y(()=>[b(`div`,null,[b(`div`,D,[b(`div`,null,[f[4]||(f[4]=b(`h3`,{class:`m-0 mb-2 text-lg font-semibold`},`您拥有访问此页面的权限`,-1)),b(`p`,O,[f[2]||(f[2]=p(` 当前用户：`,-1)),b(`strong`,k,g(K.value.userName),1)]),b(`p`,A,[f[3]||(f[3]=p(` 用户角色： `,-1)),h(x,{type:`warning`},{default:y(()=>[p(g(q(K.value.userRoles?.[0]||``)),1)]),_:1})])])])])]),_:1})]),b(`div`,j,[h(S,{class:`art-card-xs`},{header:y(()=>[...f[5]||(f[5]=[b(`div`,{class:`flex-c font-semibold`},[b(`span`,null,`页面级权限控制说明`)],-1)])]),default:y(()=>[b(`div`,null,[h(J,null,{default:y(()=>[h(W,{timestamp:`前端控制模式`,type:`primary`,size:`large`},{default:y(()=>[h(S,null,{default:y(()=>[f[6]||(f[6]=b(`h4`,{class:`m-0 mb-2 text-base font-semibold`},`基于角色的权限控制`,-1)),f[7]||(f[7]=b(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},[p(` 在前端控制模式下，页面访问权限由路由配置文件中的 `),b(`code`,{class:`px-1.5 py-0.5 font-mono text-xs text-theme bg-theme/12 rounded`},`meta.roles`),p(` 字段定义，前端会根据用户接口所拥有的角色对路由和菜单进行过滤与控制 `)],-1)),b(`pre`,M,[b(`code`,N,`{
  path: 'page-visibility',
  name: 'PermissionPageVisibility',
  component: '/examples/permission/page-visibility',
  meta: {
    title: 'menus.permission.pageVisibility',
    roles: ['`+g(_(G))+`'], // 仅超级管理员可访问
    keepAlive: true
  }
}`,1)]),f[8]||(f[8]=b(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},[b(`strong`,null,`权限验证流程：`)],-1)),f[9]||(f[9]=b(`ul`,{class:`pl-5 my-2`},[b(`li`,{class:`my-1 leading-[1.5] text-g-700`},`用户登录后，接口返回用户角色信息`),b(`li`,{class:`my-1 leading-[1.5] text-g-700`},[p(` 在 `),b(`code`,{class:`px-1.5 py-0.5 font-mono text-xs text-theme bg-theme/12 rounded`},`beforeEach`),p(` 路由守卫中检查目标路由的 `),b(`code`,{class:`px-1.5 py-0.5 font-mono text-xs text-theme bg-theme/12 rounded`},`roles`),p(` 配置 `)]),b(`li`,{class:`my-1 leading-[1.5] text-g-700`},`比较用户角色是否包含在允许访问的角色列表中`),b(`li`,{class:`my-1 leading-[1.5] text-g-700`},`权限不足时跳转到 403 页面`)],-1))]),_:1})]),_:1}),h(W,{timestamp:`后端控制模式`,type:`warning`,size:`large`},{default:y(()=>[h(S,null,{default:y(()=>[...f[10]||(f[10]=[b(`h4`,{class:`m-0 mb-2 text-base font-semibold`},`基于菜单接口的权限控制`,-1),b(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},`在后端控制模式下，页面访问权限由后端统一管理，前端通过解析后端接口返回的菜单列表来生成可访问的路由，从而实现权限控制`,-1),b(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},`接口地址：src/api/menuApi.ts getMenuList`,-1),b(`pre`,{class:`p-4 mt-3 mb-0 overflow-x-auto font-mono text-xs leading-[1.5] bg-g-200 border-full-d rounded-md`},[b(`code`,{class:``},`
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
}`)],-1),b(`p`,null,[b(`strong`,null,`权限验证流程：`)],-1),b(`ul`,null,[b(`li`,null,`用户登录成功后获取 Token`),b(`li`,null,`前端调用菜单接口获取用户可访问的菜单列表`),b(`li`,null,`前端根据菜单列表动态注册路由`),b(`li`,null,`菜单中存在的页面用户可以正常访问，不存在的页面会跳转到 404`)],-1)])]),_:1})]),_:1}),h(W,{timestamp:`菜单显示控制`,type:`success`,size:`large`},{default:y(()=>[h(S,null,{default:y(()=>[...f[11]||(f[11]=[b(`h4`,null,`侧边栏菜单可见性`,-1),b(`p`,null,[b(`strong`,null,`前端控制模式：`)],-1),b(`ul`,null,[b(`li`,null,`有权限的用户：菜单项正常显示，可以点击访问`),b(`li`,null,`无权限的用户：菜单项不显示，无法通过菜单导航到页面`),b(`li`,null,`即使通过直接输入URL尝试访问，也会被路由守卫拦截`)],-1),b(`p`,null,[b(`strong`,null,`后端控制模式：`)],-1),b(`ul`,null,[b(`li`,null,`侧边栏菜单根据后端返回的菜单列表进行渲染`),b(`li`,null,`后端应该根据用户权限过滤，只返回用户有权限访问的菜单项`),b(`li`,null,`前端只显示后端返回的菜单，确保用户只能看到和访问有权限的页面`)],-1)])]),_:1})]),_:1})]),_:1})])]),_:1})]),b(`div`,P,[h(S,{class:`art-card-xs`},{header:y(()=>[...f[12]||(f[12]=[b(`div`,{class:`card-header`},[b(`span`,null,`权限控制最佳实践`)],-1)])]),default:y(()=>[b(`div`,F,[h(Z,{gutter:24},{default:y(()=>[h(X,{span:12,class:`!mb-5`},{default:y(()=>[b(`div`,I,[b(`div`,L,[h(Y,{size:`20`,color:`#409EFF`},{default:y(()=>[h(_(i))]),_:1})]),f[13]||(f[13]=b(`div`,null,[b(`h4`,null,`多层权限验证`),b(`p`,{class:`text-g-700 text-sm`},`在前端路由、后端接口、UI组件等多个层面实施权限控制，确保安全性。`)],-1))])]),_:1}),h(X,{span:12},{default:y(()=>[b(`div`,R,[b(`div`,z,[h(Y,{size:`20`,color:`#67C23A`},{default:y(()=>[h(_(l))]),_:1})]),f[14]||(f[14]=b(`div`,null,[b(`h4`,null,`基于角色的访问控制`),b(`p`,{class:`text-g-700 text-sm`},`采用RBAC模型，通过角色分配权限，简化权限管理复杂度。`)],-1))])]),_:1}),h(X,{span:12},{default:y(()=>[b(`div`,B,[b(`div`,V,[h(Y,{size:`20`,color:`#E6A23C`},{default:y(()=>[h(_(n))]),_:1})]),f[15]||(f[15]=b(`div`,null,[b(`h4`,null,`细粒度权限控制`),b(`p`,{class:`text-g-700 text-sm`},`支持页面级、按钮级、数据级等多种粒度的权限控制。`)],-1))])]),_:1}),h(X,{span:12},{default:y(()=>[b(`div`,H,[b(`div`,U,[h(Y,{size:`20`,color:`#F56C6C`},{default:y(()=>[h(_(s))]),_:1})]),f[16]||(f[16]=b(`div`,null,[b(`h4`,null,`安全性优先原则`),b(`p`,{class:`text-g-700 text-sm`},`始终遵循最小权限原则，确保用户只能访问必要的功能和数据。`)],-1))])]),_:1})]),_:1})])]),_:1})])])}}});export{W as default};