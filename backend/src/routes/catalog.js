const express = require('express');
const { DocumentType, Template, User } = require('../models');
const { authenticate, allow } = require('../middleware/auth');
const { asyncHandler, fail } = require('../utils/errors');
const response = require('../utils/response');
const { requireFields, objectId, text } = require('../utils/validation');
const { audit } = require('../services/audit');

const router = express.Router();
router.use(authenticate);
router.get('/document-types', asyncHandler(async (req, res) => {
  const docs = await DocumentType.find(req.user.role === 'admin' ? {} : { active: true }).populate('workflow.authority', 'name email department');
  response(res, docs);
}));
router.get('/document-types/:id', asyncHandler(async (req, res) => {
  objectId(req.params.id);
  const filter = { _id: req.params.id };
  if (req.user.role !== 'admin') filter.active = true;
  const type = await DocumentType.findOne(filter).populate('workflow.authority', 'name email department');
  if (!type) fail('Document type not found', 404, 'NOT_FOUND');
  response(res, type);
}));
router.post('/document-types', allow('admin'), asyncHandler(async (req, res) => {
  requireFields(req.body, ['name']);
  const workflow = await normalizeWorkflow(req.body.workflow);
  const type = await DocumentType.create({
    name: text(req.body.name, 'name', 120), description: req.body.description || '',
    requiredFields: req.body.requiredFields || [], active: req.body.active !== false, workflow
  });
  await audit(req, 'document-type.created', 'DocumentType', type.id);
  response(res, type, 201);
}));
router.patch('/document-types/:id', allow('admin'), asyncHandler(async (req, res) => {
  objectId(req.params.id);
  const allowed = ['name', 'description', 'requiredFields', 'active', 'workflow'];
  const patch = Object.fromEntries(Object.entries(req.body).filter(([key]) => allowed.includes(key)));
  if (!Object.keys(patch).length) fail('No supported document type fields supplied', 422, 'VALIDATION_ERROR');
  if (patch.workflow) patch.workflow = await normalizeWorkflow(patch.workflow);
  if (patch.name) patch.name = text(patch.name, 'name', 120);
  if (patch.description !== undefined && typeof patch.description !== 'string') fail('description must be a string', 422, 'VALIDATION_ERROR');
  if (patch.requiredFields !== undefined && (!Array.isArray(patch.requiredFields) || patch.requiredFields.some((field) => typeof field !== 'string' || !field.trim()))) fail('requiredFields must be an array of non-empty strings', 422, 'VALIDATION_ERROR');
  if (patch.active !== undefined && typeof patch.active !== 'boolean') fail('active must be a boolean', 422, 'VALIDATION_ERROR');
  const type = await DocumentType.findByIdAndUpdate(req.params.id, patch, { new: true, runValidators: true });
  if (!type) fail('Document type not found', 404, 'NOT_FOUND');
  await audit(req, 'document-type.updated', 'DocumentType', type.id);
  response(res, type);
}));
async function normalizeWorkflow(workflow) {
  if (workflow === undefined) return [];
  if (!Array.isArray(workflow) || workflow.length > 20) fail('workflow must be an array of at most 20 steps', 422, 'VALIDATION_ERROR');
  const out = [];
  for (const [index, step] of workflow.entries()) {
    requireFields(step, ['authority', 'label']);
    objectId(step.authority, 'authority');
    const user = await User.findOne({ _id: step.authority, role: 'authority', active: true });
    if (!user) fail(`Workflow step ${index + 1} must reference an active authority`, 422, 'VALIDATION_ERROR');
    out.push({ authority: user._id, label: text(step.label, 'label', 120) });
  }
  return out;
}

router.get('/templates', asyncHandler(async (req, res) => {
  const filter = req.user.role === 'admin' ? {} : { active: true };
  if (req.query.documentType) { objectId(req.query.documentType, 'documentType'); filter.documentType = req.query.documentType; }
  response(res, await Template.find(filter).populate('documentType', 'name'));
}));
router.get('/templates/:id', asyncHandler(async (req, res) => {
  objectId(req.params.id);
  const filter = { _id: req.params.id };
  if (req.user.role !== 'admin') filter.active = true;
  const template = await Template.findOne(filter).populate('documentType', 'name');
  if (!template) fail('Template not found', 404, 'NOT_FOUND');
  response(res, template);
}));
router.post('/templates', allow('admin', 'coordinator'), asyncHandler(async (req, res) => {
  requireFields(req.body, ['name', 'documentType', 'body']);
  objectId(req.body.documentType, 'documentType');
  if (!await DocumentType.exists({ _id: req.body.documentType, active: true })) fail('Active document type not found', 404, 'NOT_FOUND');
  const template = await Template.create({
    name: text(req.body.name, 'name', 120), documentType: req.body.documentType,
    body: text(req.body.body, 'body', 20_000), active: req.body.active !== false, createdBy: req.user._id
  });
  await audit(req, 'template.created', 'Template', template.id);
  response(res, template, 201);
}));
router.patch('/templates/:id', allow('admin', 'coordinator'), asyncHandler(async (req, res) => {
  objectId(req.params.id);
  const allowed = ['name', 'body', 'active', 'documentType'];
  const patch = Object.fromEntries(Object.entries(req.body).filter(([key]) => allowed.includes(key)));
  if (!Object.keys(patch).length) fail('No supported template fields supplied', 422, 'VALIDATION_ERROR');
  if (patch.name) patch.name = text(patch.name, 'name', 120);
  if (patch.body) patch.body = text(patch.body, 'body', 20_000);
  if (patch.documentType) objectId(patch.documentType, 'documentType');
  if (patch.active !== undefined && typeof patch.active !== 'boolean') fail('active must be a boolean', 422, 'VALIDATION_ERROR');
  const template = await Template.findByIdAndUpdate(req.params.id, patch, { new: true, runValidators: true });
  if (!template) fail('Template not found', 404, 'NOT_FOUND');
  await audit(req, 'template.updated', 'Template', template.id);
  response(res, template);
}));
module.exports = router;
