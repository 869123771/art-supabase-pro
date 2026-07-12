import { h, type VNodeChild } from 'vue'
import { ElTag } from 'element-plus'
import dayjs from 'dayjs'
import { isNil } from 'lodash-es'
import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
import { fetchCarrierOptions } from '@/api/tms'

type ReminderRow = Api.VehicleMgtSys.ReminderManage.VehicleReminderRow

export const companySearchItem: SearchFormItem = {
  label: '所属承运商',
  key: 'companyName',
  type: 'select',
  api: fetchCarrierOptions,
  resultField: 'data',
  labelField: 'companyName',
  valueField: 'companyName',
  labelFn: (option) => {
    const carrier = option as Api.Tms.BasicData.CarrierOption
    return carrier.carrierCode
      ? `${carrier.companyName}（${carrier.carrierCode}）`
      : carrier.companyName
  },
  props: {
    clearable: true,
    filterable: true,
    placeholder: '请选择承运商'
  }
}

export const futureReminderSearchItems: SearchFormItem[] = [
  companySearchItem,
  { label: '车牌号', key: 'plateNo', type: 'input' },
  {
    label: '未来到期天数',
    key: 'reminderDays',
    type: 'number',
    props: { min: 0, controls: false, placeholder: '全部' }
  }
]

export const formatDate = (value?: string | null): string =>
  value && dayjs(value).isValid() ? dayjs(value).format('YYYY-MM-DD') : '--'

export const formatMileage = (value?: number | null): string =>
  isNil(value) ? '--' : Number(value).toLocaleString()

export const renderRemainingDays = (days?: number | null): VNodeChild => {
  if (isNil(days)) return h(ElTag, { type: 'info', effect: 'plain' }, () => '未配置')
  if (days < 0)
    return h(ElTag, { type: 'danger', effect: 'light' }, () => `过期${Math.abs(days)}天`)
  if (days === 0) return h(ElTag, { type: 'danger', effect: 'light' }, () => '今日到期')
  if (days <= 30) return h(ElTag, { type: 'warning', effect: 'light' }, () => `${days}天`)
  if (days <= 90) return h(ElTag, { type: 'primary', effect: 'plain' }, () => `${days}天`)
  return h(ElTag, { type: 'success', effect: 'plain' }, () => `${days}天`)
}

export const renderReminderStatus = (row: ReminderRow): VNodeChild => {
  const days = row.remainingDays
  if (row.expired) return h(ElTag, { type: 'danger', effect: 'light' }, () => '已到期')
  if (isNil(days)) return h(ElTag, { type: 'info', effect: 'plain' }, () => '未配置')
  if (days < 0) return h(ElTag, { type: 'danger', effect: 'light' }, () => '已过期')
  if (days === 0) return h(ElTag, { type: 'danger', effect: 'light' }, () => '今日到期')
  if (days <= 30) return h(ElTag, { type: 'warning', effect: 'light' }, () => '临期')
  return h(ElTag, { type: 'success', effect: 'plain' }, () => '正常')
}
