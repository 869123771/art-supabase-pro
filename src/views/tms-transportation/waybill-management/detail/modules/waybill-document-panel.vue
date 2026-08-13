<template>
  <div class="waybill-document-panel">
    <section class="waybill-document-panel__section art-card-xs">
      <div class="waybill-document-panel__heading">
        <div>
          <ArtSectionTitle title="单证影像中心" />
          <p>汇总订单附件、装卸照片、磅单、回单与签名，按来源统一归档。</p>
        </div>
        <div class="waybill-document-panel__heading-meta">
          <strong>{{ documents.length }}</strong>
          <span>份归档资料</span>
        </div>
      </div>

      <div class="waybill-document-panel__summary">
        <button
          v-for="item in categorySummary"
          :key="item.value"
          type="button"
          :class="{ 'is-active': activeCategory === item.value }"
          @click="activeCategory = item.value"
        >
          <span :class="`is-${item.tone}`">
            <ArtSvgIcon :icon="item.icon" aria-hidden="true" />
          </span>
          <div
            ><strong>{{ item.count }}</strong
            ><small>{{ item.label }}</small></div
          >
        </button>
      </div>
    </section>

    <section class="waybill-document-panel__section art-card-xs">
      <div class="waybill-document-panel__toolbar">
        <ElSegmented v-model="activeCategory" :options="filterOptions" />
        <span>当前显示 {{ filteredDocuments.length }} 份</span>
      </div>

      <div v-if="filteredDocuments.length" class="waybill-document-panel__gallery">
        <article v-for="(document, index) in filteredDocuments" :key="document.url">
          <div class="waybill-document-panel__preview">
            <ElImage
              v-if="document.isImage"
              :src="document.url"
              :alt="document.name"
              width="320"
              height="184"
              fit="cover"
              loading="lazy"
              :preview-src-list="imageUrls"
              :initial-index="imageUrls.indexOf(document.url)"
              preview-teleported
            >
              <template #error>
                <div class="waybill-document-panel__image-error">
                  <ArtSvgIcon icon="ri:image-off-line" aria-hidden="true" />
                  <span>图片加载失败</span>
                </div>
              </template>
            </ElImage>
            <div v-else class="waybill-document-panel__file-preview">
              <ArtSvgIcon :icon="fileIcon(document.mimeType)" aria-hidden="true" />
              <span>{{ fileExtension(document.name) }}</span>
            </div>
            <ElTag class="waybill-document-panel__category" size="small" effect="dark">
              {{ document.categoryLabel }}
            </ElTag>
            <span class="waybill-document-panel__index">{{ index + 1 }}</span>
          </div>
          <div class="waybill-document-panel__file-info">
            <div>
              <strong :title="document.name">{{ document.name }}</strong>
              <ElLink
                :href="document.url"
                target="_blank"
                rel="noopener noreferrer"
                type="primary"
                underline="never"
                aria-label="在新窗口打开文件"
              >
                <ArtSvgIcon icon="ri:external-link-line" aria-hidden="true" />
              </ElLink>
            </div>
            <dl>
              <div
                ><dt>来源</dt><dd>{{ document.source }}</dd></div
              >
              <div
                ><dt>上传人</dt><dd>{{ document.uploader || '-' }}</dd></div
              >
              <div
                ><dt>归档时间</dt><dd>{{ date(document.time) }}</dd></div
              >
              <div
                ><dt>文件大小</dt><dd>{{ size(document.fileSize) }}</dd></div
              >
            </dl>
            <p v-if="document.remark">{{ document.remark }}</p>
          </div>
        </article>
      </div>

      <ArtEmptyState
        v-else
        :title="activeCategory === 'all' ? '暂无单证影像' : '该分类暂无资料'"
        description="司机上传现场照片、磅单、回单或签名后，将自动汇总到这里。"
        size="compact"
        :visual-size="88"
      />
    </section>

    <section class="waybill-document-panel__section art-card-xs">
      <ArtSectionTitle title="归档覆盖" />
      <div class="waybill-document-panel__coverage">
        <article v-for="item in coverageItems" :key="item.label">
          <span :class="{ 'is-covered': item.count > 0 }">
            <ArtSvgIcon
              :icon="item.count > 0 ? 'ri:check-line' : 'ri:subtract-line'"
              aria-hidden="true"
            />
          </span>
          <div>
            <strong>{{ item.label }}</strong>
            <small>{{ item.count > 0 ? `已归档 ${item.count} 份` : item.emptyText }}</small>
          </div>
        </article>
      </div>
    </section>
  </div>
</template>

