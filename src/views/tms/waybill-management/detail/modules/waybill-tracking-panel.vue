<template>
  <section class="waybill-tracking art-card-xs">
    <div class="waybill-tracking__heading">
      <div>
        <ArtSectionTitle title="全流程跟踪" />
        <p>司机端、Web 端与系统节点统一按发生时间归档，历史记录只读展示。</p>
      </div>
      <ElTag type="info" effect="plain">共 {{ nodes.length }} 个节点</ElTag>
    </div>

    <ElScrollbar v-if="nodes.length" max-height="760px" always class="waybill-tracking__scrollbar">
      <ElTimeline class="waybill-tracking__timeline">
        <ElTimelineItem
          v-for="node in nodes"
          :key="node.id"
          :timestamp="formatDateTime(node.time)"
          placement="top"
          :type="node.tone"
          :hollow="node.tone === 'info'"
        >
          <article class="waybill-tracking__node">
            <header>
              <div class="waybill-tracking__title">
                <strong>{{ node.label }}</strong>
                <ElTag :type="node.sourceTone" effect="light" size="small">
                  {{ node.sourceLabel }}
                </ElTag>
              </div>
              <span
                ><ArtSvgIcon icon="ri:user-3-line" aria-hidden="true" />{{ node.operator }}</span
              >
            </header>

            <dl class="waybill-tracking__facts">
              <div v-if="node.location">
                <dt>操作地点</dt>
                <dd>{{ node.location }}</dd>
              </div>
              <div v-if="node.weight">
                <dt>作业重量</dt>
                <dd>{{ node.weight }}</dd>
              </div>
              <div v-if="node.mileage">
                <dt>里程记录</dt>
                <dd>{{ node.mileage }}</dd>
              </div>
              <div v-if="node.geofence">
                <dt>围栏校验</dt>
                <dd>{{ node.geofence }}</dd>
              </div>
              <div v-if="node.signer">
                <dt>签收人</dt>
                <dd>{{ node.signer }}</dd>
              </div>
            </dl>

            <p v-if="node.remark" class="waybill-tracking__remark">{{ node.remark }}</p>

            <div v-if="node.images.length" class="waybill-tracking__evidence">
              <div class="waybill-tracking__evidence-title">
                <span><ArtSvgIcon icon="ri:image-line" aria-hidden="true" />现场凭证</span>
                <small>{{ node.images.length }} 张</small>
              </div>
              <div class="waybill-tracking__images">
                <ElImage
                  v-for="(image, index) in node.images"
                  :key="image"
                  :src="image"
                  :alt="`${node.label}现场凭证${index + 1}`"
                  fit="cover"
                  loading="lazy"
                  :preview-src-list="node.images"
                  :initial-index="index"
                  preview-teleported
                >
                  <template #error>
                    <div class="waybill-tracking__image-error">
                      <ArtSvgIcon icon="ri:image-off-line" aria-hidden="true" />
                      <span>图片加载失败</span>
                    </div>
                  </template>
                </ElImage>
              </div>
            </div>
          </article>
        </ElTimelineItem>
      </ElTimeline>
    </ElScrollbar>

    <ArtEmptyState
      v-else
      title="暂无运单跟踪记录"
      description="司机或调度完成接单、装货、发车、到达、签收等操作后，节点会显示在这里。"
      size="compact"
      :visual-size="88"
    />
  </section>
</template>

