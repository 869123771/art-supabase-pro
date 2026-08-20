<template>
  <div class="waybill-operation-panel">
    <section class="waybill-operation-panel__section art-card-xs">
      <ArtSectionTitle title="装卸作业" />
      <div class="waybill-operation-panel__operation-grid">
        <article v-for="card in operationCards" :key="card.type" :class="`is-${card.type}`">
          <div class="waybill-operation-panel__card-heading">
            <span class="waybill-operation-panel__card-icon">
              <ArtSvgIcon :icon="card.icon" aria-hidden="true" />
            </span>
            <div>
              <strong>{{ card.title }}</strong>
              <small>{{ card.description }}</small>
            </div>
            <ElTag :type="card.record ? 'success' : 'info'" effect="light" size="small">
              {{ card.record ? operationStatus(card.record.operationStatus) : '待记录' }}
            </ElTag>
          </div>

          <template v-if="card.record">
            <dl class="waybill-operation-panel__detail-grid">
              <div
                ><dt>签到时间</dt><dd>{{ date(card.record.checkinTime) }}</dd></div
              >
              <div
                ><dt>完成时间</dt><dd>{{ date(card.record.completedAt) }}</dd></div
              >
              <div
                ><dt>操作人</dt><dd>{{ card.record.operatorName || '-' }}</dd></div
              >
              <div
                ><dt>签到方式</dt><dd>{{ checkinMode(card.record.checkinMode) }}</dd></div
              >
              <div
                ><dt>作业净重</dt><dd>{{ weight(card.record.weightTon) }}</dd></div
              >
              <div v-if="canView('routeCoordinates')"
                ><dt>定位精度</dt><dd>{{ distance(card.record.locationAccuracyM) }}</dd></div
              >
              <div v-if="canView('routeCoordinates')"
                ><dt>围栏距离</dt><dd>{{ distance(card.record.distanceM) }}</dd></div
              >
              <div v-if="canView('routeCoordinates')">
                <dt>电子围栏</dt>
                <dd>
                  <ElTag :type="card.record.insideGeofence ? 'success' : 'warning'" size="small">
                    {{ card.record.insideGeofence ? '围栏内' : '围栏外' }}
                  </ElTag>
                </dd>
              </div>
            </dl>
            <div v-if="canView('routeCoordinates')" class="waybill-operation-panel__location">
              <ArtSvgIcon icon="ri:map-pin-line" aria-hidden="true" />
              <div>
                <strong>{{ card.record.locationText || '未记录位置名称' }}</strong>
                <small>
                  {{ coordinates(card.record.longitude, card.record.latitude) }} · 围栏半径
                  {{ distance(card.record.geofenceRadiusM) }}
                </small>
              </div>
            </div>
            <div
              v-if="card.record.outsideReason || card.record.remark"
              class="waybill-operation-panel__note"
            >
              <span>作业说明</span>
              <p>{{ card.record.outsideReason || card.record.remark }}</p>
            </div>
            <div v-if="canView('proofAttachments')" class="waybill-operation-panel__evidence">
              <span>现场照片 {{ card.record.photoUrls?.length ?? 0 }} 份</span>
              <span>磅单 {{ card.record.weighbridgeTicketUrls?.length ?? 0 }} 份</span>
            </div>
          </template>

          <div v-else class="waybill-operation-panel__operation-empty">
            <div class="waybill-operation-panel__empty-message">
              <span><ArtSvgIcon icon="ri:route-line" aria-hidden="true" /></span>
              <div>
                <strong>{{
                  card.fallbackTime ? '流程已完成，作业档案待归集' : `${card.title}等待执行`
                }}</strong>
                <p>{{ operationEmptyDescription(card.fallbackTime) }}</p>
              </div>
            </div>
            <ul aria-label="待归档内容">
              <li v-if="canView('routeCoordinates')"
                ><ArtSvgIcon icon="ri:map-pin-line" aria-hidden="true" />围栏签到</li
              >
              <li><ArtSvgIcon icon="ri:scales-3-line" aria-hidden="true" />作业重量</li>
              <li v-if="canView('proofAttachments')"
                ><ArtSvgIcon icon="ri:camera-line" aria-hidden="true" />照片与磅单</li
              >
            </ul>
          </div>
        </article>
      </div>
    </section>

    <section class="waybill-operation-panel__section art-card-xs">
      <ArtSectionTitle title="司机执行记录" />
      <ElAlert
        v-if="returnArchiveMismatch"
        class="waybill-operation-panel__archive-alert"
        type="warning"
        :closable="false"
        show-icon
        title="运单已显示完成，但回场档案缺失。请由原司机或具备完成权限的调度人员补录回场时间、里程和照片。"
      />
      <div v-if="waybill.execution" class="waybill-operation-panel__execution-grid">
        <article v-for="stage in executionStages" :key="stage.key">
          <div class="waybill-operation-panel__stage-icon">
            <ArtSvgIcon :icon="stage.icon" aria-hidden="true" />
          </div>
          <div class="waybill-operation-panel__stage-content">
            <div>
              <strong>{{ stage.title }}</strong>
              <ElTag
                :type="stage.time ? 'success' : stage.key === 'return' ? 'warning' : 'info'"
                size="small"
              >
                {{ stage.time ? '已记录' : '待补录' }}
              </ElTag>
            </div>
            <dl>
              <div
                ><dt>业务时间</dt><dd>{{ date(stage.time) }}</dd></div
              >
              <div
                ><dt>记录时间</dt><dd>{{ date(stage.recordedAt) }}</dd></div
              >
              <div
                ><dt>操作人</dt><dd>{{ stage.operator || '-' }}</dd></div
              >
              <div
                ><dt>{{ stage.metricLabel }}</dt
                ><dd>{{ stage.metric }}</dd></div
              >
            </dl>
            <p>{{ stage.remark || '无补充说明' }}</p>
            <small>关联影像 {{ stage.imageCount }} 份</small>
          </div>
        </article>
      </div>
      <ArtEmptyState
        v-else
        title="暂无结构化司机执行记录"
        description="关键节点仍可在“全程跟踪”中查看；发车里程、签收人、回场里程等扩展字段尚未录入。"
        size="compact"
        :visual-size="72"
      />
    </section>

    <section class="waybill-operation-panel__section art-card-xs">
      <ArtSectionTitle title="作业数据完整性" />
      <div class="waybill-operation-panel__integrity-grid">
        <article v-for="item in integrityItems" :key="item.label">
          <span :class="{ 'is-complete': item.complete }">
            <ArtSvgIcon
              :icon="item.complete ? 'ri:check-line' : 'ri:information-line'"
              aria-hidden="true"
            />
          </span>
          <div
            ><strong>{{ item.label }}</strong
            ><small>{{ item.description }}</small></div
          >
        </article>
      </div>
    </section>
  </div>
