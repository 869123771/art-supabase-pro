type ReminderRow = Api.Vms.ReminderManage.VehicleReminderRow

export interface ReminderTableRowClassContext {
  row: Record<string, unknown>
}

export const getReminderRiskRowClassName = ({ row }: ReminderTableRowClassContext): string => {
  const reminder = row as Partial<ReminderRow>
  if (reminder.expired || (reminder.remainingDays ?? 0) < 0) {
    return 'vehicle-reminder-row--overdue'
  }
  if (
    reminder.remainingDays !== null &&
    reminder.remainingDays !== undefined &&
    reminder.remainingDays <= 7
  ) {
    return 'vehicle-reminder-row--urgent'
  }
  return ''
}
