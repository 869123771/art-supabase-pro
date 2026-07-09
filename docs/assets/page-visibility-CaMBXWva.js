import{F as e,G as t,I as n,J as r,K as i,Nt as a,Sr as o,fn as s,qn as c,z as l}from"./monaco-CEJdAI4S.js";import{$ as u,Jt as d,Pt as f,Q as p,Rt as m,Xt as h,Yt as g,g as _,h as v,st as y,ut as b}from"./element-plus-YV1Cp2ww.js";import{n as x,st as S}from"./index-BOyn0BiT.js";var C={class:`w-full py-2`},w={class:`mb-6`},T={class:`m-0 mb-2 text-xl font-medium`},E={class:`mb-6`},D={class:`flex-c gap-5`},O={class:`my-1 text-sm text-g-700`},k={class:`font-semibold`},A={class:`my-1 text-sm text-g-700`},j={class:`mb-6 last:mb-0`},M={class:`p-4 mt-3 mb-0 overflow-x-auto font-mono text-xs leading-[1.5] bg-g-200 border-full-d rounded-md`},N={class:``},P={class:`best-practices`},F={class:`practices-content`},I={class:`flex-c`},L={class:`size-10 bg-g-200 flex-cc rounded mr-2`},R={class:`flex-c`},z={class:`size-10 bg-g-200 flex-cc rounded mr-2`},B={class:`flex-c`},V={class:`size-10 bg-g-200 flex-cc rounded mr-2`},H={class:`flex-c`},U={class:`size-10 bg-g-200 flex-cc rounded mr-2`},W=r({name:`PermissionPageVisibility`,__name:`index`,setup(r){let W=x(),G=S.SUPER_ROLE_CODE,K=e(()=>W.info),q=e=>({[G]:`超级管理员`,R_ADMIN:`管理员`,R_USER:`普通用户`})[e]||`未知角色`;return(e,r)=>{let x=b,S=y,W=_,J=v,Y=h,X=p,Z=u;return a(),l(`div`,C,[n(`div`,w,[n(`h2`,T,o(e.$t(`menus.examples.permission.pageVisibility`)),1),r[0]||(r[0]=n(`p`,{class:`m-0 text-sm leading-[1.6] text-g-700`},[t(` 此页面仅对`),n(`strong`,{class:`font-semibold text-warning`},`超级管理员`),t(`用户可见，演示页面级别的权限控制。 如果您能看到此页面，说明您拥有相应的访问权限。 `)],-1))]),n(`div`,E,[i(S,{class:`art-card-xs`},{header:s(()=>[...r[1]||(r[1]=[n(`div`,{class:`flex-c gap-2 font-semibold`},[n(`span`,null,`权限验证成功`)],-1)])]),default:s(()=>[n(`div`,null,[n(`div`,D,[n(`div`,null,[r[4]||(r[4]=n(`h3`,{class:`m-0 mb-2 text-lg font-semibold`},`您拥有访问此页面的权限`,-1)),n(`p`,O,[r[2]||(r[2]=t(` 当前用户：`,-1)),n(`strong`,k,o(K.value.userName),1)]),n(`p`,A,[r[3]||(r[3]=t(` 用户角色： `,-1)),i(x,{type:`warning`},{default:s(()=>[t(o(q(K.value.userRoles?.[0]||``)),1)]),_:1})])])])])]),_:1})]),n(`div`,j,[i(S,{class:`art-card-xs`},{header:s(()=>[...r[5]||(r[5]=[n(`div`,{class:`flex-c font-semibold`},[n(`span`,null,`页面级权限控制说明`)],-1)])]),default:s(()=>[n(`div`,null,[i(J,null,{default:s(()=>[i(W,{timestamp:`前端控制模式`,type:`primary`,size:`large`},{default:s(()=>[i(S,null,{default:s(()=>[r[6]||(r[6]=n(`h4`,{class:`m-0 mb-2 text-base font-semibold`},`基于角色的权限控制`,-1)),r[7]||(r[7]=n(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},[t(` 在前端控制模式下，页面访问权限由路由配置文件中的 `),n(`code`,{class:`px-1.5 py-0.5 font-mono text-xs text-theme bg-theme/12 rounded`},`meta.roles`),t(` 字段定义，前端会根据用户接口所拥有的角色对路由和菜单进行过滤与控制 `)],-1)),n(`pre`,M,[n(`code`,N,`{
  path: 'page-visibility',
  name: 'PermissionPageVisibility',
  component: '/examples/permission/page-visibility',
  meta: {
    title: 'menus.permission.pageVisibility',
    roles: ['`+o(c(G))+`'], // 仅超级管理员可访问
    keepAlive: true
  }
}`,1)]),r[8]||(r[8]=n(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},[n(`strong`,null,`权限验证流程：`)],-1)),r[9]||(r[9]=n(`ul`,{class:`pl-5 my-2`},[n(`li`,{class:`my-1 leading-[1.5] text-g-700`},`用户登录后，接口返回用户角色信息`),n(`li`,{class:`my-1 leading-[1.5] text-g-700`},[t(` 在 `),n(`code`,{class:`px-1.5 py-0.5 font-mono text-xs text-theme bg-theme/12 rounded`},`beforeEach`),t(` 路由守卫中检查目标路由的 `),n(`code`,{class:`px-1.5 py-0.5 font-mono text-xs text-theme bg-theme/12 rounded`},`roles`),t(` 配置 `)]),n(`li`,{class:`my-1 leading-[1.5] text-g-700`},`比较用户角色是否包含在允许访问的角色列表中`),n(`li`,{class:`my-1 leading-[1.5] text-g-700`},`权限不足时跳转到 403 页面`)],-1))]),_:1})]),_:1}),i(W,{timestamp:`后端控制模式`,type:`warning`,size:`large`},{default:s(()=>[i(S,null,{default:s(()=>[...r[10]||(r[10]=[n(`h4`,{class:`m-0 mb-2 text-base font-semibold`},`基于菜单接口的权限控制`,-1),n(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},`在后端控制模式下，页面访问权限由后端统一管理，前端通过解析后端接口返回的菜单列表来生成可访问的路由，从而实现权限控制`,-1),n(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},`接口地址：src/api/menuApi.ts getMenuList`,-1),n(`pre`,{class:`p-4 mt-3 mb-0 overflow-x-auto font-mono text-xs leading-[1.5] bg-g-200 border-full-d rounded-md`},[n(`code`,{class:``},`
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
}`)],-1),n(`p`,null,[n(`strong`,null,`权限验证流程：`)],-1),n(`ul`,null,[n(`li`,null,`用户登录成功后获取 Token`),n(`li`,null,`前端调用菜单接口获取用户可访问的菜单列表`),n(`li`,null,`前端根据菜单列表动态注册路由`),n(`li`,null,`菜单中存在的页面用户可以正常访问，不存在的页面会跳转到 404`)],-1)])]),_:1})]),_:1}),i(W,{timestamp:`菜单显示控制`,type:`success`,size:`large`},{default:s(()=>[i(S,null,{default:s(()=>[...r[11]||(r[11]=[n(`h4`,null,`侧边栏菜单可见性`,-1),n(`p`,null,[n(`strong`,null,`前端控制模式：`)],-1),n(`ul`,null,[n(`li`,null,`有权限的用户：菜单项正常显示，可以点击访问`),n(`li`,null,`无权限的用户：菜单项不显示，无法通过菜单导航到页面`),n(`li`,null,`即使通过直接输入URL尝试访问，也会被路由守卫拦截`)],-1),n(`p`,null,[n(`strong`,null,`后端控制模式：`)],-1),n(`ul`,null,[n(`li`,null,`侧边栏菜单根据后端返回的菜单列表进行渲染`),n(`li`,null,`后端应该根据用户权限过滤，只返回用户有权限访问的菜单项`),n(`li`,null,`前端只显示后端返回的菜单，确保用户只能看到和访问有权限的页面`)],-1)])]),_:1})]),_:1})]),_:1})])]),_:1})]),n(`div`,P,[i(S,{class:`art-card-xs`},{header:s(()=>[...r[12]||(r[12]=[n(`div`,{class:`card-header`},[n(`span`,null,`权限控制最佳实践`)],-1)])]),default:s(()=>[n(`div`,F,[i(Z,{gutter:24},{default:s(()=>[i(X,{span:12,class:`!mb-5`},{default:s(()=>[n(`div`,I,[n(`div`,L,[i(Y,{size:`20`,color:`#409EFF`},{default:s(()=>[i(c(m))]),_:1})]),r[13]||(r[13]=n(`div`,null,[n(`h4`,null,`多层权限验证`),n(`p`,{class:`text-g-700 text-sm`},`在前端路由、后端接口、UI组件等多个层面实施权限控制，确保安全性。`)],-1))])]),_:1}),i(X,{span:12},{default:s(()=>[n(`div`,R,[n(`div`,z,[i(Y,{size:`20`,color:`#67C23A`},{default:s(()=>[i(c(d))]),_:1})]),r[14]||(r[14]=n(`div`,null,[n(`h4`,null,`基于角色的访问控制`),n(`p`,{class:`text-g-700 text-sm`},`采用RBAC模型，通过角色分配权限，简化权限管理复杂度。`)],-1))])]),_:1}),i(X,{span:12},{default:s(()=>[n(`div`,B,[n(`div`,V,[i(Y,{size:`20`,color:`#E6A23C`},{default:s(()=>[i(c(f))]),_:1})]),r[15]||(r[15]=n(`div`,null,[n(`h4`,null,`细粒度权限控制`),n(`p`,{class:`text-g-700 text-sm`},`支持页面级、按钮级、数据级等多种粒度的权限控制。`)],-1))])]),_:1}),i(X,{span:12},{default:s(()=>[n(`div`,H,[n(`div`,U,[i(Y,{size:`20`,color:`#F56C6C`},{default:s(()=>[i(c(g))]),_:1})]),r[16]||(r[16]=n(`div`,null,[n(`h4`,null,`安全性优先原则`),n(`p`,{class:`text-g-700 text-sm`},`始终遵循最小权限原则，确保用户只能访问必要的功能和数据。`)],-1))])]),_:1})]),_:1})])]),_:1})])])}}});export{W as default};