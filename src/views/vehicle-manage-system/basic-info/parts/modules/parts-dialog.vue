<template>
  <ArtDialog ref="dialogRef" width="920px">
    <template #subtitle>
      维护零部件的基础属性、质保寿命和供应信息，便于后续维修、库存和采购业务复用。
    </template>

    <ArtForm
      ref="formRef"
      v-model="form"
      :items="items"
      :rules="rules"
      :span="12"
      :gutter="20"
      label-width="110px"
      :show-reset="false"
      :show-submit="false"
    />
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import TreeUtils from '@/utils/tree'
  import { useUserStore } from '@/store/modules/user'
  import {
    addParts,
    editParts,
    fetchPartsCategoryTree,
    fetchSupplierOptions
  } from '@/api/vehicle-manage-system'

  type Parts = Api.VehicleMgtSys.BasicInfo.Parts
  type PartsCategory = Api.VehicleMgtSys.BasicInfo.PartsCategory
  type Supplier = Api.VehicleMgtSys.BasicInfo.Supplier

  interface Emits {
    (e: 'success', type: 'add' | 'edit'): void
  }

  const emit = defineEmits<Emits>()
  const dialogRef = ref<ArtDialogExpose<Parts | undefined>>()
  const formRef = ref<{
    validate: () => Promise<boolean>
    clearValidate: () => void
  }>()
  const { getDictMap } = storeToRefs(useUserStore())
  const categoryTreeUtils = new TreeUtils({
    idKey: 'id',
    parentKey: 'parentId',
    childrenKey: 'children'
  })

  const createInitialForm = (): Parts => ({
    id: undefined,
    partName: '',
    partCode: '',
    categoryId: null,
    brand: '',
    model: '',
    unit: '',
    supplierId: null,
    manufacturer: '',
    supplierContact: '',
    isConsumable: false,
    warrantyMileage: null,
    warrantyDuration: null,
    serviceLife: null,
    serviceMileage: null,
    status: '1',
    remark: ''
  })

  const form = reactive<Parts>(createInitialForm())

  const rules: FormRules<Parts> = {
    partName: [
      { required: true, message: '请输入零部件名称', trigger: 'blur' },
      { min: 2, max: 100, message: '长度应为 2 到 100 个字符', trigger: 'blur' }
    ],
    partCode: [
      { required: true, message: '请输入零部件编码', trigger: 'blur' },
      {
        pattern: /^[A-Za-z0-9_-]{2,60}$/,
        message: '编码仅支持字母、数字、下划线和中横线，长度 2 到 60',
        trigger: 'blur'
      }
    ],
    categoryId: [{ required: true, message: '请选择零部件类别', trigger: 'change' }],
    brand: [{ max: 80, message: '品牌不能超过 80 个字符', trigger: 'blur' }],
    model: [{ max: 80, message: '型号不能超过 80 个字符', trigger: 'blur' }],
    unit: [{ required: true, message: '请输入或选择单位', trigger: 'change' }],
    manufacturer: [{ max: 100, message: '生产厂商不能超过 100 个字符', trigger: 'blur' }],
    supplierContact: [{ max: 100, message: '供应商联系人不能超过 100 个字符', trigger: 'blur' }],
    remark: [{ max: 500, message: '备注不能超过 500 个字符', trigger: 'blur' }]
  }

  const items = computed<FormItem[]>(() => [
    {
      label: '基础信息',
      key: 'basicSection',
      type: 'divider',
      span: 24
    },
    {
      label: '零部件名称',
      key: 'partName',
      type: 'input',
      props: {
        maxlength: 100
      }
    },
    {
      label: '零部件编码',
      key: 'partCode',
      type: 'input',
      props: {
        maxlength: 60,
        placeholder: '如 ENG-IN-001'
      }
    },
    {
      label: '零部件类别',
      key: 'categoryId',
      type: 'treeSelect',
      api: fetchPartsCategoryTree,
      afterFetch: (result: unknown) => {
        const records = (result as { data?: PartsCategory[] })?.data ?? []
        return categoryTreeUtils.listToTree(records) as PartsCategory[]
      },
      labelField: 'categoryName',
      valueField: 'id',
      childrenField: 'children',
      props: {
        checkStrictly: true,
        defaultExpandAll: true,
        renderAfterExpand: false
      }
    },
    {
      label: '品牌',
      key: 'brand',
      type: 'input',
      props: {
        maxlength: 80
      }
    },
    {
      label: '型号',
      key: 'model',
      type: 'input',
      props: {
        maxlength: 80
      }
    },
    {
      label: '单位',
      key: 'unit',
      type: 'select',
      props: {
        options: getDictMap.value.parts_unit ?? [],
        allowCreate: true,
        defaultFirstOption: true
      }
    },
    {
      label: '易损/耗件',
      key: 'isConsumable',
      type: 'radioGroup',
      span: 24,
      props: {
        optionType: 'button',
        options: getBooleanDictOptions()
      }
    },
    {
      label: '质保与寿命',
      key: 'lifeSection',
      type: 'divider',
      span: 24
    },
    {
      label: '质保里程',
      key: 'warrantyMileage',
      type: 'number',
      props: {
        min: 0,
        controlsPosition: 'right',
        class: '!w-full'
      },
      description: '单位：公里'
    },
    {
      label: '质保时长',
      key: 'warrantyDuration',
      type: 'number',
      props: {
        min: 0,
        controlsPosition: 'right',
        class: '!w-full'
      },
      description: '单位：个月'
    },
    {
      label: '使用年限',
      key: 'serviceLife',
      type: 'number',
      props: {
        min: 0,
        controlsPosition: 'right',
        class: '!w-full'
      },
      description: '单位：年'
    },
    {
      label: '使用里程',
      key: 'serviceMileage',
      type: 'number',
      props: {
        min: 0,
        controlsPosition: 'right',
        class: '!w-full'
      },
      description: '单位：公里'
    },
    {
      label: '供应信息',
      key: 'supplierSection',
      type: 'divider',
      span: 24
    },
    {
      label: '生产厂商',
      key: 'manufacturer',
      type: 'input',
      props: {
        maxlength: 100
      }
    },
    {
      label: '供应厂商',
      key: 'supplierId',
      type: 'select',
      api: fetchSupplierOptions,
      resultField: 'data',
      labelField: 'supplierName',
      valueField: 'id',
      labelFn: (item) => {
        const supplier = item as Supplier
        return [supplier.supplierName, supplier.contactPerson].filter(Boolean).join(' / ')
      }
    },
    {
      label: '供应商联系人',
      key: 'supplierContact',
      type: 'input',
      props: {
        maxlength: 100
      }
    },
    {
      label: '状态',
      key: 'status',
      type: 'radioGroup',
      props: {
        options: getDictMap.value.status ?? []
      }
    },
    {
      label: '备注',
      key: 'remark',
      type: 'input',
      span: 24,
      props: {
        type: 'textarea',
        rows: 4,
        maxlength: 500,
        showWordLimit: true
      }
    }
  ])

  const getBooleanDictOptions = () =>
    (getDictMap.value.commonBoolean ?? []).map((item) => ({
      ...item,
      value: item.value === 'true'
    }))

  const replaceForm = (nextForm: Parts): void => {
    Object.keys(form).forEach((key) => {
      delete form[key as keyof Parts]
    })
    Object.assign(form, nextForm)
  }

  const resetForm = async (): Promise<void> => {
    replaceForm(createInitialForm())
    await nextTick()
    formRef.value?.clearValidate()
  }

  const handleSubmit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }

    try {
      const source = toRaw(form)
      const payload: Parts = {
        id: source.id,
        partName: source.partName,
        partCode: source.partCode,
        categoryId: source.categoryId || null,
        brand: source.brand,
        model: source.model,
        unit: source.unit,
        supplierId: source.supplierId || null,
        manufacturer: source.manufacturer,
        supplierContact: source.supplierContact,
        isConsumable: source.isConsumable,
        warrantyMileage: source.warrantyMileage,
        warrantyDuration: source.warrantyDuration,
        serviceLife: source.serviceLife,
        serviceMileage: source.serviceMileage,
        status: source.status,
        remark: source.remark
      }
      if (form.id) {
        await editParts(payload)
      } else {
        await addParts(payload)
      }
      emit('success', form.id ? 'edit' : 'add')
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (row?: Parts): Promise<void> => {
    await resetForm()
    const isEdit = !!row?.id
    if (isEdit) {
      replaceForm({
        ...createInitialForm(),
        ...(structuredClone(toRaw(row)) as Parts)
      })
    }

    await dialogRef.value?.handleOpen(row, {
      title: isEdit ? '编辑零部件' : '新增零部件',
      contentMaxHeight: '68vh',
      onConfirm: handleSubmit,
      onReset: () => void resetForm()
    })
  }

  defineExpose({
    handleOpen,
    handleClose: () => dialogRef.value?.handleClose()
  })
</script>