</template>

<script setup lang="ts">
  import ArtEmptyState from '@/components/core/layouts/art-empty-state/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import { formatWithDayjs } from '@/utils/time'
  import { canViewField } from '@/utils/field-permission'

  defineOptions({ name: 'TmsWaybillOperationPanel' })

  type OperationType = Api.Tms.Waybill.CargoOperationType
  const props = defineProps<{ waybill: Api.Tms.Waybill.WaybillDetailRecord }>()

  const operationCards = computed(() =>
    [
      {
        type: 'loading' as const,
        title: '装货作业',
        description: '装货签到、围栏、称重与现场凭证',
        icon: 'ri:archive-stack-line',
        fallbackTime: props.waybill.loadedAt
      },
      {
        type: 'unloading' as const,
        title: '卸货作业',
        description: '卸货签到、围栏、称重与现场凭证',
        icon: 'ri:inbox-unarchive-line',
        fallbackTime: props.waybill.unloadedAt
      }
    ].map((item) => ({ ...item, record: findOperation(item.type) }))
  )

  const executionStages = computed(() => {
    const record = props.waybill.execution
    if (!record) return []
    return [
      {
        key: 'departure',
        title: '发车记录',
        icon: 'ri:truck-line',
        time: record.departureTime,
        recordedAt: record.departureRecordedAt,
        operator: record.departureOperatorName,
        metricLabel: '发车里程',
        metric: odometer(record.departureOdometerKm),
        remark: record.departureRemark,
        imageCount: record.departurePhotoUrls.length
      },
      {
        key: 'signature',
        title: '签收记录',
        icon: 'ri:quill-pen-line',
        time: record.signedAt,
        recordedAt: record.signatureRecordedAt,
        operator: record.signatureOperatorName,
        metricLabel: '签收人',
        metric: record.signerName || '-',
        remark: record.signatureRemark,
        imageCount: record.receiptUrls.length + record.signatureUrls.length
      },
      {
        key: 'return',
        title: '回场记录',
        icon: 'ri:home-gear-line',
        time: record.returnTime,
        recordedAt: record.completionRecordedAt,
        operator: record.completionOperatorName,
        metricLabel: '回场里程',
        metric: odometer(record.returnOdometerKm),
        remark: record.completionRemark,
        imageCount: record.returnPhotoUrls.length
      }
    ]
  })

  const executionArchiveComplete = computed(() => {
    const record = props.waybill.execution
    return Boolean(
      record?.departureTime &&
      record.departureOdometerKm != null &&
      record.departurePhotoUrls.length &&
      record.signedAt &&
      record.signerName &&
      record.receiptUrls.length &&
      record.signatureUrls.length &&
      record.returnTime &&
      record.returnOdometerKm != null &&
      record.returnPhotoUrls.length &&
      record.completionRecordedAt
    )
  })

  const returnArchiveMismatch = computed(
    () => props.waybill.status === 'completed' && !executionArchiveComplete.value
  )

  const integrityItems = computed(() => [
    {
      label: '装货作业档案',
      complete: Boolean(findOperation('loading')),
      description: findOperation('loading')
        ? '签到与称重信息已归档'
        : '流程节点存在，结构化作业记录待补齐'
    },
    {
      label: '卸货作业档案',
      complete: Boolean(findOperation('unloading')),
      description: findOperation('unloading')
        ? '签到与称重信息已归档'
        : '流程节点存在，结构化作业记录待补齐'
    },
    {
      label: '司机执行档案',
      complete: executionArchiveComplete.value,
      description: executionArchiveComplete.value
        ? '发车、签收、回场与里程字段均已归档'
        : '发车、签收或回场档案仍有缺失，请按节点补齐'
    },
    {
      label: '流程事件审计',
      complete: props.waybill.events.length > 0,
      description: `已记录 ${props.waybill.events.length} 条全流程事件`
    }
  ])

  function findOperation(type: OperationType): Api.Tms.Waybill.CargoOperationRecord | undefined {
    return props.waybill.cargoOperations.find((item) => item.operationType === type)
  }

  function operationStatus(status: Api.Tms.Waybill.CargoOperationStatus): string {
    return status === 'completed' ? '已完成' : '已签到'
  }

  function operationEmptyDescription(fallbackTime?: string | null): string {
    return fallbackTime
      ? `${date(fallbackTime)} 完成业务节点，结构化现场数据尚未归档。`
      : '司机完成现场作业后，签到、称重和影像将在此同步呈现。'
  }

  function checkinMode(mode: Api.Tms.Waybill.CargoOperationCheckinMode): string {
    return { manual: '手动签到', automatic: '自动签到', admin: '后台补录' }[mode]
  }

  function coordinates(longitude: number, latitude: number): string {
    return `${longitude.toFixed(6)}, ${latitude.toFixed(6)}`
  }

  function distance(value?: number | null): string {
    return value == null ? '-' : `${value} m`
  }

  function weight(value?: number | null): string {
    return value == null ? '-' : `${value} t`
  }

  function odometer(value?: number | null): string {
    return value == null ? '-' : `${value} km`
  }

  function date(value?: string | null): string {
    return formatWithDayjs(value, 'YYYY-MM-DD HH:mm') || '-'
  }

  function canView(field: Api.Tms.Waybill.WaybillFieldKey): boolean {
    return canViewField(props.waybill.fieldAccess, field)
  }
