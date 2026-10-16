const test = require('node:test');
const assert = require('node:assert/strict');
const { isConfiguredWorkflow, statusAfterStep, workflowMatchesDocumentType, studentMayReadFile } = require('../src/services/workflowRules');
const { parseFields, documentTypeIdFrom } = require('../src/utils/requestPayload');
const { hasPdfSignature } = require('../src/middleware/upload');

test('only the configured authority chain can be submitted', () => {
  const configured = [{ authority: 'a1', label: 'Registrar' }, { authority: 'a2', label: 'Dean' }];
  assert.equal(isConfiguredWorkflow(undefined, configured), true);
  assert.equal(isConfiguredWorkflow(configured, configured), true);
  assert.equal(isConfiguredWorkflow([{ authority: 'a2', label: 'Dean' }], configured), false);
  assert.equal(isConfiguredWorkflow([{ authority: 'other', label: 'Registrar' }, configured[1]], configured), false);
});

test('workflow selection identifier is bound to its request document type', () => {
  assert.equal(workflowMatchesDocumentType('type-a', undefined), true);
  assert.equal(workflowMatchesDocumentType('type-a', 'type-a'), true);
  assert.equal(workflowMatchesDocumentType('type-a', 'type-b'), false);
});

test('multipart request fields are parsed as JSON objects and documentTypeId is accepted', () => {
  assert.deepEqual(parseFields('{"studentName":"Ada"}'), { studentName: 'Ada' });
  assert.deepEqual(parseFields({ studentName: 'Ada' }), { studentName: 'Ada' });
  assert.equal(documentTypeIdFrom({ documentTypeId: 'new-id' }), 'new-id');
  assert.equal(documentTypeIdFrom({ documentType: 'legacy-id' }), 'legacy-id');
  assert.throws(() => parseFields('{bad json}'), /valid JSON/);
  assert.throws(() => parseFields('[]'), /JSON object/);
});

test('accepted signature steps activate only the next task, then enter final verification', () => {
  assert.equal(statusAfterStep(true), 'in_workflow');
  assert.equal(statusAfterStep(false), 'final_verification');
});

test('only a published final version is student-downloadable', () => {
  assert.equal(studentMayReadFile({ status: 'published', student: 's1', finalVersion: 'v3' }, 'v3', 's1'), true);
  assert.equal(studentMayReadFile({ status: 'in_workflow', student: 's1', finalVersion: 'v3' }, 'v3', 's1'), false);
  assert.equal(studentMayReadFile({ status: 'published', student: 's1', finalVersion: 'v3' }, 'v2', 's1'), false);
});

test('uploads are validated by PDF file signature, not MIME label alone', () => {
  assert.equal(hasPdfSignature(Buffer.from('%PDF-1.7')), true);
  assert.equal(hasPdfSignature(Buffer.from('not a pdf')), false);
  assert.equal(hasPdfSignature(Buffer.from('%PDF')), false);
});
