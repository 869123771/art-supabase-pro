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
      from?: number
      to?: number
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
    /** Element Plus Tag 预设类型 */
    type TagPreset = 'primary' | 'success' | 'info' | 'warning' | 'danger'
    /** 字典项保存的 Tag 类型，空值表示默认样式 */
    type TagType = '' | TagPreset
  }

  /** 认证类型 */
  namespace Auth {
    /** 登录参数 */
    interface RegisterParams {
      userName?: string
      email: string
      password: string
    }

    /** 忘记密码参数 */
    interface ForgetPwdParams {
      email: string
      redirectTo: string
    }

    /** 重置密码参数 */
    interface ResetPwdParams {
      password: string
      accessToken: string
      refreshToken?: string
    }

    /** 登录响应 */
    interface LoginResponse {
      token: string
      refreshToken: string
    }

    /** 用户信息 */
    interface UserInfo {
      userRoles: string[]
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
      tenantId?: string
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
      tenantId?: string
      roleId?: number
      roleName: string
      roleCode: string
      description?: string
      enabled?: boolean
      createTime?: string
      createBy?: string
      startTime?: string
      endTime?: string
    }

    /** 角色搜索参数 */
    type RoleSearchParams = Partial<
      Pick<
        RoleListItem,
        'roleId' | 'roleName' | 'roleCode' | 'description' | 'enabled' | 'startTime' | 'endTime'
      > &
        Api.Common.CommonSearchParams & {
          startTime: string | null
          endTime: string | null
        }
    >

    /** 租户列表项 */
    interface TenantListItem {
      id?: string
      tenantCode: string
      tenantName: string
      status?: Api.Common.EnableStatus
      contactName?: string
      contactPhone?: string
      contactEmail?: string
      remark?: string
      createBy?: string
      createTime?: string
      updateBy?: string
      updateTime?: string
    }

    /** 租户搜索参数 */
    type TenantSearchParams = Partial<
      Pick<TenantListItem, 'tenantCode' | 'tenantName' | 'status' | 'contactName'> &
        Api.Common.CommonSearchParams
    >
  }

  /** 车辆管理系统 */
  namespace VehicleMgtSys {
    namespace ArchiveManage {
      type AuditStatus = 'pending' | 'approved' | 'rejected'

      interface VehicleArchiveAttachment {
        name: string
        url: string
        fileType?: string
        fileSize?: string
      }

      interface VehicleArchive {
        id?: string
        tenantId?: string
        plateNo: string
        companyName?: string
        selfNo?: string
        vehicleType: string
        originType?: string
        vin: string
        manufacturer?: string
        brandModel?: string
        operationCertNo?: string
        purchaseCertNo?: string
        registrationCertNo?: string
        vehicleColor?: string
        chassisNo?: string
        acCode?: string
        gearboxSerialNo?: string
        registerDate?: string
        issueDate?: string
        invoiceDate?: string
        startUseDate?: string
        serviceYears?: number | null
        approvedPassengerCount?: number | null
        seatCount?: number | null
        businessType?: string
        isAirConditioned?: boolean
        operationStatus?: string
        operationStatusChangeDate?: string
        purchaseStatus?: string
        purchaseStatusChangeDate?: string
        inspectionStartDate?: string
        vehicleLevel?: string
        isNewEnergy?: boolean
        threeGuaranteeMileage?: number | null
        threeGuaranteeDuration?: number | null
        warrantyMileage?: number | null
        warrantyDuration?: number | null
        remark?: string

        grossMass?: number | null
        curbWeight?: number | null
        approvedLoadMass?: number | null
        overallLength?: number | null
        overallWidth?: number | null
        overallHeight?: number | null
        platform?: string
        frontTrack?: number | null
        rearTrack?: number | null
        wheelbase?: number | null
        axleCount?: number | null
        tireCount?: number | null
        leafSpringCount?: number | null
        isDoubleDeck?: boolean

        engineNo?: string
        engineModel?: string
        fuelType?: string
        displacement?: number | null
        emissionStandard?: string
        enginePower?: number | null
        ratedTorqueSpeed?: number | null
        engineTorque?: number | null

        plateColor?: string
        transportIndustry?: string
        operationType?: string
        ownerId?: string
        ownerName?: string
        ownerPhone?: string
        terminalPhone?: string
        ownerGender?: string
        idCardNo?: string
        mailingAddress?: string
        tonnageOrSeat?: string
        driverOneName?: string
        driverOnePhone?: string
        driverTwoName?: string
        driverTwoPhone?: string
        operationRoute?: string
        licensePlateCode?: string
        serviceStartTime?: string
        serviceEndTime?: string
        supportPhoto?: boolean

        vehiclePhotoUrl?: string
        drivingLicenseFrontUrl?: string
        drivingLicenseBackUrl?: string
        operationLicenseUrl?: string
        attachments?: VehicleArchiveAttachment[]

        auditStatus?: AuditStatus
        auditRemark?: string
        auditBy?: string
        auditTime?: string
        createBy?: string
        createTime?: string
        updateBy?: string
        updateTime?: string
      }

      type VehicleArchiveSearchParams = Partial<
        Pick<
          VehicleArchive,
          | 'plateNo'
          | 'companyName'
          | 'vehicleType'
          | 'manufacturer'
          | 'chassisNo'
          | 'operationStatus'
          | 'auditStatus'
        > &
          Api.Common.CommonSearchParams & {
            createTimeRange?: string[]
          }
      >
    }

    namespace BasicInfo {
      interface InsuranceCompany {
        id?: string
        tenantId?: string
        companyName: string
        contactPerson?: string
        contactPhone?: string
        region?: string
        addressDetail?: string
        remark?: string
        createTime?: string
        updateTime?: string
      }

      type InsuranceCompanySearchParams = Partial<
        Pick<InsuranceCompany, 'companyName' | 'contactPerson' | 'contactPhone'> &
          Api.Common.CommonSearchParams
      >

      interface Supplier {
        id?: string
        tenantId?: string
        supplierName: string
        contactPerson?: string
        contactPhone?: string
        region?: string
        addressDetail?: string
        remark?: string
        createBy?: string
        createTime?: string
        updateBy?: string
        updateTime?: string
      }

      type SupplierSearchParams = Partial<
        Pick<Supplier, 'supplierName' | 'contactPerson' | 'contactPhone'> &
          Api.Common.CommonSearchParams
      >

      interface PartsCategory {
        id?: string
        tenantId?: string
        parentId?: string | null
        categoryName: string
        categoryCode: string
        categoryLevel?: number
        sort?: number
        status?: Api.Common.EnableStatus
        remark?: string
        createBy?: string
        createTime?: string
        updateBy?: string
        updateTime?: string
        children?: PartsCategory[]
      }

      type PartsCategorySearchParams = Partial<
        Pick<PartsCategory, 'parentId' | 'categoryName' | 'categoryCode' | 'status'> &
          Api.Common.CommonSearchParams
      >

      interface Parts {
        id?: string
        tenantId?: string
        partName: string
        partCode: string
        categoryId?: string | null
        categoryName?: string
        brand?: string
        model?: string
        unit?: string
        supplierId?: string | null
        supplierName?: string
        manufacturer?: string
        supplierContact?: string
        isConsumable?: boolean
        warrantyMileage?: number | null
        warrantyDuration?: number | null
        serviceLife?: number | null
        serviceMileage?: number | null
        status?: Api.Common.EnableStatus
        remark?: string
        createBy?: string
        createTime?: string
        updateBy?: string
        updateTime?: string
      }

      type PartsSearchParams = Partial<
        Pick<
          Parts,
          'partName' | 'partCode' | 'categoryId' | 'brand' | 'model' | 'supplierId' | 'status'
        > &
          Api.Common.CommonSearchParams
      >
    }
  }

  /** 数据中心类型 */
  namespace DataCenter {
    /** 数据字典列表项 */
    interface DictListItem {
      id?: string
      tenantId?: string
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
      tagType?: Api.Common.TagType
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
        tenantId?: string
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
        columns: ColumnMetadata[]
        schemas: string[]
        tables: TableMetadata[]
        functions: FunctionMetadata[]
        foreignKeys: ForeignKeyMetadata[]
      }

      interface TableMetadata {
        tableSchema: string
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

      interface ForeignKeyMetadata {
        sourceSchema: string
        sourceTable: string
        sourceColumn: string
        targetSchema: string
        targetTable: string
        targetColumn: string
        constraintName: string
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

      interface SqlAiGenerateRequest {
        prompt: string
        mode?: 'generate' | 'fix'
        currentSql?: string
        metadata?: DatabaseMetadata
      }

      interface SqlAiGenerateResponse {
        sql: string
        summary?: string
        warnings?: string[]
      }
    }
  }
}
