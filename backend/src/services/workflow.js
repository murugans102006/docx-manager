const mongoose = require('mongoose');
const { Request, RequestHistory, Notification, AuthorityTask, DocumentVersion, User, AuditLog } = require('../models');
const { fail } = require('../utils/errors');
const { statusAfterStep } = require('./workflowRules');

async function transact(callback) {
  const session = await mongoose.startSession();
  let result;
  try {
    await session.withTransaction(async () => { result = await callback(session); });
    return result;
  } finally { await session.endSession(); }
}

async function loadRequest(id, session) {
  const request = await Request.findById(id).session(session);
  if (!request) fail('Request not found', 404, 'NOT_FOUND');
  return request;
}

async function event(request, actor, action, fromStatus, toStatus, message, session, version) {
  await RequestHistory.create([{ request: request._id, actor: actor?._id || actor, action, fromStatus, toStatus, message, version }], { session });
  await AuditLog.create([{
    actor: actor?._id || actor, action: `request.${action}`, targetType: 'Request', targetId: String(request._id),
    details: { fromStatus, toStatus, message, version: version ? String(version) : undefined }
  }], { session });
}

async function notify(user, request, message, session) {
  if (user) await Notification.create([{ user, request, message }], { session });
}

exports.transact = transact;
exports.createHistory = event;
exports.notify = notify;

exports.coordinatorTransition = async ({ id, actor, action, message, fields }) => transact(async (session) => {
  const request = await loadRequest(id, session);
  if (request.status === 'published' || ['rejected', 'cancelled'].includes(request.status)) fail('Request is already closed', 409, 'INVALID_STATE');
  if (actor.role === 'coordinator' && request.coordinator && String(request.coordinator) !== String(actor._id)) fail('Request is assigned to another coordinator', 403, 'FORBIDDEN');
  const from = request.status;
  if (action === 'accept') {
    if (from !== 'submitted') fail('Request cannot be accepted in its current state', 409, 'INVALID_STATE');
    await AuthorityTask.updateMany({ request: request._id, status: { $ne: 'cancelled' } }, { $set: { status: 'cancelled' } }, { session });
    request.status = 'accepted';
    request.coordinator = actor._id;
    request.coordinatorMessage = message || '';
  } else if (action === 'request-information') {
    if (!['submitted', 'correction_requested'].includes(from)) fail('Information cannot be requested in this state', 409, 'INVALID_STATE');
    if (!message) fail('A message is required', 422, 'VALIDATION_ERROR');
    request.status = 'information_requested';
    request.coordinator = actor._id;
    request.coordinatorMessage = message;
  } else if (action === 'reject') {
    if (!['submitted', 'correction_requested', 'information_requested'].includes(from)) fail('Request cannot be rejected in this state', 409, 'INVALID_STATE');
    if (!message) fail('A reason is required', 422, 'VALIDATION_ERROR');
    request.status = 'rejected'; request.coordinator = actor._id; request.coordinatorMessage = message;
  } else if (action === 'submit-correction') {
    if (!['information_requested', 'correction_requested'].includes(from)) fail('No information or correction has been requested', 409, 'INVALID_STATE');
    request.status = 'submitted'; request.studentMessage = message || '';
    if (fields !== undefined) request.fields = fields;
  } else if (action === 'cancel') {
    if (!['submitted', 'information_requested', 'correction_requested', 'accepted', 'prepared'].includes(from)) fail('Request cannot be cancelled in its current state', 409, 'INVALID_STATE');
    if (String(request.student) !== String(actor._id) && actor.role !== 'admin' &&
      !(actor.role === 'coordinator' && (!request.coordinator || String(request.coordinator) === String(actor._id)))) fail('Only the student or assigned coordinator may cancel this request', 403, 'FORBIDDEN');
    request.status = 'cancelled';
  }
  request.revision += 1;
  await request.save({ session });
  await event(request, actor, action, from, request.status, message, session);
  await notify(request.student, request._id, `Request ${request.status.replaceAll('_', ' ')}`, session);
  return request;
});

exports.attachPreparedVersion = async ({ requestId, actor, file, notes, workflow, generated }) => transact(async (session) => {
  const request = await loadRequest(requestId, session);
  if (request.status !== 'accepted') fail('Request must be accepted before preparing a document', 409, 'INVALID_STATE');
  if (!Array.isArray(workflow) || !workflow.length) fail('Choose a configured workflow with at least one authority', 422, 'VALIDATION_ERROR');
  const current = (request.currentVersion ? await DocumentVersion.findById(request.currentVersion).session(session) : null);
  const version = await DocumentVersion.create([{
    request: request._id, number: current ? current.number + 1 : 1, kind: 'prepared',
    storageName: file.filename, originalName: file.originalname, mimeType: file.mimetype,
    size: file.size, uploadedBy: actor._id, notes
  }], { session });
  request.currentVersion = version[0]._id;
  request.selectedWorkflow = workflow.map((step) => ({ authority: step.authority, label: step.label }));
  request.status = 'prepared'; request.coordinator = actor._id; request.revision += 1;
  await request.save({ session });
  await event(request, actor, generated ? 'document-generated' : 'document-uploaded', 'accepted', 'prepared', notes, session, version[0]._id);
  await notify(request.student, request._id, 'Your document is being prepared for signature', session);
  return { request, version: version[0] };
});

