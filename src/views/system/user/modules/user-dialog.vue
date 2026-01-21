<template>
  <ElDialog
    v-model="dialogVisible"
    :title="dialogType === 'add' ? '添加用户' : '编辑用户'"
    width="60%"
    align-center
    @close="handleClose"
  >
    <ElForm ref="formRef" :model="formData" :rules="rules" label-width="100px" class="pr-4">
      <ElRow>
        <ElCol :xs="24" :sm="24" :lg="24">
          <ElFormItem label="图像" prop="avatar">
            <ArtUploadImage v-model="formData.avatar" />
          </ElFormItem>
        </ElCol>
        <ElCol :xs="24" :sm="24" :lg="12">
          <ElFormItem label="用户名" prop="userName">
            <ElInput v-model="formData.userName" placeholder="请输入用户名" />
          </ElFormItem>
        </ElCol>
        <ElCol :xs="24" :sm="24" :lg="12">
          <ElFormItem label="昵称" prop="nickName">
            <ElInput v-model="formData.nickName" placeholder="请输入昵称" />
          </ElFormItem>
        </ElCol>

        <ElCol :xs="24" :sm="24" :lg="12">
          <ElFormItem label="手机号" prop="userPhone">
            <ElInput v-model="formData.userPhone" placeholder="请输入手机号" />
          </ElFormItem>
        </ElCol>
        <ElCol :xs="24" :sm="24" :lg="12" v-if="dialogType === 'add'">
          <ElFormItem label="邮箱" prop="userEmail">
            <ElInput v-model="formData.userEmail" placeholder="请输入邮箱" />
          </ElFormItem>
        </ElCol>

        <template v-if="dialogType === 'add'">
          <ElCol :xs="24" :sm="24" :lg="12">
            <ElFormItem label="密码" prop="password">
              <ElInput
                v-model.trim="formData.password"
                placeholder="请输入密码"
                type="password"
                autocomplete="off"
                show-password
              />
            </ElFormItem>
          </ElCol>
          <ElCol :xs="24" :sm="24" :lg="12">
            <ElFormItem label="确认密码" prop="confirmPassword">
              <ElInput
                v-model.trim="formData.confirmPassword"
                placeholder="请再次输入密码"
                type="password"
                autocomplete="off"
                show-password
              />
            </ElFormItem>
          </ElCol>
        </template>
        <ElCol :xs="24" :sm="24" :lg="12">
          <ElFormItem label="性别" prop="userGender">
            <ElSelect v-model="formData.userGender">
              <ElOption
                v-for="{ label, value } in getDictMap.sex"
                :key="value"
                :value="value"
                :label="label"
              ></ElOption>
            </ElSelect>
          </ElFormItem>
        </ElCol>
        <ElCol :xs="24" :sm="24" :lg="12" v-if="dialogType === 'add'">
          <ElFormItem label="用户类型" prop="userType">
            <ElRadioGroup v-model="formData.userType">
              <ElRadioButton
                v-for="{ label, value } in getDictMap.userType"
                :key="value"
                :value="value"
                :label="label"
              />
            </ElRadioGroup>
          </ElFormItem>
        </ElCol>
        <ElCol :xs="24" :sm="24" :lg="24">
          <ElFormItem label="备注" prop="remark">
            <ElInput
              v-model.trim="formData.remark"
              placeholder="请输入备注"
              type="textarea"
              :rows="3"
            />
          </ElFormItem>
        </ElCol>
        <ElCol :xs="24" :sm="24" :lg="24">
          <ElFormItem label="状态" prop="status">
            <ElRadioGroup v-model="formData.status" multiple>
              <ElRadio
                v-for="{ label, value } in getDictMap.status"
                :key="value"
                :value="value"
                :label="label"
              />
            </ElRadioGroup>
          </ElFormItem>
        </ElCol>
      </ElRow>
    </ElForm>

    <template #footer>
      <div class="dialog-footer">
        <ElButton @click="handleClose">取消</ElButton>
        <ElButton type="primary" @click="handleSubmit" :loading="loading">提交</ElButton>
      </div>
    </template>
  </ElDialog>
</template>

