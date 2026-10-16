const { AuditLog } = require('../models');

exports.audit = (req, action, targetType, targetId, details = {}) => AuditLog.create({
  actor: req.user?._id, action, targetType, targetId: String(targetId || ''), details, ip: req.ip
});
