const { fail } = require('./errors');

function parseFields(value) {
  if (typeof value === 'string') {
    try { value = JSON.parse(value); }
    catch { fail('fields must contain valid JSON', 422, 'INVALID_JSON_FIELDS'); }
  }
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    fail('fields must be a JSON object', 422, 'VALIDATION_ERROR');
  }
  return value;
}

function documentTypeIdFrom(body) {
  return body.documentTypeId || body.documentType;
}

module.exports = { parseFields, documentTypeIdFrom };
