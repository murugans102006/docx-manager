const { fail } = require('./errors');

exports.requireFields = (body, fields) => {
  const missing = fields.filter((field) => body[field] === undefined || body[field] === null || body[field] === '');
  if (missing.length) fail(`Required fields: ${missing.join(', ')}`, 422, 'VALIDATION_ERROR');
};
exports.objectId = (value, name = 'id') => {
  const mongoose = require('mongoose');
  if (!mongoose.isValidObjectId(value)) fail(`Invalid ${name}`, 400, 'INVALID_ID');
};
exports.text = (value, name, max = 1000) => {
  if (typeof value !== 'string' || !value.trim() || value.length > max) fail(`${name} must be a non-empty string of at most ${max} characters`, 422, 'VALIDATION_ERROR');
  return value.trim();
};