<script setup lang="ts">
  import type { TagProps, TimelineItemProps } from 'element-plus'
  import { compact, uniq } from 'lodash-es'
  import ArtEmptyState from '@/components/core/layouts/art-empty-state/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import { formatWithDayjs } from '@/utils/time'

  defineOptions({ name: 'TmsWaybillTrackingPanel' })

  interface TrackingNode {
    id: string
    label: string
    time: string
    operator: string
    sourceLabel: string
    sourceTone: TagProps['type']
    tone: TimelineItemProps['type']
    location: string
    weight: string
    mileage: string
    geofence: string
    signer: string
    remark: string
    images: string[]
  }

  const props = defineProps<{ waybill: Api.Tms.Waybill.WaybillDetailRecord }>()

  const eventLabelMap: Record<string, string> = {
    created: '运单创建',
    accepted: '确认接单',
    loading_checked_in: '装货签到',
    loaded: '完成装货',
    departed: '确认发车',
    arrived: '确认到达',
    unloaded: '完成卸货',
    signed: '确认签收',
    completed: '运单完成',
    cancelled: '运单取消',
    photo_uploaded: '上传凭证',
    status_changed: '状态变更'
  }

  const nodes = computed<TrackingNode[]>(() =>
    props.waybill.events.map((event) => {
      const source = getEventSource(event)
      const operation = findOperation(event.eventType)
      const images = getEventImages(event.eventType, operation)
      const tone = getNodeTone(event.eventType)
      return {
        id: event.id,
        label: eventLabelMap[event.eventType] || event.eventType || '运输节点',
        time: event.eventTime,
        operator: event.operatorName || event.createBy || '系统记录',
        sourceLabel: source === 'driver' ? '司机端' : source === 'web' ? 'Web 端' : '系统',
        sourceTone: source === 'driver' ? 'success' : source === 'web' ? 'primary' : 'info',
        tone,
        location: event.locationText || operation?.locationText || '',
        weight: getWeight(event, operation),
        mileage: getMileage(event),
        geofence: getGeofence(event, operation),
        signer: getText(event.payload.signerName),
        remark: event.remark || operation?.remark || '',
        images
      }
    })
  )

  function findOperation(eventType: string): Api.Tms.Waybill.CargoOperationRecord | undefined {
    const operationType = ['loading_checked_in', 'loaded'].includes(eventType)
      ? 'loading'
      : ['arrived', 'unloaded'].includes(eventType)
        ? 'unloading'
        : undefined
    return operationType
      ? props.waybill.cargoOperations.find((item) => item.operationType === operationType)
      : undefined
  }

  function getEventImages(
    eventType: string,
    operation?: Api.Tms.Waybill.CargoOperationRecord
  ): string[] {
    const proofTypes = ['loaded', 'loading_checked_in'].includes(eventType)
      ? ['pickup_photo']
      : ['arrived', 'unloaded'].includes(eventType)
        ? ['delivery_photo']
        : ['signed', 'completed'].includes(eventType)
          ? ['receipt']
          : []
    const proofUrls = props.waybill.proofs
      .filter((proof) => proofTypes.includes(proof.proofType))
      .map((proof) => proof.fileUrl)
    const execution = props.waybill.execution
    const executionUrls =
      eventType === 'departed'
        ? execution?.departurePhotoUrls
        : eventType === 'signed'
          ? [...(execution?.receiptUrls ?? []), ...(execution?.signatureUrls ?? [])]
          : eventType === 'completed'
            ? execution?.returnPhotoUrls
            : []
    const operationUrls = operation
      ? [...operation.photoUrls, ...operation.weighbridgeTicketUrls]
      : []
    return uniq(compact([...proofUrls, ...(executionUrls ?? []), ...operationUrls]))
  }

  function getWeight(
    event: Api.Tms.Waybill.WaybillEventRecord,
    operation?: Api.Tms.Waybill.CargoOperationRecord
  ): string {
    const value = operation?.weightTon ?? getNumber(event.payload.weightTon)
    return value == null ? '' : `${value} 吨`
  }

  function getMileage(event: Api.Tms.Waybill.WaybillEventRecord): string {
    const odometer = getNumber(event.payload.odometerKm)
    const returnOdometer = getNumber(event.payload.returnOdometerKm)
    const runningMileage = getNumber(event.payload.runningMileageKm)
    if (runningMileage != null)
      return `本次行驶 ${runningMileage} km · 收车 ${returnOdometer ?? '-'} km`
    if (odometer != null) return `发车里程 ${odometer} km`
    return ''
  }

  function getGeofence(
    event: Api.Tms.Waybill.WaybillEventRecord,
    operation?: Api.Tms.Waybill.CargoOperationRecord
  ): string {
    const inside = operation?.insideGeofence ?? getBoolean(event.payload.insideGeofence)
    if (inside == null) return ''
    const distance = operation?.distanceM ?? getNumber(event.payload.distanceM)
    return `${inside ? '围栏内' : '围栏外'}${distance == null ? '' : ` · 距中心 ${Math.round(distance)} m`}`
  }

  function getNodeTone(eventType: string): TimelineItemProps['type'] {
    if (eventType === 'cancelled') return 'danger'
    if (['completed', 'signed'].includes(eventType)) return 'success'
    if (['arrived', 'unloaded'].includes(eventType)) return 'warning'
    if (['created', 'status_changed'].includes(eventType)) return 'info'
    return 'primary'
  }

  function getText(value: unknown): string {
    return typeof value === 'string' ? value : ''
  }

  function getEventSource(event: Api.Tms.Waybill.WaybillEventRecord): string {
    const source = getText(event.payload.source)
    if (source) return source
    return event.operatorName && event.operatorName === props.waybill.driver?.driverName
      ? 'driver'
      : 'system'
  }

  function getNumber(value: unknown): number | null {
    const number = Number(value)
    return value !== null && value !== '' && Number.isFinite(number) ? number : null
  }

  function getBoolean(value: unknown): boolean | null {
    return typeof value === 'boolean' ? value : null
  }

  function formatDateTime(value: string): string {
    return formatWithDayjs(value, 'YYYY-MM-DD HH:mm:ss') || '-'
  }