</script>

<style scoped lang="scss">
  .waybill-operation-panel {
    display: grid;
    gap: var(--art-space-3);

    &__section {
      min-width: 0;
      padding: var(--art-section-padding);
    }

    &__archive-alert {
      margin-bottom: var(--art-space-3);
    }

    &__operation-grid,
    &__execution-grid,
    &__integrity-grid {
      display: grid;
      gap: var(--art-space-3);
    }

    &__operation-grid {
      grid-template-columns: repeat(2, minmax(0, 1fr));

      > article {
        display: flex;
        flex-direction: column;
        min-width: 0;
        padding: var(--art-space-4);
        background: linear-gradient(145deg, var(--el-fill-color-lighter), var(--el-bg-color));
        border: 1px solid var(--el-border-color-lighter);
        border-top: 3px solid var(--el-color-primary);
        border-radius: var(--el-border-radius-base);

        &.is-unloading {
          border-top-color: var(--el-color-success);
        }

        &.is-unloading .waybill-operation-panel__card-icon {
          color: var(--el-color-success);
          background: var(--el-color-success-light-9);
        }
      }
    }

    &__card-heading {
      display: flex;
      gap: var(--art-space-3);
      align-items: center;

      > div {
        display: grid;
        flex: 1;
        gap: 3px;
        min-width: 0;
      }

      small {
        color: var(--el-text-color-secondary);
        overflow-wrap: anywhere;
      }

      .el-tag {
        flex: none;
        max-width: 88px;
        font-size: var(--art-font-size-caption);
        font-weight: 400;
      }
    }

    &__card-icon {
      display: grid;
      flex: none;
      place-items: center;
      width: 42px;
      height: 42px;
      font-size: 20px;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: var(--el-border-radius-base);
    }

    &__operation-empty {
      display: grid;
      gap: var(--art-space-4);
      padding: var(--art-space-4);
      margin-top: var(--art-space-4);
      background: var(--el-bg-color);
      border: 1px dashed var(--el-border-color);
      border-radius: var(--el-border-radius-base);

      ul {
        display: flex;
        flex-wrap: wrap;
        gap: var(--art-space-2);
        padding: 0;
        margin: 0;
        list-style: none;
      }

      li {
        display: inline-flex;
        gap: 5px;
        align-items: center;
        padding: 5px 9px;
        font-size: 12px;
        color: var(--el-text-color-secondary);
        background: var(--el-fill-color-lighter);
        border-radius: 999px;
      }
    }

    &__empty-message {
      display: flex;
      gap: var(--art-space-3);
      align-items: center;

      > span {
        display: grid;
        flex: none;
        place-items: center;
        width: 40px;
        height: 40px;
        font-size: 18px;
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
        border-radius: 50%;
      }

      > div {
        display: grid;
        gap: 4px;
        min-width: 0;
      }

      p {
        margin: 0;
        color: var(--el-text-color-secondary);
        overflow-wrap: anywhere;
      }
    }

    .is-unloading &__empty-message > span {
      color: var(--el-color-success);
      background: var(--el-color-success-light-9);
    }

    &__detail-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: var(--art-space-3) var(--art-space-4);
      margin: var(--art-space-4) 0;

      > div {
        display: grid;
        gap: 4px;
      }

      dt {
        color: var(--el-text-color-secondary);
      }

      dd {
        margin: 0;
      }
    }

    &__location {
      display: flex;
      gap: var(--art-space-3);
      align-items: flex-start;
      padding: var(--art-space-3);
      background: var(--el-bg-color);
      border-radius: var(--el-border-radius-base);

      > .art-svg-icon {
        flex: none;
        margin-top: 2px;
        color: var(--el-color-primary);
      }

      > div {
        display: grid;
        gap: 4px;
        min-width: 0;
      }

      small {
        color: var(--el-text-color-secondary);
        overflow-wrap: anywhere;
      }
    }

    &__note {
      display: grid;
      grid-template-columns: 72px minmax(0, 1fr);
      gap: var(--art-space-3);
      margin-top: var(--art-space-3);

      span {
        color: var(--el-text-color-secondary);
      }

      p {
        margin: 0;
        overflow-wrap: anywhere;
      }
    }

    &__evidence {
      display: flex;
      flex-wrap: wrap;
      gap: var(--art-space-2);
      margin-top: var(--art-space-3);

      span {
        padding: 4px 10px;
        color: var(--el-text-color-secondary);
        background: var(--el-bg-color);
        border-radius: 999px;
      }
    }

    &__execution-grid {
      grid-template-columns: repeat(3, minmax(0, 1fr));

      > article {
        display: flex;
        gap: var(--art-space-3);
        min-width: 0;
        padding: var(--art-space-4);
        border: 1px solid var(--el-border-color-lighter);
        border-radius: var(--el-border-radius-base);
      }
    }

    &__stage-icon {
      display: grid;
      flex: none;
      place-items: center;
      width: 38px;
      height: 38px;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: 50%;
    }

    &__stage-content {
      display: grid;
      flex: 1;
      gap: var(--art-space-3);
      min-width: 0;

      > div:first-child {
        display: flex;
        gap: var(--art-space-2);
        align-items: center;
        justify-content: space-between;
      }

      dl {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: var(--art-space-3);
        margin: 0;
      }

      dl > div {
        display: grid;
        gap: 3px;
      }

      dt,
      > small {
        color: var(--el-text-color-secondary);
      }

      dd,
      p {
        margin: 0;
      }
    }

    &__integrity-grid {
      grid-template-columns: repeat(4, minmax(0, 1fr));

      article {
        display: flex;
        gap: var(--art-space-3);
        align-items: flex-start;
        min-width: 0;
        padding: var(--art-space-3);
        background: var(--el-fill-color-lighter);
        border-radius: var(--el-border-radius-base);
      }

      article > span {
        display: grid;
        flex: none;
        place-items: center;
        width: 28px;
        height: 28px;
        color: var(--el-color-info);
        background: var(--el-color-info-light-9);
        border-radius: 50%;

        &.is-complete {
          color: var(--el-color-success);
          background: var(--el-color-success-light-9);
        }
      }

      article > div {
        display: grid;
        gap: 4px;
        min-width: 0;
      }

      small {
        color: var(--el-text-color-secondary);
      }
    }
  }

  @media (width <= 1100px) {
    .waybill-operation-panel {
      &__execution-grid,
      &__integrity-grid {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
    }
  }

  @media (width <= 768px) {
    .waybill-operation-panel {
      &__operation-grid,
      &__execution-grid,
      &__integrity-grid {
        grid-template-columns: 1fr;
      }
    }
  }

  @media (width <= 520px) {
    .waybill-operation-panel {
      &__card-heading {
        flex-wrap: wrap;

        .el-tag {
          margin-left: 54px;
        }
      }

      &__detail-grid,
      &__stage-content dl {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
