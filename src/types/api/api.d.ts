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
    interface PaginatedResponse<T = unknown> {
      records?: T[]
      current?: number
      size?: number
      total?: number
      data?: T[]
      error?: unknown
      count?: number | null
      response?: unknown
    }

    /** 启用状态 */
    type EnableStatus = '1' | '2'
    /** Element Plus Tag 预设类型 */
    type TagPreset = 'primary' | 'success' | 'info' | 'warning' | 'danger'
    /** 敏感字段统一访问级别 */
    type FieldAccessLevel = 'hidden' | 'masked' | 'read' | 'edit'
    /** 字典项保存的 Tag 类型，空值表示默认样式 */
    type TagType = '' | TagPreset
  }

  /** 认证类型 */
  namespace Auth {
    import UserListItem = Api.SystemManage.UserListItem

    /** 登录参数 */
    interface RegisterParams {
      userName?: string
      email: string
      password: string
      captchaToken?: string
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
    type UserInfo = Partial<
      Omit<UserListItem, 'id' | 'userEmail'> & {
        userId: string
        email: string
        platformSuper: boolean
      }
    >
  }

  /** 系统管理类型 */
  namespace SystemManage {
    /** 用户列表 */
    type UserList = Api.Common.PaginatedResponse<UserListItem>

    /** 用户列表项 */
    interface UserListItem {
      id?: string
      tenantId?: string
      tenant?: Pick<TenantListItem, 'tenantCode' | 'tenantName' | 'builtinType'>
      organizationId?: string | null
      organization?: Pick<
        OrganizationListItem,
        'id' | 'organizationCode' | 'organizationName'
      > | null
      hrEmployeeId?: string | null
      hrEmployee?: {
        id: string
        employeeNo: string
        employeeName: string
        jobTitle?: string | null
        employmentStatus: string
      } | null
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
      deletedAt?: string | null
      deletedBy?: string | null
      authUserId?: string
      extra?: Record<string, unknown>
    }

    /** 用户搜索参数 */
    type UserSearchParams = Partial<
      Pick<
        UserListItem,
        | 'id'
        | 'tenantId'
        | 'organizationId'
        | 'userName'
        | 'userGender'
        | 'userPhone'
        | 'userEmail'
        | 'status'
      > &
        Api.Common.CommonSearchParams & {
          organizationIds: string[]
          organizationUnassigned: boolean
        }
    >

    /** 角色列表 */
    type RoleList = Api.Common.PaginatedResponse<RoleListItem>

    /** 角色列表项 */
    type RoleBuiltinType = 'platform_super' | 'default_register'

    interface RoleListItem {
      id?: string
      tenantId?: string
      tenant?: Pick<TenantListItem, 'tenantCode' | 'tenantName' | 'builtinType'>
      organizationId?: string | null
      organization?: Pick<
        OrganizationListItem,
        'id' | 'organizationCode' | 'organizationName'
      > | null
      roleId?: number
      roleName: string
      roleCode: string
      builtinType?: RoleBuiltinType | null
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
        | 'roleId'
        | 'tenantId'
        | 'organizationId'
        | 'roleName'
        | 'roleCode'
        | 'description'
        | 'enabled'
        | 'startTime'
        | 'endTime'
      > &
        Api.Common.CommonSearchParams & {
          recordId: string
          startTime: string | null
          endTime: string | null
          organizationIds: string[]
          organizationUnassigned: boolean
        }
    >

    type FieldPermissionSubjectType = 'role' | 'user'

    interface FieldPermissionResource {
      id: string
      resourceKey: string
      resourceLabel: string
      menuName: string
      fieldCount: number
    }

    interface FieldPermissionField {
      id: string
      fieldKey: string
      fieldLabel: string
      defaultAccess: Api.Tms.BasicData.FieldAccessLevel
      maskStrategy?: string | null
      ownerOverrideEnabled: boolean
      inheritedAccess: Api.Tms.BasicData.FieldAccessLevel
      explicitAccess?: Api.Tms.BasicData.FieldAccessLevel | null
    }

    interface FieldPermissionConfiguration {
      resourceId: string
      resourceKey: string
      resourceLabel: string
      subjectType: FieldPermissionSubjectType
      subjectId: string
      fields: FieldPermissionField[]
    }

    interface FieldPermissionAuditLog {
      id: string
      action: 'replace' | 'clear'
      beforeValue: Record<string, Api.Tms.BasicData.FieldAccessLevel>
      afterValue: Record<string, Api.Tms.BasicData.FieldAccessLevel>
      actorName: string
      actorEmail?: string | null
      createTime: string
    }

    type OrganizationType = 'company' | 'division' | 'department' | 'team'

    interface OrganizationMember {
      id: string
      tenantId?: string
      organizationId?: string | null
      organization?: Pick<
        OrganizationListItem,
        'id' | 'organizationCode' | 'organizationName'
      > | null
      avatar?: string | null
      userName: string
      nickName?: string | null
      userEmail: string
      status?: string
      userRoles?: string[]
    }

    interface OrganizationRoleMenu {
      menuId: string
      menu?: {
        name?: string
        type?: string
        meta?: Record<string, unknown>
      } | null
    }

    interface OrganizationRole {
      id: string
      roleName: string
      roleCode: string
      enabled?: boolean
      roleMenus?: OrganizationRoleMenu[]
    }

    interface OrganizationListItem {
      id?: string
      tenantId?: string
      tenant?: Pick<TenantListItem, 'tenantCode' | 'tenantName'>
      parentId?: string | null
      organizationCode: string
      organizationName: string
      organizationType: OrganizationType
      leaderUserId?: string | null
      leader?: Pick<
        OrganizationMember,
        'id' | 'avatar' | 'userName' | 'nickName' | 'userEmail'
      > | null
      status: Api.Common.EnableStatus
      sort: number
      phone?: string | null
      email?: string | null
      address?: string | null
      description?: string | null
      isSystem?: boolean
      members?: OrganizationMember[]
      roles?: OrganizationRole[]
      children?: OrganizationListItem[]
      createBy?: string
      createTime?: string
      updateBy?: string
      updateTime?: string
    }

    type OrganizationScopeFilterItem = Pick<
      OrganizationListItem,
      | 'id'
      | 'tenantId'
      | 'parentId'
      | 'organizationCode'
      | 'organizationName'
      | 'organizationType'
      | 'status'
      | 'sort'
      | 'isSystem'
    > & {
      scopeCount?: number
      children?: OrganizationScopeFilterItem[]
    }

    type OrganizationSearchParams = Partial<
      Pick<OrganizationListItem, 'tenantId' | 'organizationType' | 'status'> & {
        keyword: string
        recordId: string
      }
    >

    type OrganizationSavePayload = Pick<
      OrganizationListItem,
      | 'tenantId'
      | 'parentId'
      | 'organizationCode'
      | 'organizationName'
      | 'organizationType'
      | 'leaderUserId'
      | 'status'
      | 'sort'
      | 'phone'
      | 'email'
      | 'address'
      | 'description'
    > & { id?: string }

    /** 租户列表项 */
    type TenantBuiltinType = 'platform' | 'public_register'

    interface TenantListItem {
      id?: string
      tenantCode: string
      tenantName: string
      builtinType?: TenantBuiltinType | null
      status?: Api.Common.EnableStatus
      serviceStartDate?: string | null
      serviceEndDate?: string | null
      remark?: string
      createBy?: string
      createTime?: string
      updateBy?: string
      updateTime?: string
    }

    /** 租户搜索参数 */
    type TenantSearchParams = Partial<
      Pick<TenantListItem, 'tenantCode' | 'tenantName' | 'status'> & Api.Common.CommonSearchParams
    >

    type SystemParamType = 'single_text' | 'multi_text' | 'number' | 'boolean' | 'json'

    interface SystemParamItem {
      id?: string
      tenantId?: string
      paramName: string
      paramKey: string
      groupCode: string
      groupName: string
      paramType: SystemParamType
      defaultValue?: string | null
      paramValue: string
      extendConfig?: Record<string, unknown>
      enabled: boolean
      builtin: boolean
      sort: number
      remark?: string | null
      createBy?: string
      createTime?: string
      updateBy?: string
      updateTime?: string
    }

    type SystemParamSearchParams = Partial<
      Pick<SystemParamItem, 'groupCode' | 'paramType'> &
        Api.Common.CommonSearchParams & {
          keyword?: string
          enabled?: boolean
          builtin?: boolean
        }
    >

    interface SystemParamStats {
      total: number
      enabled: number
      builtin: number
      groups: number
      groupCounts: Record<string, number>
      lastRefreshTime?: string
    }

    interface RegistrationRoleOption {
      id: string
      roleName: string
      roleCode: string
      builtinType?: RoleBuiltinType | null
    }

    type DocumentNumberCategory = 'business_document' | 'master_data' | 'vehicle'
    type DocumentNumberResetCycle = 'none' | 'year' | 'month' | 'day'

    interface DocumentNumberCounterItem {
      id?: string
      ruleId: string
      tenantId: string
      ruleVersion: number
      periodKey: string
      currentValue: number
      updateTime?: string
    }

    interface DocumentNumberRuleItem {
      id?: string
      tenantId: string
      tenant?: Pick<TenantListItem, 'tenantCode' | 'tenantName'> | null
      ruleKey: string
      ruleName: string
      category: DocumentNumberCategory
      targetTable: string
      targetColumn: string
      autoEnabled: boolean
      template: string
      resetCycle: DocumentNumberResetCycle
      sequenceStart: number
      timezone: string
      ruleVersion: number
      manualRequired: boolean
      builtin: boolean
      enabled: boolean
      remark?: string | null
      createBy?: string
      createTime?: string
      updateBy?: string
      updateTime?: string
      counters?: DocumentNumberCounterItem[]
      currentValue?: number | null
      currentPeriodKey?: string
      nextValue?: number
      preview?: string
      scene?: DocumentNumberSceneItem | null
    }

    interface DocumentNumberSceneItem {
      ruleKey: string
      ruleName: string
      fieldLabel: string
      category: DocumentNumberCategory
      menuId: string
      menu?: Pick<AppRouteRecord, 'id' | 'name' | 'path' | 'component' | 'parentId' | 'meta'> | null
      targetTable: string
      targetColumn: string
      defaultTemplate: string
      defaultResetCycle: DocumentNumberResetCycle
      manualRequired: boolean
      enabled: boolean
      remark?: string | null
    }

    type DocumentNumberRuleSearchParams = Partial<
      Pick<DocumentNumberRuleItem, 'tenantId' | 'category' | 'autoEnabled'> &
        Api.Common.CommonSearchParams & {
          keyword?: string
          ruleKeys?: string[]
        }
    >

    type DocumentNumberRuleUpdatePayload = Pick<
      DocumentNumberRuleItem,
      'id' | 'autoEnabled' | 'template' | 'resetCycle' | 'sequenceStart' | 'timezone' | 'remark'
    >

    interface DocumentNumberRuleCreatePayload {
      tenantIds: string[]
      scene: DocumentNumberSceneItem
      autoEnabled: boolean
      template: string
      resetCycle: DocumentNumberResetCycle
      sequenceStart: number
      timezone: string
      remark?: string | null
    }

    interface DocumentNumberRuleBatchResult {
      created: number
      updated: number
      assigned: number
    }

    interface DocumentNumberRuleStats {
      total: number
      automatic: number
      manual: number
      tenantCount: number
      categoryCounts: Record<DocumentNumberCategory, number>
      lastUpdateTime?: string
    }

    type WebsiteWatermarkContentType = 'username' | 'username_time' | 'site_name' | 'custom'
    type WebsiteCaptchaType = 'turnstile'
    type WebsiteTurnstileSize = 'normal' | 'compact' | 'flexible' | 'hidden'
    type WebsiteTurnstileTheme = 'light' | 'dark' | 'auto'
    type WebsiteDefaultLanguage = 'zh' | 'en'
    type WebsiteConfigParamMeta = Pick<
      SystemParamItem,
      | 'paramName'
      | 'paramKey'
      | 'groupCode'
      | 'groupName'
      | 'paramType'
      | 'defaultValue'
      | 'extendConfig'
      | 'enabled'
      | 'builtin'
      | 'sort'
      | 'remark'
    >

    interface WebsiteConfigItem {
      id?: string
      tenantId?: string
      paramMeta?: WebsiteConfigParamMeta
      siteName: string
      siteShortName?: string | null
      siteDescription?: string | null
      logoUrl?: string | null
      faviconUrl?: string | null
      watermarkEnabled: boolean
      watermarkContentType: WebsiteWatermarkContentType
      watermarkCustomText?: string | null
      loginTitle: string
      loginSubtitle?: string | null
      loginDescription?: string | null
      defaultLanguage: WebsiteDefaultLanguage
      captchaEnabled: boolean
      captchaType: WebsiteCaptchaType
      turnstileSiteKey: string
      turnstileSize?: WebsiteTurnstileSize
      turnstileTheme?: WebsiteTurnstileTheme
      captchaMaxAttempts: number
      captchaLockMinutes: number
      registerEnabled: boolean
      maintenanceEnabled: boolean
      maintenanceMessage?: string | null
      seoTitle?: string | null
      seoKeywords?: string | null
      seoDescription?: string | null
      contactEmail?: string | null
      contactPhone?: string | null
      contactAddress?: string | null
      copyrightText?: string | null
      icpRecord?: string | null
      policeRecord?: string | null
      enabled: boolean
      createBy?: string
      createTime?: string
      updateBy?: string
      updateTime?: string
    }

    interface GeofenceConfigItem {
      id?: string
      tenantId?: string
      enabled: boolean
      loadingRadiusM: number
      unloadingRadiusM: number
      loadingAllowOutsideCheckIn: boolean
      unloadingAllowOutsideCheckIn: boolean
      autoConfirmLoading: boolean
      autoConfirmUnloading: boolean
      createBy?: string
      createTime?: string
      updateBy?: string
      updateTime?: string
    }
  }

  /** 车辆管理系统 */
  namespace Tms {
    namespace BasicData {
      type CustomerAddressType = 'shipping' | 'receiving'
      type CustomerFieldKey = 'contactPhone' | 'addressDetail' | 'taxNo' | 'bankAccount'
      type CustomerFieldAccessMap = Partial<Record<CustomerFieldKey, FieldAccessLevel>>
      type CustomerAddressFieldKey = 'contactPhone' | 'addressDetail'
      type CustomerAddressFieldAccessMap = Partial<
        Record<CustomerAddressFieldKey, FieldAccessLevel>
      >
      type CarrierFieldKey =
        'contactPhone' | 'addressDetail' | 'taxNo' | 'bankAccount' | 'attachments'
      type CarrierFieldAccessMap = Partial<Record<CarrierFieldKey, FieldAccessLevel>>
      type DriverFieldKey =
        'contactPhone' | 'idCardNo' | 'homeAddress' | 'emergencyContact' | 'identityDocuments'
      type DriverFieldAccessMap = Partial<Record<DriverFieldKey, FieldAccessLevel>>
      type SensitiveNumber = number | string | null
      type CarrierPriceFieldKey = 'contactPhones' | 'costAmounts' | 'paymentAmounts'
      type CarrierPriceFieldAccessMap = Partial<Record<CarrierPriceFieldKey, FieldAccessLevel>>
      type CustomerPriceFieldKey =
        'contactPhones' | 'addressDetails' | 'quoteAmounts' | 'paymentAmounts'
      type CustomerPriceFieldAccessMap = Partial<Record<CustomerPriceFieldKey, FieldAccessLevel>>

      /** VMS 通过只读集成契约提供给 TMS 的最小车辆视图。 */
      interface VehicleReferenceOption {
        id?: string
        carrierId?: string | null
        plateNo: string
        companyName?: string
        vin?: string
        selfNo?: string
        vehicleType?: string
        fieldAccess?: Record<string, Api.System.FieldPermissionAccessLevel>
        isRecordOwner?: boolean
      }

      interface Customer {
        id?: string
        tenantId?: string
        parentUnitId?: string | null
        customerCode?: string
        customerName: string
        industry?: string
        customerLevel?: string
        tags?: string[]
        region?: string
        regionAdcode?: string | null
        addressDetail?: string
        longitude?: number | string | null
        latitude?: number | string | null
        coordinateSystem?: string | null
        coordinateSource?: string | null
        coordinateStatus?: string | null
        geocodeProvider?: string | null
        geocodedAt?: string | null
        postalCode?: string
        enabled?: boolean
        contactName?: string
        contactPhone?: string
        contactDepartment?: string
        contactPosition?: string
        contactEmail?: string
        contactQq?: string
        invoiceTitle?: string
        taxNo?: string
        bankName?: string
        bankAccount?: string
        remark?: string
        createBy?: string
        createTime?: string
        updateBy?: string
        updateTime?: string
        fieldAccess?: CustomerFieldAccessMap
        isRecordOwner?: boolean
      }

      type CustomerSearchParams = Partial<
        Pick<Customer, 'customerLevel' | 'industry' | 'enabled'> &
          Api.Common.CommonSearchParams & {
            customerId?: string
            keyword?: string
            createTimeRange?: string[]
          }
      >

      interface CustomerOption {
        id: string
        tenantId?: string
        customerCode?: string
        customerName: string
        enabled?: boolean
        contactName?: string
        contactPhone?: string
        region?: string
        regionAdcode?: string | null
        addressDetail?: string
        longitude?: number | string | null
        latitude?: number | string | null
        coordinateSystem?: string | null
        coordinateSource?: string | null
        coordinateStatus?: string | null
        geocodeProvider?: string | null
        geocodedAt?: string | null
        postalCode?: string
        fieldAccess?: CustomerFieldAccessMap
        isRecordOwner?: boolean
      }

      interface CustomerAddress {
        id?: string
        tenantId?: string
        customerId: string | null
        addressType: CustomerAddressType
        contactName: string
        contactPhone: string
        region: string
        regionAdcode?: string | null
        addressDetail: string
        longitude?: number | string | null
        latitude?: number | string | null
        coordinateSystem?: string | null
        coordinateSource?: string | null
        coordinateStatus?: string | null
        geocodeProvider?: string | null
        geocodedAt?: string | null
        geofenceEnabled?: boolean
        geofenceRadiusM?: number | null
        geofenceUpdatedAt?: string | null
        postalCode?: string
        isDefault?: boolean
        remark?: string
        customer?: CustomerOption | null
        createBy?: string
        createTime?: string
        updateBy?: string
        updateTime?: string
        fieldAccess?: CustomerAddressFieldAccessMap
        isRecordOwner?: boolean
      }

      type CustomerAddressSearchParams = Partial<
        Pick<CustomerAddress, 'customerId' | 'addressType'> &
          Api.Common.CommonSearchParams & {
            keyword?: string
            createTimeRange?: string[]
            recordId?: string
          }
      >

      interface FavoriteRoute {
        id?: string
        tenantId?: string
        tenant?: Pick<Api.SystemManage.TenantListItem, 'id' | 'tenantCode' | 'tenantName'> | null
        routeName: string
        customerId: string
        customer?: CustomerOption | null
        originAddressId: string
        originAddress?: CustomerAddress | null
        destinationAddressId: string
        destinationAddress?: CustomerAddress | null
        distanceKm?: number | string | null
        estimatedMinutes?: number | null
        enabled: boolean
        remark?: string | null
        createBy?: string
        createTime?: string
        updateBy?: string
        updateTime?: string
      }

      type FavoriteRouteSearchParams = Partial<
        Pick<FavoriteRoute, 'tenantId' | 'customerId' | 'enabled'> &
          Api.Common.CommonSearchParams & {
            keyword?: string
          }
      >

      interface CustomerPriceCargoItem {
        cargoName?: string | null
        quantity?: number | null
        unit?: string | null
        volumeM3?: number | null
        weightKg?: number | null
      }

      interface CustomerPrice {
        id?: string
        tenantId?: string
        customerId: string
        customer?: CustomerOption | null
        originRegion: string
        destinationRegion: string
        transportType: string
        cargoType?: string | null
        shippingAddressId?: string | null
        receivingAddressId?: string | null
        shippingContactName?: string | null
        shippingContactPhone?: string | null
        shippingAddressDetail?: string | null
        shippingLongitude?: number | string | null
        shippingLatitude?: number | string | null
        receivingContactName?: string | null
        receivingContactPhone?: string | null
        receivingAddressDetail?: string | null
        receivingLongitude?: number | string | null
        receivingLatitude?: number | string | null
        cargoItems?: CustomerPriceCargoItem[]
        cargoQuantityTotal?: number | null
        cargoVolumeTotal?: number | null
        cargoWeightTotal?: number | null
        vehicleType?: string | null
        vehicleLength?: string | null
        vehicleCount?: number | null
        billingMethod: string
        transportFee?: SensitiveNumber
        insuranceFee?: SensitiveNumber
        packageFee?: SensitiveNumber
        loadingFee?: SensitiveNumber
        transferFee?: SensitiveNumber
        fuelFee?: SensitiveNumber
        serviceFee?: SensitiveNumber
        otherFee?: SensitiveNumber
        totalFee?: SensitiveNumber
        cashAmount?: SensitiveNumber
        prepaidAmount?: SensitiveNumber
        collectAmount?: SensitiveNumber
        periodicAmount?: SensitiveNumber
        paymentTotal?: SensitiveNumber
        remark?: string | null
        createBy?: string
        createTime?: string
        updateBy?: string
        updateTime?: string
        fieldAccess?: CustomerPriceFieldAccessMap
        isRecordOwner?: boolean
      }

      type CustomerPriceSearchParams = Partial<
        Pick<
          CustomerPrice,
          | 'customerId'
          | 'originRegion'
          | 'destinationRegion'
          | 'transportType'
          | 'cargoType'
          | 'billingMethod'
        > &
          Api.Common.CommonSearchParams & {
            keyword?: string
            createTimeRange?: string[]
            recordId?: string
          }
      >

      interface Carrier {
        id?: string
        tenantId?: string
        parentUnitId?: string | null
        carrierCode?: string
        companyName: string
        carrierType: string
        businessLicenseNo?: string
        taxRegistrationNo?: string
        legalRepresentative?: string
        region?: string
        addressDetail?: string
        postalCode?: string
        enabled?: boolean
        businessLicenseUrl?: string
        driverCount?: number | null
        vehicleCount?: number | null
        contactName?: string
        contactPhone?: string
        contactDepartment?: string
        contactPosition?: string
        contactEmail?: string
        contactQq?: string
        invoiceTitle?: string
        taxNo?: string
        bankName?: string
        bankAccountName?: string
        bankAccount?: string
        signedContract?: boolean
        contractAttachmentUrl?: string
        remark?: string
        createBy?: string
        createTime?: string
        updateBy?: string
        updateTime?: string
        fieldAccess?: CarrierFieldAccessMap
        isRecordOwner?: boolean
      }

      type CarrierSearchParams = Partial<
        Pick<Carrier, 'carrierType' | 'enabled' | 'signedContract'> &
          Api.Common.CommonSearchParams & {
            keyword?: string
            createTimeRange?: string[]
            recordId?: string
          }
      >

      interface CarrierOption {
        id: string
        carrierCode?: string
        companyName: string
        enabled?: boolean
        contactName?: string
        contactPhone?: string
        fieldAccess?: CarrierFieldAccessMap
        isRecordOwner?: boolean
      }

      type CarrierPerformanceSeverity = 'critical' | 'high' | 'medium'
      type CarrierPerformanceRiskLevel = CarrierPerformanceSeverity | 'low'
      type CarrierCooperationStrategy =
        | 'manual_qualification_review'
        | 'conditional_cooperation'
        | 'improve_and_monitor'
        | 'preferred_partner'
        | 'insufficient_evidence'

      interface CarrierPerformanceSignal {
        type: string
        severity: CarrierPerformanceSeverity
        title: string
        detail: string
        evidence: string[]
      }

      interface CarrierPerformanceWaybill {
        id: string
        waybillNo: string
        route: string
        status: string
        freightAmount: number
        plannedUnloadTime: string | null
        arrivedAt: string | null
        riskScore: number
        reasons: string[]
      }

      interface CarrierPerformanceAssessment {
        carrierId: string
        carrierCode: string
        companyName: string
        riskLevel: CarrierPerformanceRiskLevel
        riskScore: number
        performanceScore: number
        confidence: number
        cooperationStrategy: CarrierCooperationStrategy
        summary: string
        signals: CarrierPerformanceSignal[]
        riskWaybills: CarrierPerformanceWaybill[]
        recommendedActions: string[]
        limitations: string[]
        metrics: {
          waybillCount: number
          completedCount: number
          cancelledCount: number
          activeCount: number
          completionRate: number
          cancellationRate: number
          onTimeRate: number | null
          onTimeSampleCount: number
          routeCount: number
          totalFreightAmount: number
          totalCostAmount: number
          costToFreightRate: number | null
          pendingCostCount: number
          rejectedCostCount: number
          openStatementCount: number
          driverCount: number
          vehicleCount: number
          daysSinceLastWaybill: number | null
        }
      }

      interface CarrierPerformanceAdvisorResponse {
        runId: string
        ruleVersion: string
        generatedAt: string
        assessment: CarrierPerformanceAssessment
      }

      interface CarrierPriceCargoItem {
        orderNo?: string | null
        originRegion?: string | null
        destinationRegion?: string | null
        cargoName?: string | null
        quantity?: number | null
        unit?: string | null
        volumeM3?: number | null
        weightKg?: number | null
        splitTransportFee?: SensitiveNumber
        loadingFee?: SensitiveNumber
        packageFee?: SensitiveNumber
      }

      interface CarrierPrice {
        id?: string
        tenantId?: string
        quoteNo: string
        carrierId: string
        carrier?: CarrierOption | null
        driverId?: string | null
        driver?: DriverOption | null
        vehicleId?: string | null
        vehicle?: VehicleReferenceOption | null
        originRegion: string
        destinationRegion: string
        transportMode: string
        contactName?: string | null
        contactPhone?: string | null
        driverName?: string | null
        driverPhone?: string | null
        plateNo?: string | null
        vehicleType?: string | null
        vehicleLength?: string | null
        cargoItems?: CarrierPriceCargoItem[]
        cargoQuantityTotal?: number | null
        cargoVolumeTotal?: number | null
        cargoWeightTotal?: number | null
        billingMethod: string
        transportCost?: SensitiveNumber
        splitTransportFee?: SensitiveNumber
        loadingFee?: SensitiveNumber
        packageFee?: SensitiveNumber
        otherFee?: SensitiveNumber
        totalFee?: SensitiveNumber
        cashAmount?: SensitiveNumber
        prepaidAmount?: SensitiveNumber
        collectAmount?: SensitiveNumber
        periodicAmount?: SensitiveNumber
        paymentTotal?: SensitiveNumber
        remark?: string | null
        createBy?: string
        createTime?: string
        updateBy?: string
        updateTime?: string
        fieldAccess?: CarrierPriceFieldAccessMap
        isRecordOwner?: boolean
      }

      type CarrierPriceSearchParams = Partial<
        Pick<
          CarrierPrice,
          'carrierId' | 'originRegion' | 'destinationRegion' | 'transportMode' | 'billingMethod'
        > &
          Api.Common.CommonSearchParams & {
            keyword?: string
            createTimeRange?: string[]
            recordId?: string
          }
      >

      interface Driver {
        id?: string
        tenantId?: string
        employeeId?: string | null
        carrierId: string
        driverName: string
        phone?: string
        gender: string
        idCardNo?: string
        licenseType: string
        driverType: 'primary' | 'secondary'
        licenseExpireDate?: string | null
        homeAddress?: string
        emergencyContactName?: string
        emergencyContactPhone?: string
        enabled?: boolean
        idCardFrontUrl?: string | null
        idCardBackUrl?: string | null
        driverLicenseFrontUrl?: string | null
        driverLicenseBackUrl?: string | null
        remark?: string
        carrier?: CarrierOption | null
        assignedVehicles?: DriverAssignedVehicle[]
        createBy?: string
        createTime?: string
        updateBy?: string
        updateTime?: string
        fieldAccess?: DriverFieldAccessMap
        isRecordOwner?: boolean
      }

      interface DriverEmployeeOption {
        id: string
        tenantId: string
        tenant: Pick<Api.SystemManage.TenantListItem, 'id' | 'tenantCode' | 'tenantName'>
        employeeNo: string
        employeeName: string
        organizationId?: string | null
        organization?: Pick<
          Api.SystemManage.OrganizationListItem,
          'id' | 'organizationCode' | 'organizationName'
        > | null
        jobTitle?: string | null
        employmentStatus: string
        gender?: string | null
        phone?: string | null
        idCardNo?: string | null
        homeAddress?: string | null
        emergencyContactName?: string | null
        emergencyContactPhone?: string | null
      }

      interface DriverAssignedVehicle {
        id: string
        carrierId?: string | null
        plateNo: string
      }

      type DriverSearchParams = Partial<
        Pick<Driver, 'carrierId' | 'driverType' | 'gender' | 'enabled'> &
          Api.Common.CommonSearchParams & {
            keyword?: string
            createTimeRange?: string[]
            recordId?: string
          }
      >

      interface DriverOption {
        id: string
        carrierId?: string | null
        driverName: string
        phone?: string
        driverType?: 'primary' | 'secondary'
        licenseType?: string
        licenseExpireDate?: string | null
        enabled?: boolean
        fieldAccess?: DriverFieldAccessMap
        isRecordOwner?: boolean
      }

      interface Cargo {
        id?: string
        tenantId?: string
        cargoCode?: string
        cargoName: string
        unit: string
        lengthM?: number | null
        widthM?: number | null
        heightM?: number | null
        volumeM3?: number | null
        weightKg?: number | null
        valueAmount?: number | null
        enabled?: boolean
        remark?: string | null
        createBy?: string
        createTime?: string
        updateBy?: string
        updateTime?: string
      }

      type CargoSearchParams = Partial<
        Pick<Cargo, 'unit' | 'enabled'> &
          Api.Common.CommonSearchParams & {
            keyword?: string
            createTimeRange?: string[]
            recordId?: string
          }
      >

      type ContractStatus = 'draft' | 'pending' | 'approved' | 'rejected' | 'terminated'
      type ContractBusinessType = 'customer' | 'carrier'
      type FieldAccessLevel = 'hidden' | 'masked' | 'read' | 'edit'
      type ContractFieldKey =
        | 'contractAmount'
        | 'transportUnitPrice'
        | 'roadConsumptionRate'
        | 'lossDeductionPrice'
        | 'transportDetailsPricing'
        | 'partyContactPhone'
        | 'attachments'
      type ContractFieldAccessMap = Partial<Record<ContractFieldKey, FieldAccessLevel>>

      interface ContractAttachment {
        name: string
        url?: string
        fileType?: string
        fileSize?: string
      }

      interface ContractTransportDetail {
        cargoId?: string | null
        cargoDescription: string
        cargoCode: string
        contractQuantity: number
        unit: string
        transportUnitPrice?: SensitiveNumber
        freight?: SensitiveNumber
      }

      interface Contract {
        id?: string
        tenantId?: string
        contractNo?: string
        contractName: string
        contractStatus?: ContractStatus
        paperContractNo?: string | null
        mnemonicCode?: string | null
        contractCategory: string
        transportMode: string
        businessContractType: ContractBusinessType
        customerId?: string | null
        customer?: CustomerOption | null
        carrierId?: string | null
        partyContactPhone?: string | null
        contactName?: string | null
        waybillNo?: string | null
        customerSignatory?: string | null
        billingMethod: string
        contractAmount?: SensitiveNumber
        transportUnitPrice?: SensitiveNumber
        roadConsumptionRate?: SensitiveNumber
        lossDeductionPrice?: SensitiveNumber
        signTime: string
        effectiveDate?: string | null
        expiryDate?: string | null
        isCompleted: boolean
        agreedTransportQuantity?: number | null
        transportRoute?: string | null
        shipperName?: string | null
        payerName?: string | null
        consigneeName?: string | null
        specialTransportRequirements?: string | null
        otherDeductionTerms?: string | null
        handler: string
        contractDescription?: string | null
        transportDetails: ContractTransportDetail[]
        attachments?: ContractAttachment[]
        carrier?: CarrierOption | null
        createBy?: string
        createTime?: string
        updateBy?: string
        updateTime?: string
        fieldAccess?: ContractFieldAccessMap
        isRecordOwner?: boolean
      }

      type ContractSearchParams = Partial<
        Pick<
          Contract,
          | 'contractStatus'
          | 'businessContractType'
          | 'contractCategory'
          | 'customerId'
          | 'carrierId'
          | 'billingMethod'
        > &
          Api.Common.CommonSearchParams & {
            keyword?: string
            createTimeRange?: string[]
            recordId?: string
          }
      >

      interface ContractDetailSelectorItem extends Omit<
        ContractTransportDetail,
        'transportUnitPrice' | 'freight'
      > {
        key: string
        contractId: string
        contractNo: string
        contractName: string
        effectiveDate?: string | null
        expiryDate?: string | null
        transportUnitPrice: number | null
        freight: number | null
      }

      interface ContractDetailSelectorSearchParams extends Api.Common.CommonSearchParams {
        keyword?: string
      }
    }

    namespace Order {
      type OrderFieldKey =
        | 'shipperContact'
        | 'shipperAddress'
        | 'receiverContact'
        | 'receiverAddress'
        | 'cargoPricing'
        | 'freightAmounts'
        | 'settlementAmounts'
        | 'driverPhone'
        | 'proofAttachments'
        | 'routeCoordinates'
      type OrderFieldAccessMap = Partial<Record<OrderFieldKey, Api.Tms.BasicData.FieldAccessLevel>>

      interface StationOption {
        id: string
        stationCode: string
        stationName: string
        stationType: string
        stationRoles?: Api.Tms.Station.StationRoleRecord[]
        regionCode?: string | null
      }

      interface CustomerSelectorItem {
        id: string
        customerCode?: string
        customerName: string
        addressId?: string | null
        addressType?: Api.Tms.BasicData.CustomerAddressType
        contactName?: string
        contactPhone?: string
        region?: string
        regionAdcode?: string | null
        addressDetail?: string
        longitude?: number | string | null
        latitude?: number | string | null
        fieldAccess?:
          Api.Tms.BasicData.CustomerFieldAccessMap | Api.Tms.BasicData.CustomerAddressFieldAccessMap
        isRecordOwner?: boolean
      }

      interface CargoItem {
        cargoId?: string | null
        cargoName?: string | null
        cargoCode?: string | null
        packageType?: string | null
        quantity?: number | null
        unit?: string | null
        weightKg?: number | null
        volumeM3?: number | null
        unitPrice?: number | string | null
        freight?: number | string | null
        sourceContractId?: string | null
        sourceContractNo?: string | null
        sourceContractName?: string | null
        sourceContractDetailKey?: string | null
      }

      interface AiOrderOption {
        label: string
        value: string
      }

      interface AiOrderAnalyzeRequest {
        action?: 'analyze'
        prompt?: string
        imageUrls?: string[]
        options?: {
          deliveryMethods?: AiOrderOption[]
          paymentMethods?: AiOrderOption[]
          transportModes?: AiOrderOption[]
          cargoUnits?: AiOrderOption[]
        }
      }

      interface AiOrderExampleRequest {
        options?: AiOrderAnalyzeRequest['options']
      }

      interface AiOrderExampleResponse {
        prompt: string
      }

      interface AiOrderDraft {
        originStationName?: string | null
        destinationStationName?: string | null
        transferStationName?: string | null
        deliveryMethod?: string | null
        shippingCustomerName?: string | null
        shippingContactName?: string | null
        shippingContactPhone?: string | null
        shippingAddressDetail?: string | null
        receivingCustomerName?: string | null
        receivingContactName?: string | null
        receivingContactPhone?: string | null
        receivingAddressDetail?: string | null
        cargoItems?: CargoItem[]
        transportFee?: number | null
        deliveryFee?: number | null
        unloadingFee?: number | null
        collectPaymentFee?: number | null
        transferFee?: number | null
        declaredValue?: number | null
        insuranceFee?: number | null
        packageFee?: number | null
        otherFee?: number | null
        paymentMethod?: string | null
        cashAmount?: number | null
        collectAmount?: number | null
        monthlyAmount?: number | null
        codAmount?: number | null
        handlingFee?: number | null
        transportMode?: string | null
        orderRemark?: string | null
      }

      interface AiOrderAnalyzeResponse {
        artifactId: string
        runId: string
        summary: string
        confidence: number
        fieldConfidence?: Record<string, number>
        missingFields: string[]
        warnings: string[]
        order: AiOrderDraft
      }

      interface AiOrderReviewRequest {
        action: 'review'
        artifactId: string
        entityId: string
        outcome: 'applied'
        finalPayload: AiOrderDraft
        reviewNote?: string
      }

      interface AiOrderReviewResponse {
        artifactId: string
        status: 'applied' | 'rejected'
        acceptedFields: string[]
        correctedFields: string[]
      }

      type AiOrderMasterDataTaskKind = 'station' | 'customer' | 'address' | 'cargo'

      interface AiOrderMasterDataCreateTask {
        key: string
        kind: AiOrderMasterDataTaskKind
        payload: Record<string, unknown>
      }

      interface AiOrderMasterDataCreateResult {
        key: string
        kind: AiOrderMasterDataTaskKind
        id: string
      }

      interface OrderRecord {
        id?: string
        tenantId?: string
        orderNo: string
        waybillNo?: string | null
        cargoNo?: string | null
        orderStatus?: string
        originStationId?: string | null
        destinationStationId?: string | null
        transferStationId?: string | null
        originStation: string
        destinationStation: string
        transferStation?: string | null
        originStationRef?: StationOption | null
        destinationStationRef?: StationOption | null
        transferStationRef?: StationOption | null
        deliveryMethod: string
        shippingCustomerId?: string | null
        receivingCustomerId?: string | null
        shippingAddressId?: string | null
        receivingAddressId?: string | null
        shippingCustomer?: CustomerSelectorItem | null
        receivingCustomer?: CustomerSelectorItem | null
        shippingContactName: string
        shippingContactPhone: string
        shippingAddressDetail: string
        shippingLongitude?: number | string | null
        shippingLatitude?: number | string | null
        receivingContactName: string
        receivingContactPhone: string
        receivingAddressDetail: string
        receivingLongitude?: number | string | null
        receivingLatitude?: number | string | null
        cargoItems?: CargoItem[]
        cargoQuantityTotal?: number | null
        cargoWeightTotal?: number | null
        cargoVolumeTotal?: number | null
        transportFee?: number | string | null
        deliveryFee?: number | string | null
        unloadingFee?: number | string | null
        collectPaymentFee?: number | string | null
        transferFee?: number | string | null
        declaredValue?: number | string | null
        insuranceFee?: number | string | null
        packageFee?: number | string | null
        otherFee?: number | string | null
        totalFee?: number | string | null
        paymentMethod: string
        cashAmount?: number | string | null
        collectAmount?: number | string | null
        monthlyAmount?: number | string | null
        codAmount?: number | string | null
        handlingFee?: number | string | null
        paymentTotal?: number | string | null
        transportMode?: string | null
        orderRemark?: string | null
        imageUrls?: string[]
        signedCodAmount?: number | string | null
        receiptImageUrls?: string[]
        signedAt?: string | null
        relatedWaybills?: Waybill.RelatedWaybillSummary[]
        driverWaybillAcceptedAt?: string | null
        driverWaybillLoadedAt?: string | null
        driverWaybillDepartedAt?: string | null
        driverWaybillUnloadedAt?: string | null
        driverWaybillCompletedAt?: string | null
        driverWaybillSignedAt?: string | null
        driverWaybillSignedBy?: string | null
        driverWaybillSignatureProofCount?: number
        driverWaybillReturnTime?: string | null
        driverWaybillReturnOdometerKm?: number | null
        driverWaybillReturnPhotoCount?: number
        driverWaybillUnloadingStatus?: Waybill.CargoOperationStatus | null
        driverWaybillId?: string | null
        waybillStatus?: string | null
        dispatchStatus?: string
        dispatchVehicleId?: string | null
        dispatchDriverId?: string | null
        dispatchPlateNo?: string | null
        dispatchVehicleType?: string | null
        dispatchVehicleLength?: string | null
        dispatchDriverName?: string | null
        dispatchDriverPhone?: string | null
        plannedDepartureTime?: string | null
        plannedArrivalTime?: string | null
        dispatchRemark?: string | null
        dispatchedAt?: string | null
        dispatchBy?: string | null
        dispatchVehicle?: Waybill.DispatchVehicleOption | null
        dispatchDriver?: BasicData.DriverOption | null
        createBy?: string
        createTime?: string
        updateBy?: string
        updateTime?: string
        fieldAccess?: OrderFieldAccessMap
        isRecordOwner?: boolean
      }

      type OrderSearchParams = Partial<
        Pick<
          OrderRecord,
          | 'orderStatus'
          | 'paymentMethod'
          | 'originStationId'
          | 'destinationStationId'
          | 'transferStationId'
        > & {
          recordId?: string
          cargoKeyword?: string
          shippingKeyword?: string
          receivingKeyword?: string
          createTimeRange?: string[]
        }
      >

      type OrderFreightPayload = Pick<OrderRecord, 'id' | 'totalFee'>

      type CustomerSelectorSearchParams = Api.Common.CommonSearchParams & {
        keyword?: string
        addressType?: Api.Tms.BasicData.CustomerAddressType
      }
    }

    namespace Waybill {
      type WaybillFieldKey = Api.Tms.Order.OrderFieldKey | 'carrierPhone'
      type WaybillFieldAccessMap = Partial<
        Record<WaybillFieldKey, Api.Tms.BasicData.FieldAccessLevel>
      >
      type DispatchStatus = 'pending' | 'loaded' | 'transporting' | 'completed' | 'cancelled'
      type WaybillStatus =
        | 'pending'
        | 'accepted'
        | 'loading'
        | 'transporting'
        | 'unloading'
        | 'signed'
        | 'completed'
        | 'cancelled'
      type WaybillRecord = Api.Tms.Order.OrderRecord

      interface RelatedWaybillSummary {
        id: string
        waybillNo: string
        status: WaybillStatus | string
        driverName?: string | null
        driverPhone?: string | null
        plateNo?: string | null
        acceptedAt?: string | null
        departedAt?: string | null
        completedAt?: string | null
      }

      interface WaybillRoutePoint {
        name?: string | null
        address?: string | null
        type?: string | null
        capturedAt?: string | null
        speedKmh?: number | null
        source?: string | null
        longitude: number
        latitude: number
      }

      interface WaybillExpenseLocationRecord {
        id: string
        occurredOn: string
        expenseLocation?: string | null
        expenseLongitude: number
        expenseLatitude: number
        expenseCoordinateSource?: string | null
        expenseItem?: {
          id?: string
          itemCode: string
          itemName: string
          businessCategory?: string | null
        } | null
      }

      interface WaybillDriverSummary {
        id: string
        driverName: string
        phone?: string | null
        licenseType?: string | null
      }

      interface WaybillVehicleSummary {
        id: string
        plateNo: string
        vehicleType?: string | null
        brandModel?: string | null
        approvedLoadMass?: number | null
        vehiclePhotoUrl?: string | null
      }

      interface WaybillCarrierSummary {
        id: string
        companyName: string
        contactName?: string | null
        contactPhone?: string | null
      }

      interface WaybillCargoSummary {
        id: string
        cargoCode?: string | null
        cargoName: string
        unit?: string | null
      }

      interface WaybillEventRecord {
        id: string
        waybillId: string
        eventType: string
        eventTime: string
        operatorName?: string | null
        locationText?: string | null
        longitude?: number | null
        latitude?: number | null
        payload: Record<string, unknown>
        remark?: string | null
        createBy?: string | null
        createTime: string
      }

      interface WaybillProofRecord {
        id: string
        waybillId: string
        proofType: string
        attachmentId?: string | null
        fileUrl: string
        fileName?: string | null
        mimeType?: string | null
        fileSize?: number | null
        uploadedAt?: string | null
        uploaderName?: string | null
        remark?: string | null
      }

      interface WaybillDetailRecord {
        id: string
        tenantId: string
        waybillNo: string
        status: WaybillStatus | string
        orderId?: string | null
        carrierId?: string | null
        driverId?: string | null
        vehicleId?: string | null
        cargoId?: string | null
        originCity?: string | null
        destinationCity?: string | null
        shipperName?: string | null
        shipperPhone?: string | null
        shipperAddress?: string | null
        receiverName?: string | null
        receiverPhone?: string | null
        receiverAddress?: string | null
        shipperLongitude?: number | null
        shipperLatitude?: number | null
        receiverLongitude?: number | null
        receiverLatitude?: number | null
        plannedLoadTime?: string | null
        plannedUnloadTime?: string | null
        acceptedAt?: string | null
        loadedAt?: string | null
        departedAt?: string | null
        arrivedAt?: string | null
        unloadedAt?: string | null
        completedAt?: string | null
        cancelledAt?: string | null
        cargoName?: string | null
        cargoType?: string | null
        cargoWeightTon?: number | null
        cargoVolumeM3?: number | null
        cargoQuantity?: number | null
        freightAmount?: number | string | null
        estimatedDurationMin?: number | null
        remainingDistanceKm?: number | null
        routePoints: unknown
        pickupPhotos: string[]
        deliveryPhotos: string[]
        receiptAttachments: string[]
        remark?: string | null
        createBy?: string | null
        createTime: string
        updateBy?: string | null
        updateTime: string
        order?: Api.Tms.Order.OrderRecord | null
        driver?: WaybillDriverSummary | null
        vehicle?: WaybillVehicleSummary | null
        carrier?: WaybillCarrierSummary | null
        cargo?: WaybillCargoSummary | null
        events: WaybillEventRecord[]
        proofs: WaybillProofRecord[]
        cargoOperations: CargoOperationRecord[]
        expenseLocations: WaybillExpenseLocationRecord[]
        execution?: ExecutionRecord | null
        fieldAccess?: WaybillFieldAccessMap
        isRecordOwner?: boolean
      }

      interface DispatchVehicleOption extends Api.Tms.BasicData.VehicleReferenceOption {
        primaryDriverId?: string | null
        primaryDriver?: BasicData.DriverOption | null
        tonnageOrSeat?: string | null
        overallLength?: number | null
      }

      type WaybillSearchParams = Partial<
        Api.Tms.Order.OrderSearchParams & {
          dispatchStatus?: DispatchStatus | string
          dispatchStatuses?: Array<DispatchStatus | string>
          waybillStatus?: string
          dispatchVehicleId?: string | null
          vehicleKeyword?: string
          plannedTimeRange?: string[]
        }
      >

      type DispatchVehicleSearchParams = Api.Common.CommonSearchParams & {
        keyword?: string
      }

      interface WaybillDispatchPayload {
        id?: string
        ids?: string[]
        dispatchVehicleId: string
        dispatchDriverId?: string | null
        dispatchPlateNo: string
        dispatchVehicleType?: string | null
        dispatchVehicleLength?: string | null
        dispatchDriverName?: string | null
        dispatchDriverPhone?: string | null
        plannedDepartureTime: string
        plannedArrivalTime: string
        dispatchRemark?: string | null
      }

      type CargoOperationType = 'loading' | 'unloading'
      type CargoOperationStatus = 'checked_in' | 'completed'
      type CargoOperationCheckinMode = 'manual' | 'automatic' | 'admin'

      interface CargoOperationRecord {
        id: string
        tenantId: string
        waybillId: string
        operationType: CargoOperationType
        operationStatus: CargoOperationStatus
        checkinTime: string
        checkinMode: CargoOperationCheckinMode
        operatorName?: string | null
        longitude: number
        latitude: number
        locationAccuracyM?: number | null
        locationText?: string | null
        geofenceCenterLongitude: number
        geofenceCenterLatitude: number
        geofenceRadiusM: number
        distanceM: number
        insideGeofence: boolean
        outsideReason?: string | null
        weightTon?: number | null
        photoUrls: string[]
        weighbridgeTicketUrls: string[]
        completedAt?: string | null
        remark?: string | null
        createBy?: string | null
        createTime: string
        updateBy?: string | null
        updateTime: string
      }

      interface CargoOperationContext {
        waybillId: string
        operationType: CargoOperationType
        waybillStatus: string
        centerLongitude?: number | null
        centerLatitude?: number | null
        radiusM: number
        allowOutsideCheckIn: boolean
        autoCheckIn: boolean
        geofenceEnabled: boolean
        canManage: boolean
        operation?: CargoOperationRecord | null
      }

      interface CargoOperationCheckinPayload {
        waybillId: string
        operationType: CargoOperationType
        longitude: number
        latitude: number
        accuracyM?: number | null
        locationText?: string | null
        outsideReason?: string | null
        automatic?: boolean
      }

      interface CargoOperationCompletePayload {
        waybillId: string
        operationType: CargoOperationType
        weightTon: number
        photoUrls: string[]
        weighbridgeTicketUrls: string[]
        remark?: string | null
      }

      type ExecutionAction = 'departure' | 'signature' | 'completion'

      interface ExecutionRecord {
        id: string
        tenantId: string
        waybillId: string
        departureTime?: string | null
        departureOdometerKm?: number | null
        departurePhotoUrls: string[]
        departureRemark?: string | null
        departureOperatorName?: string | null
        departureRecordedAt?: string | null
        signedAt?: string | null
        signerName?: string | null
        receiptUrls: string[]
        signatureUrls: string[]
        signatureRemark?: string | null
        signatureOperatorName?: string | null
        signatureRecordedAt?: string | null
        returnTime?: string | null
        returnOdometerKm?: number | null
        returnPhotoUrls: string[]
        completionRemark?: string | null
        completionOperatorName?: string | null
        completionRecordedAt?: string | null
        createTime: string
        updateTime: string
      }

      interface ExecutionContext {
        waybillId: string
        waybillStatus: string
        loadingStatus?: CargoOperationStatus | null
        unloadingStatus?: CargoOperationStatus | null
        arrivalTime?: string | null
        arrivalAddress?: string | null
        arrivalLongitude?: number | null
        arrivalLatitude?: number | null
        canAccept: boolean
        canDepart: boolean
        canArrive: boolean
        canUnload: boolean
        canSign: boolean
        canComplete: boolean
        canCancel: boolean
        needsReturnCompletion: boolean
        record?: ExecutionRecord | null
      }

      interface ExecutionDeparturePayload {
        waybillId: string
        departureTime: string
        odometerKm: number
        photoUrls: string[]
        remark?: string | null
      }

      interface ExecutionSignaturePayload {
        waybillId: string
        signedAt: string
        signerName: string
        receiptUrls: string[]
        signatureUrls: string[]
        remark?: string | null
      }

      interface ExecutionCompletionPayload {
        waybillId: string
        returnTime: string
        returnOdometerKm: number
        photoUrls: string[]
        remark?: string | null
      }

      interface DispatchRecommendationDriver {
        id: string
        driverName: string
        phone?: string | null
        licenseType?: string | null
        licenseExpireDate?: string | null
      }

      interface DispatchRecommendationVehicle {
        id: string
        carrierId?: string | null
        plateNo: string
        companyName?: string | null
        vehicleType?: string | null
        tonnageOrSeat?: string | null
        overallLength?: number | null
        approvedLoadMass?: number | null
        primaryDriver: DispatchRecommendationDriver
      }

      interface DispatchRecommendation {
        rank: number
        score: number
        confidence: number
        vehicle: DispatchRecommendationVehicle
        reasons: string[]
        warnings: string[]
        metrics: {
          capacityUtilization?: number | null
          routeTrips: number
          historyTrips: number
          onTimeRate?: number | null
        }
      }

      interface DispatchRecommendationResponse {
        runId: string
        ruleVersion: string
        generatedAt: string
        order: {
          id: string
          orderNo: string
          originStation: string
          destinationStation: string
        }
        summary: string
        recommendations: DispatchRecommendation[]
        evaluatedVehicles: number
        eligibleVehicles: number
        rejectedVehicles: number
        rejectedByReason: Record<string, number>
      }
    }

    namespace Delivery {
      type DeliveryStatus = 'pending_sign' | 'signed' | 'completed'
      type DeliveryRecord = Api.Tms.Order.OrderRecord
      type DeliverySearchParams = Partial<
        Api.Tms.Order.OrderSearchParams & {
          deliveryStatus?: string
          orderStatuses?: string[]
          signedTimeRange?: string[]
        }
      >

      type DeliveryReceiptArchivePayload = Pick<
        DeliveryRecord,
        'id' | 'signedCodAmount' | 'receiptImageUrls' | 'signedAt'
      >

      type ReceiptOcrField =
        | 'waybillNo'
        | 'signerName'
        | 'signedAt'
        | 'deliveryResult'
        | 'signedQuantity'
        | 'damagedQuantity'
        | 'shortageQuantity'
        | 'exceptionNote'
      type ReceiptDeliveryResult =
        'normal' | 'damaged' | 'shortage' | 'refused' | 'partial' | 'unclear'
      type ReceiptRiskLevel = 'none' | 'medium' | 'high' | 'critical'

      interface ReceiptOcrDraft {
        waybillNo: string | null
        signerName: string | null
        signedAt: string | null
        deliveryResult: ReceiptDeliveryResult
        signedQuantity: number | null
        damagedQuantity: number | null
        shortageQuantity: number | null
        exceptionNote: string | null
      }

      interface ReceiptOcrSignal {
        type: string
        severity: Exclude<ReceiptRiskLevel, 'none'>
        title: string
        detail: string
      }

      interface ReceiptOcrAssessment {
        riskLevel: ReceiptRiskLevel
        matched: boolean
        signals: ReceiptOcrSignal[]
        recommendedAction: 'normal_review' | 'manual_review' | 'block_completion'
      }

      interface ReceiptOcrAnalyzeRequest {
        action: 'analyze'
        imageUrls: string[]
        orderId: string
        orderNo: string
        receiverName?: string | null
        plannedArrivalTime?: string | null
        cargoQuantityTotal?: number | null
      }

      interface ReceiptOcrAnalyzeResponse {
        artifactId: string
        runId: string
        generatedAt: string
        rawText: string
        summary: string
        confidence: number
        fieldConfidence: Partial<Record<ReceiptOcrField, number>>
        missingFields: string[]
        warnings: string[]
        receipt: ReceiptOcrDraft
        assessment: ReceiptOcrAssessment
        reviewConfidenceThreshold: number
        order: {
          id: string
          orderNo: string
          receiverName?: string | null
          plannedArrivalTime?: string | null
          cargoQuantityTotal?: number | null
        }
      }

      interface ReceiptOcrReviewRequest {
        action: 'review'
        artifactId: string
        entityId: string
        outcome: 'applied'
        finalPayload: Record<string, unknown>
        reviewNote?: string
      }

      interface ReceiptOcrReviewResponse {
        artifactId: string
        status: 'applied'
        acceptedFields: string[]
        correctedFields: string[]
      }

      type ReceiptExceptionStatus = 'pending' | 'in_progress' | 'resolved' | 'closed' | 'cancelled'
      type ReceiptExceptionSeverity = 'low' | 'medium' | 'high' | 'critical'

      interface ReceiptExceptionWorkOrder {
        id: string
        tenantId: string
        workOrderNo: string
        orderId: string
        aiArtifactReviewId: string
        orderNoSnapshot: string
        severity: ReceiptExceptionSeverity
        status: ReceiptExceptionStatus
        exceptionTypes: string[]
        summary: string
        evidenceUrls: string[]
        assigneeId?: string | null
        dueAt: string
        startedAt?: string | null
        resolutionNote?: string | null
        createBy?: string | null
        createTime: string
        updateTime: string
      }
    }
  }

  /** Shared finance domain contracts. Transport-backed records remain source-specific DTOs. */
  namespace Tms {
    namespace InTransit {
      interface RoutePoint {
        type?: string
        name?: string | null
        address?: string | null
        capturedAt?: string | null
        timestamp?: string | null
        recordedAt?: string | null
        speedKmh?: number | string | null
        source?: string | null
        longitude?: number | string | null
        latitude?: number | string | null
        lng?: number | string | null
        lat?: number | string | null
      }

      interface MonitorRecord {
        id?: string
        tenantId?: string
        waybillNo: string
        status?: string | null
        driverId?: string | null
        vehicleId?: string | null
        shipperAddressId?: string | null
        receiverAddressId?: string | null
        originCity?: string | null
        destinationCity?: string | null
        shipperName?: string | null
        shipperPhone?: string | null
        shipperAddress?: string | null
        shipperLongitude?: number | string | null
        shipperLatitude?: number | string | null
        receiverName?: string | null
        receiverPhone?: string | null
        receiverAddress?: string | null
        receiverLongitude?: number | string | null
        receiverLatitude?: number | string | null
        plannedLoadTime?: string | null
        plannedUnloadTime?: string | null
        acceptedAt?: string | null
        loadedAt?: string | null
        departedAt?: string | null
        unloadedAt?: string | null
        completedAt?: string | null
        currentLongitude?: number | string | null
        currentLatitude?: number | string | null
        speedKmh?: number | string | null
        cargoName?: string | null
        cargoWeightTon?: number | string | null
        cargoVolumeM3?: number | string | null
        cargoQuantity?: number | string | null
        freightAmount?: number | string | null
        routePoints?: RoutePoint[] | null
        remark?: string | null
        cancelledAt?: string | null
        createBy?: string
        createTime?: string
        updateBy?: string
        updateTime?: string
        order?: Api.Tms.Order.OrderRecord | null
        vehicle?: Api.Tms.Waybill.DispatchVehicleOption | null
        driver?: Api.Tms.BasicData.DriverOption | null
        fieldAccess?: Api.Tms.Waybill.WaybillFieldAccessMap
        isRecordOwner?: boolean
      }

      type TransportAnomalyType =
        | 'arrival_overdue'
        | 'departure_overdue'
        | 'data_stale'
        | 'missing_assignment'
        | 'missing_schedule'
        | 'status_mismatch'

      type TransportRiskLevel = 'critical' | 'high' | 'medium' | 'low'

      interface TransportAnomalySignal {
        type: TransportAnomalyType
        severity: Exclude<TransportRiskLevel, 'low'>
        title: string
        detail: string
        evidence: string[]
      }

      interface TransportAnomalyAssessment {
        orderId: string
        orderNo: string
        route: string
        orderStatus: string
        waybillStatus: string
        riskLevel: TransportRiskLevel
        riskScore: number
        confidence: number
        summary: string
        signals: TransportAnomalySignal[]
        recommendedActions: string[]
        limitations: string[]
        metrics: {
          overdueArrivalHours: number
          overdueDepartureHours: number
          staleHours: number
          hasVehicle: boolean
          hasDriver: boolean
          hasSchedule: boolean
        }
      }

      interface TransportAnomalyAdvisorResponse {
        runId: string
        ruleVersion: string
        generatedAt: string
        assessment: TransportAnomalyAssessment
      }

      type MonitorSearchParams = Api.Common.CommonSearchParams & {
        keyword?: string
        statuses?: string[]
      }
    }

    namespace Station {
      type StationType = 'shipping' | 'transfer' | 'arrival'

      interface StationRoleRecord {
        id?: string
        stationId?: string
        roleType: StationType | string
        tenantId?: string
        createBy?: string
        createTime?: string
        updateBy?: string
        updateTime?: string
      }

      interface StationRecord {
        id?: string
        tenantId?: string
        stationCode?: string
        stationName: string
        /** 兼容用主类型；完整业务能力读取 stationRoles。 */
        stationType: StationType | string
        stationRoles?: StationRoleRecord[]
        regionCode?: string | null
        managerName?: string | null
        contactPhone?: string | null
        enabled?: boolean
        sort?: number
        remark?: string | null
        createBy?: string
        createTime?: string
        updateBy?: string
        updateTime?: string
      }

      type StationSavePayload = Omit<
        StationRecord,
        | 'tenantId'
        | 'stationType'
        | 'stationRoles'
        | 'createBy'
        | 'createTime'
        | 'updateBy'
        | 'updateTime'
      > & {
        stationTypes: Array<StationType | string>
      }

      type StationSearchParams = Partial<
        Pick<StationRecord, 'stationType' | 'enabled'> &
          Api.Common.CommonSearchParams & {
            keyword?: string
            createTimeRange?: string[]
          }
      >

      type StationOptionSearchParams = Partial<
        Pick<StationRecord, 'stationType'> & {
          keyword?: string
        }
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
      parentId?: string | null
      name: string
      code: string
      status: string
      label?: string
      value: string
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
      children?: DictListItem[]
    }

    type DictTypeNodeType = 'directory' | 'dictionary'

    interface DictTypeItem {
      id?: string
      tenantId?: string
      parentId?: string | null
      nodeType: DictTypeNodeType
      name: string
      code: string
      status: string
      sort?: number
      remark?: string
      createBy?: string
      createTime?: string
      updateBy?: string
      updateTime?: string
      children?: DictTypeItem[]
    }
    namespace Resources {
      interface Args {
        btn?: Button
        handleGetResourceList?: () => void | Promise<void>
        [key: string]: unknown
      }

      /** 用户搜索参数 */
      type ResourceSearchParams = Partial<
        Pick<ResourceListItem, 'originName' | 'suffix'> & Api.Common.CommonSearchParams
      >

      interface Button {
        name: string
        label: string
        icon: string
        click?: (btn: Resources.Button, selected: ResourceListItem[]) => void
        upload?: (files: File | File[], args: Args) => void | Promise<void>
        uploadConfig?: Record<string, unknown>
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
        rows?: Array<Record<string, unknown>>
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
        runId?: string
        model?: string
        promptVersion?: string
        providerDurationMs?: number
        durationMs?: number
      }
    }
  }
}
