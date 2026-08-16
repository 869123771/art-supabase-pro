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
  namespace VehicleMgtSys {
    namespace ArchiveManage {
      type AuditStatus = 'pending' | 'approved' | 'rejected'

      interface VehicleAttachment {
        name: string
        url: string
        fileType?: string
        fileSize?: string
      }

      type VehicleArchiveAttachment = VehicleAttachment

      interface VehicleArchive {
        id?: string
        tenantId?: string
        plateNo: string
        carrierId?: string | null
        carrier?: Api.Tms.BasicData.CarrierOption | null
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
        primaryDriverId?: string | null
        primaryDriver?: Api.Tms.BasicData.DriverOption | null
        secondaryDriverId?: string | null
        secondaryDriver?: Api.Tms.BasicData.DriverOption | null
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
        attachments?: VehicleAttachment[]

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
          | 'carrierId'
          | 'plateNo'
          | 'companyName'
          | 'vehicleType'
          | 'manufacturer'
          | 'vin'
          | 'operationStatus'
          | 'auditStatus'
        > &
          Api.Common.CommonSearchParams & {
            createTimeRange?: string[]
            auditStatuses?: AuditStatus[]
            recordId?: string
          }
      >
    }

    namespace VehicleManage {
      type VehicleAttachment = Api.VehicleMgtSys.ArchiveManage.VehicleAttachment

      interface VehicleOption {
        id?: string
        carrierId?: string | null
        plateNo: string
        companyName?: string
        vin?: string
        selfNo?: string
        vehicleType?: string
      }

      interface InsuranceCompanyOption {
        id?: string
        companyName: string
        contactPerson?: string
        contactPhone?: string
      }

      interface VehicleInsurance {
        id?: string
        tenantId?: string
        vehicleId?: string | null
        plateNo: string
        companyName?: string
        commercialPolicyNo?: string
        commercialCompanyId?: string | null
        commercialCompanyName?: string
        commercialInsureDate?: string
        commercialPremium?: number | null
        commercialExpireDate?: string
        compulsoryPolicyNo?: string
        compulsoryCompanyId?: string | null
        compulsoryCompanyName?: string
        compulsoryInsureDate?: string
        compulsoryPremium?: number | null
        compulsoryExpireDate?: string
        remark?: string
        attachments?: VehicleAttachment[]
        createBy?: string
        createTime?: string
        updateBy?: string
        updateTime?: string
      }

      type VehicleInsuranceSearchParams = Partial<
        Pick<
          VehicleInsurance,
          'companyName' | 'plateNo' | 'commercialPolicyNo' | 'compulsoryPolicyNo'
        > &
          Api.Common.CommonSearchParams & {
            commercialExpireDateRange?: string[]
            compulsoryExpireDateRange?: string[]
            createTimeRange?: string[]
          }
      >

      interface VehicleInspection {
        id?: string
        tenantId?: string
        vehicleId?: string | null
        plateNo: string
        companyName?: string
        inspectionNo?: string
        inspectionDate?: string
        inspectionAmount?: number | null
        vehicleOffice?: string
        expireDate?: string
        compulsoryPolicyNo?: string
        compulsoryCompanyId?: string | null
        compulsoryCompanyName?: string
        compulsoryInsureDate?: string
        compulsoryPremium?: number | null
        compulsoryExpireDate?: string
        remark?: string
        attachments?: VehicleAttachment[]
        createBy?: string
        createTime?: string
        updateBy?: string
        updateTime?: string
      }

      type VehicleInspectionSearchParams = Partial<
        Pick<VehicleInspection, 'companyName' | 'plateNo' | 'inspectionNo'> &
          Api.Common.CommonSearchParams & {
            expireDateRange?: string[]
            createTimeRange?: string[]
          }
      >

      type VehicleRoutineInspectionType = 'daily' | 'monthly'
      type VehicleRoutineInspectionResult = 'qualified' | 'unqualified'

      interface VehicleRoutineInspectionRecord {
        id?: string
        tenantId?: string
        vehicleId?: string | null
        plateNo: string
        companyName?: string
        routineInspectionNo?: string
        inspectionType: VehicleRoutineInspectionType | string
        inspectionTime: string
        inspector?: string
        driverName?: string
        checkCondition?: string
        checkResult: VehicleRoutineInspectionResult | string
        handlingMethod?: string
        remark?: string
        attachments?: VehicleAttachment[]
        createBy?: string
        createTime?: string
        updateBy?: string
        updateTime?: string
      }

      type VehicleRoutineInspectionSearchParams = Partial<
        Pick<
          VehicleRoutineInspectionRecord,
          'companyName' | 'plateNo' | 'inspectionType' | 'checkResult'
        > &
          Api.Common.CommonSearchParams & {
            inspectionTimeRange?: string[]
            createTimeRange?: string[]
          }
      >

      interface VehicleMileageRecord {
        id?: string
        tenantId?: string
        vehicleId?: string | null
        plateNo: string
        companyName?: string
        runningMileage?: number | null
        startTime: string
        startMileage?: number | null
        endTime?: string | null
        endMileage?: number | null
        createBy?: string
        createTime?: string
        updateBy?: string
        updateTime?: string
      }

      type VehicleMileageSearchParams = Partial<
        Pick<VehicleMileageRecord, 'companyName' | 'plateNo'> &
          Api.Common.CommonSearchParams & {
            drivingTimeRange?: string[]
          }
      >

      interface VehicleViolationRecord {
        id?: string
        tenantId?: string
        vehicleId?: string | null
        plateNo: string
        companyName?: string
        driverName?: string
        violationBehavior: string
        violationTime: string
        violationLocation?: string
        penaltyPoints?: number | null
        fineAmount?: number | null
        processed: boolean
        remark?: string
        createBy?: string
        createTime?: string
        updateBy?: string
        updateTime?: string
      }

      type VehicleViolationSearchParams = Partial<
        Pick<
          VehicleViolationRecord,
          'companyName' | 'plateNo' | 'driverName' | 'violationBehavior' | 'processed'
        > &
          Api.Common.CommonSearchParams & {
            violationTimeRange?: string[]
          }
      >

      type VehicleAccidentResponsibility = 'primary' | 'secondary' | 'equal' | 'none' | 'full'
      type VehicleAccidentDataSource = 'self' | 'external'

      interface VehicleAccidentRecord {
        id?: string
        tenantId?: string
        vehicleId?: string | null
        plateNo: string
        companyName?: string
        driverName?: string
        driverPhone?: string
        accidentTime: string
        accidentLocation?: string
        accidentLongitude?: number | null
        accidentLatitude?: number | null
        accidentSummary: string
        damageLevel?: string
        responsibilityType?: VehicleAccidentResponsibility | string
        responsibilityPercent?: number | null
        companyBearAmount?: number | null
        economicLoss?: number | null
        reported: boolean
        insuranceReported: boolean
        processed: boolean
        dataSource: VehicleAccidentDataSource | string
        remark?: string
        attachments?: VehicleAttachment[]
        createBy?: string
        createTime?: string
        updateBy?: string
        updateTime?: string
      }

      type VehicleAccidentSearchParams = Partial<
        Pick<
          VehicleAccidentRecord,
          'companyName' | 'plateNo' | 'driverName' | 'processed' | 'dataSource'
        > &
          Api.Common.CommonSearchParams & {
            accidentTimeRange?: string[]
            createTimeRange?: string[]
          }
      >

      type VehicleMaintenanceType = 'repair' | 'maintenance'

      interface VehicleMaintenanceItem {
        itemName: string
        totalAmount?: number | null
        laborAmount?: number | null
        partName?: string
        partPrice?: number | null
        quantity?: number | null
      }

      interface VehicleMaintenanceRecord {
        id?: string
        tenantId?: string
        vehicleId?: string | null
        plateNo: string
        companyName?: string
        maintenanceNo: string
        maintenanceType: VehicleMaintenanceType | string
        initiator?: string
        startTime: string
        endTime?: string | null
        costAmount?: number | null
        workshop?: string
        externalRepair: boolean
        remark?: string
        items?: VehicleMaintenanceItem[]
        attachments?: VehicleAttachment[]
        createBy?: string
        createTime?: string
        updateBy?: string
        updateTime?: string
      }

      type VehicleMaintenanceSearchParams = Partial<
        Pick<
          VehicleMaintenanceRecord,
          'companyName' | 'plateNo' | 'maintenanceNo' | 'maintenanceType'
        > &
          Api.Common.CommonSearchParams & {
            createTimeRange?: string[]
          }
      >

      type VehiclePartType = 'original' | 'replacement'
      type VehiclePartUsageStatus = 'normal' | 'reused' | 'scrapped'
      type VehiclePartEnableMode = 'vehicle' | 'date'
      type VehiclePartWarrantyMode = 'vehicle' | 'self'

      interface VehiclePartUsage {
        id?: string
        tenantId?: string
        vehicleId?: string | null
        plateNo: string
        companyName?: string
        partId?: string | null
        partType: VehiclePartType
        partName: string
        partCode: string
        categoryId?: string | null
        categoryName?: string
        brand?: string
        model?: string
        unit?: string
        qualityCategory?: string
        manufacturer?: string
        supplierId?: string | null
        supplierName?: string
        supplierContact?: string
        isConsumable: boolean
        rfidEnabled: boolean
        rfidTag?: string
        enableMode: VehiclePartEnableMode
        enableDate?: string | null
        warrantyMode: VehiclePartWarrantyMode
        warrantyMileage?: number | null
        warrantyDuration?: number | null
        serviceMileageEnabled: boolean
        serviceMileage?: number | null
        serviceYearsEnabled: boolean
        serviceYears?: number | null
        usedMileage?: number | null
        status: VehiclePartUsageStatus
        scrapReason?: string
        remark?: string
        createBy?: string
        createTime?: string
        updateBy?: string
        updateTime?: string
      }

      type VehiclePartUsageSearchParams = Partial<
        Pick<
          VehiclePartUsage,
          'companyName' | 'plateNo' | 'partType' | 'partName' | 'categoryId' | 'rfidTag' | 'status'
        > &
          Api.Common.CommonSearchParams & {
            createTimeRange?: string[]
          }
      >

      type VehicleHealthSignalType =
        | 'insurance_expired'
        | 'insurance_expiring'
        | 'inspection_expired'
        | 'inspection_expiring'
        | 'maintenance_overdue'
        | 'maintenance_history_missing'
        | 'repair_frequency_high'
        | 'unresolved_accident'
        | 'routine_inspection_failed'
        | 'part_service_due'
        | 'mileage_data_stale'

      type VehicleHealthSeverity = 'critical' | 'high' | 'medium'
      type VehicleHealthRiskLevel = VehicleHealthSeverity | 'low'

      interface VehicleHealthSignal {
        type: VehicleHealthSignalType
        severity: VehicleHealthSeverity
        title: string
        detail: string
        evidence: string[]
      }

      interface VehicleHealthAssessment {
        vehicleId: string
        plateNo: string
        vehicleType: string
        operationStatus: string
        riskLevel: VehicleHealthRiskLevel
        riskScore: number
        healthScore: number
        confidence: number
        summary: string
        signals: VehicleHealthSignal[]
        recommendedActions: string[]
        limitations: string[]
        metrics: {
          currentMileage: number | null
          insuranceDaysRemaining: number | null
          inspectionDaysRemaining: number | null
          daysSinceMaintenance: number | null
          repairCount90Days: number
          unresolvedAccidentCount: number
          failedRoutineInspectionCount: number
          duePartCount: number
        }
      }

      interface VehicleHealthAdvisorResponse {
        runId: string
        ruleVersion: string
        generatedAt: string
        assessment: VehicleHealthAssessment
      }
    }

    namespace ReminderManage {
      type ReminderKind = 'insurance' | 'inspection' | 'maintenance' | 'part' | 'vehicle'
      type WorkOrderStatus = 'pending' | 'in_progress' | 'resolved' | 'closed' | 'cancelled'
      type WorkOrderPriority = 'low' | 'normal' | 'high' | 'urgent'

      type InsuranceType = 'commercial' | 'compulsory'

      interface VehicleReminderRow {
        id: string
        sourceId?: string
        sourceVersion?: string
        vehicleId?: string | null
        companyName?: string
        plateNo: string
        insuranceType?: InsuranceType
        insuranceTypeName?: string
        expireDate?: string | null
        remainingDays?: number | null
        expired: boolean
        currentMaintenanceDate?: string | null
        currentMileage?: number | null
        nextMaintenanceMileage?: number | null
        nextMaintenanceDate?: string | null
        partType?: VehicleManage.VehiclePartType
        partName?: string
        categoryName?: string
        brand?: string
        model?: string
        rfidTag?: string
        usedMileage?: number | null
        serviceMileage?: number | null
        startUseDate?: string | null
        serviceYears?: number | null
        workOrder?: VehicleReminderWorkOrder | null
        workOrderStatus?: WorkOrderStatus | null
      }

      interface VehicleReminderRiskOverview {
        total: number
        overdue: number
        dueWithin7Days: number
        dueWithin30Days: number
        stable: number
      }

      type VehicleReminderRiskBand = 'all' | 'overdue' | 'due_7' | 'due_30'

      interface VehicleReminderWorkOrder {
        id: string
        tenantId: string
        sourceType: ReminderKind
        sourceKey: string
        sourceVersion: string
        sourceId?: string | null
        vehicleId: string
        plateNoSnapshot: string
        companyNameSnapshot?: string | null
        title: string
        status: WorkOrderStatus
        priority: WorkOrderPriority
        dueDate?: string | null
        remainingDaysSnapshot?: number | null
        assigneeName?: string | null
        resolution?: string | null
        evidence?: unknown[]
        startedAt?: string | null
        resolvedAt?: string | null
        closedAt?: string | null
        createBy?: string | null
        createTime: string
        updateBy?: string | null
        updateTime: string
      }

      interface VehicleReminderWorkOrderCreatePayload {
        sourceType: ReminderKind
        sourceKey: string
        sourceVersion: string
        sourceId?: string | null
        vehicleId: string
        plateNo: string
        companyName?: string | null
        title: string
        dueDate?: string | null
        remainingDays?: number | null
      }

      interface VehicleReminderWorkOrderTransitionPayload {
        workOrderId: string
        nextStatus: WorkOrderStatus
        resolution?: string | null
      }

      type VehicleReminderSearchParams = Partial<
        Pick<VehicleReminderRow, 'companyName' | 'plateNo' | 'expired'> &
          Api.Common.CommonSearchParams & {
            reminderDays?: number | null
            riskBand?: VehicleReminderRiskBand
          } & Api.Common.PaginationParams
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
        category?: Pick<PartsCategory, 'id' | 'categoryName'> | null
        brand?: string
        model?: string
        unit?: string
        supplierId?: string | null
        supplier?: Pick<Supplier, 'id' | 'supplierName' | 'contactPerson' | 'contactPhone'> | null
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

  /** TMS 运输管理系统 */
  namespace Hr {
    type EmploymentStatus = 'probation' | 'active' | 'leave' | 'terminated'
    type EmploymentType = 'full_time' | 'part_time' | 'intern' | 'contractor'

    interface EmployeeAccount {
      id: string
      userEmail: string
      status: string
    }

    interface Employee {
      id?: string
      tenantId?: string
      tenant?: Pick<SystemManage.TenantListItem, 'id' | 'tenantCode' | 'tenantName'> | null
      organizationId?: string | null
      organization?: Pick<
        SystemManage.OrganizationListItem,
        'id' | 'organizationCode' | 'organizationName'
      > | null
      employeeNo: string
      employeeName: string
      avatarUrl?: string | null
      jobTitle?: string | null
      employmentStatus: EmploymentStatus
      employmentType: EmploymentType
      gender?: string | null
      birthDate?: string | null
      phone?: string | null
      email?: string | null
      idCardNo?: string | null
      ethnicity?: string | null
      educationLevel?: string | null
      schoolName?: string | null
      majorName?: string | null
      maritalStatus?: string | null
      politicalStatus?: string | null
      nativePlace?: string | null
      homeAddress?: string | null
      hireDate?: string | null
      probationEndDate?: string | null
      leaveDate?: string | null
      contractStartDate?: string | null
      contractEndDate?: string | null
      emergencyContactName?: string | null
      emergencyContactRelation?: string | null
      emergencyContactPhone?: string | null
      remark?: string | null
      account?: EmployeeAccount | null
      createBy?: string
      createTime?: string
      updateBy?: string
      updateTime?: string
    }

    type EmployeeSearchParams = Partial<
      Pick<Employee, 'tenantId' | 'organizationId' | 'employmentStatus' | 'employmentType'> &
        Api.Common.CommonSearchParams & {
          keyword?: string
          hireDateRange?: string[]
          recordId?: string
          organizationIds?: string[]
          organizationUnassigned?: boolean
        }
    >

    interface EmployeeContract {
      id?: string
      tenantId?: string
      employeeId?: string
      contractNo: string
      contractType: string
      contractStatus: string
      signDate?: string | null
      startDate: string
      endDate?: string | null
      probationEndDate?: string | null
      workLocation?: string | null
      monthlySalary?: number | null
      remark?: string | null
    }

    interface EmployeeEducation {
      id?: string
      tenantId?: string
      employeeId?: string
      schoolName: string
      majorName?: string | null
      educationLevel: string
      degree?: string | null
      startDate?: string | null
      endDate?: string | null
      fullTime: boolean
      certificateNo?: string | null
      remark?: string | null
    }

    interface EmployeeWorkExperience {
      id?: string
      tenantId?: string
      employeeId?: string
      companyName: string
      departmentName?: string | null
      jobTitle: string
      startDate: string
      endDate?: string | null
      responsibilities?: string | null
      leavingReason?: string | null
      referenceName?: string | null
      referencePhone?: string | null
    }

    interface EmployeeTraining {
      id?: string
      tenantId?: string
      employeeId?: string
      trainingName: string
      trainingType: string
      providerName?: string | null
      startDate: string
      endDate?: string | null
      trainingResult?: string | null
      certificateName?: string | null
      certificateNo?: string | null
      cost?: number | null
      remark?: string | null
    }

    interface EmployeeReward {
      id?: string
      tenantId?: string
      employeeId?: string
      recordType: string
      recordLevel?: string | null
      title: string
      recordDate: string
      issuingOrganization?: string | null
      amount?: number | null
      description?: string | null
    }

    interface EmployeeProfile extends Employee {
      contracts: EmployeeContract[]
      educations: EmployeeEducation[]
      workExperiences: EmployeeWorkExperience[]
      trainings: EmployeeTraining[]
      rewards: EmployeeReward[]
    }

    interface EmployeeProfilePayload {
      employee: Employee
      contracts: EmployeeContract[]
      educations: EmployeeEducation[]
      workExperiences: EmployeeWorkExperience[]
      trainings: EmployeeTraining[]
      rewards: EmployeeReward[]
    }

    interface EmployeeSelectorItem {
      id: string
      tenantId: string
      organizationId?: string | null
      employeeNo: string
      employeeName: string
      avatarUrl?: string | null
      jobTitle?: string | null
      employmentStatus: EmploymentStatus
      gender?: string | null
      phone?: string | null
      email?: string | null
      organization?: Pick<
        SystemManage.OrganizationListItem,
        'id' | 'organizationCode' | 'organizationName'
      > | null
    }
  }

  namespace Tms {
    namespace BasicData {
      type CustomerAddressType = 'shipping' | 'receiving'

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
        cargoItems?: CustomerPriceCargoItem[]
        cargoQuantityTotal?: number | null
        cargoVolumeTotal?: number | null
        cargoWeightTotal?: number | null
        vehicleType?: string | null
        vehicleLength?: string | null
        vehicleCount?: number | null
        billingMethod: string
        transportFee?: number | null
        insuranceFee?: number | null
        packageFee?: number | null
        loadingFee?: number | null
        transferFee?: number | null
        fuelFee?: number | null
        serviceFee?: number | null
        otherFee?: number | null
        totalFee?: number | null
        cashAmount?: number | null
        prepaidAmount?: number | null
        collectAmount?: number | null
        periodicAmount?: number | null
        paymentTotal?: number | null
        remark?: string | null
        createBy?: string
        createTime?: string
        updateBy?: string
        updateTime?: string
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
        splitTransportFee?: number | null
        loadingFee?: number | null
        packageFee?: number | null
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
        vehicle?: Api.VehicleMgtSys.VehicleManage.VehicleOption | null
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
        transportCost?: number | null
        splitTransportFee?: number | null
        loadingFee?: number | null
        packageFee?: number | null
        otherFee?: number | null
        totalFee?: number | null
        cashAmount?: number | null
        prepaidAmount?: number | null
        collectAmount?: number | null
        periodicAmount?: number | null
        paymentTotal?: number | null
        remark?: string | null
        createBy?: string
        createTime?: string
        updateBy?: string
        updateTime?: string
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
        carrierId: string
        driverName: string
        phone: string
        gender: string
        idCardNo: string
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
        enabled?: boolean
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
        transportUnitPrice: number
        freight: number
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
        contactName?: string | null
        waybillNo?: string | null
        customerSignatory?: string | null
        billingMethod: string
        contractAmount?: number | null
        transportUnitPrice?: number | null
        roadConsumptionRate?: number | null
        lossDeductionPrice?: number | null
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

      interface ContractDetailSelectorItem extends ContractTransportDetail {
        key: string
        contractId: string
        contractNo: string
        contractName: string
        effectiveDate?: string | null
        expiryDate?: string | null
      }

      interface ContractDetailSelectorSearchParams extends Api.Common.CommonSearchParams {
        keyword?: string
      }
    }

    namespace Order {
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
        unitPrice?: number | null
        freight?: number | null
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
        transportFee?: number | null
        deliveryFee?: number | null
        unloadingFee?: number | null
        collectPaymentFee?: number | null
        transferFee?: number | null
        declaredValue?: number | null
        insuranceFee?: number | null
        packageFee?: number | null
        otherFee?: number | null
        totalFee?: number | null
        paymentMethod: string
        cashAmount?: number | null
        collectAmount?: number | null
        monthlyAmount?: number | null
        codAmount?: number | null
        handlingFee?: number | null
        paymentTotal?: number | null
        transportMode?: string | null
        orderRemark?: string | null
        imageUrls?: string[]
        signedCodAmount?: number | null
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
        expenseItem?: Pick<
          Api.Finance.ExpenseItem,
          'id' | 'itemCode' | 'itemName' | 'businessCategory'
        > | null
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
        freightAmount?: number | null
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
      }

      interface DispatchVehicleOption extends Api.VehicleMgtSys.VehicleManage.VehicleOption {
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
  namespace Finance {
    type ExpenseOcrStatus = 'not_started' | 'processing' | 'succeeded' | 'failed'
    type ReimbursementApprovalStatus =
      'draft' | 'pending_review' | 'approved' | 'rejected' | 'paid' | 'cancelled'

    interface ExpenseReimbursementItem {
      id: string
      tenantId: string
      reimbursementId: string
      costId: string
      waybillId: string
      costNoSnapshot: string
      waybillNoSnapshot: string
      expenseItemNameSnapshot: string
      amountSnapshot: number
      occurredOnSnapshot: string
      createTime: string
    }

    interface ExpenseReimbursementRecord {
      id: string
      tenantId: string
      reimbursementNo: string
      applicantUserId?: string | null
      applicantNameSnapshot: string
      payeeName: string
      payeeBank?: string | null
      payeeAccount?: string | null
      plannedPaymentDate: string
      paymentMethod: CashPaymentMethod
      totalAmount: number
      basisUrls: string[]
      status: ReimbursementApprovalStatus
      submittedAt?: string | null
      submittedBy?: string | null
      reviewedAt?: string | null
      reviewedBy?: string | null
      reviewRemark?: string | null
      paidAt?: string | null
      paidBy?: string | null
      paymentReference?: string | null
      paymentVoucherUrls: string[]
      remark?: string | null
      itemCount: number
      waybillCount: number
      waybillNos?: string | null
      paymentId?: string | null
      paymentNo?: string | null
      createBy?: string | null
      createTime: string
      updateBy?: string | null
      updateTime: string
      items?: ExpenseReimbursementItem[]
    }

    type ExpenseReimbursementSearchParams = Api.Common.CommonSearchParams & {
      keyword?: string
      status?: string
      paymentMethod?: string
      plannedPaymentDateRange?: string[]
    }

    interface CreateExpenseReimbursementPayload {
      reimbursementNo?: string | null
      costIds: string[]
      payeeName: string
      payeeBank?: string | null
      payeeAccount?: string | null
      plannedPaymentDate: string
      paymentMethod: CashPaymentMethod
      basisUrls?: string[]
      remark?: string | null
    }

    interface ExecuteExpenseReimbursementPayload {
      paymentNo?: string | null
      reimbursementId: string
      paymentDate: string
      bankReference?: string | null
      voucherUrls?: string[]
      remark?: string | null
    }

    interface WaybillCostOverview {
      totalCount: number
      pendingReviewCount: number
      approvedUnconvertedCount: number
      pendingPaymentAmount: number
      paidAmount: number
    }

    type WaybillExpenseOcrField =
      | 'amount'
      | 'occurredOn'
      | 'quantity'
      | 'unitPrice'
      | 'providerName'
      | 'payeeName'
      | 'paymentChannel'
      | 'invoiceNo'
      | 'meterNo'
      | 'expenseLocation'
      | 'remark'

    interface WaybillExpenseOcrDraft {
      amount: number | null
      occurredOn: string | null
      quantity: number | null
      unitPrice: number | null
      providerName: string | null
      payeeName: string | null
      paymentChannel: string | null
      invoiceNo: string | null
      meterNo: string | null
      expenseLocation: string | null
      remark: string | null
    }

    interface WaybillExpenseOcrAnalyzeResponse {
      artifactId: string
      runId: string
      generatedAt: string
      rawText: string
      summary: string
      confidence: number
      fieldConfidence: Partial<Record<WaybillExpenseOcrField, number>>
      missingFields: string[]
      warnings: string[]
      expense: WaybillExpenseOcrDraft
      reviewConfidenceThreshold: number
    }

    interface WaybillExpenseOcrRunRecord {
      id: string
      feature: string
      model: string
      status: 'pending' | 'running' | 'succeeded' | 'failed'
      latencyMs?: number | null
      errorCode?: string | null
      errorMessage?: string | null
      metadata?: Record<string, unknown>
      startedAt: string
      finishedAt?: string | null
      createBy?: string | null
    }

    type WaybillExpenseOcrRunSearchParams = Api.Common.CommonSearchParams & {
      status?: string
      keyword?: string
      createTimeRange?: string[]
    }

    type WaybillCostType =
      | 'carrier_freight'
      | 'toll'
      | 'parking'
      | 'fuel'
      | 'loading'
      | 'waiting'
      | 'driver_expense'
      | 'cargo_damage'
      | 'other'
      | 'in_transit_energy'
      | 'in_transit_charging'
      | 'in_transit_gas'
      | 'in_transit_other'

    type CostAuditStatus = 'draft' | 'pending_review' | 'approved' | 'rejected' | 'voided'
    type CostSettlementStatus = 'unsettled' | 'pending_payment' | 'paid'

    interface ExpenseItem {
      id?: string
      tenantId?: string
      tenant?: Pick<Api.SystemManage.TenantListItem, 'id' | 'tenantCode' | 'tenantName'> | null
      parentId?: string | null
      itemCode: string
      itemName: string
      businessCategory?: WaybillCostType | null
      isSelectable: boolean
      reimbursementAllowed: boolean
      isEnabled: boolean
      sort: number
      remark?: string | null
      createBy?: string | null
      createTime?: string
      updateBy?: string | null
      updateTime?: string
      children?: ExpenseItem[]
    }

    type ExpenseItemSearchParams = Api.Common.CommonSearchParams & {
      keyword?: string
      tenantId?: string
      parentId?: string | null
      isEnabled?: boolean
    }

    interface WaybillCostWaybill {
      id: string
      waybillNo: string
      status: string
      orderId?: string | null
      carrierId?: string | null
      driverId?: string | null
      originCity?: string | null
      destinationCity?: string | null
      carrier?: Pick<BasicData.CarrierOption, 'id' | 'companyName'> | null
      driver?: Pick<BasicData.DriverOption, 'id' | 'driverName' | 'phone'> | null
      order?: Pick<
        Order.OrderRecord,
        | 'id'
        | 'orderNo'
        | 'dispatchPlateNo'
        | 'dispatchDriverName'
        | 'dispatchDriverPhone'
        | 'originStation'
        | 'destinationStation'
      > | null
    }

    interface WaybillCostRecord {
      id?: string
      tenantId?: string
      costNo?: string
      waybillId: string
      expenseItemId: string
      costType: WaybillCostType | string
      amount: number
      occurredOn: string
      quantity?: number | null
      unitPrice?: number | null
      providerName?: string | null
      payeeName?: string | null
      paymentChannel?: string | null
      invoiceNo?: string | null
      meterNo?: string | null
      expenseLocation?: string | null
      expenseRegion?: string | null
      expenseRegionAdcode?: string | null
      expenseLongitude?: number | string | null
      expenseLatitude?: number | string | null
      expenseCoordinateSystem?: string | null
      expenseCoordinateSource?: string | null
      expenseCoordinateStatus?: string | null
      expenseGeocodeProvider?: string | null
      expenseGeocodedAt?: string | null
      carrierId?: string | null
      driverId?: string | null
      remark?: string | null
      attachments?: string[]
      reporterUserId?: string | null
      reporterNameSnapshot?: string | null
      reporterDepartmentSnapshot?: string | null
      auditStatus?: CostAuditStatus
      settlementStatus?: CostSettlementStatus
      reimbursementId?: string | null
      expensePaymentId?: string | null
      paidAt?: string | null
      waybillNoSnapshot?: string | null
      orderNoSnapshot?: string | null
      plateNoSnapshot?: string | null
      driverNameSnapshot?: string | null
      driverPhoneSnapshot?: string | null
      routeSnapshot?: string | null
      latestOcrRunId?: string | null
      ocrArtifactId?: string | null
      ocrStatus?: ExpenseOcrStatus
      submittedAt?: string | null
      submittedBy?: string | null
      reviewedAt?: string | null
      reviewedBy?: string | null
      reviewRemark?: string | null
      createBy?: string | null
      createTime?: string
      updateBy?: string | null
      updateTime?: string
      expenseItem?: ExpenseItem | null
      reimbursement?: Pick<ExpenseReimbursementRecord, 'id' | 'reimbursementNo' | 'status'> | null
      expensePayment?: {
        id: string
        paymentNo: string
        paymentDate?: string | null
        bankReference?: string | null
      } | null
      waybill?: WaybillCostWaybill | null
    }

    type WaybillCostSearchParams = Api.Common.CommonSearchParams & {
      recordId?: string
      orderId?: string
      keyword?: string
      expenseItemId?: string
      costType?: string
      auditStatus?: string
      settlementStatus?: string
      occurredOnRange?: string[]
    }

    interface WaybillOption extends WaybillCostWaybill {
      completedAt?: string | null
    }

    interface WaybillOptionSearchParams extends Api.Common.CommonSearchParams {
      keyword?: string
      orderId?: string
    }

    interface CostReviewPayload {
      id: string
      auditStatus: 'approved' | 'rejected'
      reviewRemark?: string | null
    }

    type WaybillCostAuditSignalType =
      | 'amount_outlier'
      | 'cost_concentration'
      | 'duplicate_cost'
      | 'future_occurred_date'
      | 'missing_attachment'
      | 'missing_payee'
      | 'missing_remark'
      | 'negative_margin'
      | 'thin_margin'

    type WaybillCostAuditSeverity = 'critical' | 'high' | 'medium'
    type WaybillCostAuditRiskLevel = WaybillCostAuditSeverity | 'low'
    type WaybillCostAuditRecommendation =
      'block_for_verification' | 'manual_review' | 'routine_review'

    interface WaybillCostAuditSignal {
      type: WaybillCostAuditSignalType
      severity: WaybillCostAuditSeverity
      title: string
      detail: string
      evidence: string[]
    }

    interface WaybillCostAuditAssessment {
      costId: string
      waybillId: string
      waybillNo: string
      route: string
      riskLevel: WaybillCostAuditRiskLevel
      riskScore: number
      confidence: number
      recommendation: WaybillCostAuditRecommendation
      summary: string
      signals: WaybillCostAuditSignal[]
      recommendedActions: string[]
      limitations: string[]
      metrics: {
        amount: number
        benchmarkMedian: number | null
        benchmarkSampleSize: number
        duplicateCount: number
        projectedTotalCost: number
        receivableAmount: number | null
        projectedGrossMargin: number | null
        attachmentCount: number
      }
    }

    interface WaybillCostAuditResponse {
      runId: string
      ruleVersion: string
      generatedAt: string
      assessment: WaybillCostAuditAssessment
    }

    type WaybillProfitAnalysisRiskLevel = 'critical' | 'high' | 'medium' | 'low'
    type WaybillProfitAnalysisSeverity = 'critical' | 'high' | 'medium'
    type WaybillProfitAnalysisRecommendation =
      'repair_cost_baseline' | 'manual_profit_review' | 'routine_monitoring'

    interface WaybillProfitAnalysisSignal {
      type: string
      severity: WaybillProfitAnalysisSeverity
      title: string
      detail: string
      evidence: string[]
    }

    interface WaybillProfitRiskWaybill {
      id: string
      waybillId: string
      waybillNo: string
      route: string
      customerName: string
      carrierName: string
      waybillStatus: string
      receivableAmount: number
      totalCostAmount: number
      grossProfit: number
      grossMargin: number
      riskScore: number
      reasons: string[]
    }

    interface WaybillProfitAnalysisAssessment {
      riskLevel: WaybillProfitAnalysisRiskLevel
      riskScore: number
      confidence: number
      recommendation: WaybillProfitAnalysisRecommendation
      summary: string
      signals: WaybillProfitAnalysisSignal[]
      riskWaybills: WaybillProfitRiskWaybill[]
      recommendedActions: string[]
      limitations: string[]
      metrics: {
        totalWaybills: number
        finalizedWaybills: number
        receivableAmount: number
        totalCostAmount: number
        bookGrossProfit: number
        bookGrossMargin: number | null
        costCoverage: number
        finalizedCostCoverage: number
        missingCostCount: number
        negativeMarginCount: number
        carrierPayableMissingCount: number
      }
    }

    interface WaybillProfitAnalysisResponse {
      runId: string
      ruleVersion: string
      generatedAt: string
      assessment: WaybillProfitAnalysisAssessment
    }

    interface WaybillProfitRecord {
      id: string
      tenantId: string
      waybillId: string
      orderId?: string | null
      waybillNo: string
      waybillStatus: string
      orderStatus?: string | null
      customerId?: string | null
      customerName?: string | null
      carrierId?: string | null
      carrierName?: string | null
      plateNo?: string | null
      driverName?: string | null
      originStation?: string | null
      destinationStation?: string | null
      receivableAmount: number
      carrierPayableAmount: number
      otherCostAmount: number
      totalCostAmount: number
      grossProfit: number
      grossMargin: number
      completedAt?: string | null
      signedAt?: string | null
      createTime?: string
      updateTime?: string
    }

    type WaybillProfitSearchParams = Api.Common.CommonSearchParams & {
      keyword?: string
      waybillStatus?: string
      completedAtRange?: string[]
    }

    type CustomerStatementStatus =
      'draft' | 'pending_review' | 'confirmed' | 'partially_settled' | 'settled' | 'voided'

    interface CustomerStatementItem {
      id: string
      tenantId: string
      statementId: string
      customerId: string
      waybillId: string
      orderId: string
      waybillNoSnapshot: string
      orderNoSnapshot: string
      originStationSnapshot?: string | null
      destinationStationSnapshot?: string | null
      completedAtSnapshot?: string | null
      receivableAmount: number
      adjustmentAmount: number
      lineAmount: number
      isActive: boolean
      remark?: string | null
      createBy?: string | null
      createTime: string
      updateBy?: string | null
      updateTime: string
    }

    interface CustomerStatementRecord {
      id: string
      tenantId: string
      statementNo: string
      customerId: string
      customerName: string
      periodStart: string
      periodEnd: string
      status: CustomerStatementStatus
      waybillCount: number
      statementAmount: number
      settledAmount: number
      outstandingAmount: number
      submittedAt?: string | null
      submittedBy?: string | null
      reviewedAt?: string | null
      reviewedBy?: string | null
      reviewRemark?: string | null
      voidedAt?: string | null
      voidedBy?: string | null
      voidReason?: string | null
      remark?: string | null
      createBy?: string | null
      createTime: string
      updateBy?: string | null
      updateTime: string
      items?: CustomerStatementItem[]
    }

    type CustomerStatementSearchParams = Api.Common.CommonSearchParams & {
      customerId?: string
      keyword?: string
      periodRange?: string[]
      recordId?: string
      status?: string
    }

    interface CustomerStatementEligibleWaybill {
      id: string
      tenantId: string
      waybillNo: string
      waybillStatus: string
      orderId: string
      orderNo: string
      customerId: string
      customerName: string
      originStation?: string | null
      destinationStation?: string | null
      completedAt: string
      receivableAmount: number
    }

    interface CustomerStatementEligibleWaybillSearchParams extends Api.Common.CommonSearchParams {
      customerId: string
      periodStart: string
      periodEnd: string
      keyword?: string
    }

    interface CreateCustomerStatementPayload {
      statementNo?: string | null
      customerId: string
      periodStart: string
      periodEnd: string
      waybillIds: string[]
      remark?: string | null
    }

    interface CustomerStatementStatusPayload {
      id: string
      status: CustomerStatementStatus
      reviewRemark?: string | null
      voidReason?: string | null
    }

    interface CarrierStatementItem {
      id: string
      tenantId: string
      statementId: string
      carrierId: string
      costId: string
      waybillId: string
      waybillNoSnapshot: string
      costTypeSnapshot: string
      occurredOnSnapshot: string
      payeeNameSnapshot?: string | null
      costAmount: number
      adjustmentAmount: number
      lineAmount: number
      isActive: boolean
      remark?: string | null
      createBy?: string | null
      createTime: string
      updateBy?: string | null
      updateTime: string
    }

    interface CarrierStatementRecord {
      id: string
      tenantId: string
      statementNo: string
      carrierId: string
      carrierName: string
      periodStart: string
      periodEnd: string
      status: CustomerStatementStatus
      costCount: number
      waybillCount: number
      statementAmount: number
      settledAmount: number
      outstandingAmount: number
      submittedAt?: string | null
      submittedBy?: string | null
      reviewedAt?: string | null
      reviewedBy?: string | null
      reviewRemark?: string | null
      voidedAt?: string | null
      voidedBy?: string | null
      voidReason?: string | null
      remark?: string | null
      createBy?: string | null
      createTime: string
      updateBy?: string | null
      updateTime: string
      items?: CarrierStatementItem[]
    }

    type CarrierStatementSearchParams = Api.Common.CommonSearchParams & {
      carrierId?: string
      keyword?: string
      periodRange?: string[]
      recordId?: string
      status?: string
    }

    interface CarrierStatementEligibleCost {
      id: string
      tenantId: string
      carrierId: string
      carrierName: string
      waybillId: string
      waybillNo: string
      waybillStatus: string
      costType: string
      costAmount: number
      occurredOn: string
      payeeName?: string | null
      remark?: string | null
      originCity?: string | null
      destinationCity?: string | null
    }

    interface CarrierStatementEligibleCostSearchParams extends Api.Common.CommonSearchParams {
      carrierId: string
      periodStart: string
      periodEnd: string
      keyword?: string
    }

    interface CreateCarrierStatementPayload {
      statementNo?: string | null
      carrierId: string
      periodStart: string
      periodEnd: string
      costIds: string[]
      remark?: string | null
    }

    interface CarrierStatementStatusPayload {
      id: string
      status: CustomerStatementStatus
      reviewRemark?: string | null
      voidReason?: string | null
    }

    type CashDirection = 'receipt' | 'payment'
    type CashPaymentMethod = 'bank_transfer' | 'cash' | 'wechat' | 'alipay' | 'other'
    type CashTransactionStatus =
      'pending_allocation' | 'partially_allocated' | 'allocated' | 'voided'

    interface CashAllocationStatement {
      id: string
      statementNo: string
      customerId: string
      customerNameSnapshot: string
      periodStart: string
      periodEnd: string
      status: CustomerStatementStatus
      settledAmount: number
    }

    interface CashAllocationRecord {
      id: string
      tenantId: string
      transactionId: string
      statementId: string
      customerId: string
      allocatedAmount: number
      isActive: boolean
      allocatedAt: string
      allocatedBy?: string | null
      reversedAt?: string | null
      reversedBy?: string | null
      reverseReason?: string | null
      remark?: string | null
      createBy?: string | null
      createTime: string
      updateBy?: string | null
      updateTime: string
      statement?: CashAllocationStatement | null
    }

    interface CashTransactionRecord {
      id: string
      tenantId: string
      transactionNo: string
      direction: CashDirection
      customerId?: string | null
      carrierId?: string | null
      counterpartyName: string
      transactionDate: string
      amount: number
      allocatedAmount: number
      unallocatedAmount: number
      allocationCount: number
      paymentMethod: CashPaymentMethod
      bankReference?: string | null
      voucherUrls: string[]
      status: CashTransactionStatus
      voidedAt?: string | null
      voidedBy?: string | null
      voidReason?: string | null
      remark?: string | null
      createBy?: string | null
      createTime: string
      updateBy?: string | null
      updateTime: string
      paymentApplicationId?: string | null
      allocations?: Array<CashAllocationRecord | CarrierCashAllocationRecord>
    }

    type CashTransactionSearchParams = Api.Common.CommonSearchParams & {
      customerId?: string
      carrierId?: string
      direction?: string
      recordId?: string
      status?: string
      dateRange?: string[]
      keyword?: string
    }

    interface CustomerStatementAllocatable {
      id: string
      tenantId: string
      statementNo: string
      customerId: string
      customerName: string
      periodStart: string
      periodEnd: string
      waybillCount: number
      statementAmount: number
      settledAmount: number
      outstandingAmount: number
      status: CustomerStatementStatus
      createTime: string
    }

    interface CustomerStatementAllocatableSearchParams extends Api.Common.CommonSearchParams {
      customerId: string
      keyword?: string
    }

    interface CashAllocationInput {
      statementId: string
      amount: number
    }

    interface CreateCustomerReceiptPayload {
      transactionNo?: string | null
      customerId: string
      transactionDate: string
      amount: number
      paymentMethod: CashPaymentMethod
      bankReference?: string | null
      voucherUrls?: string[]
      remark?: string | null
      allocations: CashAllocationInput[]
    }

    interface AllocateCustomerReceiptPayload {
      transactionId: string
      allocations: CashAllocationInput[]
    }

    interface CarrierStatementAllocatable {
      id: string
      tenantId: string
      statementNo: string
      carrierId: string
      carrierName: string
      periodStart: string
      periodEnd: string
      costCount: number
      waybillCount: number
      statementAmount: number
      settledAmount: number
      outstandingAmount: number
      statementOutstandingAmount?: number
      reservedAmount?: number
      status: CustomerStatementStatus
      createTime: string
    }

    interface CarrierStatementAllocatableSearchParams extends Api.Common.CommonSearchParams {
      carrierId: string
      keyword?: string
    }

    interface CarrierCashAllocationRecord {
      id: string
      tenantId: string
      transactionId: string
      statementId: string
      carrierId: string
      allocatedAmount: number
      isActive: boolean
      allocatedAt: string
      allocatedBy?: string | null
      reversedAt?: string | null
      reversedBy?: string | null
      reverseReason?: string | null
      remark?: string | null
      createBy?: string | null
      createTime: string
      updateBy?: string | null
      updateTime: string
      statement?: CarrierStatementRecord | null
    }

    interface CreateCarrierPaymentPayload {
      transactionNo?: string | null
      carrierId: string
      transactionDate: string
      amount: number
      paymentMethod: CashPaymentMethod
      bankReference?: string | null
      voucherUrls?: string[]
      remark?: string | null
      allocations: CashAllocationInput[]
    }

    interface AllocateCarrierPaymentPayload {
      transactionId: string
      allocations: CashAllocationInput[]
    }

    type CarrierPaymentApplicationStatus =
      'draft' | 'pending_review' | 'approved' | 'rejected' | 'paid' | 'cancelled'

    interface CarrierPaymentApplicationItem {
      id: string
      tenantId: string
      applicationId: string
      statementId: string
      carrierId: string
      statementNoSnapshot: string
      statementAmountSnapshot: number
      outstandingAmountSnapshot: number
      appliedAmount: number
      remark?: string | null
      createBy?: string | null
      createTime: string
      updateBy?: string | null
      updateTime: string
    }

    interface CarrierPaymentApplicationRecord {
      id: string
      tenantId: string
      applicationNo: string
      carrierId: string
      carrierName: string
      plannedPaymentDate: string
      amount: number
      paymentMethod: CashPaymentMethod
      basisUrls: string[]
      status: CarrierPaymentApplicationStatus
      paidTransactionId?: string | null
      paidTransactionNo?: string | null
      statementCount: number
      statementNos: string
      submittedAt?: string | null
      submittedBy?: string | null
      reviewedAt?: string | null
      reviewedBy?: string | null
      reviewRemark?: string | null
      paidAt?: string | null
      paidBy?: string | null
      cancelledAt?: string | null
      cancelledBy?: string | null
      cancelReason?: string | null
      remark?: string | null
      createBy?: string | null
      createTime: string
      updateBy?: string | null
      updateTime: string
      items?: CarrierPaymentApplicationItem[]
    }

    type CarrierPaymentApplicationSearchParams = Api.Common.CommonSearchParams & {
      carrierId?: string
      status?: string
      plannedPaymentDateRange?: string[]
      keyword?: string
      recordId?: string
    }

    interface SaveCarrierPaymentApplicationPayload {
      applicationNo?: string | null
      id?: string
      carrierId: string
      plannedPaymentDate: string
      amount: number
      paymentMethod: CashPaymentMethod
      basisUrls?: string[]
      remark?: string | null
      allocations: CashAllocationInput[]
    }

    interface ExecuteCarrierPaymentApplicationPayload {
      transactionNo?: string | null
      applicationId: string
      transactionDate: string
      bankReference?: string | null
      voucherUrls?: string[]
    }

    type CashVoucherOcrField =
      'payerName' | 'payeeName' | 'transactionDate' | 'amount' | 'bankReference' | 'paymentMethod'

    interface CashVoucherOcrDraft {
      payerName: string | null
      payeeName: string | null
      transactionDate: string | null
      amount: number | null
      bankReference: string | null
      paymentMethod: CashPaymentMethod
    }

    interface CashVoucherStatementMatch {
      statementId: string
      statementNo: string
      counterpartyId: string
      counterpartyName: string
      periodStart: string
      periodEnd: string
      statementAmount: number
      settledAmount: number
      outstandingAmount: number
      score: number
      confidence: number
      recommendedAllocation: number
      reasons: string[]
    }

    interface CashVoucherOcrAnalyzeRequest {
      action: 'analyze'
      imageUrls: string[]
      direction: CashDirection
    }

    interface CashVoucherOcrAnalyzeResponse {
      artifactId: string
      runId: string
      generatedAt: string
      rawText: string
      summary: string
      confidence: number
      fieldConfidence: Partial<Record<CashVoucherOcrField, number>>
      missingFields: string[]
      warnings: string[]
      voucher: CashVoucherOcrDraft
      matches: CashVoucherStatementMatch[]
      evaluatedStatements: number
      reviewConfidenceThreshold: number
    }

    interface CashVoucherOcrReviewRequest {
      action: 'review'
      artifactId: string
      entityId: string
      outcome: 'applied'
      finalPayload: Record<string, unknown>
      reviewNote?: string
    }

    interface CashVoucherOcrReviewResponse {
      artifactId: string
      status: 'applied'
      acceptedFields: string[]
      correctedFields: string[]
    }

    type BankBatchRowStatus = 'ready' | 'review' | 'duplicate' | 'invalid'

    interface BankBatchMatchRow {
      rowId: string
      sourceRow: number
      status: BankBatchRowStatus
      direction: CashDirection | null
      transactionDate: string | null
      amount: number
      bankReference: string | null
      counterpartyName: string | null
      counterpartyId: string | null
      counterpartyScore: number
      paymentMethod: CashPaymentMethod
      remark: string | null
      statementMatches: CashVoucherStatementMatch[]
      allocations: CashAllocationInput[]
      issues: string[]
    }

    interface BankBatchAnalyzeResponse {
      artifactId: string
      runId: string
      generatedAt: string
      mapping: Record<string, string>
      usedAi: boolean
      confidence: number
      reviewConfidenceThreshold: number
      summary: Record<BankBatchRowStatus, number>
      rows: BankBatchMatchRow[]
    }

    interface BankBatchCommitResponse {
      artifactId: string
      committedCount: number
      transactionIds: string[]
    }

    type InvoiceDirection = 'output' | 'input'
    type InvoiceType = 'vat_special' | 'vat_ordinary' | 'electronic'
    type InvoiceStatus = 'draft' | 'pending_review' | 'issued' | 'certified' | 'voided'
    type InvoiceStatusAction = 'submit' | 'approve' | 'reject' | 'void'

    interface InvoiceStatementLinkInput {
      statementId: string
      linkedAmount: number
    }

    interface InvoiceStatementLinkRecord {
      id: string
      tenantId: string
      invoiceId: string
      direction: InvoiceDirection
      statementId: string
      statementNo: string
      counterpartyId: string
      counterpartyName: string
      periodStart: string
      periodEnd: string
      statementAmount: number
      linkedAmount: number
      createBy?: string | null
      createTime: string
    }

    interface InvoiceRecord {
      id: string
      tenantId: string
      invoiceRecordNo: string
      direction: InvoiceDirection
      invoiceType: InvoiceType
      customerId?: string | null
      carrierId?: string | null
      counterpartyNameSnapshot: string
      invoiceTitle?: string | null
      taxNumber?: string | null
      invoiceCode?: string | null
      invoiceNo?: string | null
      issueDate: string
      taxRate: number
      amountExcludingTax: number
      taxAmount: number
      totalAmount: number
      status: InvoiceStatus
      attachments: Array<Record<string, unknown>>
      statementCount: number
      linkedAmount: number
      unlinkedAmount: number
      submittedAt?: string | null
      submittedBy?: string | null
      reviewedAt?: string | null
      reviewedBy?: string | null
      reviewRemark?: string | null
      voidedAt?: string | null
      voidedBy?: string | null
      voidReason?: string | null
      remark?: string | null
      createBy?: string | null
      createTime: string
      updateBy?: string | null
      updateTime: string
      statementLinks?: InvoiceStatementLinkRecord[]
    }

    interface InvoiceDuplicateRecord {
      id: string
      invoiceRecordNo: string
      direction: InvoiceDirection
      invoiceNo: string
      status: InvoiceStatus
      counterpartyNameSnapshot: string
      issueDate: string
      totalAmount: number
    }

    type InvoiceSearchParams = Api.Common.CommonSearchParams & {
      direction?: string
      status?: string
      invoiceType?: string
      customerId?: string
      carrierId?: string
      recordId?: string
      issueDateRange?: string[]
      keyword?: string
    }

    interface InvoiceableStatement {
      direction: InvoiceDirection
      statementId: string
      tenantId: string
      statementNo: string
      counterpartyId: string
      counterpartyName: string
      periodStart: string
      periodEnd: string
      status: CustomerStatementStatus
      statementAmount: number
      invoicedAmount: number
      uninvoicedAmount: number
    }

    interface InvoiceableStatementSearchParams extends Api.Common.CommonSearchParams {
      direction: InvoiceDirection
      counterpartyId: string
      keyword?: string
      includeFullyInvoiced?: boolean
    }

    interface SaveInvoicePayload {
      invoiceRecordNo?: string | null
      id?: string | null
      direction: InvoiceDirection
      invoiceType: InvoiceType
      customerId?: string | null
      carrierId?: string | null
      invoiceTitle?: string | null
      taxNumber?: string | null
      invoiceCode?: string | null
      invoiceNo?: string | null
      issueDate: string
      taxRate: number
      amountExcludingTax: number
      taxAmount: number
      totalAmount: number
      attachments?: Array<Record<string, unknown>>
      remark?: string | null
      statementLinks: InvoiceStatementLinkInput[]
    }

    interface InvoiceStatusPayload {
      id: string
      action: InvoiceStatusAction
      remark?: string | null
    }

    type InvoiceComplianceSignalType =
      | 'amount_formula_mismatch'
      | 'counterparty_mismatch'
      | 'duplicate_invoice_number'
      | 'future_issue_date'
      | 'incomplete_statement_coverage'
      | 'missing_attachment'
      | 'missing_invoice_identity'
      | 'missing_tax_identity'
      | 'statement_amount_mismatch'
      | 'tax_calculation_mismatch'
    type InvoiceComplianceSeverity = 'critical' | 'high' | 'medium'
    type InvoiceComplianceRiskLevel = InvoiceComplianceSeverity | 'low'
    type InvoiceComplianceRecommendation =
      'block_for_verification' | 'manual_review' | 'routine_review'

    interface InvoiceComplianceSignal {
      type: InvoiceComplianceSignalType
      severity: InvoiceComplianceSeverity
      title: string
      detail: string
      evidence: string[]
    }

    interface InvoiceComplianceAssessment {
      invoiceId: string
      invoiceRecordNo: string
      invoiceNo: string
      counterpartyName: string
      direction: string
      riskLevel: InvoiceComplianceRiskLevel
      riskScore: number
      confidence: number
      recommendation: InvoiceComplianceRecommendation
      summary: string
      signals: InvoiceComplianceSignal[]
      recommendedActions: string[]
      limitations: string[]
      metrics: {
        totalAmount: number
        calculatedTotalAmount: number
        linkedAmount: number
        unlinkedAmount: number
        statementCount: number
        duplicateCount: number
        attachmentCount: number
        coverageRate: number
        taxRate: number
      }
    }

    interface InvoiceComplianceAuditResponse {
      runId: string
      ruleVersion: string
      generatedAt: string
      assessment: InvoiceComplianceAssessment
    }

    type InvoiceOcrField =
      | 'invoiceType'
      | 'invoiceTitle'
      | 'taxNumber'
      | 'invoiceCode'
      | 'invoiceNo'
      | 'issueDate'
      | 'taxRate'
      | 'amountExcludingTax'
      | 'taxAmount'
      | 'totalAmount'
      | 'buyerName'
      | 'buyerTaxNumber'
      | 'sellerName'
      | 'sellerTaxNumber'

    interface InvoiceOcrDraft {
      invoiceType?: InvoiceType | null
      invoiceTitle?: string | null
      taxNumber?: string | null
      invoiceCode?: string | null
      invoiceNo?: string | null
      issueDate?: string | null
      taxRate?: number | null
      amountExcludingTax?: number | null
      taxAmount?: number | null
      totalAmount?: number | null
      buyerName?: string | null
      buyerTaxNumber?: string | null
      sellerName?: string | null
      sellerTaxNumber?: string | null
    }

    interface InvoiceOcrAnalyzeRequest {
      action?: 'analyze'
      imageUrls: string[]
      direction: InvoiceDirection
    }

    interface InvoiceOcrAnalyzeResponse {
      runId: string
      artifactId: string
      generatedAt: string
      rawText: string
      summary: string
      confidence: number
      fieldConfidence: Partial<Record<InvoiceOcrField, number>>
      missingFields: string[]
      warnings: string[]
      invoice: InvoiceOcrDraft
    }

    type InvoiceCounterpartyResolutionStatus =
      'matched' | 'unmatched' | 'ambiguous' | 'conflict' | 'disabled' | 'invalid'

    interface InvoiceCounterpartyOption {
      id: string
      partyName: string
      partyCode?: string | null
      taxNo?: string | null
      enabled: boolean
    }

    interface InvoiceCounterpartyResolution {
      status: InvoiceCounterpartyResolutionStatus
      direction: InvoiceDirection
      partyKind: 'customer' | 'carrier'
      name?: string | null
      taxNo?: string | null
      confidence: number
      matchMethod?: 'tax_no' | 'name' | null
      canCreate: boolean
      requiresReview: boolean
      message: string
      party?: InvoiceCounterpartyOption | null
    }

    interface CreateInvoiceCounterpartyFromOcrPayload {
      artifactId: string
      name: string
      taxNo?: string | null
      carrierType?: string | null
    }

    interface CreateInvoiceCounterpartyFromOcrResponse {
      created: boolean
      direction: InvoiceDirection
      party: InvoiceCounterpartyOption
    }

    interface InvoiceOcrReviewRequest {
      action: 'review'
      artifactId: string
      entityId: string
      outcome: 'applied'
      finalPayload: Record<string, unknown>
      reviewNote?: string
    }

    interface InvoiceOcrReviewResponse {
      artifactId: string
      status: 'applied'
      acceptedFields: string[]
      correctedFields: string[]
    }

    interface FinanceWorkbenchStats {
      customerReceivableBalance: number
      carrierPayableBalance: number
      monthReceiptAmount: number
      monthPaymentAmount: number
      monthRevenueAmount: number
      monthCostAmount: number
      monthGrossProfit: number
      receiptCompletionRate: number
      paymentCompletionRate: number
      invoiceMatchRate: number
      costApprovalRate: number
      pendingCustomerStatementCount: number
      pendingCustomerStatementAmount: number
      pendingCarrierStatementCount: number
      pendingCarrierStatementAmount: number
      pendingCostCount: number
      pendingCostAmount: number
      unallocatedReceiptCount: number
      unallocatedReceiptAmount: number
      unallocatedPaymentCount: number
      unallocatedPaymentAmount: number
      draftInvoiceCount: number
      draftInvoiceAmount: number
      pendingInvoiceCount: number
      pendingInvoiceAmount: number
      pendingPaymentApplicationCount: number
      pendingPaymentApplicationAmount: number
      approvedUnpaidPaymentCount: number
      approvedUnpaidPaymentAmount: number
      unapprovedPaymentCount: number
      unapprovedPaymentAmount: number
      overdueReceivableCount: number
      overdueReceivableAmount: number
      uninvoicedReceivableCount: number
      uninvoicedReceivableAmount: number
    }

    type ReceivablesRiskLevel = 'critical' | 'high' | 'medium' | 'low'
    type ReceivablesSignalSeverity = 'critical' | 'high' | 'medium'
    type ReceivablesRecommendation =
      'unblock_settlement' | 'complete_invoicing' | 'prioritize_collection' | 'routine_monitoring'

    interface ReceivablesRiskSignal {
      type: string
      severity: ReceivablesSignalSeverity
      title: string
      detail: string
      evidence: string[]
    }

    interface ReceivablesPriorityStatement {
      id: string
      statementNo: string
      customerId: string
      customerName: string
      periodStart: string
      periodEnd: string
      status: string
      ageDays: number
      statementAmount: number
      settledAmount: number
      outstandingAmount: number
      uninvoicedAmount: number
      riskScore: number
      reasons: string[]
    }

    interface ReceivablesRiskCustomer {
      customerId: string
      customerName: string
      statementCount: number
      outstandingAmount: number
      maxAgeDays: number
      riskScore: number
      statementNos: string[]
    }

    interface ReceivablesCollectionAssessment {
      riskLevel: ReceivablesRiskLevel
      riskScore: number
      confidence: number
      recommendation: ReceivablesRecommendation
      summary: string
      signals: ReceivablesRiskSignal[]
      priorityStatements: ReceivablesPriorityStatement[]
      riskCustomers: ReceivablesRiskCustomer[]
      recommendedActions: string[]
      limitations: string[]
      metrics: {
        totalStatementCount: number
        openStatementCount: number
        statementAmount: number
        settledAmount: number
        outstandingAmount: number
        collectionRate: number
        aging30Amount: number
        aging60Amount: number
        aging90Amount: number
        uninvoicedAmount: number
        reviewBlockedAmount: number
        atRiskAmount: number
      }
    }

    interface ReceivablesCollectionResponse {
      runId: string
      ruleVersion: string
      generatedAt: string
      assessment: ReceivablesCollectionAssessment
    }
  }

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
