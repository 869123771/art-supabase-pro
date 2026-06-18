<template>
  <ArtDialog ref="dialogRef">
    <ArtForm
      ref="formRef"
      v-model="form.data"
      :items="form.items"
      :rules="form.rules"
      :span="12"
      :gutter="20"
      label-width="100px"
      :show-reset="false"
      :show-submit="false"
    >
      <template #color>
        <el-color-picker
          v-model="form.data.color"
          :predefine="['#67C23A', '#E6A23C', '#F56C6C', '#909399']"
        />
      </template>

      <template #tagType>
        <div class="dict-tag-style-field">
          <el-select v-model="form.data.tagType" clearable placeholder="请选择标签样式">
            <el-option
              v-for="option in tagTypeOptions"
              :key="option.value"
              :label="option.value"
              :value="option.value"
            >
              <div class="dict-tag-style-field__option">
                <span class="dict-tag-style-field__value">{{ option.value }}</span>
                <el-tag :type="option.value">{{ option.label }}</el-tag>
              </div>
            </el-option>
          </el-select>
        </div>
      </template>
    </ArtForm>
  </ArtDialog>
</template>

<script setup lang="ts">
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm from '@/components/core/forms/art-form/index.vue'
  import type { FormItem } from '@/components/core/forms/art-form/index.vue'
  import type { FormInstance, FormRules } from 'element-plus'
  import { cloneDeep, isEmpty, omit } from 'lodash-es'
  import { addDict, editDict, fetchGetDictListByTypeId } from '@/api/data-center'
  import { useUserStore } from '@/store/modules/user'
  import { uniqueValidator } from '@/utils'
  import TreeUtils from '@/utils/tree'

  type DictListItem = Api.DataCenter.DictListItem
  interface ArtFormExpose {
    ref: Ref<FormInstance | undefined>
    validate: () => Promise<boolean | void>
    reloadOptions: (key?: string) => Promise<unknown>
  }

  interface FormGroup {
    data: DictListItem | Record<string, any>
    items: FormItem[]
    rules: FormRules
  }

  const emits = defineEmits(['success'])

  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore)

  const dialogRef = ref<ArtDialogExpose<DictListItem>>()
  const formRef = ref<ArtFormExpose>()
  const treeUtils = new TreeUtils({
    idKey: 'id',
    parentKey: 'parentId',
    childrenKey: 'children'
  })

  const dataDefault = {
    typeId: '',
    parentId: undefined,
    dictTypeName: '',
    label: '',
    code: '',
    value: '',
    i18nScope: '1',
    status: '1',
    sort: 1,
    color: '',
    tagType: '',
    remark: ''
  }
  const tagTypeOptions: Array<{ label: string; value: Api.Common.TagPreset }> = [
    { label: '主要', value: 'primary' },
    { label: '成功', value: 'success' },
    { label: '信息', value: 'info' },
    { label: '警告', value: 'warning' },
    { label: '危险', value: 'danger' }
  ]
  const form: Ref<FormGroup> = ref({
    data: cloneDeep(dataDefault) as DictListItem | Record<string, any>,
    items: computed(
      (): FormItem[] =>
        [
          {
            label: '所属类型',
            key: 'dictTypeName',
            type: 'input',
            span: 24,
            props: {
              placeholder: '请输入所属类型',
              clearable: true,
              disabled: true
            }
          },
          {
            label: '上级字典项',
            key: 'parentId',
            type: 'treeSelect',
            span: 24,
            api: fetchGetDictListByTypeId,
            immediate: false,
            params: {},
            beforeFetch: () => ({
              typeId: String(form.value.data.typeId || '')
            }),
            shouldFetch: (params): boolean => !!params?.typeId,
            afterFetch: ({ data = [] }) => {
              const tree = treeUtils.listToTree(data as DictListItem[]) as DictListItem[]
              const excludedIds = new Set(
                treeUtils
                  .getDescendants(tree, String(form.value.data.id || ''), true)
                  .map((item) => String(item.id))
              )
              const available = (data as DictListItem[]).filter(
                (item) => !item.id || !excludedIds.has(String(item.id))
              )
              return treeUtils.listToTree(
                available,
                (a, b) => Number(a.sort || 0) - Number(b.sort || 0)
              ) as DictListItem[]
            },
            labelField: 'label',
            valueField: 'id',
            childrenField: 'children',
            props: {
              clearable: true,
              checkStrictly: true,
              defaultExpandAll: true,
              renderAfterExpand: false,
              placeholder: '不选择则为一级字典项',
              props: {
                label: 'label',
                value: 'id',
                children: 'children'
              }
            }
          },
          {
            label: '字典标签',
            key: 'label',
            type: 'input',
            props: {
              placeholder: '请输入字典标签',
              clearable: true
            }
          },
          {
            label: '字典编码',
            key: 'code',
            type: 'input',
            props: {
              placeholder: '请输入字典编码',
              clearable: true
            }
          },
          {
            label: '字典值',
            key: 'value',
            type: 'input',
            props: {
              placeholder: '请输入字典值',
              clearable: true
            }
          },
          {
            label: '国际化',
            key: 'i18n',
            type: 'input',
            props: {
              placeholder: '请输入国际化',
              clearable: true
            }
          },
          {
            label: '国际化范围',
            key: 'i18nScope',
            type: 'radioGroup',
            props: {
              options: getDictMap.value.i18nScope ?? []
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
            label: '排序',
            key: 'sort',
            type: 'number',
            help: '值越小越靠前',
            props: {
              placeholder: '请输入排序'
            }
          },
          {
            label: '文字颜色',
            key: 'color',
            slots: 'color'
          },
          {
            label: '标签样式',
            key: 'tagType',
            slots: 'tagType'
          },
          {
            label: '备注信息',
            key: 'remark',
            type: 'input',
            span: 24,
            props: {
              placeholder: '请输入描述',
              type: 'textarea',
              rows: 4,
              clearable: true
            }
          }
        ] as FormItem[]
    ),
    rules: computed<FormRules>(() => {
      return {
        label: [{ required: true, message: '字典标签不能为空', trigger: 'change' }],
        code: [
          { required: true, message: '字典编码不能为空', trigger: 'change' },
          {
            validator: uniqueValidator({
              table: 'sys_dictionary',
              field: 'code',
              getExcludeId: (): string | undefined => form.value.data?.id,
              extraWhere: (): Record<string, any> => ({
                type_id: form.value.data?.typeId
              }),
              message: '字典编码已存在'
            }),
            trigger: 'change'
          }
        ],
        value: [{ required: true, message: '字典值不能为空', trigger: 'change' }]
      }
    })
  })

  const handleResetFields = () => {
    form.value.data = cloneDeep(dataDefault)
    formRef.value?.ref.value?.clearValidate()
  }

  const handleOpen = async (data: DictListItem = {} as DictListItem): Promise<void> => {
    handleResetFields()
    if (!isEmpty(data)) {
      form.value.data = {
        ...form.value.data,
        ...cloneDeep(data)
      }
    }
    await formRef.value?.reloadOptions('parentId')

    await dialogRef.value?.handleOpen(data, {
      title: isEdit.value ? '编辑字典' : '新增字典',
      width: '60%',
      onConfirm: handleSubmit,
      onReset: handleResetFields
    })
  }

  const normalizePayload = (data: DictListItem): DictListItem => ({
    ...data,
    parentId: data.parentId === '' ? null : data.parentId
  })

  const handleSubmit = async (): Promise<boolean> => {
    if (!formRef.value) return false

    try {
      await formRef.value.validate()
      const {
        data: { id, ...rest }
      } = form.value
      const params = normalizePayload(
        omit(rest, [
          'dictTypeName',
          'children',
          'tenantId',
          'createBy',
          'createTime',
          'updateBy',
          'updateTime',
          'dictTypeTable'
        ]) as DictListItem
      )
      if (!isEdit.value) {
        await addDict(params as DictListItem)
      } else {
        await editDict({ ...params, id } as DictListItem)
      }
      await useUserStore().fetchDictList()
      emits('success')
      return true
    } catch (error) {
      console.log('表单验证失败:', error)
      return false
    }
  }

  defineExpose({
    handleOpen
  })

  const isEdit = computed(() => !!form.value.data?.id)
</script>

<style scoped lang="scss">
  .dict-tag-style-field {
    display: flex;
    align-items: center;
    width: 100%;
    gap: 8px;

    .el-select {
      flex: 1;
      min-width: 0;
    }

    .el-tag {
      flex: none;
    }

    &__option {
      display: flex;
      align-items: center;
      justify-content: space-between;
      width: 100%;
      min-width: 0;
      gap: 12px;
    }

    &__value {
      overflow: hidden;
      font-family:
        ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', monospace;
      color: var(--el-text-color-regular);
      text-overflow: ellipsis;
      white-space: nowrap;
    }
  }
</style>
