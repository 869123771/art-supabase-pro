import{$ as e,Gt as t,It as n,Kt as r,Mn as i,On as a,Pn as o,Pt as s,Q as c,Tn as l,Tr as u,Yn as d,cr as f,g as p,h as m,jn as h,ni as g,qt as _,st as v,ut as y,wn as b}from"./element-plus-BJEh_tcM.js";import{n as x,st as S}from"./index-bxL_XiAt.js";var C={class:`w-full py-2`},w={class:`mb-6`},T={class:`m-0 mb-2 text-xl font-medium`},E={class:`mb-6`},D={class:`flex-c gap-5`},O={class:`my-1 text-sm text-g-700`},k={class:`font-semibold`},A={class:`my-1 text-sm text-g-700`},j={class:`mb-6 last:mb-0`},M={class:`p-4 mt-3 mb-0 overflow-x-auto font-mono text-xs leading-[1.5] bg-g-200 border-full-d rounded-md`},N={class:``},P={class:`best-practices`},F={class:`practices-content`},I={class:`flex-c`},L={class:`size-10 bg-g-200 flex-cc rounded mr-2`},R={class:`flex-c`},z={class:`size-10 bg-g-200 flex-cc rounded mr-2`},B={class:`flex-c`},V={class:`size-10 bg-g-200 flex-cc rounded mr-2`},H={class:`flex-c`},U={class:`size-10 bg-g-200 flex-cc rounded mr-2`},W=o({name:`PermissionPageVisibility`,__name:`index`,setup(o){let W=x(),G=S.SUPER_ROLE_CODE,K=b(()=>W.info),q=e=>({[G]:`超级管理员`,R_ADMIN:`管理员`,R_USER:`普通用户`})[e]||`未知角色`;return(o,b)=>{let x=y,S=v,W=p,J=m,Y=_,X=c,Z=e;return d(),a(`div`,C,[l(`div`,w,[l(`h2`,T,g(o.$t(`menus.examples.permission.pageVisibility`)),1),b[0]||(b[0]=l(`p`,{class:`m-0 text-sm leading-[1.6] text-g-700`},[h(` 此页面仅对`),l(`strong`,{class:`font-semibold text-warning`},`超级管理员`),h(`用户可见，演示页面级别的权限控制。 如果您能看到此页面，说明您拥有相应的访问权限。 `)],-1))]),l(`div`,E,[i(S,{class:`art-card-xs`},{header:f(()=>[...b[1]||(b[1]=[l(`div`,{class:`flex-c gap-2 font-semibold`},[l(`span`,null,`权限验证成功`)],-1)])]),default:f(()=>[l(`div`,null,[l(`div`,D,[l(`div`,null,[b[4]||(b[4]=l(`h3`,{class:`m-0 mb-2 text-lg font-semibold`},`您拥有访问此页面的权限`,-1)),l(`p`,O,[b[2]||(b[2]=h(` 当前用户：`,-1)),l(`strong`,k,g(K.value.userName),1)]),l(`p`,A,[b[3]||(b[3]=h(` 用户角色： `,-1)),i(x,{type:`warning`},{default:f(()=>[h(g(q(K.value.userRoles?.[0]||``)),1)]),_:1})])])])])]),_:1})]),l(`div`,j,[i(S,{class:`art-card-xs`},{header:f(()=>[...b[5]||(b[5]=[l(`div`,{class:`flex-c font-semibold`},[l(`span`,null,`页面级权限控制说明`)],-1)])]),default:f(()=>[l(`div`,null,[i(J,null,{default:f(()=>[i(W,{timestamp:`前端控制模式`,type:`primary`,size:`large`},{default:f(()=>[i(S,null,{default:f(()=>[b[6]||(b[6]=l(`h4`,{class:`m-0 mb-2 text-base font-semibold`},`基于角色的权限控制`,-1)),b[7]||(b[7]=l(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},[h(` 在前端控制模式下，页面访问权限由路由配置文件中的 `),l(`code`,{class:`px-1.5 py-0.5 font-mono text-xs text-theme bg-theme/12 rounded`},`meta.roles`),h(` 字段定义，前端会根据用户接口所拥有的角色对路由和菜单进行过滤与控制 `)],-1)),l(`pre`,M,[l(`code`,N,`{
  path: 'page-visibility',
  name: 'PermissionPageVisibility',
  component: '/examples/permission/page-visibility',
  meta: {
    title: 'menus.permission.pageVisibility',
    roles: ['`+g(u(G))+`'], // 仅超级管理员可访问
    keepAlive: true
  }
}`,1)]),b[8]||(b[8]=l(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},[l(`strong`,null,`权限验证流程：`)],-1)),b[9]||(b[9]=l(`ul`,{class:`pl-5 my-2`},[l(`li`,{class:`my-1 leading-[1.5] text-g-700`},`用户登录后，接口返回用户角色信息`),l(`li`,{class:`my-1 leading-[1.5] text-g-700`},[h(` 在 `),l(`code`,{class:`px-1.5 py-0.5 font-mono text-xs text-theme bg-theme/12 rounded`},`beforeEach`),h(` 路由守卫中检查目标路由的 `),l(`code`,{class:`px-1.5 py-0.5 font-mono text-xs text-theme bg-theme/12 rounded`},`roles`),h(` 配置 `)]),l(`li`,{class:`my-1 leading-[1.5] text-g-700`},`比较用户角色是否包含在允许访问的角色列表中`),l(`li`,{class:`my-1 leading-[1.5] text-g-700`},`权限不足时跳转到 403 页面`)],-1))]),_:1})]),_:1}),i(W,{timestamp:`后端控制模式`,type:`warning`,size:`large`},{default:f(()=>[i(S,null,{default:f(()=>[...b[10]||(b[10]=[l(`h4`,{class:`m-0 mb-2 text-base font-semibold`},`基于菜单接口的权限控制`,-1),l(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},`在后端控制模式下，页面访问权限由后端统一管理，前端通过解析后端接口返回的菜单列表来生成可访问的路由，从而实现权限控制`,-1),l(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},`接口地址：src/api/menuApi.ts getMenuList`,-1),l(`pre`,{class:`p-4 mt-3 mb-0 overflow-x-auto font-mono text-xs leading-[1.5] bg-g-200 border-full-d rounded-md`},[l(`code`,{class:``},`
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
}`)],-1),l(`p`,null,[l(`strong`,null,`权限验证流程：`)],-1),l(`ul`,null,[l(`li`,null,`用户登录成功后获取 Token`),l(`li`,null,`前端调用菜单接口获取用户可访问的菜单列表`),l(`li`,null,`前端根据菜单列表动态注册路由`),l(`li`,null,`菜单中存在的页面用户可以正常访问，不存在的页面会跳转到 404`)],-1)])]),_:1})]),_:1}),i(W,{timestamp:`菜单显示控制`,type:`success`,size:`large`},{default:f(()=>[i(S,null,{default:f(()=>[...b[11]||(b[11]=[l(`h4`,null,`侧边栏菜单可见性`,-1),l(`p`,null,[l(`strong`,null,`前端控制模式：`)],-1),l(`ul`,null,[l(`li`,null,`有权限的用户：菜单项正常显示，可以点击访问`),l(`li`,null,`无权限的用户：菜单项不显示，无法通过菜单导航到页面`),l(`li`,null,`即使通过直接输入URL尝试访问，也会被路由守卫拦截`)],-1),l(`p`,null,[l(`strong`,null,`后端控制模式：`)],-1),l(`ul`,null,[l(`li`,null,`侧边栏菜单根据后端返回的菜单列表进行渲染`),l(`li`,null,`后端应该根据用户权限过滤，只返回用户有权限访问的菜单项`),l(`li`,null,`前端只显示后端返回的菜单，确保用户只能看到和访问有权限的页面`)],-1)])]),_:1})]),_:1})]),_:1})])]),_:1})]),l(`div`,P,[i(S,{class:`art-card-xs`},{header:f(()=>[...b[12]||(b[12]=[l(`div`,{class:`card-header`},[l(`span`,null,`权限控制最佳实践`)],-1)])]),default:f(()=>[l(`div`,F,[i(Z,{gutter:24},{default:f(()=>[i(X,{span:12,class:`!mb-5`},{default:f(()=>[l(`div`,I,[l(`div`,L,[i(Y,{size:`20`,color:`#409EFF`},{default:f(()=>[i(u(n))]),_:1})]),b[13]||(b[13]=l(`div`,null,[l(`h4`,null,`多层权限验证`),l(`p`,{class:`text-g-700 text-sm`},`在前端路由、后端接口、UI组件等多个层面实施权限控制，确保安全性。`)],-1))])]),_:1}),i(X,{span:12},{default:f(()=>[l(`div`,R,[l(`div`,z,[i(Y,{size:`20`,color:`#67C23A`},{default:f(()=>[i(u(t))]),_:1})]),b[14]||(b[14]=l(`div`,null,[l(`h4`,null,`基于角色的访问控制`),l(`p`,{class:`text-g-700 text-sm`},`采用RBAC模型，通过角色分配权限，简化权限管理复杂度。`)],-1))])]),_:1}),i(X,{span:12},{default:f(()=>[l(`div`,B,[l(`div`,V,[i(Y,{size:`20`,color:`#E6A23C`},{default:f(()=>[i(u(s))]),_:1})]),b[15]||(b[15]=l(`div`,null,[l(`h4`,null,`细粒度权限控制`),l(`p`,{class:`text-g-700 text-sm`},`支持页面级、按钮级、数据级等多种粒度的权限控制。`)],-1))])]),_:1}),i(X,{span:12},{default:f(()=>[l(`div`,H,[l(`div`,U,[i(Y,{size:`20`,color:`#F56C6C`},{default:f(()=>[i(u(r))]),_:1})]),b[16]||(b[16]=l(`div`,null,[l(`h4`,null,`安全性优先原则`),l(`p`,{class:`text-g-700 text-sm`},`始终遵循最小权限原则，确保用户只能访问必要的功能和数据。`)],-1))])]),_:1})]),_:1})])]),_:1})])])}}});export{W as default};