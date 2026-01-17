import dayjs from 'dayjs'
import utc from 'dayjs/plugin/utc'
import timezone from 'dayjs/plugin/timezone'

dayjs.extend(utc)
dayjs.extend(timezone)

/** Format value to 'YYYY-MM-DD HH:mm:ss' using dayjs.
 *  value can be:
 *   - full ISO timestamp string
 *   - Date
 *   - time-only string like '12:34:56' (will use today's date)
 *  timezone: IANA timezone string (e.g., 'Asia/Shanghai') or undefined to use local timezone
 */
export function formatWithDayjs(
  value: string | Date | null | undefined,
  tz?: string
): string | null {
  if (value == null) return null

  // If it's time-only (HH:mm or HH:mm:ss), attach today's date
  if (typeof value === 'string' && /^\d{2}:\d{2}(:\d{2})?$/.test(value)) {
    const today = dayjs()
    const datePart = today.format('YYYY-MM-DD')
    const composed = `${datePart} ${value}`
    return tz
      ? dayjs.tz(composed, tz).format('YYYY-MM-DD HH:mm:ss')
      : dayjs(composed).format('YYYY-MM-DD HH:mm:ss')
  }

  const d = typeof value === 'string' ? dayjs(value) : dayjs(value)
  if (!d.isValid()) return String(value)
  return tz ? d.tz(tz).format('YYYY-MM-DD HH:mm:ss') : d.format('YYYY-MM-DD HH:mm:ss')
}

export function toStartOfDayUTC(dateStr: string) {
  if (!dateStr) return null
  const d = new Date(dateStr + 'T00:00:00Z')
  return d.toISOString()
}
export function toNextDayStartUTC(dateStr: string) {
  if (!dateStr) return null
  const d = new Date(dateStr + 'T00:00:00Z')
  d.setUTCDate(d.getUTCDate() + 1)
  return d.toISOString()
}
