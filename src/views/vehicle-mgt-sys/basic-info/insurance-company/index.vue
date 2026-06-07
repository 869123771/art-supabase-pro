<template>
  <div class="art-full-height">
    <InsuranceCompanySearch
      v-show="showSearchBar"
      v-model="searchForm"
      @search="handleSearch"
      @reset="handleResetSearch"
    />

    <ElCard
      class="art-table-card"
      shadow="never"
      :style="{ marginTop: showSearchBar ? '12px' : '0' }"
    >
      <ArtTableHeader
        v-model:columns="columnChecks"
        v-model:show-search-bar="showSearchBar"
        :loading="loading"
        @refresh="refreshData"
      >
        <template #left>
          <ElButton type="primary" plain v-ripple @click="openDialog('add')">
            <ElIcon><Plus /></ElIcon>
            新增保险公司
          </ElButton>
        </template>
      </ArtTableHeader>

      <ArtTable
        row-key="id"
        table-layout="fixed"
        :loading="loading"
        :data="data"
        :columns="columns"
        :pagination="pagination"
        @pagination:size-change="handleSizeChange"
        @pagination:current-change="handleCurrentChange"
      />
    </ElCard>

    <InsuranceCompanyDialog ref="dialogRef" @success="handleSaveSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import { Plus } from '@element-plus/icons-vue'
  import { ElMessageBox } from 'element-plus'
  import { useTable } from '@/hooks/core/useTable'
  import type { ColumnOption } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import { deleteInsuranceCompany, fetchInsuranceCompanyList } from '@/api/vehicle-mgt-sys'
  import InsuranceCompanySearch from './modules/insurance-company-search.vue'
  import InsuranceCompanyDialog from './modules/insurance-company-dialog.vue'

  defineOptions({ name: 'InsuranceCompany' })

  type InsuranceCompany = Api.VehicleMgtSys.BasicInfo.InsuranceCompany
  type SearchParams = Api.VehicleMgtSys.BasicInfo.InsuranceCompanySearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface DialogExpose {
    handleOpen: (data: { type: 'add' | 'edit'; editData?: InsuranceCompany }) => Promise<void>
  }

  const showSearchBar = ref(true)
  const dialogRef = ref<DialogExpose>()
  const searchForm = ref<SearchParams>({
    companyName: undefined,
    contactPerson: undefined,
    contactPhone: undefined
  })

  const {
    data,
    columns,
    columnChecks,
    loading,
    pagination,
    replaceSearchParams,
    getData,
    refreshData,
    refreshCreate,
    refreshUpdate,
    refreshRemove,
    resetSearchParams,
    handleSizeChange,
    handleCurrentChange
  } = useTable<InsuranceCompany>({
    core: {
      apiFn: (params: TableParams) => {
        const { from, to } = pageInfoHandler({
          current: params.current,
          size: params.size
        })
        return fetchInsuranceCompanyList({
          ...params,
          from,
          to
        })
      },
      apiParams: {
        current: 1,
        size: 20
      },
      columnsFactory: (): ColumnOption<InsuranceCompany>[] => [
        {
          type: 'globalIndex',
          label: '序号',
          width: 80
        },
        {
          prop: 'companyName',
          label: '保险公司名称',
          minWidth: 180,
          showOverflowTooltip: true
        },
        {
          prop: 'contactPerson',
          label: '联系人',
          width: 130
        },
        {
          prop: 'contactPhone',
          label: '联系电话',
          width: 160
        },
        {
          prop: 'address',
          label: '联系地址',
          minWidth: 260,
          showOverflowTooltip: true,
          formatter: (row) => [row.region, row.addressDetail].filter(Boolean).join(' ') || '-'
        },
        {
          prop: 'remark',
          label: '备注',
          minWidth: 180,
          showOverflowTooltip: true
        },
        {
          prop: 'operation',
          label: '操作',
          width: 120,
          fixed: 'right',
          formatter: (row) => (
            <div>
              <ArtButtonTable type="edit" onClick={() => openDialog('edit', row)} />
              <ArtButtonTable type="delete" onClick={() => handleDelete(row)} />
            </div>
          )
        }
      ]
    }
  })

  const handleSearch = (params: SearchParams): void => {
    replaceSearchParams(params)
    void getData()
  }

  const handleResetSearch = (): void => {
    searchForm.value = {}
    void resetSearchParams()
  }

  const openDialog = (type: 'add' | 'edit', editData?: InsuranceCompany): void => {
    void dialogRef.value?.handleOpen({ type, editData })
  }

  const handleSaveSuccess = (type: 'add' | 'edit'): void => {
    void (type === 'add' ? refreshCreate() : refreshUpdate())
  }

  const handleDelete = async (row: InsuranceCompany): Promise<void> => {
    if (!row.id) return

    try {
      await ElMessageBox.confirm(
        `确定删除保险公司“${row.companyName}”吗？删除后无法恢复。`,
        '删除确认',
        {
          confirmButtonText: '删除',
          cancelButtonText: '取消',
          type: 'warning',
          confirmButtonClass: 'el-button--danger'
        }
      )
      await deleteInsuranceCompany(row.id)
      await refreshRemove()
    } catch {
      // 用户取消删除时无需额外提示。
    }
  }
</script>
