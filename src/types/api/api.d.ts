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
      tenant?: Pick<TenantListItem, 'tenantCode' | 'tenantName'>
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
      extra?: Record<string, any>
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
      tenant?: Pick<TenantListItem, 'tenantCode' | 'tenantName'>
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
      extendConfig?: Record<string, any>
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
          | 'chassisNo'
          | 'operationStatus'
          | 'auditStatus'
        > &
          Api.Common.CommonSearchParams & {
            createTimeRange?: string[]
            auditStatuses?: AuditStatus[]
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
        accidentTime: string
        accidentLocation?: string
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
    }

    namespace ReminderManage {
      type ReminderKind = 'insurance' | 'inspection' | 'maintenance' | 'part' | 'vehicle'

      type InsuranceType = 'commercial' | 'compulsory'

      interface VehicleReminderRow {
        id: string
        sourceId?: string
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
      }

      type VehicleReminderSearchParams = Partial<
        Pick<VehicleReminderRow, 'companyName' | 'plateNo' | 'expired'> &
          Api.Common.CommonSearchParams & {
            reminderDays?: number | null
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
  namespace Tms {
    namespace BasicData {
      type CustomerAddressType = 'shipping' | 'receiving'

      interface Customer {
        id?: string
        tenantId?: string
        customerCode?: string
        customerName: string
        industry?: string
        customerLevel?: string
        tags?: string[]
        region?: string
        addressDetail?: string
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
            keyword?: string
            createTimeRange?: string[]
          }
      >

      interface CustomerOption {
        id: string
        customerCode?: string
        customerName: string
        contactName?: string
        contactPhone?: string
      }

      interface CustomerAddress {
        id?: string
        tenantId?: string
        customerId: string
        addressType: CustomerAddressType
        contactName: string
        contactPhone: string
        region: string
        addressDetail: string
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
        shippingContactName: string
        shippingContactPhone: string
        shippingAddressDetail: string
        receivingContactName: string
        receivingContactPhone: string
        receivingAddressDetail: string
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
          }
      >

      interface Carrier {
        id?: string
        tenantId?: string
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
          }
      >

      interface CarrierOption {
        id: string
        carrierCode?: string
        companyName: string
        contactName?: string
        contactPhone?: string
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
        createBy?: string
        createTime?: string
        updateBy?: string
        updateTime?: string
      }

      type DriverSearchParams = Partial<
        Pick<Driver, 'carrierId' | 'gender' | 'enabled'> &
          Api.Common.CommonSearchParams & {
            keyword?: string
            createTimeRange?: string[]
          }
      >

      interface DriverOption {
        id: string
        carrierId?: string | null
        driverName: string
        phone?: string
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
          }
      >

      type ContractStatus = 'draft' | 'pending' | 'approved' | 'rejected' | 'terminated'

      interface ContractAttachment {
        name: string
        url?: string
        fileType?: string
        fileSize?: string
      }

      interface Contract {
        id?: string
        tenantId?: string
        contractNo?: string
        contractName: string
        contractStatus?: ContractStatus
        carrierId: string
        contactName?: string | null
        waybillNo?: string | null
        billingMethod: string
        contractAmount?: number | null
        signTime: string
        handler: string
        contractDescription?: string | null
        attachments?: ContractAttachment[]
        carrier?: CarrierOption | null
        createBy?: string
        createTime?: string
        updateBy?: string
        updateTime?: string
      }

      type ContractSearchParams = Partial<
        Pick<Contract, 'contractStatus' | 'carrierId' | 'billingMethod'> &
          Api.Common.CommonSearchParams & {
            keyword?: string
            createTimeRange?: string[]
          }
      >
    }

    namespace Order {
      interface StationOption {
        id: string
        stationCode: string
        stationName: string
        stationType: string
        regionCode?: string | null
      }

      interface CustomerSelectorItem {
        id: string
        customerCode?: string
        customerName: string
        contactName?: string
        contactPhone?: string
        region?: string
        addressDetail?: string
      }

      interface CargoItem {
        cargoName?: string | null
        packageType?: string | null
        quantity?: number | null
        unit?: string | null
        weightKg?: number | null
        volumeM3?: number | null
      }

      interface OrderRecord {
        id?: string
        tenantId?: string
        orderNo: string
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
        shippingCustomer?: CustomerSelectorItem | null
        receivingCustomer?: CustomerSelectorItem | null
        shippingContactName: string
        shippingContactPhone: string
        shippingAddressDetail: string
        receivingContactName: string
        receivingContactPhone: string
        receivingAddressDetail: string
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
          cargoKeyword?: string
          shippingKeyword?: string
          receivingKeyword?: string
          createTimeRange?: string[]
        }
      >

      type OrderFreightPayload = Pick<OrderRecord, 'id' | 'totalFee'>

      type CustomerSelectorSearchParams = Api.Common.CommonSearchParams & {
        keyword?: string
      }
    }

    namespace Station {
      type StationType = 'shipping' | 'transfer' | 'arrival'

      interface StationRecord {
        id?: string
        tenantId?: string
        stationCode?: string
        stationName: string
        stationType: StationType | string
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