<script setup lang="ts">
  import { uniqBy } from 'lodash-es'
  import ArtEmptyState from '@/components/core/layouts/art-empty-state/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import { formatWithDayjs } from '@/utils/time'

  defineOptions({ name: 'TmsWaybillDocumentPanel' })

  type DocumentCategory = 'all' | 'order' | 'loading' | 'unloading' | 'receipt' | 'execution'

  interface WaybillDocument {
    url: string
    name: string
    category: Exclude<DocumentCategory, 'all'>
    categoryLabel: string
    source: string
    uploader?: string | null
    time?: string | null
    fileSize?: number | null
    mimeType?: string | null
    remark?: string | null
    isImage: boolean
  }

  const props = defineProps<{ waybill: Api.Tms.Waybill.WaybillDetailRecord }>()
  const activeCategory = ref<DocumentCategory>('all')

  const documents = computed<WaybillDocument[]>(() =>
    uniqBy(
      [
        ...proofDocuments(),
        ...urlDocuments(props.waybill.pickupPhotos, 'loading', '装货凭证', '运单装货附件'),
        ...urlDocuments(props.waybill.deliveryPhotos, 'unloading', '卸货凭证', '运单卸货附件'),
        ...urlDocuments(props.waybill.receiptAttachments, 'receipt', '回单签收', '运单回单'),
        ...urlDocuments(props.waybill.order?.imageUrls, 'order', '订单附件', '关联订单'),
        ...urlDocuments(
          props.waybill.order?.receiptImageUrls,
          'receipt',
          '回单签收',
          '订单签收回单'
        ),
        ...operationDocuments(),
        ...executionDocuments()
      ],
      (item) => item.url
    )
  )

  const filteredDocuments = computed(() =>
    activeCategory.value === 'all'
      ? documents.value
      : documents.value.filter((item) => item.category === activeCategory.value)
  )
  const imageUrls = computed(() =>
    documents.value.filter((item) => item.isImage).map((item) => item.url)
  )

  const categorySummary = computed(() => [
    {
      label: '全部资料',
      value: 'all' as const,
      count: documents.value.length,
      icon: 'ri:folder-5-line',
      tone: 'primary'
    },
    {
      label: '装货凭证',
      value: 'loading' as const,
      count: countCategory('loading'),
      icon: 'ri:archive-stack-line',
      tone: 'warning'
    },
    {
      label: '卸货凭证',
      value: 'unloading' as const,
      count: countCategory('unloading'),
      icon: 'ri:inbox-unarchive-line',
      tone: 'success'
    },
    {
      label: '回单签收',
      value: 'receipt' as const,
      count: countCategory('receipt'),
      icon: 'ri:quill-pen-line',
      tone: 'info'
    },
    {
      label: '订单附件',
      value: 'order' as const,
      count: countCategory('order'),
      icon: 'ri:file-list-3-line',
      tone: 'primary'
    },
    {
      label: '司机执行',
      value: 'execution' as const,
      count: countCategory('execution'),
      icon: 'ri:smartphone-line',
      tone: 'info'
    }
  ])

  const filterOptions = computed(() => [
    { label: '全部', value: 'all' },
    { label: `订单附件 ${countCategory('order')}`, value: 'order' },
    { label: `装货 ${countCategory('loading')}`, value: 'loading' },
    { label: `卸货 ${countCategory('unloading')}`, value: 'unloading' },
    { label: `回单签收 ${countCategory('receipt')}`, value: 'receipt' },
    { label: `司机执行 ${countCategory('execution')}`, value: 'execution' }
  ])

  const coverageItems = computed(() => [
    { label: '订单原始附件', count: countCategory('order'), emptyText: '未上传订单原始附件' },
    { label: '装货现场凭证', count: countCategory('loading'), emptyText: '未归档装货照片或磅单' },
    { label: '卸货现场凭证', count: countCategory('unloading'), emptyText: '未归档卸货照片或磅单' },
    { label: '回单与签名', count: countCategory('receipt'), emptyText: '未归档回单或电子签名' },
    { label: '司机执行影像', count: countCategory('execution'), emptyText: '未归档发车或回场影像' }
  ])

  function proofDocuments(): WaybillDocument[] {
    return props.waybill.proofs.map((proof) => {
      const category = proofCategory(proof.proofType)
      return createDocument(proof.fileUrl, {
        name: proof.fileName,
        category,
        source: '运单凭证库',
        uploader: proof.uploaderName,
        time: proof.uploadedAt,
        fileSize: proof.fileSize,
        mimeType: proof.mimeType,
        remark: proof.remark
      })
    })
  }

  function operationDocuments(): WaybillDocument[] {
    return props.waybill.cargoOperations.flatMap((operation) => {
      const category = operation.operationType
      const title = category === 'loading' ? '装货' : '卸货'
      return [
        ...urlDocuments(
          operation.photoUrls,
          category,
          `${title}凭证`,
          `${title}作业现场`,
          operation
        ),
        ...urlDocuments(
          operation.weighbridgeTicketUrls,
          category,
          `${title}磅单`,
          `${title}称重`,
          operation
        )
      ]
    })
  }

  function executionDocuments(): WaybillDocument[] {
    const record = props.waybill.execution
    if (!record) return []
    return [
      ...urlDocuments(record.departurePhotoUrls, 'execution', '司机执行', '发车影像', {
        operatorName: record.departureOperatorName,
        completedAt: record.departureRecordedAt,
        remark: record.departureRemark
      }),
      ...urlDocuments(record.receiptUrls, 'receipt', '回单签收', '司机签收回单', {
        operatorName: record.signatureOperatorName,
        completedAt: record.signatureRecordedAt,
        remark: record.signatureRemark
      }),
      ...urlDocuments(record.signatureUrls, 'receipt', '回单签收', '电子签名', {
        operatorName: record.signatureOperatorName,
        completedAt: record.signatureRecordedAt,
        remark: record.signatureRemark
      }),
      ...urlDocuments(record.returnPhotoUrls, 'execution', '司机执行', '回场影像', {
        operatorName: record.completionOperatorName,
        completedAt: record.completionRecordedAt,
        remark: record.completionRemark
      })
    ]
  }

  function urlDocuments(
    urls: string[] | null | undefined,
    category: Exclude<DocumentCategory, 'all'>,
    categoryLabel: string,
    source: string,
    meta?: { operatorName?: string | null; completedAt?: string | null; remark?: string | null }
  ): WaybillDocument[] {
    return (urls ?? []).map((url) =>
      createDocument(url, {
        category,
        categoryLabel,
        source,
        uploader: meta?.operatorName,
        time: meta?.completedAt,
        remark: meta?.remark
      })
    )
  }

  function createDocument(
    url: string,
    meta: Partial<Omit<WaybillDocument, 'url' | 'name' | 'isImage'>> & { name?: string | null }
  ): WaybillDocument {
    const mimeType = meta.mimeType || null
    const category = meta.category ?? 'order'
    const name = meta.name || filename(url)
    return {
      url,
      name,
      category,
      categoryLabel: meta.categoryLabel || categoryLabel(category),
      source: meta.source || '运单附件',
      uploader: meta.uploader,
      time: meta.time,
      fileSize: meta.fileSize,
      mimeType,
      remark: meta.remark,
      isImage:
        Boolean(mimeType?.startsWith('image/')) || /\.(avif|gif|jpe?g|png|webp)(\?|$)/i.test(url)
    }
  }

  function proofCategory(type: string): Exclude<DocumentCategory, 'all'> {
    if (/pickup|loading|load_/i.test(type)) return 'loading'
    if (/delivery|unload/i.test(type)) return 'unloading'
    if (/receipt|signature|signed/i.test(type)) return 'receipt'
    return 'execution'
  }

  function categoryLabel(category: Exclude<DocumentCategory, 'all'>): string {
    return {
      order: '订单附件',
      loading: '装货凭证',
      unloading: '卸货凭证',
      receipt: '回单签收',
      execution: '司机执行'
    }[category]
  }

  function countCategory(category: Exclude<DocumentCategory, 'all'>): number {
    return documents.value.filter((item) => item.category === category).length
  }

  function filename(url: string): string {
    const raw = url.split('?')[0]?.split('/').at(-1) || '未命名附件'
    try {
      return decodeURIComponent(raw)
    } catch {
      return raw
    }
  }

  function fileExtension(name: string): string {
    return name.includes('.') ? name.split('.').at(-1)?.toUpperCase() || 'FILE' : 'FILE'
  }

  function fileIcon(mimeType?: string | null): string {
    if (mimeType?.includes('pdf')) return 'ri:file-pdf-2-line'
    if (mimeType?.includes('sheet') || mimeType?.includes('excel')) return 'ri:file-excel-2-line'
    return 'ri:file-3-line'
  }

  function size(value?: number | null): string {
    if (value == null) return '-'
    if (value < 1024) return `${value} B`
    if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`
    return `${(value / 1024 / 1024).toFixed(1)} MB`
  }

  function date(value?: string | null): string {
    return formatWithDayjs(value, 'YYYY-MM-DD HH:mm') || '-'
  }
</script>

<style scoped lang="scss">
  .waybill-document-panel {
    display: grid;
    gap: var(--art-space-3);

    &__section {
      min-width: 0;
      padding: var(--art-section-padding);
    }

    &__heading {
      display: flex;
      gap: var(--art-space-4);
      align-items: flex-start;
      justify-content: space-between;

      p {
        margin: -8px 0 0;
        color: var(--el-text-color-secondary);
      }
    }

    &__heading-meta {
      display: grid;
      flex: none;
      place-items: end;

      strong {
        font-size: 24px;
        color: var(--el-color-primary);
      }

      span {
        color: var(--el-text-color-secondary);
      }
    }

    &__summary {
      display: grid;
      grid-template-columns: repeat(6, minmax(0, 1fr));
      gap: var(--art-space-3);
      margin-top: var(--art-space-4);

      button {
        display: flex;
        gap: var(--art-space-3);
        align-items: center;
        min-width: 0;
        padding: var(--art-space-3);
        color: inherit;
        text-align: left;
        cursor: pointer;
        background: var(--el-fill-color-lighter);
        border: 1px solid transparent;
        border-radius: var(--el-border-radius-base);
        transition:
          border-color 0.2s ease,
          background-color 0.2s ease;

        &:hover,
        &.is-active {
          background: var(--el-color-primary-light-9);
          border-color: var(--el-color-primary-light-7);
        }

        > span {
          display: grid;
          flex: none;
          place-items: center;
          width: 38px;
          height: 38px;
          color: var(--el-color-primary);
          background: var(--el-color-primary-light-9);
          border-radius: var(--el-border-radius-base);

          &.is-success {
            color: var(--el-color-success);
            background: var(--el-color-success-light-9);
          }

          &.is-warning {
            color: var(--el-color-warning);
            background: var(--el-color-warning-light-9);
          }

          &.is-info {
            color: var(--el-color-info);
            background: var(--el-color-info-light-9);
          }
        }

        > div {
          display: grid;
          gap: 2px;
          min-width: 0;
        }

        strong {
          font-size: 18px;
        }

        small {
          overflow: hidden;
          text-overflow: ellipsis;
          color: var(--el-text-color-secondary);
          white-space: nowrap;
        }
      }
    }

    &__toolbar {
      display: flex;
      gap: var(--art-space-3);
      align-items: center;
      justify-content: space-between;
      padding-bottom: var(--art-space-4);
      overflow-x: auto;

      > span {
        flex: none;
        color: var(--el-text-color-secondary);
      }
    }

    &__gallery {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: var(--art-space-3);

      > article {
        min-width: 0;
        overflow: hidden;
        background: var(--el-bg-color);
        border: 1px solid var(--el-border-color-lighter);
        border-radius: var(--el-border-radius-base);
        transition:
          box-shadow 0.2s ease,
          transform 0.2s ease;

        &:hover {
          box-shadow: var(--el-box-shadow-light);
          transform: translateY(-2px);
        }
      }
    }

    &__preview {
      position: relative;
      aspect-ratio: 16 / 9;
      overflow: hidden;
      background: var(--el-fill-color-lighter);

      :deep(.el-image) {
        width: 100%;
        height: 100%;
      }
    }

    &__image-error,
    &__file-preview {
      display: grid;
      gap: var(--art-space-2);
      place-items: center;
      width: 100%;
      height: 100%;
      color: var(--el-text-color-secondary);

      .art-svg-icon {
        font-size: 32px;
      }
    }

    &__category,
    &__index {
      position: absolute;
      top: var(--art-space-2);
    }

    &__category {
      left: var(--art-space-2);
    }

    &__index {
      right: var(--art-space-2);
      display: grid;
      place-items: center;
      min-width: 24px;
      height: 24px;
      padding: 0 6px;
      color: white;
      background: rgb(0 0 0 / 45%);
      border-radius: 999px;
    }

    &__file-info {
      display: grid;
      gap: var(--art-space-3);
      padding: var(--art-space-3);

      > div:first-child {
        display: flex;
        gap: var(--art-space-2);
        align-items: center;

        strong {
          flex: 1;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      }

      dl {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: var(--art-space-2);
        margin: 0;
      }

      dl > div {
        display: grid;
        gap: 2px;
      }

      dt {
        color: var(--el-text-color-secondary);
      }

      dd,
      p {
        margin: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      p {
        padding-top: var(--art-space-2);
        color: var(--el-text-color-secondary);
        border-top: 1px dashed var(--el-border-color-lighter);
      }
    }

    &__coverage {
      display: grid;
      grid-template-columns: repeat(5, minmax(0, 1fr));
      gap: var(--art-space-3);

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

        &.is-covered {
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

  @media (width <= 1200px) {
    .waybill-document-panel {
      &__summary,
      &__coverage {
        grid-template-columns: repeat(3, minmax(0, 1fr));
      }

      &__gallery {
        grid-template-columns: repeat(3, minmax(0, 1fr));
      }
    }
  }

  @media (width <= 900px) {
    .waybill-document-panel {
      &__gallery {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
    }
  }

  @media (width <= 640px) {
    .waybill-document-panel {
      &__heading {
        flex-direction: column;
      }

      &__heading-meta {
        place-items: start;
      }

      &__summary,
      &__coverage,
      &__gallery {
        grid-template-columns: 1fr;
      }

      &__toolbar {
        flex-direction: column;
        align-items: flex-start;
      }
    }
  }
</style>
