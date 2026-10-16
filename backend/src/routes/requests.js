const express = require('express');
const fs = require('node:fs');
const path = require('node:path');
const PDFDocument = require('pdfkit');
const { Request, DocumentType, Template, DocumentVersion, AuthorityTask, RequestHistory, User, Notification } = require('../models');
const { authenticate, allow } = require('../middleware/auth');
const { singlePdf, supportingFiles, removeUploadedFile } = require('../middleware/upload');
const { asyncHandler, fail } = require('../utils/errors');
const response = require('../utils/response');
const { requireFields, objectId, text } = require('../utils/validation');
const workflow = require('../services/workflow');
const { audit } = require('../services/audit');
const { isConfiguredWorkflow, studentMayReadFile, workflowMatchesDocumentType } = require('../services/workflowRules');
const { parseFields, documentTypeIdFrom } = require('../utils/requestPayload');
const config = require('../config');
const { storageDir } = config;

const router = express.Router();
router.use(authenticate);
const staff = allow('coordinator', 'admin');

router.post('/requests', allow('student'), supportingFiles, asyncHandler(async (req, res) => {
  let created;
  try {
    const documentTypeId = documentTypeIdFrom(req.body);
    requireFields({ documentTypeId, fields: req.body.fields }, ['documentTypeId', 'fields']);
    objectId(documentTypeId, 'documentTypeId');
    const fields = parseFields(req.body.fields);
    const type = await DocumentType.findOne({ _id: documentTypeId, active: true });
    if (!type) fail('Active document type not found', 404, 'NOT_FOUND');
    const missing = type.requiredFields.filter((field) => typeof fields[field] !== 'string' || !fields[field].trim());
    if (missing.length) fail(`Required document fields: ${missing.join(', ')}`, 422, 'VALIDATION_ERROR');
    const files = req.files || [];
    created = await Request.create({
      student: req.user._id, documentType: type._id,
      fields, studentMessage: req.body.message || '',
      supportingFiles: files.map((file) => ({
        storageName: file.filename,
        originalName: file.originalname,
        mimeType: file.mimetype,
        size: file.size
      }))
    });
    await workflow.createHistory(created, req.user, 'request-submitted', null, created.status, req.body.message, null);
    await audit(req, 'request.created', 'Request', created.id);
    const coordinators = await User.find({ role: 'coordinator', active: true }).select('_id');
    if (coordinators.length) {
      await Notification.insertMany(
        coordinators.map(({ _id }) => ({
          user: _id,
          request: created._id,
          message: 'A new student document request is ready for review'
        }))
      );
    }
    return response(res, created, 201);
  } catch (error) {
    if (!created) removeUploadedFile(req);
    throw error;
  }
}));

router.get('/requests/my', allow('student'), asyncHandler(async (req, res) => {
  const items = await Request.find({ student: req.user._id }).sort({ createdAt: -1 }).populate('documentType', 'name').populate('finalVersion');
  response(res, items);
}));

async function requestAccess(requestId, user) {
  const request = await Request.findById(requestId);
  if (!request) fail('Request not found', 404, 'NOT_FOUND');
  if (user.role === 'student' && String(request.student) !== String(user._id)) fail('Forbidden', 403, 'FORBIDDEN');
  if (user.role === 'coordinator' && request.coordinator && String(request.coordinator) !== String(user._id)) fail('Forbidden', 403, 'FORBIDDEN');
  if (user.role === 'authority') {
    const assigned = await AuthorityTask.exists({ request: request._id, authority: user._id });
    if (!assigned) fail('Forbidden', 403, 'FORBIDDEN');
  }
  return request;
}

router.get('/requests/:id/progress', asyncHandler(async (req, res) => {
  objectId(req.params.id);
  const request = await requestAccess(req.params.id, req.user);
  const timeline = await RequestHistory.find({ request: request._id })
    .sort({ createdAt: 1 }).populate('actor', 'name role');
  response(res, { request, timeline });
}));
router.get('/requests/:id/history', asyncHandler(async (req, res) => {
  objectId(req.params.id);
  const request = await requestAccess(req.params.id, req.user);
  response(res, await RequestHistory.find({ request: request._id }).sort({ createdAt: 1 }).populate('actor', 'name role'));
}));

