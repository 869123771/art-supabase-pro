import assert from 'node:assert/strict'
import test from 'node:test'
import {
  updateFormFieldValue,
  type FormRecord
} from '../../src/components/core/forms/art-form/model-utils'

test('更新普通字段时保留无关附件数组的引用', () => {
  const attachments = ['https://example.com/first.png', 'https://example.com/second.png']
  const form: FormRecord = {
    payeeName: '原收款人',
    basisUrls: attachments
  }

  const result = updateFormFieldValue(form, 'payeeName', '新收款人')

  assert.equal(result, form)
  assert.equal(result.payeeName, '新收款人')
  assert.equal(result.basisUrls, attachments)
})

test('支持嵌套字段更新和清除', () => {
  const form: FormRecord = {
    contact: { name: '张三', phone: '13800000000' }
  }

  updateFormFieldValue(form, 'contact.name', '李四')
  assert.deepEqual(form.contact, { name: '李四', phone: '13800000000' })

  updateFormFieldValue(form, 'contact.phone', undefined)
  assert.deepEqual(form.contact, { name: '李四' })
})
