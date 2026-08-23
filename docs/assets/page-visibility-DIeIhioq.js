import"./rolldown-runtime-DAXXjFlN.js";import{Ba as e,Si as t,Ui as n,_i as r,aa as i,mi as a,pi as o,wa as s,wi as c,xi as l}from"./framework-zmx8ZOtz.js";import{nt as u,t as d}from"./user-Daptobl2.js";import{t as f}from"./icon-Ds7H3eYK.js";import{J as p,T as m,k as h,q as g}from"./style-DT-Q-OBS.js";import{t as _}from"./style-DY9LYPEO2.js";import{t as v}from"./style-30D1MWDe.js";import{n as y,t as b}from"./style-gBbHHbis.js";import{n as x,t as S}from"./style-CBmDVENu.js";import"./style-BctRytV1.js";var C={class:`w-full py-2`},w={class:`mb-6`},T={class:`m-0 mb-2 text-xl font-medium`},E={class:`mb-6`},D={class:`flex-c gap-5`},O={class:`my-1 text-sm text-g-700`},k={class:`font-semibold`},A={class:`my-1 text-sm text-g-700`},j={class:`mb-6 last:mb-0`},M={class:`p-4 mt-3 mb-0 overflow-x-auto font-mono text-xs leading-[1.5] bg-g-200 border-full-d rounded-md`},N={class:``},P={class:`best-practices`},F={class:`practices-content`},I={class:`flex-c`},L={class:`size-10 bg-g-200 flex-cc rounded mr-2`},R={class:`flex-c`},z={class:`size-10 bg-g-200 flex-cc rounded mr-2`},B={class:`flex-c`},V={class:`size-10 bg-g-200 flex-cc rounded mr-2`},H={class:`flex-c`},U={class:`size-10 bg-g-200 flex-cc rounded mr-2`},W=c({name:`PermissionPageVisibility`,__name:`index`,setup(c){let W=d(),G=u.SUPER_ROLE_CODE,K=o(()=>W.info),q=e=>({[G]:`超级管理员`,R_ADMIN:`管理员`,R_USER:`普通用户`})[e]||`未知角色`;return(o,c)=>{let u=_,d=v,W=x,J=S,Y=f,X=b,Z=y;return n(),r(`div`,C,[a(`div`,w,[a(`h2`,T,e(o.$t(`menus.examples.permission.pageVisibility`)),1),c[0]||(c[0]=a(`p`,{class:`m-0 text-sm leading-[1.6] text-g-700`},[l(` 此页面仅对`),a(`strong`,{class:`font-semibold text-warning`},`超级管理员`),l(`用户可见，演示页面级别的权限控制。 如果您能看到此页面，说明您拥有相应的访问权限。 `)],-1))]),a(`div`,E,[t(d,{class:`art-card-xs`},{header:i(()=>[...c[1]||(c[1]=[a(`div`,{class:`flex-c gap-2 font-semibold`},[a(`span`,null,`权限验证成功`)],-1)])]),default:i(()=>[a(`div`,null,[a(`div`,D,[a(`div`,null,[c[4]||(c[4]=a(`h3`,{class:`m-0 mb-2 text-lg font-semibold`},`您拥有访问此页面的权限`,-1)),a(`p`,O,[c[2]||(c[2]=l(` 当前用户：`,-1)),a(`strong`,k,e(K.value.userName),1)]),a(`p`,A,[c[3]||(c[3]=l(` 用户角色： `,-1)),t(u,{type:`warning`},{default:i(()=>[l(e(q(K.value.userRoles?.[0]||``)),1)]),_:1})])])])])]),_:1})]),a(`div`,j,[t(d,{class:`art-card-xs`},{header:i(()=>[...c[5]||(c[5]=[a(`div`,{class:`flex-c font-semibold`},[a(`span`,null,`页面级权限控制说明`)],-1)])]),default:i(()=>[a(`div`,null,[t(J,null,{default:i(()=>[t(W,{timestamp:`前端控制模式`,type:`primary`,size:`large`},{default:i(()=>[t(d,null,{default:i(()=>[c[6]||(c[6]=a(`h4`,{class:`m-0 mb-2 text-base font-semibold`},`基于角色的权限控制`,-1)),c[7]||(c[7]=a(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},[l(` 在前端控制模式下，页面访问权限由路由配置文件中的 `),a(`code`,{class:`px-1.5 py-0.5 font-mono text-xs text-theme bg-theme/12 rounded`},`meta.roles`),l(` 字段定义，前端会根据用户接口所拥有的角色对路由和菜单进行过滤与控制 `)],-1)),a(`pre`,M,[a(`code`,N,`{
  path: 'page-visibility',
  name: 'PermissionPageVisibility',
  component: '/examples/permission/page-visibility',
  meta: {
    title: 'menus.permission.pageVisibility',
    roles: ['`+e(s(G))+`'], // 仅超级管理员可访问
    keepAlive: true
  }
}`,1)]),c[8]||(c[8]=a(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},[a(`strong`,null,`权限验证流程：`)],-1)),c[9]||(c[9]=a(`ul`,{class:`pl-5 my-2`},[a(`li`,{class:`my-1 leading-[1.5] text-g-700`},`用户登录后，接口返回用户角色信息`),a(`li`,{class:`my-1 leading-[1.5] text-g-700`},[l(` 在 `),a(`code`,{class:`px-1.5 py-0.5 font-mono text-xs text-theme bg-theme/12 rounded`},`beforeEach`),l(` 路由守卫中检查目标路由的 `),a(`code`,{class:`px-1.5 py-0.5 font-mono text-xs text-theme bg-theme/12 rounded`},`roles`),l(` 配置 `)]),a(`li`,{class:`my-1 leading-[1.5] text-g-700`},`比较用户角色是否包含在允许访问的角色列表中`),a(`li`,{class:`my-1 leading-[1.5] text-g-700`},`权限不足时跳转到 403 页面`)],-1))]),_:1})]),_:1}),t(W,{timestamp:`后端控制模式`,type:`warning`,size:`large`},{default:i(()=>[t(d,null,{default:i(()=>[...c[10]||(c[10]=[a(`h4`,{class:`m-0 mb-2 text-base font-semibold`},`基于菜单接口的权限控制`,-1),a(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},`在后端控制模式下，页面访问权限由后端统一管理，前端通过解析后端接口返回的菜单列表来生成可访问的路由，从而实现权限控制`,-1),a(`p`,{class:`m-0 mb-2 leading-[1.6] text-g-700`},`接口地址：src/api/menuApi.ts getMenuList`,-1),a(`pre`,{class:`p-4 mt-3 mb-0 overflow-x-auto font-mono text-xs leading-[1.5] bg-g-200 border-full-d rounded-md`},[a(`code`,{class:``},`
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
}`)],-1),a(`p`,null,[a(`strong`,null,`权限验证流程：`)],-1),a(`ul`,null,[a(`li`,null,`用户登录成功后获取 Token`),a(`li`,null,`前端调用菜单接口获取用户可访问的菜单列表`),a(`li`,null,`前端根据菜单列表动态注册路由`),a(`li`,null,`菜单中存在的页面用户可以正常访问，不存在的页面会跳转到 404`)],-1)])]),_:1})]),_:1}),t(W,{timestamp:`菜单显示控制`,type:`success`,size:`large`},{default:i(()=>[t(d,null,{default:i(()=>[...c[11]||(c[11]=[a(`h4`,null,`侧边栏菜单可见性`,-1),a(`p`,null,[a(`strong`,null,`前端控制模式：`)],-1),a(`ul`,null,[a(`li`,null,`有权限的用户：菜单项正常显示，可以点击访问`),a(`li`,null,`无权限的用户：菜单项不显示，无法通过菜单导航到页面`),a(`li`,null,`即使通过直接输入URL尝试访问，也会被路由守卫拦截`)],-1),a(`p`,null,[a(`strong`,null,`后端控制模式：`)],-1),a(`ul`,null,[a(`li`,null,`侧边栏菜单根据后端返回的菜单列表进行渲染`),a(`li`,null,`后端应该根据用户权限过滤，只返回用户有权限访问的菜单项`),a(`li`,null,`前端只显示后端返回的菜单，确保用户只能看到和访问有权限的页面`)],-1)])]),_:1})]),_:1})]),_:1})])]),_:1})]),a(`div`,P,[t(d,{class:`art-card-xs`},{header:i(()=>[...c[12]||(c[12]=[a(`div`,{class:`card-header`},[a(`span`,null,`权限控制最佳实践`)],-1)])]),default:i(()=>[a(`div`,F,[t(Z,{gutter:24},{default:i(()=>[t(X,{span:12,class:`!mb-5`},{default:i(()=>[a(`div`,I,[a(`div`,L,[t(Y,{size:`20`,color:`#409EFF`},{default:i(()=>[t(s(h))]),_:1})]),c[13]||(c[13]=a(`div`,null,[a(`h4`,null,`多层权限验证`),a(`p`,{class:`text-g-700 text-sm`},`在前端路由、后端接口、UI组件等多个层面实施权限控制，确保安全性。`)],-1))])]),_:1}),t(X,{span:12},{default:i(()=>[a(`div`,R,[a(`div`,z,[t(Y,{size:`20`,color:`#67C23A`},{default:i(()=>[t(s(g))]),_:1})]),c[14]||(c[14]=a(`div`,null,[a(`h4`,null,`基于角色的访问控制`),a(`p`,{class:`text-g-700 text-sm`},`采用RBAC模型，通过角色分配权限，简化权限管理复杂度。`)],-1))])]),_:1}),t(X,{span:12},{default:i(()=>[a(`div`,B,[a(`div`,V,[t(Y,{size:`20`,color:`#E6A23C`},{default:i(()=>[t(s(m))]),_:1})]),c[15]||(c[15]=a(`div`,null,[a(`h4`,null,`细粒度权限控制`),a(`p`,{class:`text-g-700 text-sm`},`支持页面级、按钮级、数据级等多种粒度的权限控制。`)],-1))])]),_:1}),t(X,{span:12},{default:i(()=>[a(`div`,H,[a(`div`,U,[t(Y,{size:`20`,color:`#F56C6C`},{default:i(()=>[t(s(p))]),_:1})]),c[16]||(c[16]=a(`div`,null,[a(`h4`,null,`安全性优先原则`),a(`p`,{class:`text-g-700 text-sm`},`始终遵循最小权限原则，确保用户只能访问必要的功能和数据。`)],-1))])]),_:1})]),_:1})])]),_:1})])])}}});export{W as default};