async function statusAction(req, action) {
  objectId(req.params.id);
  return workflow.coordinatorTransition({ id: req.params.id, actor: req.user, action, message: req.body.message, fields: req.body.fields });
}
router.post('/requests/:id/accept', staff, asyncHandler(async (req, res) => response(res, await statusAction(req, 'accept'))));
router.post('/requests/:id/request-information', staff, asyncHandler(async (req, res) => response(res, await statusAction(req, 'request-information'))));
router.post('/requests/:id/reject', staff, asyncHandler(async (req, res) => response(res, await statusAction(req, 'reject'))));
router.post('/requests/:id/submit-correction', allow('student'), asyncHandler(async (req, res) => {
  objectId(req.params.id);
  const current = await Request.findById(req.params.id);
  if (!current || String(current.student) !== String(req.user._id)) fail('Request not found', 404, 'NOT_FOUND');
  if (req.body.fields !== undefined) {
    if (!req.body.fields || typeof req.body.fields !== 'object' || Array.isArray(req.body.fields)) fail('fields must be an object', 422, 'VALIDATION_ERROR');
    const type = await DocumentType.findById(current.documentType);
    const oldFields = current.fields && typeof current.fields.toObject === 'function' ? current.fields.toObject() : current.fields;
    const updated = { ...oldFields, ...req.body.fields };
    const missing = type.requiredFields.filter((field) => typeof updated[field] !== 'string' || !updated[field].trim());
    if (missing.length) fail(`Required document fields: ${missing.join(', ')}`, 422, 'VALIDATION_ERROR');
    req.body.fields = updated;
  }
  response(res, await statusAction(req, 'submit-correction'));
}));
router.post('/requests/:id/cancel', asyncHandler(async (req, res) => {
  objectId(req.params.id);
  response(res, await statusAction(req, 'cancel'));
}));

function configuredWorkflow(type, selected, workflowId) {
  if (!type) fail('Document type not found', 404, 'NOT_FOUND');
  if (!workflowMatchesDocumentType(type._id, workflowId)) fail('workflowId must match the request document type', 422, 'INVALID_WORKFLOW');
  const configured = type.workflow.map((step) => ({ authority: step.authority, label: step.label }));
  if (!configured.length) fail('No signature workflow is configured for this document type', 409, 'WORKFLOW_NOT_CONFIGURED');
  if (!isConfiguredWorkflow(selected, configured)) fail('Only the document type configured workflow can be selected', 422, 'INVALID_WORKFLOW');
  return configured;
}

function parseWorkflow(body) {
  if (typeof body.workflow !== 'string') return body.workflow;
  try { return JSON.parse(body.workflow); }
  catch { fail('workflow must contain valid JSON', 422, 'INVALID_JSON_WORKFLOW'); }
}

function renderedText(body, fields, student) {
  const values = { ...fields, studentName: student.name, studentId: student.studentId || '', email: student.email };
  return body.replace(/\{\{\s*([a-zA-Z0-9_.-]+)\s*\}\}/g, (_, key) => String(values[key] ?? ''));
}