<script setup lang="tsx">
  import ArtUploadImage from '@/components/core/forms/art-upload-image/index.vue'
  import type { FormInstance, FormRules } from 'element-plus'
  import { useI18n } from 'vue-i18n'
  import { cloneDeep, isEmpty } from 'lodash-es'
  import { useUserStore } from '@/store/modules/user'
  import { addUser, editUser } from '@/api/system-manage'

  type UserListItem = Api.SystemManage.UserListItem

  const { getDictMap } = storeToRefs(useUserStore())
  const { t } = useI18n()

  interface Props {
    visible: boolean
    type: string
    userData?: Partial<Api.SystemManage.UserListItem>
  }

  interface Emits {
    (e: 'update:visible', value: boolean): void
    (e: 'submit'): void
  }

  const props = defineProps<Props>()
  const emit = defineEmits<Emits>()

  // 对话框显示控制
  const dialogVisible = computed({
    get: () => props.visible,
    set: (value) => emit('update:visible', value)
  })

  const loading = ref(false)

  const dialogType = computed(() => props.type)

  //  定义表单初始值常量（统一管理默认值，方便重置）
  const DEFAULT_FORM_DATA: UserListItem = {
    avatar: null,
    userName: '',
    nickName: '',
    userPhone: '',
    userGender: '1', // 默认性别男
    userEmail: '',
    password: '',
    confirmPassword: '',
    userType: '1',
    userRoles: [] as string[],
    remark: '',
    status: '1'
  }

  // 表单实例
  const formRef = ref<FormInstance>()

  // 表单数据
  const formData: UserListItem = reactive(cloneDeep(DEFAULT_FORM_DATA))

  // 表单验证规则
  const rules: FormRules = {
    userName: [{ min: 2, max: 20, message: '长度在 2 到 20 个字符', trigger: 'change' }],
    userPhone: [{ pattern: /^1[3-9]\d{9}$/, message: '请输入正确的手机号格式', trigger: 'change' }],
    userEmail: [{ required: true, type: 'email', message: '请输入正确的邮箱', trigger: 'change' }],
    password: [
      { required: true, validator: validatePassword, trigger: 'change' },
      { min: 6, message: t('register.rule.passwordLength'), trigger: 'change' }
    ],
    confirmPassword: [{ required: true, validator: validateConfirmPassword, trigger: 'change' }]
  }

  /**
   * 验证密码
   * 当密码输入后，如果确认密码已填写，则触发确认密码的验证
   */
  function validatePassword(_rule: any, value: string, callback: (error?: Error) => void) {
    if (!value) {
      callback(new Error(t('register.placeholder.password')))
      return
    }

    if (formData.confirmPassword) {
      formRef.value?.validateField('confirmPassword')
    }

    callback()
  }

  /**
   * 验证确认密码
   * 检查确认密码是否与密码一致
   */
  function validateConfirmPassword(_rule: any, value: string, callback: (error?: Error) => void) {
    if (!value) {
      callback(new Error(t('register.rule.confirmPasswordRequired')))
      return
    }

    if (value !== formData.password) {
      callback(new Error(t('register.rule.passwordMismatch')))
      return
    }

    callback()
  }

  /**
   * 重置表单到初始状态（核心优化：全量重置）
   */
  const resetFields = async () => {
    // 遍历初始值，重置每个属性，确保无残留
    Object.keys(DEFAULT_FORM_DATA).forEach((key) => {
      ;(formData as any)[key] = (cloneDeep(DEFAULT_FORM_DATA) as any)[key]
    })
    await nextTick()
    formRef.value?.resetFields()
  }

  /**
   * 初始化表单数据
   * 根据对话框类型（新增/编辑）填充表单
   */
  const initFormData = () => {
    if (!isEmpty(props.userData)) {
      const {
        id,
        avatar,
        userName,
        nickName,
        userPhone,
        userGender,
        userEmail,
        userRoles,
        remark,
        status,
        userType,
        authUserId
      } = props.userData ?? {}
      Object.assign(formData, {
        id,
        avatar,
        userName,
        nickName,
        userPhone,
        userEmail,
        userGender,
        userRoles,
        remark,
        status,
        userType,
        authUserId
      })
    }
  }

  /**
   * 监听对话框状态变化
   * 当对话框打开时初始化表单数据并清除验证状态
   */
  watch(
    () => [props.visible, props.type, props.userData],
    ([visible]) => {
      if (visible) {
        initFormData()
      }
    },
    { immediate: true }
  )

  const handleClose = () => {
    dialogVisible.value = false
    resetFields()
  }
  /**
   * 提交表单
   * 验证通过后触发提交事件
   */
  const handleSubmit = () => {
    if (!formRef.value) return
    formRef.value.validate(async (valid) => {
      if (valid) {
        try {
          loading.value = true
          const { id, userEmail, password, authUserId, ...rest } = toRaw(formData) as UserListItem
          const params: UserListItem = {
            userEmail,
            password,
            ...rest
          }
          if (dialogType.value === 'add') {
            await addUser(params)
          } else {
            Object.assign(params, { id, authUserId })
            await editUser(params)
          }
        } finally {
          loading.value = false
        }
        dialogVisible.value = false
        emit('submit')
      }
    })
  }
</script>
