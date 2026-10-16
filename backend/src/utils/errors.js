class AppError extends Error {
  constructor(message, status = 400, code = 'BAD_REQUEST') {
    super(message);
    this.status = status;
    this.code = code;
  }
}

const asyncHandler = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
const fail = (message, status = 400, code = 'BAD_REQUEST') => {
  throw new AppError(message, status, code);
};

function errorHandler(err, req, res, next) {
  if (res.headersSent) return next(err);
  if (err.name === 'ValidationError') {
    return res.status(400).json({ success: false, error: { message: err.message, code: 'VALIDATION_ERROR' } });
  }
  if (err.name === 'CastError') {
    return res.status(400).json({ success: false, error: { message: 'Invalid identifier', code: 'INVALID_ID' } });
  }
  if (err.name === 'VersionError') {
    return res.status(409).json({ success: false, error: { message: 'This request changed concurrently; reload and retry', code: 'CONCURRENT_MODIFICATION' } });
  }
  if (err.code === 11000) {
    return res.status(409).json({ success: false, error: { message: 'A record with that value already exists', code: 'DUPLICATE' } });
  }
  const status = err.status || 500;
  if (status >= 500) console.error(err);
  return res.status(status).json({
    success: false,
    error: { message: status >= 500 ? 'An unexpected server error occurred' : err.message, code: err.code || 'INTERNAL_ERROR' }
  });
}

module.exports = { AppError, asyncHandler, fail, errorHandler };