router.post('/requests/:id/generate-document', staff, asyncHandler(async (req, res) => {
  objectId(req.params.id);
  requireFields(req.body, ['templateId']);
  objectId(req.body.templateId, 'templateId');
  const request = await Request.findById(req.params.id).populate('student');
  if (!request) fail('Request not found', 404, 'NOT_FOUND');
  if (request.status !== 'accepted') fail('Request must be accepted before a document can be generated', 409, 'INVALID_STATE');
  if (request.coordinator && String(request.coordinator) !== String(req.user._id) && req.user.role !== 'admin') fail('Request is assigned to another coordinator', 403, 'FORBIDDEN');
  const template = await Template.findOne({ _id: req.body.templateId, documentType: request.documentType, active: true });
  if (!template) fail('Active template for this document type not found', 404, 'NOT_FOUND');
  const type = await DocumentType.findById(request.documentType);
  const chain = configuredWorkflow(type, parseWorkflow(req.body), req.body.workflowId);
  const filename = `${require('node:crypto').randomUUID()}.pdf`;
  const filepath = path.join(storageDir, filename);
  const doc = new PDFDocument({ size: 'A4', margin: 55 });
  const stream = fs.createWriteStream(filepath);
  doc.pipe(stream);
  doc.fontSize(18).text(template.name, { align: 'center' }).moveDown();
  doc.fontSize(12).text(renderedText(template.body, request.fields, request.student), { lineGap: 4 });
  doc.end();
  await new Promise((resolve, reject) => { stream.on('finish', resolve); stream.on('error', reject); });
  try {
    const result = await workflow.attachPreparedVersion({
      requestId: request.id, actor: req.user, file: { filename, originalname: `${template.name}.pdf`, mimetype: 'application/pdf', size: fs.statSync(filepath).size },
      notes: req.body.message, workflow: chain, generated: true
    });
    await audit(req, 'request.document-generated', 'Request', request.id);
    return response(res, result, 201);
  } catch (error) { fs.promises.unlink(filepath).catch(() => {}); throw error; }
}));

router.post('/requests/:id/submit-for-signature', staff, asyncHandler(async (req, res) => {
  objectId(req.params.id);
  const request = await Request.findById(req.params.id);
  if (!request) fail('Request not found', 404, 'NOT_FOUND');
  if (request.status !== 'prepared') fail('A prepared document is required before starting the workflow', 409, 'INVALID_STATE');
  if (request.coordinator && String(request.coordinator) !== String(req.user._id) && req.user.role !== 'admin') fail('Request is assigned to another coordinator', 403, 'FORBIDDEN');
  const type = await DocumentType.findById(request.documentType);
  const chain = configuredWorkflow(type, parseWorkflow(req.body), req.body.workflowId);
  const version = await DocumentVersion.findById(request.currentVersion);
  if (!version || version.kind !== 'prepared') fail('Upload or generate the prepared document first', 409, 'INVALID_STATE');
  request.selectedWorkflow = chain;
  await request.save();
  response(res, await workflow.startWorkflow({ requestId: request.id, actor: req.user }));
}));

router.post('/requests/:id/verification/accept', staff, asyncHandler(async (req, res) => {
  objectId(req.params.id);
  response(res, await workflow.verifySigned({ requestId: req.params.id, actor: req.user, accept: true, message: req.body.message }));
}));
router.post('/requests/:id/verification/return', staff, asyncHandler(async (req, res) => {
  objectId(req.params.id);
  response(res, await workflow.verifySigned({ requestId: req.params.id, actor: req.user, accept: false, message: req.body.message }));
}));
router.post('/requests/:id/publish', staff, singlePdf('file'), asyncHandler(async (req, res) => {
  try {
    objectId(req.params.id);
    const result = await workflow.finalize({ requestId: req.params.id, actor: req.user, file: req.file && {
      filename: req.file.filename, originalname: req.file.originalname, mimetype: req.file.mimetype, size: req.file.size
    }, message: req.body.message, publish: true });
    await audit(req, 'request.published', 'Request', req.params.id);
    response(res, result);
  } catch (error) { removeUploadedFile(req); throw error; }
}));
router.post('/requests/:id/verification/complete', staff, singlePdf('file'), asyncHandler(async (req, res) => {
  try {
    objectId(req.params.id);
    response(res, await workflow.finalize({ requestId: req.params.id, actor: req.user, file: req.file && {
      filename: req.file.filename, originalname: req.file.originalname, mimetype: req.file.mimetype, size: req.file.size
    }, message: req.body.message, publish: false }));
  } catch (error) { removeUploadedFile(req); throw error; }
}));

