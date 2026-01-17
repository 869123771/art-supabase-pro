import Resources = Api.DataCenter.Resources
import { uploadAttachment } from '@/api/common'

const resourceDefaultButtons: Resources.Button[] = [
  {
    name: 'local-image-upload',
    label: '图片上传',
    icon: 'ri-image-add-line',
    upload: async (files: File | File[], args: Resources.Args) => {
      await uploadAttachment(files)
      args?.handleGetResourceList?.()
    },
    uploadConfig: {
      accept: 'image/*',
      limit: 1
    },
    order: 0
  },
  {
    name: 'local-file-upload',
    label: '文件上传',
    icon: 'ri-file-upload-line',
    upload: async (files: File | File[], args: Resources.Args) => {
      await uploadAttachment(files)
      args?.handleGetResourceList?.()
    },
    uploadConfig: {
      accept: '.doc,.xls,.ppt,.txt,.pdf',
      limit: 1
    },
    order: 1
  }
]

const useResourceStore = defineStore('resourceStore', () => {
  const resourceButtons = ref<Resources.Button[]>([])

  const getButton = (name: string): Resources.Button | undefined => {
    return resourceButtons.value.find((item) => item.name === name)
  }

  const addButton = (button: Resources.Button): boolean => {
    if (getButton(button.name)) {
      return false
    } else {
      resourceButtons.value.push(button)
      return true
    }
  }

  const removeButton = (name: string) => {
    resourceButtons.value = resourceButtons.value.filter((item) => item.name !== name)
  }

  const getAllButton = () => {
    return resourceButtons.value
  }

  resourceDefaultButtons.forEach((item) => addButton(item))

  return {
    addButton,
    removeButton,
    getButton,
    getAllButton
  }
})

export default useResourceStore
