import { expect, test } from '@playwright/test'

test.use({ storageState: { cookies: [], origins: [] } })
test.setTimeout(120_000)
for (const kind of ['issue', 'return', 'finished_inbound', 'finished_return']) {
  test(`${kind}详情失败恢复及两行编辑复制保持布局`, async ({ page }, testInfo) => {
    let failure = true
    let serialFailure = true
    let writes = 0
    const errors: string[] = []
    page.on('pageerror', (error) => errors.push(error.message))
    const outbound = kind === 'issue' || kind === 'finished_return'
    const negative = kind === 'return' || kind === 'finished_return'
    const lines = [1, 2].map((n) => ({
      id: `line-${n}`,
      line_no: n,
      material_id: `material-${n}`,
      material: {
        id: `material-${n}`,
        material_code: `MAT-${n}`,
        material_name: `测试生产物料 ${n}（完整规格和型号用于核对）`,
        unit_conversions: [],
        serial_management_enabled: true
      },
      work_order_id: null,
      project_id: null,
      construction_no: null,
      inventory_unit_id: 'unit-test',
      production_unit_id: null,
      requested_quantity: negative ? -2 : 2,
      actual_quantity: negative ? -2 : 2,
      base_unit_id: null,
      base_quantity: negative ? -2 : 2,
      batch_no: `BATCH-TEST-${n}`,
      warehouse_id: 'warehouse-test',
      bin_id: null,
      source_batch_id: null,
      pack_id: null,
      source_line_id: null,
      return_type: negative ? 'good' : null,
      stock_type: 'normal',
      owner_type: n === 1 ? 'supplier' : 'customer',
      owner_id: n === 1 ? 'supplier-test' : 'customer-test',
      stock_status: 'available',
      keeper_id: null,
      auxiliary_unit_id: null,
      auxiliary_quantity: null,
      auxiliary_unit_2_id: null,
      auxiliary_quantity_2: null,
      production_date: null,
      expiry_date: null,
      tracking_no: null,
      fulfilled_quantity: 1,
      source_document: null,
      source_line_no: null,
      remark: `测试明细备注 ${n}`,
      serial_ids: outbound && n === 1 ? ['serial-1', 'serial-2'] : [],
      serial_nos: !outbound && n === 1 ? ['SN-TEST-001', 'SN-TEST-002'] : [],
      movement_id: null
    }))
    const document = {
      id: 'production-test',
      tenant_id: 'tenant-test',
      kind,
      document_no: `TEST-${kind.toUpperCase()}-001`,
      document_type_id: 'type-test',
      business_type_id: 'business-test',
      organization_id: 'org-test',
      business_date: '2026-10-05',
      warehouse_id: 'warehouse-test',
      work_order_id: null,
      project_id: null,
      customer_id: null,
      demand_date: null,
      applicant_id: null,
      department_id: null,
      keeper_id: null,
      status: 'draft',
      material_status: 'partial',
      remark: '测试单据备注：核对表头及两行明细，不写入真实业务数据。',
      created_at: '2026-10-05',
      updated_at: '2026-10-05',
      approved_at: null,
      lines
    }
    await page.route('**/rest/v1/**', (route) => {
      if (
        route.request().method() !== 'GET' &&
        !route.request().url().includes('/rpc/wms_work_order_options_secure')
      )
        writes++
      const table = new URL(route.request().url()).pathname.split('/').at(-1)
      return route.fulfill({
        headers: {
          'content-range': [
            'mdm_organization',
            'mdm_document_type',
            'mdm_business_type',
            'mdm_supplier',
            'mdm_customer'
          ].includes(table || '')
            ? '0-0/1'
            : '*/0',
          'access-control-expose-headers': 'content-range'
        },
        json:
          table === 'mdm_organization'
            ? [
                {
                  id: 'org-test',
                  tenant_id: 'tenant-test',
                  organization_code: 'ORG',
                  organization_name: '测试库存组织',
                  status: '1',
                  initialization: {
                    enabled_on: '2026-01-01',
                    is_default: true,
                    initialization_closed_at: '2026-01-02'
                  }
                }
              ]
            : table === 'mdm_document_type'
              ? [
                  {
                    id: 'type-test',
                    tenant_id: 'tenant-test',
                    document_type_code: 'TEST',
                    document_type_name: '测试单据类型',
                    is_default: true
                  }
                ]
              : table === 'mdm_business_type'
                ? [
                    {
                      id: 'business-test',
                      tenant_id: 'tenant-test',
                      business_type_code: 'TEST',
                      business_type_name: '测试业务类型',
                      is_default: true
                    }
                  ]
                : table === 'mdm_supplier'
                  ? [
                      {
                        id: 'supplier-test',
                        tenant_id: 'tenant-test',
                        supplier_code: 'SUP-TEST',
                        supplier_name: '测试生产供应商'
                      }
                    ]
                  : table === 'mdm_customer'
                    ? [
                        {
                          id: 'customer-test',
                          tenant_id: 'tenant-test',
                          customer_code: 'CUS-TEST',
                          customer_name: '测试生产客户'
                        }
                      ]
                    : []
      })
    })
    await page.route('**/rest/v1/sys_menu?*', (route) =>
      route.fulfill({ json: { id: 'menu-test' } })
    )
    await page.route('**/rest/v1/wms_production_material_document?*', (route) =>
      failure
        ? route.fulfill({ status: 503, json: { message: '测试单据读取失败', code: 'XX000' } })
        : route.fulfill({ json: document })
    )
    await page.route('**/rest/v1/wms_serial_number?*', (route) => {
      const url = new URL(route.request().url())
      expect(url.searchParams.get('id')).toContain('serial-1')
      expect(url.searchParams.has('status')).toBe(false)
      if (serialFailure)
        return route.fulfill({
          status: 503,
          json: { message: '测试序列号读取失败', code: 'XX000' }
        })
      return route.fulfill({
        json: [1, 2].map((n) => ({
          id: `serial-${n}`,
          serial_no: `SN-TEST-00${n}`,
          status: 'consumed',
          project_id: null,
          construction_no: null
        }))
      })
    })
    await page.goto(`/tests/e2e/fixtures/wms-operation-retry.html?kind=${kind}`)
    await page.getByRole('button', { name: '测试生产单据 view', exact: true }).click()
    const drawer = page.locator('.el-drawer:visible')
    await expect(drawer.getByText('单据加载失败', { exact: true })).toBeVisible()
    await expect(drawer.getByText('测试生产物料 1', { exact: false })).toHaveCount(0)
    failure = false
    await drawer.getByRole('button', { name: '重新加载', exact: true }).click()
    await expect(drawer.getByText(document.document_no, { exact: true }).first()).toBeVisible()
    await expect(drawer.locator('.art-descriptions table')).toHaveClass(/is-bordered/)
    const remarkRow = drawer.locator('.art-descriptions tr').filter({ hasText: document.remark })
    await expect(remarkRow.locator('td')).toHaveCount(2)
    await expect(drawer.getByRole('button', { name: '保存', exact: true })).toHaveCount(0)
    await expect(drawer.locator('.el-table__body').getByRole('checkbox')).toHaveCount(0)
    await expect(
      drawer.locator('.el-table__body').getByText('测试生产供应商', { exact: true })
    ).toHaveCount(1)
    await expect(
      drawer.locator('.el-table__body').getByText('测试生产客户', { exact: true })
    ).toHaveCount(1)
    await expect(
      drawer.getByText(lines[1].material.material_name, { exact: true }).first()
    ).toBeVisible()
    expect(await drawer.evaluate((el) => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
    await drawer
      .locator('.el-table__body')
      .getByText('测试生产供应商', { exact: true })
      .scrollIntoViewIfNeeded()
    await page.screenshot({
      path: testInfo.outputPath('production-owner-names.png'),
      animations: 'disabled'
    })
    await page.screenshot({
      path: testInfo.outputPath('wms-production-view.png'),
      animations: 'disabled'
    })
    await drawer.getByRole('button', { name: '序列号 2', exact: true }).click()
    const serialDialog = page.locator('.el-dialog:visible')
    if (outbound) {
      await expect(serialDialog.getByText('序列号加载失败', { exact: true })).toBeVisible()
      serialFailure = false
      await serialDialog.getByRole('button', { name: '重新加载', exact: true }).click()
    }
    await expect(serialDialog.getByRole('textbox', { name: '当前明细序列号' })).toHaveValue(
      'SN-TEST-001\nSN-TEST-002'
    )
    await expect(serialDialog.getByRole('textbox', { name: '当前明细序列号' })).toHaveAttribute(
      'readonly',
      ''
    )
    await expect(serialDialog.getByRole('button', { name: '保存序列号', exact: true })).toHaveCount(
      0
    )
    await page.screenshot({
      path: testInfo.outputPath('wms-production-serials.png'),
      animations: 'disabled'
    })
    await serialDialog.getByRole('button', { name: '关闭此对话框', exact: true }).click()
    await drawer.getByRole('button', { name: '序列号 0', exact: true }).click()
    await expect(serialDialog.getByText('暂无序列号', { exact: true })).toBeVisible()
    await serialDialog.getByRole('button', { name: '关闭此对话框', exact: true }).click()
    await drawer.getByRole('button', { name: '关闭此对话框', exact: true }).click()
    for (const mode of ['edit', 'copy']) {
      await page.getByRole('button', { name: `测试生产单据 ${mode}`, exact: true }).click()
      await expect(
        drawer.getByText(lines[1].material.material_name, { exact: true }).first()
      ).toBeVisible()
      await expect(
        drawer.getByRole('button', { name: mode === 'copy' ? '保存副本' : '保存', exact: true })
      ).toBeEnabled()
      if (testInfo.project.name.includes('mobile')) {
        await expect(
          drawer.locator(
            '.el-table__body td.el-table-fixed-column--left, .el-table__body td.el-table-fixed-column--right'
          )
        ).toHaveCount(0)
      }
      if (mode === 'copy')
        await expect(drawer.getByText('保存后自动生成', { exact: true })).toBeVisible()
      const table = drawer.locator('.art-table.wms-editable-line-table')
      await expect(table.locator('.art-table__required-marker')).toHaveCount(3)
      const sizes = await table.locator('.el-select').evaluateAll((els) =>
        els.map((el) => ({
          width: el.getBoundingClientRect().width,
          cell: el.closest('td')?.getBoundingClientRect().width || 0
        }))
      )
      expect(sizes.length).toBeGreaterThan(5)
      for (const size of sizes) {
        expect(size.width).toBeGreaterThan(80)
        expect(size.width / size.cell).toBeGreaterThan(0.6)
      }
      expect(await drawer.evaluate((el) => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
      if (mode === 'edit') {
        await drawer.getByRole('button', { name: '全屏', exact: true }).click()
        await expect(drawer).toHaveClass(/(?:^|\s)is-fullscreen(?:\s|$)/)
        const wrap = drawer.locator('.art-drawer__scrollbar > .el-scrollbar__wrap')
        await wrap.evaluate((el) => {
          el.scrollTop = el.scrollHeight
        })
        await expect
          .poll(() =>
            drawer.evaluate((el) => {
              const content = el.querySelector('.art-drawer__content')!.getBoundingClientRect()
              const footer = el.querySelector('.el-drawer__footer')!.getBoundingClientRect()
              return content.bottom <= footer.top + 1
            })
          )
          .toBe(true)
        await page.screenshot({
          path: testInfo.outputPath('production-fullscreen-bottom.png'),
          animations: 'disabled'
        })
        await drawer.getByRole('button', { name: '退出全屏', exact: true }).click()
        await expect(drawer).not.toHaveClass(/(?:^|\s)is-fullscreen(?:\s|$)/)
        await page.screenshot({
          path: testInfo.outputPath('wms-production-edit.png'),
          animations: 'disabled'
        })
        await table.scrollIntoViewIfNeeded()
        await page.screenshot({
          path: testInfo.outputPath('wms-production-edit-lower.png'),
          animations: 'disabled'
        })
      }
      const deleteLines = drawer.getByRole('button', { name: '批量删除', exact: true })
      await expect(deleteLines).toBeDisabled()
      if (mode === 'edit') {
        await table.locator('.el-table__body tr').first().locator('.el-checkbox').click()
        await deleteLines.click()
        await expect(table.locator('.el-table__body tr')).toHaveCount(1)
        await expect(table.locator('.el-table__body tr').first()).toContainText(
          lines[1].material.material_name
        )
        await expect(table.locator('.el-table__body tr').first().locator('td').nth(1)).toHaveText(
          '10'
        )
        await expect(deleteLines).toBeDisabled()
        await table.locator('.el-table__body tr').first().locator('.el-checkbox').click()
      } else {
        await table.locator('.el-table__header-wrapper .el-checkbox').click()
        await expect(table.locator('.el-table__body .el-checkbox.is-checked')).toHaveCount(2)
      }
      await deleteLines.click()
      await expect(table.locator('.el-table__body tr')).toHaveCount(0)
      await expect(deleteLines).toBeDisabled()
      expect(writes).toBe(0)
      await page.screenshot({
        path: testInfo.outputPath(`production-${mode}-delete-lines.png`),
        animations: 'disabled'
      })
      await drawer.getByRole('button', { name: '取消', exact: true }).click()
      await expect(drawer).toHaveCount(0)
    }
    expect(writes).toBe(0)
    await page.getByRole('button', { name: '测试生产单据 create', exact: true }).click()
    await expect(drawer.getByRole('button', { name: '保存', exact: true })).toBeEnabled()
    await expect(drawer.locator('.el-table__body tr')).toHaveCount(0)
    await expect(drawer.getByText(document.document_no, { exact: true })).toHaveCount(0)
    const createRemark = drawer.getByRole('textbox', { name: '备注', exact: true }).first()
    await expect(createRemark).toHaveValue('')
    await createRemark.fill('取消的生产草稿')
    await drawer.getByRole('button', { name: '取消', exact: true }).click()
    await page.getByRole('button', { name: '测试生产单据 create', exact: true }).click()
    await expect(createRemark).toHaveValue('')
    await expect(drawer.locator('.el-table__body tr')).toHaveCount(0)
    await drawer.getByRole('button', { name: '取消', exact: true }).click()
    expect(writes).toBe(0)
    const optionRows: Record<string, object[]> = {
      mdm_organization: [
        {
          id: 'org-test',
          tenant_id: 'tenant-test',
          organization_code: 'ORG-TEST',
          organization_name: '测试生产组织',
          initialization: {
            enabled_on: '2026-10-01',
            initialization_closed_at: '2026-10-02',
            is_default: true
          },
          status: '1'
        }
      ],
      wms_inventory_initialization: [
        {
          organization_id: 'org-test',
          enabled_on: '2026-10-01',
          initialization_closed_at: '2026-10-02',
          is_default: true
        }
      ],
      mdm_warehouse: [
        {
          id: 'warehouse-test',
          tenant_id: 'tenant-test',
          organization_id: 'org-test',
          warehouse_code: 'WH-TEST',
          warehouse_name: '测试生产仓库',
          status: 'enabled',
          warehouse_type: 'finished',
          enable_locations: false
        }
      ],
      mdm_unit_of_measure: [
        { id: 'unit-test', tenant_id: 'tenant-test', unit_code: 'PCS', unit_name: '件' }
      ],
      mdm_document_type: [
        {
          id: 'type-test',
          tenant_id: 'tenant-test',
          document_type_code: 'TYPE-TEST',
          document_type_name: '测试生产类型',
          is_default: true,
          status: 'enabled'
        }
      ],
      mdm_business_type: [
        {
          id: 'business-test',
          tenant_id: 'tenant-test',
          business_type_code: 'BUSINESS-TEST',
          business_type_name: '测试生产业务',
          document_type_id: 'type-test',
          is_default: true,
          status: 'enabled'
        }
      ]
    }
    for (const [tableName, rows] of Object.entries(optionRows))
      await page.route(`**/rest/v1/${tableName}?*`, (route) =>
        route.fulfill({
          json: rows,
          headers: {
            'content-range': rows.length ? `0-${rows.length - 1}/${rows.length}` : '*/0',
            'access-control-expose-headers': 'content-range'
          }
        })
      )
    await page.route('**/rest/v1/wms_production_material_document?*', (route) =>
      route.fulfill({
        json: {
          ...document,
          lines: lines.map((line) => ({
            ...line,
            material: { ...line.material, serial_management_enabled: false },
            work_order_id: 'order-test',
            production_unit_id: 'unit-test',
            source_line_id: negative ? 'source-line-test' : null,
            source_batch_id: kind === 'finished_return' ? 'source-batch-test' : null,
            available_inventory_quantity: 5
          }))
        }
      })
    )
    let saveFailed = true
    const saves: Array<{ p_payload: { save_action: string; kind: string; lines: unknown[] } }> = []
    await page.route('**/rpc/wms_save_production_material_secure', (route) => {
      saves.push(route.request().postDataJSON())
      return route.fulfill(
        saveFailed
          ? { status: 400, json: { code: 'P0001', message: '测试生产单据保存失败' } }
          : { json: 'saved-production-test' }
      )
    })
    for (const saveMode of ['edit', 'copy', 'edit-deleted', 'copy-deleted']) {
      saveFailed = true
      const mode = saveMode.startsWith('copy') ? 'copy' : 'edit'
      const deletedLine = saveMode.endsWith('-deleted')
      await page.getByRole('button', { name: `测试生产单据 ${mode}`, exact: true }).click()
      const saveButton = drawer.getByRole('button', {
        name: mode === 'copy' ? '保存副本' : '保存',
        exact: true
      })
      await expect(saveButton).toBeEnabled()
      await expect(drawer.getByText('测试生产类型', { exact: true })).toBeVisible()
      await expect(drawer.getByText('测试生产业务', { exact: true })).toBeVisible()
      if (deletedLine) {
        await drawer.locator('.el-table__body tr').first().locator('.el-checkbox').click()
        await drawer.getByRole('button', { name: '批量删除', exact: true }).click()
        await expect(drawer.locator('.el-table__body tr')).toHaveCount(1)
      }
      await saveButton.click()
      await expect(page.getByText('测试生产单据保存失败', { exact: true }).first()).toBeVisible()
      await expect(drawer.locator('.el-table__body tr')).toHaveCount(deletedLine ? 1 : 2)
      await expect(drawer.getByRole('textbox', { name: '备注', exact: true }).first()).toHaveValue(
        document.remark
      )
      await page.screenshot({
        path: testInfo.outputPath(`production-${saveMode}-save-error.png`),
        animations: 'disabled'
      })
      saveFailed = false
      await saveButton.click()
      await expect(drawer).toBeHidden()
    }
    expect(saves).toHaveLength(8)
    expect(saves[0]).toEqual(saves[1])
    expect(saves[2]).toEqual(saves[3])
    expect(saves[4]).toEqual(saves[5])
    expect(saves[6]).toEqual(saves[7])
    for (const entry of saves.slice(4)) {
      expect(entry.p_payload.lines).toHaveLength(1)
      expect(entry.p_payload.lines[0]).toMatchObject({
        material_id: 'material-2',
        serial_ids: [],
        serial_nos: [],
        line_no: 10
      })
    }
    expect(saves.map((entry) => entry.p_payload.save_action)).toEqual([
      'edit',
      'edit',
      'copy',
      'copy',
      'edit',
      'edit',
      'copy',
      'copy'
    ])
    expect(
      saves.every(
        (entry, index) =>
          entry.p_payload.kind === kind && entry.p_payload.lines.length === (index < 4 ? 2 : 1)
      )
    ).toBe(true)
    {
      await page.route('**/rest/v1/mdm_material?*', (route) =>
        route.fulfill({
          json: [1, 2].map((n) => ({
            id: `new-material-${n}`,
            material_code: `NEW-MAT-${n}`,
            material_name: `新增生产物料${n}`,
            serial_management_enabled: false,
            inventory_unit_id: 'unit-test',
            production_unit_id: 'unit-test',
            unit_conversions: []
          })),
          headers: { 'content-range': '0-1/2', 'access-control-expose-headers': 'content-range' }
        })
      )
      await page.route('**/rpc/wms_work_order_options_secure', (route) =>
        route.fulfill({
          json: [1, 2].map((n) => ({
            id: `new-order-${n}`,
            work_order_no: `NEW-ORDER-${n}`,
            material_id: `new-material-${n}`,
            order_quantity: 5,
            completed_quantity: 4,
            warehoused_quantity: 1,
            project_id: null,
            construction_no: null
          }))
        })
      )
      await page.route('**/rest/v1/wms_finished_inbound_source_list?*', (route) =>
        route.fulfill({
          json: [1, 2].map((n) => ({
            id: `new-source-${n}`,
            document_no: `NEW-INBOUND-${n}`,
            line_no: n * 10,
            material_id: `new-material-${n}`,
            material_code: `NEW-MAT-${n}`,
            material_name: `新增生产物料${n}`,
            work_order_id: 'new-order-1',
            work_order_no: 'NEW-ORDER-1',
            warehouse_id: 'warehouse-test',
            inventory_unit_id: 'unit-test',
            production_unit_id: 'unit-test',
            inbound_quantity: 4,
            available_quantity: 4,
            source_batch_id: `new-batch-${n}`,
            stock_type: 'normal',
            owner_type: 'self',
            owner_id: null,
            stock_status: 'available'
          })),
          headers: { 'content-range': '0-1/2', 'access-control-expose-headers': 'content-range' }
        })
      )
      for (const draft of [1, 2]) {
        await page.getByRole('button', { name: '测试生产单据 create', exact: true }).click()
        const warehouseField = drawer
          .locator('.el-form-item')
          .filter({ has: page.getByText('仓库', { exact: true }) })
        await warehouseField.getByRole('combobox').press('ArrowDown')
        await page.getByRole('option', { name: '测试生产仓库 · WH-TEST', exact: true }).click()
        await drawer
          .getByRole('button', {
            name:
              kind === 'finished_inbound'
                ? '选生产工单'
                : kind === 'finished_return'
                  ? '选单'
                  : '选择物料',
            exact: true
          })
          .click()
        const picker = page.locator('.el-dialog:visible')
        await expect(
          picker.getByText(
            kind === 'finished_inbound'
              ? 'NEW-ORDER-2'
              : kind === 'finished_return'
                ? 'NEW-INBOUND-2'
                : 'NEW-MAT-2',
            { exact: true }
          )
        ).toBeVisible()
        await picker.locator('.el-table__header-wrapper .el-checkbox').click()
        await expect(
          picker.getByRole('checkbox', { name: '选择所有行', exact: true })
        ).toBeChecked()
        await page.screenshot({
          path: testInfo.outputPath(`production-new-picker-${draft}.png`),
          animations: 'disabled'
        })
        await picker.getByRole('button', { name: /确定|确认/ }).click()
        await expect(drawer.locator('.el-table__body tr')).toHaveCount(2)
        for (const row of await drawer.locator('.el-table__body tr').all()) {
          for (const input of (await row.getByRole('spinbutton').all()).slice(0, 2)) {
            await input.fill('2')
            await input.press('Tab')
          }
        }
        await drawer
          .getByRole('textbox', { name: '备注', exact: true })
          .first()
          .fill(`新增生产测试单据${draft}`)
        saveFailed = true
        await drawer.getByRole('button', { name: '保存', exact: true }).click()
        await expect(page.getByText('测试生产单据保存失败', { exact: true }).first()).toBeVisible()
        await drawer.locator('.el-table__body tr').last().scrollIntoViewIfNeeded()
        await page.screenshot({
          path: testInfo.outputPath(`production-new-save-error-${draft}.png`),
          animations: 'disabled'
        })
        saveFailed = false
        await drawer.getByRole('button', { name: '保存', exact: true }).click()
        await expect(drawer).toBeHidden()
      }
      expect(saves).toHaveLength(8)
      expect(
        saves
          .slice(4)
          .every(
            (entry) => entry.p_payload.save_action === 'add' && entry.p_payload.lines.length === 2
          )
      ).toBe(true)
    }
    expect(errors).toEqual([])
  })
}
