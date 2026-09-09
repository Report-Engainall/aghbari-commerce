import { describe, expect, it } from 'vitest';
import { MAX_IMPORT_FILE_BYTES } from '../domain/import';
import { parseProductWorkbook } from './importExcel';

describe('XLSX import guardrails', () => {
  it('rejects non-XLSX files before parsing', async () => {
    await expect(parseProductWorkbook(new File(['x'], 'products.csv', { type: 'text/csv' }))).rejects.toThrow('XLSX');
  });

  it('rejects oversized workbooks before invoking the parser', async () => {
    const bytes = new Uint8Array(MAX_IMPORT_FILE_BYTES + 1);
    bytes.set([0x50, 0x4b, 0x03, 0x04]);
    const file = new File([bytes], 'products.xlsx', { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });
    await expect(parseProductWorkbook(file)).rejects.toThrow('100 MB');
  });

  it('rejects XLSX-looking filenames whose bytes are not a ZIP container', async () => {
    const file = new File(['not-an-xlsx'], 'products.xlsx', { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });
    await expect(parseProductWorkbook(file)).rejects.toThrow('حاوية XLSX');
  });

  it('accepts the standard XLSX ZIP signatures before spreadsheet parsing', async () => {
    const signatures = [new Uint8Array([0x50, 0x4b, 0x03, 0x04]), new Uint8Array([0x50, 0x4b, 0x05, 0x06]), new Uint8Array([0x50, 0x4b, 0x07, 0x08])];
    for (const signature of signatures) {
      const file = new File([signature], 'products.xlsx', { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });
      await expect(parseProductWorkbook(file)).rejects.not.toThrow('حاوية XLSX');
    }
  });
});