exports.replaceAfterAuthorityReturn = async ({ requestId, actor, file, notes }) => transact(async (session) => {
  const request = await loadRequest(requestId, session);
  if (request.status !== 'authority_correction') fail('The request is not awaiting coordinator corrections', 409, 'INVALID_STATE');
  if (request.coordinator && String(request.coordinator) !== String(actor._id) && actor.role !== 'admin') fail('Request is assigned to another coordinator', 403, 'FORBIDDEN');
  const previous = request.currentVersion
    ? await DocumentVersion.findById(request.currentVersion).session(session)
    : null;
  if (!previous) fail('Current document version is unavailable', 409, 'INVALID_STATE');
  const versions = await DocumentVersion.create([{
    request: request._id,
    number: previous.number + 1,
    kind: 'prepared',
    storageName: file.filename,
    originalName: file.originalname,
    mimeType: file.mimetype,
    size: file.size,
    uploadedBy: actor._id,
    notes
  }], { session });
  await AuthorityTask.updateMany(
    { request: request._id, status: { $ne: 'cancelled' } },
    { $set: { status: 'cancelled' } },
    { session }
  );
  const from = request.status;
  request.currentVersion = versions[0]._id;
  request.currentStep = -1;
  request.status = 'prepared';
  request.revision += 1;
  await request.save({ session });
  await event(request, actor, 'document-corrected-after-authority-return', from, request.status, notes, session, versions[0]._id);
  await notify(request.student, request._id, 'The coordinator is preparing a corrected document', session);
  return { request, version: versions[0] };
});

exports.startWorkflow = async ({ requestId, actor }) => transact(async (session) => {
  const request = await loadRequest(requestId, session);
  if (request.status !== 'prepared' || !request.currentVersion || !request.selectedWorkflow.length) fail('A prepared document and workflow are required', 409, 'INVALID_STATE');
  const authorityIds = request.selectedWorkflow.map((step) => step.authority);
  const activeAuthorities = await User.countDocuments({ _id: { $in: authorityIds }, role: 'authority', active: true }).session(session);
  if (activeAuthorities !== authorityIds.length) fail('The configured workflow contains an inactive authority', 409, 'WORKFLOW_NOT_AVAILABLE');
  const existing = await AuthorityTask.findOne({ request: request._id }).session(session);
  if (existing) {
    const activeTasks = await AuthorityTask.countDocuments({ request: request._id, status: { $ne: 'cancelled' } }).session(session);
    if (activeTasks) fail('Signature workflow has already started', 409, 'DUPLICATE_ACTION');
    await AuthorityTask.deleteMany({ request: request._id, status: 'cancelled' }, { session });
  }
  const now = new Date();
  const taskData = request.selectedWorkflow.map((step, index) => ({
    request: request._id, authority: step.authority, step: index, label: step.label,
    status: index === 0 ? 'active' : 'pending', activatedAt: index === 0 ? now : undefined
  }));
  await AuthorityTask.create(taskData, { session });
  const from = request.status; request.status = 'in_workflow'; request.currentStep = 0; request.coordinator = actor._id; request.revision += 1;
  await request.save({ session });
  await event(request, actor, 'workflow-started', from, request.status, '', session);
  await notify(request.selectedWorkflow[0].authority, request._id, 'A document is awaiting your signature', session);
  return request;
});

exports.uploadSigned = async ({ taskId, actor, file, message }) => transact(async (session) => {
  const task = await AuthorityTask.findById(taskId).session(session);
  if (!task) fail('Task not found', 404, 'NOT_FOUND');
  if (String(task.authority) !== String(actor._id)) fail('This task belongs to another authority', 403, 'FORBIDDEN');
  if (task.status !== 'active') fail('Only the active task can receive a signed document', 409, 'INVALID_STATE');
  const request = await loadRequest(task.request, session);
  if (request.status !== 'in_workflow' || request.currentStep !== task.step) fail('Task is out of sequence', 409, 'INVALID_STATE');
  const previous = await DocumentVersion.findById(request.currentVersion).session(session);
  const versions = await DocumentVersion.create([{
    request: request._id, number: previous.number + 1, kind: 'signed', storageName: file.filename,
    originalName: file.originalname, mimeType: file.mimetype, size: file.size, uploadedBy: actor._id, notes: message
  }], { session });
  request.currentVersion = versions[0]._id; request.status = 'correction_requested'; request.revision += 1;
  task.status = 'uploaded'; task.signedVersion = versions[0]._id; task.message = message || ''; task.completedAt = new Date();
  await request.save({ session }); await task.save({ session });
  await event(request, actor, 'signed-document-uploaded', 'in_workflow', 'correction_requested', message, session, versions[0]._id);
  await notify(request.coordinator, request._id, 'A signed document is ready for verification', session);
  return { request, task, version: versions[0] };
});

