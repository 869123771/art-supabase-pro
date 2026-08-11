import dayjs from 'dayjs'

export type Invoice = Api.Tms.Finance.InvoiceRecord

export interface InvoiceFormModel {
  id?: string
  invoiceRecordNo: string
  direction: Api.Tms.Finance.InvoiceDirection
  counterpartyId: string
  invoiceType: Api.Tms.Finance.InvoiceType
  invoiceTitle: string
  taxNumber: string
  invoiceCode: string
  invoiceNo: string
  issueDate: string
  taxRate: number
  amountExcludingTax: number
  taxAmount: number
  totalAmount: number
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
  duplicate?: Api.Tms.Finance.InvoiceDuplicateRecord
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

export function buildInvoicePayload({
  form,
  statementLinks,
  duplicate,
  mergeDuplicate
}: BuildInvoicePayloadOptions): Api.Tms.Finance.SaveInvoicePayload {
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
    taxRate: Number(form.taxRate),
    amountExcludingTax: Number(form.amountExcludingTax),
    taxAmount: Number(form.taxAmount),
    totalAmount: Number(form.totalAmount),
    attachments: form.attachments,
    remark: form.remark.trim() || null,
    statementLinks
  }
}
