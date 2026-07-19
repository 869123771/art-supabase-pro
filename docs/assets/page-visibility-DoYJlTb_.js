import"./rolldown-runtime-DAXXjFlN.js";import{$ as e,Bt as t,Et as n,Wt as r,ct as i,dt as a,et as o,g as s,h as c,in as l,sn as u}from"./element-plus-DkVo8qmm.js";import{B as d,Cr as f,I as p,Jn as m,K as h,L as g,Pt as _,Y as v,pn as y,q as b}from"./monaco-aKhfTkcy.js";import{Q as x,t as S}from"./user-MTVLYy-X.js";var C={class:`w-full py-2`},w={class:`mb-6`},T={class:`m-0 mb-2 text-xl font-medium`},E={class:`mb-6`},D={class:`flex-c gap-5`},O={class:`my-1 text-sm text-g-700`},k={class:`font-semibold`},A={class:`my-1 text-sm text-g-700`},j={class:`mb-6 last:mb-0`},M={class:`p-4 mt-3 mb-0 overflow-x-auto font-mono text-xs leading-[1.5] bg-g-200 border-full-d rounded-md`},N={class:``},P={class:`best-practices`},F={class:`practices-content`},I={class:`flex-c`},L={class:`size-10 bg-g-200 flex-cc rounded mr-2`},R={class:`flex-c`},z={class:`size-10 bg-g-200 flex-cc rounded mr-2`},B={class:`flex-c`},V={class:`size-10 bg-g-200 flex-cc rounded mr-2`},H={class:`flex-c`},U={class:`size-10 bg-g-200 flex-cc rounded mr-2`},W=v({name:`PermissionPageVisibility`,__name:`index`,setup(v){let W=S(),G=x.SUPER_ROLE_CODE,K=p(()=>W.info),q=e=>({[G]:`超级管理员`,R_ADMIN:`管理员`,R_USER:`普通用户`})[e]||`未知角色`;return(p,v)=>{let x=a,S=i,W=s,J=c,Y=n,X=e,Z=o;return _(),d(`div`,C,[g(`div`,w,[g(`h2`,T,f(p.$t(`menus.examples.permission.pageVisibility`)),1),v[0]||(v[0]=g(`p`,{class:`m-0 text-sm leading-[1.6] text-g-700`},[h(` 此页面仅对`),g(`strong`,{class:`font-semibold text-warning`},`超级管理员`),h(`用户可见，演示页面级别的权限控制。 如果您能看到此页面，说明您拥有相应的访问权限。 `)],-1))]),g(`div`,E,[b(S,{class:`art-card-xs`},{header:y(()=>[...v[1]||(v[1]=[g(`div`,{class:`flex-c gap-2 font-semibold`},[g(`span`,null,`权限验证成功`)],-1)])]),default:y(()=>[g(`div`,null,[g(`div`,D,[g(`div`,null,[v[4]||(v[4]=g(`h3`,{class:`m-0 mb-2 text-lg font-semibold`},`您拥有访问此页面的权限`,-1)),g(`p`,O,[v[2]||(v[2]=h(` 当前用户：`,-1)),g(`strong`,k,f(K.value.userName),1)]),g(`p`,A,[v[3]||(v[3]=h(` 用户角色： `,-1)),b(x,{type:`warning`},{default:y(()=>[h(f(q(K.value.userRoles?.[0]||``)),1)]),_:1})])])])])]),_:1})]),g(`div`,j,[b(S,{class:`art-card-xs`},{header:y(()=>[...v[5]||(v[5]=[g(`div`,{class:`flex-c font-semibold`},[g(`span`,null,`页面级权限控制说明`)],-1)])]),default:y(()=>[g(`div`,null,[b(J,null,{default:y(()=>[b(W,{timestamp:`前端控制模式`,type:`primary`,size:`large`},{default:y(()=>[b(S,null,{default:y(()=>[v[6]||(v[6]=g(`h4`,{class:`m-0 mb-2 text-base font-semibold`},`基于角色的权限控制`,-1)),v[7]||(v[7]=g(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},[h(` 在前端控制模式下，页面访问权限由路由配置文件中的 `),g(`code`,{class:`px-1.5 py-0.5 font-mono text-xs text-theme bg-theme/12 rounded`},`meta.roles`),h(` 字段定义，前端会根据用户接口所拥有的角色对路由和菜单进行过滤与控制 `)],-1)),g(`pre`,M,[g(`code`,N,`{
  path: 'page-visibility',
  name: 'PermissionPageVisibility',
  component: '/examples/permission/page-visibility',
  meta: {
    title: 'menus.permission.pageVisibility',
    roles: ['`+f(m(G))+`'], // 仅超级管理员可访问
    keepAlive: true
  }
}`,1)]),v[8]||(v[8]=g(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},[g(`strong`,null,`权限验证流程：`)],-1)),v[9]||(v[9]=g(`ul`,{class:`pl-5 my-2`},[g(`li`,{class:`my-1 leading-[1.5] text-g-700`},`用户登录后，接口返回用户角色信息`),g(`li`,{class:`my-1 leading-[1.5] text-g-700`},[h(` 在 `),g(`code`,{class:`px-1.5 py-0.5 font-mono text-xs text-theme bg-theme/12 rounded`},`beforeEach`),h(` 路由守卫中检查目标路由的 `),g(`code`,{class:`px-1.5 py-0.5 font-mono text-xs text-theme bg-theme/12 rounded`},`roles`),h(` 配置 `)]),g(`li`,{class:`my-1 leading-[1.5] text-g-700`},`比较用户角色是否包含在允许访问的角色列表中`),g(`li`,{class:`my-1 leading-[1.5] text-g-700`},`权限不足时跳转到 403 页面`)],-1))]),_:1})]),_:1}),b(W,{timestamp:`后端控制模式`,type:`warning`,size:`large`},{default:y(()=>[b(S,null,{default:y(()=>[...v[10]||(v[10]=[g(`h4`,{class:`m-0 mb-2 text-base font-semibold`},`基于菜单接口的权限控制`,-1),g(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},`在后端控制模式下，页面访问权限由后端统一管理，前端通过解析后端接口返回的菜单列表来生成可访问的路由，从而实现权限控制`,-1),g(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},`接口地址：src/api/menuApi.ts getMenuList`,-1),g(`pre`,{class:`p-4 mt-3 mb-0 overflow-x-auto font-mono text-xs leading-[1.5] bg-g-200 border-full-d rounded-md`},[g(`code`,{class:``},`
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
}`)],-1),g(`p`,null,[g(`strong`,null,`权限验证流程：`)],-1),g(`ul`,null,[g(`li`,null,`用户登录成功后获取 Token`),g(`li`,null,`前端调用菜单接口获取用户可访问的菜单列表`),g(`li`,null,`前端根据菜单列表动态注册路由`),g(`li`,null,`菜单中存在的页面用户可以正常访问，不存在的页面会跳转到 404`)],-1)])]),_:1})]),_:1}),b(W,{timestamp:`菜单显示控制`,type:`success`,size:`large`},{default:y(()=>[b(S,null,{default:y(()=>[...v[11]||(v[11]=[g(`h4`,null,`侧边栏菜单可见性`,-1),g(`p`,null,[g(`strong`,null,`前端控制模式：`)],-1),g(`ul`,null,[g(`li`,null,`有权限的用户：菜单项正常显示，可以点击访问`),g(`li`,null,`无权限的用户：菜单项不显示，无法通过菜单导航到页面`),g(`li`,null,`即使通过直接输入URL尝试访问，也会被路由守卫拦截`)],-1),g(`p`,null,[g(`strong`,null,`后端控制模式：`)],-1),g(`ul`,null,[g(`li`,null,`侧边栏菜单根据后端返回的菜单列表进行渲染`),g(`li`,null,`后端应该根据用户权限过滤，只返回用户有权限访问的菜单项`),g(`li`,null,`前端只显示后端返回的菜单，确保用户只能看到和访问有权限的页面`)],-1)])]),_:1})]),_:1})]),_:1})])]),_:1})]),g(`div`,P,[b(S,{class:`art-card-xs`},{header:y(()=>[...v[12]||(v[12]=[g(`div`,{class:`card-header`},[g(`span`,null,`权限控制最佳实践`)],-1)])]),default:y(()=>[g(`div`,F,[b(Z,{gutter:24},{default:y(()=>[b(X,{span:12,class:`!mb-5`},{default:y(()=>[g(`div`,I,[g(`div`,L,[b(Y,{size:`20`,color:`#409EFF`},{default:y(()=>[b(m(r))]),_:1})]),v[13]||(v[13]=g(`div`,null,[g(`h4`,null,`多层权限验证`),g(`p`,{class:`text-g-700 text-sm`},`在前端路由、后端接口、UI组件等多个层面实施权限控制，确保安全性。`)],-1))])]),_:1}),b(X,{span:12},{default:y(()=>[g(`div`,R,[g(`div`,z,[b(Y,{size:`20`,color:`#67C23A`},{default:y(()=>[b(m(l))]),_:1})]),v[14]||(v[14]=g(`div`,null,[g(`h4`,null,`基于角色的访问控制`),g(`p`,{class:`text-g-700 text-sm`},`采用RBAC模型，通过角色分配权限，简化权限管理复杂度。`)],-1))])]),_:1}),b(X,{span:12},{default:y(()=>[g(`div`,B,[g(`div`,V,[b(Y,{size:`20`,color:`#E6A23C`},{default:y(()=>[b(m(t))]),_:1})]),v[15]||(v[15]=g(`div`,null,[g(`h4`,null,`细粒度权限控制`),g(`p`,{class:`text-g-700 text-sm`},`支持页面级、按钮级、数据级等多种粒度的权限控制。`)],-1))])]),_:1}),b(X,{span:12},{default:y(()=>[g(`div`,H,[g(`div`,U,[b(Y,{size:`20`,color:`#F56C6C`},{default:y(()=>[b(m(u))]),_:1})]),v[16]||(v[16]=g(`div`,null,[g(`h4`,null,`安全性优先原则`),g(`p`,{class:`text-g-700 text-sm`},`始终遵循最小权限原则，确保用户只能访问必要的功能和数据。`)],-1))])]),_:1})]),_:1})])]),_:1})])])}}});export{W as default};