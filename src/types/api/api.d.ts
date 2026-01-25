/**
 * API 接口类型定义模块
 *
 * 提供所有后端接口的类型定义
 *
 * ## 主要功能
 *
 * - 通用类型（分页参数、响应结构等）
 * - 认证类型（登录、用户信息等）
 * - 系统管理类型（用户、角色等）
 * - 全局命名空间声明
 *
 * ## 使用场景
 *
 * - API 请求参数类型约束
 * - API 响应数据类型定义
 * - 接口文档类型同步
 *
 * ## 注意事项
 *
 * - 在 .vue 文件使用需要在 eslint.config.mjs 中配置 globals: { Api: 'readonly' }
 * - 使用全局命名空间，无需导入即可使用
 *
 * ## 使用方式
 *
 * ```typescript
 * const params: Api.Auth.LoginParams = { userName: 'admin', password: '123456' }
 * const response: Api.Auth.UserInfo = await fetchUserInfo()
 * ```
 *
 * @module types/api/api
 * @author Art Design Pro Team
 */

declare namespace Api {
  /** 通用类型 */
  namespace Common {
    /** 分页参数 */
    interface PaginationParams {
      /** 当前页码 */
      current: number
      /** 每页条数 */
      size: number
      /** 总条数 */
      total: number
      /*适配supabase分页*/
      from: number
      to: number
    }

    /** 通用搜索参数 */
    type CommonSearchParams = Pick<PaginationParams, 'from' | 'to'>

    /** 分页响应基础结构 */
    interface PaginatedResponse<T = any> {
      records?: T[]
      current?: number
      size?: number
      total?: number
      data?: any
      error?: any
      count?: number | null
      response?: any
    }

    /** 启用状态 */
    type EnableStatus = '1' | '2'
  }

  /** 认证类型 */
  namespace Auth {
    /** 登录参数 */
    interface RegisterParams {
      userName?: string
      email: string
      password: string
    }

    /** 登录响应 */
    interface LoginResponse {
      token: string
      refreshToken: string
    }

    /** 用户信息 */
    interface UserInfo {
      roles: string[]
      userId: number
      userName?: string
      nickName?: string
      email: string
      avatar?: string
    }
  }

  /** 系统管理类型 */
  namespace SystemManage {
    /** 用户列表 */
    type UserList = Api.Common.PaginatedResponse<UserListItem>

    /** 用户列表项 */
    interface UserListItem {
      id?: string
      avatar?: string | null
      status?: string
      password: string
      confirmPassword: string
      userName: string
      userGender: string
      nickName: string
      userPhone: string
      userEmail: string
      userRoles: string[]
      userType?: string
      remark?: string
      createBy?: string
      createTime?: string
      updateBy?: string
      updateTime?: string
      authUserId?: string
    }

    /** 用户搜索参数 */
    type UserSearchParams = Partial<
      Pick<UserListItem, 'id' | 'userName' | 'userGender' | 'userPhone' | 'userEmail' | 'status'> &
        Api.Common.CommonSearchParams
    >

    /** 角色列表 */
    type RoleList = Api.Common.PaginatedResponse<RoleListItem>

    /** 角色列表项 */
    interface RoleListItem {
      id?: string
      roleId?: number
      roleName: string
      roleCode: string
      description?: string
      enabled?: boolean
      createTime?: string
      startTime?: string
      endTime?: string
    }

    /** 角色搜索参数 */
    type RoleSearchParams = Partial<
      Pick<
        RoleListItem,
        'roleId' | 'roleName' | 'roleCode' | 'description' | 'enabled' | 'startTime' | 'endTime'
      > &
        Api.Common.CommonSearchParams
    >
  }

  /** 数据中心类型 */
  namespace DataCenter {
    /** 数据字典列表项 */
    interface DictListItem {
      id?: string
      typeId?: string
      name: string
      code: string
      status: string
      label?: string
      value?: string
      i18n?: string
      i18nScope?: string
      remark?: string
      color?: string
      sort?: number
      createBy?: string
      createTime?: string
      updateBy?: string
      updateTime?: string
    }
    namespace Resources {
      interface Args {
        [key: string]: any
      }

      /** 用户搜索参数 */
      type ResourceSearchParams = Partial<
        Pick<ResourceListItem, 'originName' | 'suffix'> & Api.Common.CommonSearchParams
      >

      interface Button {
        name: string
        label: string
        icon: string
        click?: (btn: Resources.Button, selected: any[]) => void
        upload?: (files: File | File[], args: Args) => void
        uploadConfig?: Record<string, any>
        order?: number
      }

      interface ResourceListItem {
        id?: number
        storageMode?: number
        originName?: string
        objectName?: string
        hash?: string
        mimeType?: string
        storagePath?: string
        suffix?: string
        sizeByte?: number
        sizeInfo?: string
        url?: string
      }
    }
    namespace SqlConsole {
      interface DatabaseMetadata {
        schemas: string[]
        tables: TableMetadata[]
        functions: FunctionMetadata[]
      }

      interface TableMetadata {
        schema: string
        tableName: string
        columns: Array<{
          name: string
          dataType: string
          isNullable: boolean
        }>
      }

      interface ColumnMetadata {
        tableSchema: string
        tableName: string
        columnName: string
        dataType: string
        isNullable: string
        ordinalPosition: number
      }

      interface FunctionMetadata {
        routineSchema: string
        routineName: string
        returnType: string
      }

      interface SqlExecuteRequest {
        query: string
      }

      interface SqlExecuteResponse {
        status: 'ok' | 'error'
        errorMessage?: string
        rows?: any[]
        columns?: Array<{
          name: string
          type?: string | null
          fullType?: string | null
          nullable?: boolean | null
          jsType?: string | null
          description?: string | null
          maxLength?: number | null
          precision?: number | null
          scale?: number | null
          display?: {
            title?: string | null
            width?: number | null
            align?: 'left' | 'center' | 'right' | null
          }
        }>
        commandTag?: string
        rowCount?: number
        durationMs?: number
        notices?: string[]
        warnings?: string[]
        queryText?: string
      }
    }
  }
}
