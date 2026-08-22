export interface SmisSafetyEvidence {
  criticalRiskPoints: number
  majorRiskPoints: number
  openDangers: number
  overdueDangers: number
  overdueInspections: number
  openAccidents: number
  majorAccidents: number
  activeEmergencyPlans: number
  upcomingDrills: number
}

export interface SmisSafetySignal {
  type: string
  title: string
  detail: string
  severity: 'info' | 'warning' | 'danger'
  count: number
}

export function assessSmisSafety(evidence: SmisSafetyEvidence) {
  const score = Math.min(
    100,
    evidence.criticalRiskPoints * 12 +
      evidence.majorRiskPoints * 5 +
      evidence.overdueDangers * 10 +
      Math.max(0, evidence.openDangers - evidence.overdueDangers) * 3 +
      evidence.overdueInspections * 4 +
      evidence.majorAccidents * 15 +
      Math.max(0, evidence.openAccidents - evidence.majorAccidents) * 6 +
      (evidence.activeEmergencyPlans === 0 ? 12 : 0) +
      (evidence.upcomingDrills === 0 ? 4 : 0)
  )
  const riskLevel =
    score >= 75 ? 'critical' : score >= 50 ? 'high' : score >= 25 ? 'medium' : 'low'
  const signals: SmisSafetySignal[] = []
  if (evidence.criticalRiskPoints) {
    signals.push({
      type: 'critical_risk_point',
      title: '重大风险点需优先管控',
      detail: '复核重大风险点的管控措施、责任人和检查频次，确保现场措施持续有效。',
      severity: 'danger',
      count: evidence.criticalRiskPoints
    })
  }
  if (evidence.overdueDangers) {
    signals.push({
      type: 'overdue_hidden_danger',
      title: '隐患整改已经逾期',
      detail: '按逾期天数和隐患等级升级督办，重大隐患应立即组织复查。',
      severity: 'danger',
      count: evidence.overdueDangers
    })
  }
  if (evidence.overdueInspections) {
    signals.push({
      type: 'overdue_inspection',
      title: '检查任务执行滞后',
      detail: '重新安排检查责任人和执行窗口，避免风险点出现检查空档。',
      severity: 'warning',
      count: evidence.overdueInspections
    })
  }
  if (evidence.openAccidents) {
    signals.push({
      type: 'open_accident',
      title: '事故事件尚未闭环',
      detail: '聚焦原因调查、纠正措施和验证证据，避免同类事件重复发生。',
      severity: evidence.majorAccidents ? 'danger' : 'warning',
      count: evidence.openAccidents
    })
  }
  if (evidence.activeEmergencyPlans === 0) {
    signals.push({
      type: 'emergency_plan_gap',
      title: '缺少生效中的应急预案',
      detail: '至少维护一份覆盖核心场景的生效预案，并明确响应层级和责任人。',
      severity: 'warning',
      count: 1
    })
  }
  if (!signals.length) {
    signals.push({
      type: 'stable',
      title: '当前安全运行总体平稳',
      detail: '未识别到高优先级异常，建议继续保持例行检查和动态风险评估。',
      severity: 'info',
      count: 0
    })
  }
  const actions = signals
    .filter((item) => item.type !== 'stable')
    .map((item) => item.detail)
    .slice(0, 5)
  return {
    riskLevel,
    riskScore: score,
    summary:
      riskLevel === 'critical'
        ? '当前存在需要立即升级处置的安全风险，请优先处理红色预警项。'
        : riskLevel === 'high'
          ? '当前安全风险偏高，应集中清理逾期隐患和未闭环事故事件。'
          : riskLevel === 'medium'
            ? '当前存在若干待治理信号，建议按优先级推进检查和整改。'
            : '当前安全态势总体平稳，继续维持动态风险管控和闭环检查。',
    signals,
    actions: actions.length ? actions : ['保持例行检查、风险评估和应急演练节奏。'],
    limitations: [
      '研判仅使用当前租户可见的结构化业务数据，不替代现场检查和法定专业判断。',
      '缺失定位、附件或尚未录入的线下事件不会进入本次计算。',
      '输出为只读建议，不会自动修改风险等级、隐患状态或业务数据。'
    ]
  }
}