exports.verifySigned = async ({ requestId, actor, accept, message }) => transact(async (session) => {
  const request = await loadRequest(requestId, session);
  if (request.status !== 'correction_requested') fail('No signed document is awaiting verification', 409, 'INVALID_STATE');
  if (request.coordinator && String(request.coordinator) !== String(actor._id) && actor.role !== 'admin') fail('Only the assigned coordinator may verify', 403, 'FORBIDDEN');
  const task = await AuthorityTask.findOne({ request: request._id, step: request.currentStep }).session(session);
  if (!task || task.status !== 'uploaded') fail('Current task has no uploaded version', 409, 'INVALID_STATE');
  const from = request.status;
  if (!accept) {
    if (!message) fail('A return reason is required', 422, 'VALIDATION_ERROR');
    task.status = 'active'; task.message = message; task.activatedAt = new Date(); task.completedAt = undefined;
    request.status = 'in_workflow'; request.revision += 1;
    await task.save({ session }); await request.save({ session });
    await event(request, actor, 'verification-returned', from, request.status, message, session, task.signedVersion);
    await notify(task.authority, request._id, `Your signed document needs correction: ${message}`, session);
    return { request, task };
  }
  task.status = 'accepted'; task.completedAt = new Date(); task.message = message || '';
  const next = await AuthorityTask.findOne({ request: request._id, step: request.currentStep + 1 }).session(session);
  if (next) {
    next.status = 'active'; next.activatedAt = new Date();
    await next.save({ session });
    request.currentStep += 1; request.status = statusAfterStep(true);
    await notify(next.authority, request._id, 'A document is awaiting your signature', session);
  } else request.status = statusAfterStep(false);
  request.revision += 1;
  await task.save({ session }); await request.save({ session });
  await event(request, actor, 'verification-accepted', from, request.status, message, session, task.signedVersion);
  await notify(request.student, request._id, next ? 'A signature was verified; workflow continues' : 'All signatures are complete; final verification is underway', session);
  return { request, task, next };
});

exports.finalize = async ({ requestId, actor, file, message, publish }) => transact(async (session) => {
  const request = await loadRequest(requestId, session);
  const expected = publish ? 'final_verification' : 'final_verification';
  if (request.status !== expected) fail('Request is not ready for final verification', 409, 'INVALID_STATE');
  if (request.coordinator && String(request.coordinator) !== String(actor._id) && actor.role !== 'admin') fail('Only the assigned coordinator may finalize', 403, 'FORBIDDEN');
  if (publish && !request.finalVerifiedAt) fail('Complete final verification before publishing', 409, 'FINAL_VERIFICATION_REQUIRED');
  if (publish && file) fail('Final files must be uploaded before completing final verification', 409, 'FINAL_FILE_MUST_BE_VERIFIED');
  if (!publish && file) {
    const previous = await DocumentVersion.findById(request.currentVersion).session(session);
    if (!previous) fail('Current document version is unavailable', 409, 'INVALID_STATE');
    const version = await DocumentVersion.create([{
      request: request._id, number: previous.number + 1, kind: 'final', storageName: file.filename,
      originalName: file.originalname, mimeType: file.mimetype, size: file.size, uploadedBy: actor._id, notes: message
    }], { session });
    request.currentVersion = version[0]._id; request.finalVersion = version[0]._id;
  } else {
    const current = await DocumentVersion.findById(request.currentVersion).session(session);
    if (!current || !['signed', 'final'].includes(current.kind)) fail('The latest signed version cannot be published as a final document', 409, 'INVALID_STATE');
    request.finalVersion = current._id;
  }
  if (!publish) {
    request.finalVerifiedAt = new Date();
    request.revision += 1; await request.save({ session });
    await event(request, actor, 'final-verification-complete', expected, expected, message, session, request.finalVersion);
    return request;
  }
  if (!request.finalVersion || String(request.finalVersion) !== String(request.currentVersion)) fail('The verified final version is unavailable', 409, 'INVALID_STATE');
  request.status = 'published'; request.publishedAt = new Date(); request.revision += 1;
  await request.save({ session });
  await event(request, actor, 'document-published', expected, 'published', message, session, request.finalVersion);
  await notify(request.student, request._id, 'Your final document is available to download', session);
  return request;
});

exports.returnForCorrection = async ({ taskId, actor, message }) => transact(async (session) => {
  const task = await AuthorityTask.findById(taskId).session(session);
  if (!task || String(task.authority) !== String(actor._id)) fail('Task not found', 404, 'NOT_FOUND');
  if (task.status !== 'active') fail('Only the active task can be returned', 409, 'INVALID_STATE');
  const request = await loadRequest(task.request, session);
  if (request.status !== 'in_workflow' || request.currentStep !== task.step) fail('Task is out of sequence', 409, 'INVALID_STATE');
  if (!message) fail('A return reason is required', 422, 'VALIDATION_ERROR');
  task.status = 'returned'; task.message = message; task.completedAt = new Date();
  request.status = 'authority_correction'; request.revision += 1;
  await task.save({ session }); await request.save({ session });
  await event(request, actor, 'returned-for-correction', 'in_workflow', request.status, message, session);
  await notify(request.coordinator, request._id, `A signature task was returned: ${message}`, session);
  return { request, task };
});