</script>

<style scoped lang="scss">
  .waybill-tracking {
    min-width: 0;
    padding: var(--art-section-padding);

    &__heading {
      display: flex;
      gap: var(--art-space-4);
      align-items: flex-start;
      justify-content: space-between;

      p {
        margin: var(--art-space-1) 0 0;
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }
    }

    &__scrollbar {
      margin-top: var(--art-space-4);
    }

    &__timeline {
      padding: 4px 18px 0 4px;
    }

    &__node {
      min-width: 0;
      padding: var(--art-space-4);
      background: var(--el-fill-color-blank);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);

      header {
        display: flex;
        gap: var(--art-space-3);
        align-items: flex-start;
        justify-content: space-between;

        > span {
          display: inline-flex;
          gap: 5px;
          align-items: center;
          color: var(--el-text-color-secondary);
          white-space: nowrap;
        }
      }
    }

    &__title {
      display: flex;
      flex-wrap: wrap;
      gap: var(--art-space-2);
      align-items: center;

      strong {
        font-size: 15px;
        color: var(--el-text-color-primary);
      }
    }

    &__facts {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: var(--art-space-3);
      margin: var(--art-space-4) 0 0;

      > div {
        min-width: 0;
        padding: var(--art-space-3);
        background: var(--el-fill-color-lighter);
        border-radius: var(--el-border-radius-small);
      }

      dt {
        margin-bottom: 4px;
        font-size: 11px;
        color: var(--el-text-color-secondary);
      }

      dd {
        margin: 0;
        color: var(--el-text-color-regular);
        overflow-wrap: anywhere;
      }
    }

    &__remark {
      padding: var(--art-space-3);
      margin: var(--art-space-3) 0 0;
      line-height: 1.6;
      color: var(--el-text-color-regular);
      background: var(--el-color-warning-light-9);
      border-left: 3px solid var(--el-color-warning);
      border-radius: var(--el-border-radius-small);
    }

    &__evidence {
      margin-top: var(--art-space-4);
    }

    &__evidence-title {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: var(--art-space-2);

      span {
        display: inline-flex;
        gap: 6px;
        align-items: center;
        font-weight: 600;
      }

      small {
        color: var(--el-text-color-secondary);
      }
    }

    &__images {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(112px, 1fr));
      gap: var(--art-space-2);

      :deep(.el-image) {
        width: 100%;
        height: 108px;
        overflow: hidden;
        cursor: zoom-in;
        border: 1px solid var(--el-border-color-lighter);
        border-radius: var(--el-border-radius-small);
      }
    }

    &__image-error {
      display: grid;
      gap: 5px;
      place-items: center;
      align-content: center;
      width: 100%;
      height: 100%;
      font-size: 11px;
      color: var(--el-text-color-secondary);
      background: var(--el-fill-color-light);
    }

    :deep(.el-timeline-item__timestamp) {
      color: var(--el-text-color-secondary);
    }
  }

  @media (width <= 768px) {
    .waybill-tracking {
      &__heading,
      &__node header {
        align-items: flex-start;
      }

      &__facts {
        grid-template-columns: 1fr;
      }

      &__node header {
        flex-direction: column;
      }
    }
  }
</style>
