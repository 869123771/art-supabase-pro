declare namespace Api {
  namespace Smis {
    namespace RiskControl {
      type RiskLevel = 'low' | 'general' | 'major' | 'critical'
      type RiskPointStatus = 'active' | 'inactive' | 'archived'
      type RiskAssessmentStatus = 'draft' | 'submitted' | 'effective' | 'superseded'
      type RiskAssessmentTransitionAction = 'submit' | 'withdraw' | 'activate'
      type ControlMeasureType = 'engineering' | 'administrative' | 'training' | 'ppe' | 'emergency'
      type ControlMeasureStatus = 'draft' | 'active' | 'suspended' | 'retired'

      interface NamedOption {
        id: string
        label: string
        code?: string | null
      }

      interface SiteOption extends NamedOption {
        organizationId?: string | null
      }

      interface AreaOption extends NamedOption {
        siteId: string
        parentId?: string | null
      }

      interface SiteRecord {
        id?: string
        organizationId?: string | null
        siteCode: string
        siteName: string
        address?: string | null
        floorplanUrl?: string | null
        mapBoundary?: Record<string, unknown> | null
        enabled: boolean
        sort: number
        remark?: string | null
        createTime?: string
        updateTime?: string
      }

      interface AreaRecord {
        id?: string
        siteId: string
        parentId?: string | null
        managerUserId?: string | null
        areaCode: string
        areaName: string
        floorplanGeometry?: Record<string, unknown> | null
        enabled: boolean
        sort: number
        remark?: string | null
      }

      interface RiskPointRecord {
        id?: string
        organizationId?: string | null
        siteId: string
        areaId: string
        responsibleUserId?: string | null
        riskPointNo: string
        riskPointName: string
        operationActivity?: string | null
        riskCategory?: string | null
        possibleConsequence?: string | null
        currentRiskLevel?: RiskLevel | null
        status: RiskPointStatus
        inspectionFrequency?: string | null
        mapGeometry?: Record<string, unknown> | null
        qrCodeValue?: string | null
        remark?: string | null
        createTime?: string
        updateTime?: string
        site?: { id: string; siteCode: string; siteName: string } | null
        area?: { id: string; areaCode: string; areaName: string } | null
        organization?: { id: string; organizationCode: string; organizationName: string } | null
        responsibleUser?: {
          id: string
          userName?: string | null
          nickName?: string | null
          userEmail: string
        } | null
      }

      interface RiskPointSearchParams {
        keyword?: string
        siteId?: string
        areaId?: string
        status?: RiskPointStatus | ''
        currentRiskLevel?: RiskLevel | ''
        createTimeRange?: string[]
        from?: number
        to?: number
      }

      interface HazardSourceRecord {
        id?: string
        riskPointId: string
        sourceNo: string
        hazardName: string
        hazardDescription?: string | null
        accidentType?: string | null
        possibleConsequence?: string | null
        existingControls?: string | null
        enabled: boolean
        sort: number
        remark?: string | null
        createTime?: string
        updateTime?: string
      }

      interface RiskAssessmentRecord {
        id?: string
        riskPointId: string
        assessorUserId?: string | null
        reviewerUserId?: string | null
        versionNo: number
        assessmentMethod: 'LEC'
        status: RiskAssessmentStatus
        assessmentDate: string
        submittedAt?: string | null
        effectiveAt?: string | null
        reviewComment?: string | null
        assessmentSummary?: string | null
        maxRiskScore?: number | null
        maxRiskLevel?: RiskLevel | null
        createTime?: string
        updateTime?: string
        assessorUser?: {
          id: string
          userName?: string | null
          nickName?: string | null
          userEmail: string
        } | null
        reviewerUser?: {
          id: string
          userName?: string | null
          nickName?: string | null
          userEmail: string
        } | null
      }

      interface ControlMeasureRecord {
        id?: string
        assessmentItemId: string
        responsibleUserId?: string | null
        measureType: ControlMeasureType
        measureContent: string
        verificationCriteria?: string | null
        targetDate?: string | null
        status: ControlMeasureStatus
        createTime?: string
        updateTime?: string
        responsibleUser?: {
          id: string
          userName?: string | null
          nickName?: string | null
          userEmail: string
        } | null
      }

      interface RiskAssessmentItemRecord {
        id?: string
        assessmentId: string
        hazardSourceId: string
        likelihood: number
        exposure: number
        consequence: number
        riskScore?: number
        riskLevel?: RiskLevel
        evaluationNote?: string | null
        hazardNameSnapshot?: string
        hazardDescriptionSnapshot?: string | null
        accidentTypeSnapshot?: string | null
        possibleConsequenceSnapshot?: string | null
        existingControlsSnapshot?: string | null
        createTime?: string
        updateTime?: string
        hazardSource?: HazardSourceRecord | null
        controlMeasures?: ControlMeasureRecord[]
      }

      interface RiskAssessmentEventRecord {
        id: string
        assessmentId: string
        fromStatus?: RiskAssessmentStatus | null
        toStatus: RiskAssessmentStatus
        action: RiskAssessmentTransitionAction
        comment?: string | null
        actorUserId?: string | null
        createTime: string
        actorUser?: {
          id: string
          userName?: string | null
          nickName?: string | null
          userEmail: string
        } | null
      }
    }

    namespace InspectionControl {
      type InspectionPlanStatus = 'draft' | 'active' | 'suspended' | 'archived'
      type InspectionTaskStatus = 'pending' | 'in_progress' | 'completed' | 'cancelled'
      type InspectionResult = 'normal' | 'hidden_danger' | 'not_applicable'
      type HiddenDangerStatus =
        'reported' | 'rectifying' | 'pending_review' | 'closed' | 'cancelled'
      type HiddenDangerAction = 'assign' | 'submit_review' | 'reject' | 'close' | 'cancel'
      type HiddenDangerEventAction =
        | HiddenDangerAction
        | 'report'
        | 'workflow_started'
        | 'workflow_approved'
        | 'workflow_rejected'
        | 'workflow_withdrawn'
        | 'workflow_cancelled'
      type AttachmentRef = Record<string, unknown> & {
        id?: string
        originName?: string
        url?: string
      }

      interface InspectionPlanRecord {
        id?: string
        organizationId?: string | null
        siteId?: string | null
        areaId?: string | null
        riskPointId?: string | null
        ownerUserId?: string | null
        planNo: string
        planName: string
        inspectionType: 'routine' | 'special' | 'seasonal' | 'comprehensive'
        frequencyValue: number
        frequencyUnit: 'day' | 'week' | 'month' | 'quarter' | 'year'
        nextDueAt?: string | null
        checklist?: string | null
        status: InspectionPlanStatus
        remark?: string | null
        createTime?: string
        updateTime?: string
      }

      interface InspectionTaskRecord {
        id?: string
        planId?: string | null
        riskPointId: string
        inspectorUserId?: string | null
        taskNo: string
        taskName: string
        sourceType: 'manual' | 'plan' | 'vms_routine_inspection' | 'tms_waybill'
        sourceBusinessId?: string | null
        scheduledStartAt: string
        scheduledEndAt: string
        status: InspectionTaskStatus
        startedAt?: string | null
        completedAt?: string | null
        cancelledAt?: string | null
        cancellationReason?: string | null
        remark?: string | null
        createTime?: string
        updateTime?: string
        plan?: Pick<InspectionPlanRecord, 'id' | 'planNo' | 'planName'> | null
        riskPoint?: Api.Smis.RiskControl.RiskPointRecord | null
        inspectorUser?: {
          id: string
          userName?: string | null
          nickName?: string | null
          userEmail: string
        } | null
        result?: InspectionResultRecord | null
        hiddenDangerCount?: number
      }

      interface InspectionTaskSearchParams {
        keyword?: string
        status?: InspectionTaskStatus | ''
        riskPointId?: string
        scheduledTimeRange?: string[]
        from?: number
        to?: number
      }

      interface InspectionResultRecord {
        id: string
        taskId: string
        checkResult: InspectionResult
        resultSummary?: string | null
        attachmentRefs: AttachmentRef[]
        createTime: string
        updateTime: string
      }

      interface HiddenDangerRecord {
        id?: string
        taskId?: string | null
        riskPointId: string
        hazardSourceId?: string | null
        responsibleUserId?: string | null
        reviewerUserId?: string | null
        dangerNo: string
        dangerTitle: string
        dangerDescription: string
        dangerLevel: Api.Smis.RiskControl.RiskLevel
        rectificationRequirement?: string | null
        rectificationDeadline?: string | null
        status: HiddenDangerStatus
        reportedAt?: string
        rectificationSubmittedAt?: string | null
        closedAt?: string | null
        cancelledAt?: string | null
        attachmentRefs: AttachmentRef[]
        remark?: string | null
        createTime?: string
        updateTime?: string
        task?: Pick<InspectionTaskRecord, 'id' | 'taskNo' | 'taskName'> | null
        riskPoint?: Api.Smis.RiskControl.RiskPointRecord | null
        hazardSource?: Pick<
          Api.Smis.RiskControl.HazardSourceRecord,
          'id' | 'sourceNo' | 'hazardName'
        > | null
        responsibleUser?: {
          id: string
          userName?: string | null
          nickName?: string | null
          userEmail: string
        } | null
        reviewerUser?: {
          id: string
          userName?: string | null
          nickName?: string | null
          userEmail: string
        } | null
      }

      interface HiddenDangerSearchParams {
        keyword?: string
        status?: HiddenDangerStatus | ''
        dangerLevel?: Api.Smis.RiskControl.RiskLevel | ''
        riskPointId?: string
        overdueOnly?: boolean
        reportedTimeRange?: string[]
        from?: number
        to?: number
      }

      interface HiddenDangerEventRecord {
        id: string
        hiddenDangerId: string
        workflowInstanceId?: string | null
        fromStatus?: HiddenDangerStatus | null
        toStatus: HiddenDangerStatus
        action: HiddenDangerEventAction
        comment?: string | null
        attachmentRefs: AttachmentRef[]
        actorUserId?: string | null
        createTime: string
        actorUser?: {
          id: string
          userName?: string | null
          nickName?: string | null
          userEmail: string
        } | null
      }
    }

    namespace AccidentEmergency {
      type AccidentCaseStatus = 'reported' | 'investigating' | 'rectifying' | 'closed' | 'cancelled'
      type AccidentCaseAction = 'investigate' | 'rectify' | 'close' | 'cancel'
      type AccidentSeverity = 'slight' | 'general' | 'major' | 'critical'
      type AccidentCaseFieldKey =
        | 'incidentLocation'
        | 'casualtyAndLoss'
        | 'investigationDetails'
        | 'caseEvidence'
        | 'caseParticipants'
      type AccidentCaseFieldAccessMap = Partial<
        Record<AccidentCaseFieldKey, Api.Common.FieldAccessLevel>
      >
      type AttachmentRef = Api.Smis.InspectionControl.AttachmentRef
      interface UserRef {
        id?: string
        userName?: string | null
        nickName?: string | null
        userEmail: string
      }

      interface AccidentCaseRecord {
        id?: string
        riskPointId?: string | null
        reporterUserId?: string | null
        investigatorUserId?: string | null
        sourceType: 'manual' | 'vms_accident' | 'tms_waybill'
        sourceBusinessId?: string | null
        caseNo: string
        caseTitle: string
        incidentType: 'accident' | 'near_miss' | 'unsafe_event'
        severity: AccidentSeverity
        occurredAt: string
        location?: string | null
        longitude?: number | null
        latitude?: number | null
        description?: string | null
        casualties?: number | string | null
        economicLoss?: number | string | null
        immediateActions?: string | null
        causeAnalysis?: string | null
        correctiveActions?: string | null
        status: AccidentCaseStatus
        closedAt?: string | null
        attachmentRefs?: AttachmentRef[]
        remark?: string | null
        createTime?: string
        updateTime?: string
        riskPoint?: Api.Smis.RiskControl.RiskPointRecord | null
        reporterUser?: UserRef | null
        investigatorUser?: UserRef | null
        createdByUserId?: string | null
        fieldAccess?: AccidentCaseFieldAccessMap
        isRecordOwner?: boolean
      }

      interface AccidentCaseEventRecord {
        id: string
        accidentCaseId: string
        fromStatus?: AccidentCaseStatus | null
        toStatus: AccidentCaseStatus
        action: AccidentCaseAction | 'report'
        comment?: string | null
        attachmentRefs?: AttachmentRef[]
        actorUser?: UserRef | null
        createTime: string
      }

      interface AccidentCaseSearchParams {
        keyword?: string
        status?: AccidentCaseStatus | ''
        severity?: AccidentSeverity | ''
        occurredTimeRange?: string[]
        from?: number
        to?: number
      }

      interface EmergencyPlanRecord {
        id?: string
        ownerUserId?: string | null
        planNo: string
        planName: string
        planType: 'comprehensive' | 'special' | 'onsite'
        responseLevel: 'enterprise' | 'department' | 'site'
        versionNo: number
        applicableScope?: string | null
        contentSummary?: string | null
        effectiveFrom?: string | null
        effectiveTo?: string | null
        status: 'draft' | 'active' | 'retired'
        attachmentRefs: AttachmentRef[]
        remark?: string | null
        createTime?: string
        updateTime?: string
        ownerUser?: UserRef | null
      }

      interface EmergencyDrillRecord {
        id?: string
        planId: string
        organizerUserId?: string | null
        drillNo: string
        drillName: string
        drillType: 'desktop' | 'functional' | 'full_scale'
        scheduledAt: string
        actualAt?: string | null
        scenario?: string | null
        participants?: string | null
        result?: 'excellent' | 'good' | 'needs_improvement' | null
        issuesFound?: string | null
        improvementActions?: string | null
        status: 'planned' | 'completed' | 'cancelled'
        attachmentRefs: AttachmentRef[]
        remark?: string | null
        createTime?: string
        updateTime?: string
        plan?: Pick<EmergencyPlanRecord, 'id' | 'planNo' | 'planName'> | null
        organizerUser?: UserRef | null
      }

      interface VmsAccidentOption {
        id: string
        plateNo: string
        accidentTime: string
        accidentLocation?: string | null
        accidentSummary: string
        economicLoss?: number | null
      }
    }

    namespace Dashboard {
      interface RiskDistributionItem {
        level: Api.Smis.RiskControl.RiskLevel
        count: number
      }
      interface HotspotRecord {
        id: string
        riskPointNo: string
        riskPointName: string
        riskLevel?: Api.Smis.RiskControl.RiskLevel | null
        siteName?: string | null
        areaName?: string | null
        openDangerCount: number
        overdueDangerCount: number
        mapGeometry?: Record<string, unknown> | null
      }
      interface SafetyMapPoint {
        id: string
        kind: 'risk_point' | 'accident'
        title: string
        subtitle?: string | null
        level: Api.Smis.RiskControl.RiskLevel
        longitude: number
        latitude: number
      }
      interface SafetyDashboardData {
        riskPointTotal: number
        majorRiskPointCount: number
        openDangerCount: number
        overdueDangerCount: number
        pendingInspectionCount: number
        openAccidentCount: number
        activeEmergencyPlanCount: number
        upcomingDrillCount: number
        riskDistribution: RiskDistributionItem[]
        hotspots: HotspotRecord[]
        mapPoints: SafetyMapPoint[]
        recentDangers: Api.Smis.InspectionControl.HiddenDangerRecord[]
        recentAccidents: Api.Smis.AccidentEmergency.AccidentCaseRecord[]
      }
      interface SafetyAdvisorSignal {
        type: string
        title: string
        detail: string
        severity: 'info' | 'warning' | 'danger'
        count: number
      }
      interface SafetyAdvisorAssessment {
        riskLevel: 'low' | 'medium' | 'high' | 'critical'
        riskScore: number
        summary: string
        signals: SafetyAdvisorSignal[]
        actions: string[]
        limitations: string[]
      }
      interface SafetyAdvisorResponse {
        runId: string
        ruleVersion: string
        generatedAt: string
        assessment: SafetyAdvisorAssessment
      }
    }
  }
}