router.post('/requests/:id/prepare-upload', staff, singlePdf('file'), asyncHandler(async (req, res) => {
  try {
    objectId(req.params.id);
    if (!req.file) fail('PDF field "file" is required', 422, 'FILE_REQUIRED');
    const request = await Request.findById(req.params.id);
    if (!request) fail('Request not found', 404, 'NOT_FOUND');
    const type = await DocumentType.findById(request.documentType);
    const chain = configuredWorkflow(type, parseWorkflow(req.body), req.body.workflowId);
    if (request.coordinator && String(request.coordinator) !== String(req.user._id) && req.user.role !== 'admin') fail('Request is assigned to another coordinator', 403, 'FORBIDDEN');
    const upload = {
      filename: req.file.filename,
      originalname: req.file.originalname,
      mimetype: req.file.mimetype,
      size: req.file.size
    };
    const result = request.status === 'authority_correction'
      ? await workflow.replaceAfterAuthorityReturn({
          requestId: request.id, actor: req.user, file: upload, notes: req.body.message
        })
      : await workflow.attachPreparedVersion({
          requestId: request.id, actor: req.user, file: upload,
          notes: req.body.message, workflow: chain, generated: false
        });
    response(res, result, 201);
  } catch (error) { removeUploadedFile(req); throw error; }
}));

router.get('/coordinator/requests', staff, asyncHandler(async (req, res) => {
  const filter = req.user.role === 'admin' ? {} : { $or: [{ coordinator: req.user._id }, { coordinator: null }] };
  if (req.query.status) filter.status = req.query.status;
  const items = await Request.find(filter).sort({ updatedAt: -1 }).populate('student', 'name email studentId').populate('documentType', 'name');
  response(res, items);
}));
router.get('/coordinator/stats', staff, asyncHandler(async (req, res) => {
  const filter = req.user.role === 'admin' ? {} : { $or: [{ coordinator: req.user._id }, { coordinator: null }] };
  const [grouped, types] = await Promise.all([
    Request.aggregate([{ $match: filter }, { $group: { _id: '$status', count: { $sum: 1 } } }]),
    DocumentType.find({ active: true, 'workflow.0': { $exists: true } })
      .populate('workflow.authority', 'name role active')
  ]);
  const signingWorkflows = types
    .filter((type) => type.workflow.every((step) => step.authority?.active && step.authority.role === 'authority'))
    .map((type) => ({ id: type.id, label: type.name }));
  response(res, { ...Object.fromEntries(grouped.map((row) => [row._id, row.count])), signingWorkflows });
}));

router.get('/authority/tasks', allow('authority'), asyncHandler(async (req, res) => {
  const filter = { authority: req.user._id };
  if (req.query.status) filter.status = req.query.status;
  response(res, await AuthorityTask.find(filter).sort({ status: 1, createdAt: -1 }).populate('request', 'status documentType student currentStep').populate({ path: 'request', populate: [{ path: 'student', select: 'name studentId' }, { path: 'documentType', select: 'name' }] }));
}));
router.get('/authority/tasks/:id', allow('authority'), asyncHandler(async (req, res) => {
  objectId(req.params.id);
  const task = await AuthorityTask.findOne({ _id: req.params.id, authority: req.user._id }).populate({ path: 'request', populate: [{ path: 'student', select: 'name studentId' }, { path: 'documentType', select: 'name' }, { path: 'currentVersion' }] });
  if (!task) fail('Task not found', 404, 'NOT_FOUND');
  response(res, task);
}));
router.post('/authority/tasks/:id/upload-signed-document', allow('authority'), singlePdf('file'), asyncHandler(async (req, res) => {
  try {
    objectId(req.params.id);
    if (!req.file) fail('PDF field "file" is required', 422, 'FILE_REQUIRED');
    const result = await workflow.uploadSigned({ taskId: req.params.id, actor: req.user, file: {
      filename: req.file.filename, originalname: req.file.originalname, mimetype: req.file.mimetype, size: req.file.size
    }, message: req.body.message });
    response(res, result, 201);
  } catch (error) { removeUploadedFile(req); throw error; }
}));
router.post('/authority/tasks/:id/return-for-correction', allow('authority'), asyncHandler(async (req, res) => {
  objectId(req.params.id);
  response(res, await workflow.returnForCorrection({ taskId: req.params.id, actor: req.user, message: req.body.message }));
}));

