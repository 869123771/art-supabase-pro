<template>
  <main class="preview">
    <ArtTableMultipleSelect
      v-model="companyValue"
      v-model:selected-data="companySelected"
      title="选择合作企业"
      subtitle="可按企业名称、城市、行业或统一社会信用代码检索。"
      row-key="id"
      label-key="name"
      description-key="code"
      filter-key="industry"
      :data="companies"
      :columns="companyColumns"
      :filter-options="industryOptions"
    />

    <ArtTableSingleSelect
      v-model="warehouseValue"
      v-model:selected-data="warehouseSelected"
      title="选择发货仓"
      subtitle="单选模式确认后返回一条记录，可用于订单、调拨和库存业务。"
      row-key="id"
      label-key="name"
      description-key="city"
      :data="warehouses"
      :columns="warehouseColumns"
      :show-selected-panel="false"
      :show-pagination="false"
    />

    <ArtTreeMultipleSelect
      v-model="regionValue"
      v-model:selected-data="regionSelected"
      title="选择经营区域"
      subtitle="支持父级和子级独立选择，已选项会在右侧聚合展示。"
      row-key="id"
      label-key="label"
      description-key="manager"
      :data="regions"
      :show-pagination="false"
    />

    <ArtTreeSingleSelect
      v-model="singleRegionValue"
      v-model:selected-data="singleRegionSelected"
      title="选择默认区域"
      subtitle="单选模式下使用高亮当前节点，确认后返回一条层级记录。"
      row-key="id"
      label-key="label"
      description-key="manager"
      :data="regions"
      :show-selected-panel="false"
      :show-pagination="false"
    />
  </main>
</template>

<script setup lang="ts">
  import ArtTableMultipleSelect from './table-multiple.vue'
  import ArtTableSingleSelect from './table-single.vue'
  import ArtTreeMultipleSelect from './tree-multiple.vue'
  import ArtTreeSingleSelect from './tree-single.vue'
  import type { DataSelectColumn, DataSelectRecord } from './types'

  const companies: DataSelectRecord[] = [
    {
      id: 6910,
      name: '宁波澄澜数智园区服务有限公司',
      code: 'NB-P6910',
      industry: 'park',
      city: '宁波市',
      risk: '低'
    },
    {
      id: 7094,
      name: '洛阳砚川装备运维股份有限公司',
      code: 'LY-M56210',
      industry: 'maintenance',
      city: '洛阳市',
      risk: '中'
    },
    {
      id: 5691,
      name: '合肥青岚绿色材料科技有限公司',
      code: 'HF-G5691',
      industry: 'material',
      city: '合肥市',
      risk: '低'
    },
    {
      id: 9828,
      name: '泉州简仓即时零售集团',
      code: 'QZ-R39022',
      industry: 'retail',
      city: '泉州市',
      risk: '高'
    },
    {
      id: 8153,
      name: '无锡云拓智能供应链有限公司',
      code: 'WX-S8153',
      industry: 'supply',
      city: '无锡市',
      risk: '中'
    },
    {
      id: 7342,
      name: '晋江跨境集拼服务中心',
      code: 'JJ-C7342',
      industry: 'logistics',
      city: '晋江市',
      risk: '低'
    }
  ]
  const warehouses: DataSelectRecord[] = [
    { id: 2001, name: '海曙云拣中心', city: '宁波市', capacity: '82%' },
    { id: 2002, name: '洛龙前置调拨仓', city: '洛阳市', capacity: '64%' },
    { id: 2003, name: '包河医药恒温仓', city: '合肥市', capacity: '71%' },
    { id: 2004, name: '晋江跨境集拼仓', city: '泉州市', capacity: '58%' },
    { id: 2100, name: '无锡云拣仓', city: '无锡市', capacity: '52%' }
  ]
  const regions: DataSelectRecord[] = [
    {
      id: 'east',
      label: '东部协同区',
      manager: '负责人：宋承言',
      children: [
        { id: 'ningbo', label: '宁波湾组', manager: '负责人：谢闻舟' },
        { id: 'jiahe', label: '嘉禾组', manager: '负责人：许清和' },
        { id: 'taihu', label: '太湖组', manager: '负责人：秦砚' }
      ]
    },
    {
      id: 'central',
      label: '中原运营区',
      manager: '负责人：陆行知',
      children: [
        { id: 'luoyang', label: '洛阳组', manager: '负责人：许清和' },
        { id: 'zhengzhou', label: '郑州组', manager: '负责人：周明远' },
        { id: 'hefei', label: '合肥组', manager: '负责人：林知夏' }
      ]
    },
    {
      id: 'south',
      label: '南部增长区',
      manager: '负责人：顾云帆',
      children: [
        { id: 'quanzhou', label: '泉州组', manager: '负责人：叶澜' },
        { id: 'xiamen', label: '厦门组', manager: '负责人：苏禾' }
      ]
    }
  ]
  const industryOptions = [
    { label: '智慧园区', value: 'park' },
    { label: '装备运维', value: 'maintenance' },
    { label: '绿色材料', value: 'material' },
    { label: '即时零售', value: 'retail' },
    { label: '供应链', value: 'supply' },
    { label: '物流服务', value: 'logistics' }
  ]
  const companyColumns: DataSelectColumn[] = [
    { prop: 'id', label: 'ID', width: 90 },
    { prop: 'name', label: '企业名称', minWidth: 220 },
    {
      prop: 'industry',
      label: '行业',
      minWidth: 130,
      formatter: (row) => industryOptions.find((item) => item.value === row.industry)?.label ?? ''
    },
    { prop: 'city', label: '城市', width: 120 },
    {
      prop: 'risk',
      label: '风险',
      width: 90,
      align: 'center',
      tagType: (row) => (row.risk === '低' ? 'success' : row.risk === '中' ? 'warning' : 'danger')
    }
  ]
  const warehouseColumns: DataSelectColumn[] = [
    { prop: 'id', label: '编号', width: 110 },
    { prop: 'name', label: '仓库名称', minWidth: 220 },
    { prop: 'city', label: '城市', width: 140 },
    { prop: 'capacity', label: '库容', width: 120, align: 'right' }
  ]

  const companyValue = ref<Array<string | number>>([7094, 9828])
  const companySelected = ref([companies[1], companies[3]])
  const warehouseValue = ref<string | number>(2003)
  const warehouseSelected = ref([warehouses[2]])
  const regionValue = ref<Array<string | number>>(['ningbo', 'taihu', 'luoyang'])
  const regionSelected = ref([
    regions[0].children[0],
    regions[0].children[2],
    regions[1].children[0]
  ])
  const singleRegionValue = ref<string | number>('taihu')
  const singleRegionSelected = ref([regions[0].children[2]])
</script>

<style scoped>
  .preview {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 24px;
    min-height: 100vh;
    padding: 48px;
    background: #f5f7fa;
  }
</style>
