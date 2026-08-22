import dayjs from 'dayjs'

export type Invoice = Api.Fms.InvoiceRecord

export interface InvoiceFormModel {
  id?: string
  invoiceRecordNo: string
  direction: Api.Fms.InvoiceDirection
  counterpartyId: string
  invoiceType: Api.Fms.InvoiceType
  invoiceTitle: string
  taxNumber: string
  invoiceCode: string
  invoiceNo: string
  issueDate: string
  taxRate: number | string
  amountExcludingTax: number | string
  taxAmount: number | string
  totalAmount: number | string
  statementIds: string[]
  attachments: Array<Record<string, unknown>>
  remark: string
}

export interface InvoiceStatementLink {
  statementId: string
  linkedAmount: number
}

interface BuildInvoicePayloadOptions {
  form: InvoiceFormModel
  statementLinks: InvoiceStatementLink[]
  duplicate?: Api.Fms.InvoiceDuplicateRecord
  mergeDuplicate: boolean
}

export const INVOICE_NO_PATTERN = /^[A-Z0-9]{6,30}$/

export function createInitialInvoiceForm(): InvoiceFormModel {
  return {
    id: undefined,
    invoiceRecordNo: '',
    direction: 'output',
    counterpartyId: '',
    invoiceType: 'vat_special',
    invoiceTitle: '',
    taxNumber: '',
    invoiceCode: '',
    invoiceNo: '',
    issueDate: dayjs().format('YYYY-MM-DD'),
    taxRate: 9,
    amountExcludingTax: 0,
    taxAmount: 0,
    totalAmount: 0,
    statementIds: [],
    attachments: [],
    remark: ''
  }
}

export function roundInvoiceMoney(value: number): number {
  return Math.round((Number(value) + Number.EPSILON) * 100) / 100
}

export function normalizeInvoiceNo(value: unknown): string {
  return String(value ?? '')
    .trim()
    .replace(/\s+/g, '')
    .toUpperCase()
}

function finiteNumber(value: unknown): number {
  const numeric = Number(value)
  return Number.isFinite(numeric) ? numeric : 0
}

export function buildInvoicePayload({
  form,
  statementLinks,
  duplicate,
  mergeDuplicate
}: BuildInvoicePayloadOptions): Api.Fms.SaveInvoicePayload {
  return {
    id: duplicate?.id ?? form.id,
    invoiceRecordNo:
      (mergeDuplicate ? duplicate?.invoiceRecordNo : form.invoiceRecordNo.trim()) || null,
    direction: form.direction,
    invoiceType: form.invoiceType,
    customerId: form.direction === 'output' ? form.counterpartyId : null,
    carrierId: form.direction === 'input' ? form.counterpartyId : null,
    invoiceTitle: form.invoiceTitle.trim() || null,
    taxNumber: form.taxNumber.trim() || null,
    invoiceCode: form.invoiceCode.trim() || null,
    invoiceNo: normalizeInvoiceNo(form.invoiceNo) || null,
    issueDate: form.issueDate,
    taxRate: finiteNumber(form.taxRate),
    amountExcludingTax: finiteNumber(form.amountExcludingTax),
    taxAmount: finiteNumber(form.taxAmount),
    totalAmount: finiteNumber(form.totalAmount),
    attachments: form.attachments,
    remark: form.remark.trim() || null,
    statementLinks
  }
}
