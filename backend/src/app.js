const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const { frontendOrigin } = require('./config');
const { errorHandler, AppError } = require('./utils/errors');

const app = express();
app.disable('x-powered-by');
app.use(helmet({ crossOriginResourcePolicy: { policy: 'same-site' } }));
app.use(cors({
  origin: frontendOrigin === '*' ? true : frontendOrigin.split(',').map((origin) => origin.trim()),
  methods: ['GET', 'POST', 'PATCH', 'OPTIONS'],
  allowedHeaders: ['Authorization', 'Content-Type'],
  exposedHeaders: ['Content-Disposition']
}));
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: false, limit: '1mb' }));
app.get('/health', (req, res) => res.json({ success: true, data: { status: 'ok' } }));
const authLimiter = rateLimit({ windowMs: 15 * 60_000, limit: 30, standardHeaders: true, legacyHeaders: false });
app.use('/api/auth', authLimiter, require('./routes/auth'));
app.use('/api', require('./routes/catalog'));
app.use('/api', require('./routes/requests'));
app.use((req, res, next) => next(new AppError('Route not found', 404, 'NOT_FOUND')));
app.use((err, req, res, next) => {
  if (err.code === 'LIMIT_FILE_SIZE') err = new AppError('Uploaded file exceeds the configured size limit', 413, 'FILE_TOO_LARGE');
  if (err.code === 'LIMIT_FILE_COUNT' || err.code === 'LIMIT_UNEXPECTED_FILE') err = new AppError('Unexpected file field or file count', 400, 'INVALID_FILE_FIELD');
  return errorHandler(err, req, res, next);
});

module.exports = app;