router.get('/files/:versionId/:operation(preview|download)', asyncHandler(async (req, res) => {
  objectId(req.params.versionId);
  const version = await DocumentVersion.findById(req.params.versionId);
  if (!version) fail('File not found', 404, 'NOT_FOUND');
  const request = await Request.findById(version.request);
  if (!request) fail('File not found', 404, 'NOT_FOUND');
  const user = req.user;
  let allowed = false;
  if (user.role === 'student') allowed = studentMayReadFile(request, version._id, user._id);
  if (user.role === 'coordinator' || user.role === 'admin') allowed = user.role === 'admin' || !request.coordinator || String(request.coordinator) === String(user._id);
  if (user.role === 'authority') {
    const ownSignedVersion = await AuthorityTask.exists({
      request: request._id,
      authority: user._id,
      signedVersion: version._id
    });
    const activeTask = await AuthorityTask.exists({
      request: request._id,
      authority: user._id,
      status: 'active'
    });
    allowed = Boolean(
      ownSignedVersion ||
      (activeTask && String(request.currentVersion) === String(version._id))
    );
  }
  if (!allowed) fail('Forbidden', 403, 'FORBIDDEN');
  const filepath = path.join(storageDir, path.basename(version.storageName));
  if (!fs.existsSync(filepath)) fail('Stored file is unavailable', 404, 'FILE_NOT_FOUND');
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Content-Disposition', `${req.params.operation === 'download' ? 'attachment' : 'inline'}; filename="${path.basename(version.originalName).replace(/["\\\r\n]/g, '_')}"`);
  fs.createReadStream(filepath).pipe(res);
}));

router.get('/notifications', asyncHandler(async (req, res) => {
  response(res, await Notification.find({ user: req.user._id }).sort({ createdAt: -1 }).limit(100).populate('request', 'status documentType'));
}));
router.patch('/notifications/:id/read', asyncHandler(async (req, res) => {
  objectId(req.params.id);
  const notification = await Notification.findOneAndUpdate({ _id: req.params.id, user: req.user._id }, { $set: { readAt: new Date() } }, { new: true });
  if (!notification) fail('Notification not found', 404, 'NOT_FOUND');
  response(res, notification);
}));

router.get('/admin/users', allow('admin'), asyncHandler(async (req, res) => {
  const filter = {};
  if (req.query.role) filter.role = req.query.role;
  response(res, await User.find(filter).select('-passwordHash -resetTokenHash -resetTokenExpiresAt').sort({ createdAt: -1 }));
}));
router.patch('/admin/users/:id', allow('admin'), asyncHandler(async (req, res) => {
  objectId(req.params.id);
  const allowed = ['name', 'role', 'department', 'studentId', 'active'];
  const patch = Object.fromEntries(Object.entries(req.body).filter(([key]) => allowed.includes(key)));
  if (!Object.keys(patch).length) fail('No supported user fields supplied', 422, 'VALIDATION_ERROR');
  if (patch.role && !['student', 'coordinator', 'authority', 'admin'].includes(patch.role)) fail('Invalid role', 422, 'VALIDATION_ERROR');
  const user = await User.findByIdAndUpdate(req.params.id, { $set: patch }, { new: true, runValidators: true });
  if (!user) fail('User not found', 404, 'NOT_FOUND');
  await audit(req, 'user.updated', 'User', user.id, patch);
  response(res, user);
}));
router.get('/admin/audit-logs', allow('admin'), asyncHandler(async (req, res) => {
  const limit = Math.min(Math.max(Number(req.query.limit) || 50, 1), 200);
  response(res, await require('../models').AuditLog.find().sort({ createdAt: -1 }).limit(limit).populate('actor', 'name email role'));
}));

module.exports = router;
