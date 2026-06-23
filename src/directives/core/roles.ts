/**
 * v-roles 角色权限指令
 *
 * 基于用户角色控制 DOM 元素的显示和隐藏�?
 * 只要用户拥有指定角色中的任意一个，元素就会显示，否则从 DOM 中移除�?
 *
 * ## 主要功能
 *
 * - 角色验证 - 检查用户是否拥有指定角�?
 * - 多角色支�?- 支持单个角色或多个角色（满足其一即可�?
 * - DOM 控制 - 无权限时自动移除元素，而非隐藏
 * - 响应式更�?- 角色变化时自动更新元素状�?
 *
 * ## 使用示例
 *
 * ```vue
 * <template>
 *   <!-- 单个角色 - 只有超级管理员可�?-->
 *   <el-button v-roles="superRoleCode">超级管理员功�?/el-button>
 *
 *   <!-- 多个角色 - 超级管理员或普通管理员可见 -->
 *   <el-button v-roles="[superRoleCode, adminRoleCode]">管理员功�?/el-button>
 *
 *   <!-- 应用到任意元�?-->
 *   <div v-roles="[superRoleCode, adminRoleCode, userRoleCode]">
 *     所有登录用户可见的内容
 *   </div>
 * </template>
 * ```
 *
 * ## 权限逻辑
 *
 * - 用户角色�?userStore.getUserInfo.userRoles 获取
 * - 只要用户拥有指定角色中的任意一个，元素就会显示
 * - 如果用户没有任何角色或不满足条件，元素将被移�?
 *
 * ## 注意事项
 *
 * - 该指令会直接移除 DOM 元素，而不是使�?v-if 隐藏
 * - 适用于基于角色的粗粒度权限控�?
 * - 如需基于具体操作的细粒度权限控制，请使用 v-auth 指令
 *
 * @module directives/roles
 * @author Art Design Pro Team
 */

import { useUserStore } from '@/store/modules/user'
import { App, Directive, DirectiveBinding } from 'vue'

export type RolesDirective = Directive<HTMLElement, string | string[]>

function checkRolePermission(el: HTMLElement, binding: DirectiveBinding<string | string[]>): void {
  const userStore = useUserStore()
  const userRoles = userStore.getUserInfo.userRoles

  // 如果用户角色为空或未定义，移除元�?
  if (!userRoles?.length) {
    removeElement(el)
    return
  }

  // 确保指令值为数组格式
  const requiredRoles = Array.isArray(binding.value) ? binding.value : [binding.value]

  // 检查用户是否具有所需角色之一
  const hasPermission = requiredRoles.some((role: string) => userRoles.includes(role))

  // 如果没有权限，安全地移除元素
  if (!hasPermission) {
    removeElement(el)
  }
}

function removeElement(el: HTMLElement): void {
  if (el.parentNode) {
    el.parentNode.removeChild(el)
  }
}

const rolesDirective: RolesDirective = {
  mounted: checkRolePermission,
  updated: checkRolePermission
}

export function setupRolesDirective(app: App): void {
  app.directive('roles', rolesDirective)
}
