const mongoose = require('mongoose');

const { Schema } = mongoose;
const options = { timestamps: true, toJSON: { virtuals: true, transform: (_, value) => { value.id = value._id; delete value._id; delete value.__v; return value; } } };

const userSchema = new Schema({
  name: { type: String, required: true, trim: true, maxlength: 120 },
  email: { type: String, required: true, unique: true, lowercase: true, trim: true },
  passwordHash: { type: String, required: true, select: false },
  role: { type: String, enum: ['student', 'coordinator', 'authority', 'admin'], default: 'student', required: true },
  studentId: { type: String, trim: true, sparse: true },
  department: { type: String, trim: true },
  active: { type: Boolean, default: true },
  resetTokenHash: { type: String, select: false },
  resetTokenExpiresAt: { type: Date, select: false },
  tokenVersion: { type: Number, default: 0 }
}, options);

const documentTypeSchema = new Schema({
  name: { type: String, required: true, unique: true, trim: true },
  description: { type: String, default: '' },
  requiredFields: [{ type: String }],
  active: { type: Boolean, default: true },
  workflow: [{
    authorityRole: { type: String, enum: ['authority'], default: 'authority' },
    authority: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    label: { type: String, required: true, trim: true }
  }]
}, options);

const templateSchema = new Schema({
  name: { type: String, required: true, trim: true },
  documentType: { type: Schema.Types.ObjectId, ref: 'DocumentType', required: true },
  body: { type: String, required: true },
  active: { type: Boolean, default: true },
  createdBy: { type: Schema.Types.ObjectId, ref: 'User', required: true }
}, options);

const requestSchema = new Schema({
  student: { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  documentType: { type: Schema.Types.ObjectId, ref: 'DocumentType', required: true },
  fields: { type: Schema.Types.Mixed, default: {} },
  supportingFiles: [{
    storageName: { type: String, required: true },
    originalName: { type: String, required: true },
    mimeType: { type: String, required: true },
    size: { type: Number, required: true },
    uploadedAt: { type: Date, default: Date.now }
  }],
  status: { type: String, enum: ['submitted', 'information_requested', 'correction_requested', 'authority_correction', 'accepted', 'prepared', 'in_workflow', 'final_verification', 'published', 'rejected', 'cancelled'], default: 'submitted', index: true },
  coordinator: { type: Schema.Types.ObjectId, ref: 'User' },
  currentStep: { type: Number, default: -1 },
  selectedWorkflow: [{ authority: { type: Schema.Types.ObjectId, ref: 'User' }, label: String }],
  currentVersion: { type: Schema.Types.ObjectId, ref: 'DocumentVersion' },
  finalVersion: { type: Schema.Types.ObjectId, ref: 'DocumentVersion' },
  finalVerifiedAt: Date,
  studentMessage: String,
  coordinatorMessage: String,
  publishedAt: Date,
  revision: { type: Number, default: 0 }
}, { ...options, optimisticConcurrency: true });
requestSchema.index({ student: 1, createdAt: -1 });

const versionSchema = new Schema({
  request: { type: Schema.Types.ObjectId, ref: 'Request', required: true, index: true },
  number: { type: Number, required: true },
  kind: { type: String, enum: ['prepared', 'signed', 'final'], required: true },
  storageName: { type: String, required: true },
  originalName: { type: String, required: true },
  mimeType: { type: String, required: true },
  size: { type: Number, required: true },
  uploadedBy: { type: Schema.Types.ObjectId, ref: 'User', required: true },
  notes: String
}, options);
versionSchema.index({ request: 1, number: 1 }, { unique: true });

const taskSchema = new Schema({
  request: { type: Schema.Types.ObjectId, ref: 'Request', required: true, index: true },
  authority: { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  step: { type: Number, required: true },
  label: { type: String, required: true },
  status: { type: String, enum: ['pending', 'active', 'uploaded', 'returned', 'accepted', 'cancelled'], default: 'pending', index: true },
  signedVersion: { type: Schema.Types.ObjectId, ref: 'DocumentVersion' },
  message: String,
  activatedAt: Date,
  completedAt: Date
}, options);
taskSchema.index({ request: 1, step: 1 }, { unique: true });

const historySchema = new Schema({
  request: { type: Schema.Types.ObjectId, ref: 'Request', required: true, index: true },
  actor: { type: Schema.Types.ObjectId, ref: 'User' },
  action: { type: String, required: true },
  fromStatus: String,
  toStatus: String,
  message: String,
  version: { type: Schema.Types.ObjectId, ref: 'DocumentVersion' },
  createdAt: { type: Date, default: Date.now }
}, { ...options, timestamps: false });

const notificationSchema = new Schema({
  user: { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  request: { type: Schema.Types.ObjectId, ref: 'Request' },
  message: { type: String, required: true },
  readAt: Date
}, options);

const auditSchema = new Schema({
  actor: { type: Schema.Types.ObjectId, ref: 'User' },
  action: { type: String, required: true },
  targetType: String,
  targetId: String,
  details: Schema.Types.Mixed,
  ip: String
}, options);

module.exports = {
  User: mongoose.models.User || mongoose.model('User', userSchema),
  DocumentType: mongoose.models.DocumentType || mongoose.model('DocumentType', documentTypeSchema),
  Template: mongoose.models.Template || mongoose.model('Template', templateSchema),
  Request: mongoose.models.Request || mongoose.model('Request', requestSchema),
  DocumentVersion: mongoose.models.DocumentVersion || mongoose.model('DocumentVersion', versionSchema),
  AuthorityTask: mongoose.models.AuthorityTask || mongoose.model('AuthorityTask', taskSchema),
  RequestHistory: mongoose.models.RequestHistory || mongoose.model('RequestHistory', historySchema),
  Notification: mongoose.models.Notification || mongoose.model('Notification', notificationSchema),
  AuditLog: mongoose.models.AuditLog || mongoose.model('AuditLog', auditSchema)
};
