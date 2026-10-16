const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const crypto = require('node:crypto');
const { User } = require('../models');
const config = require('../config');
const { jwtSecret, jwtExpiresIn, resetTtlMinutes } = config;
const { asyncHandler, fail } = require('../utils/errors');
const response = require('../utils/response');
const { authenticate } = require('../middleware/auth');
const { requireFields, text } = require('../utils/validation');
const { audit } = require('../services/audit');

const router = express.Router();
const tokenFor = (user) => jwt.sign({ sub: user.id, ver: user.tokenVersion }, jwtSecret, { expiresIn: jwtExpiresIn });
const publicUser = (user) => ({ id: user.id, name: user.name, email: user.email, role: user.role, studentId: user.studentId, department: user.department });

router.post('/register', asyncHandler(async (req, res) => {
  requireFields(req.body, ['name', 'email', 'password']);
  const email = text(req.body.email, 'email', 254).toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) fail('A valid email address is required', 422, 'VALIDATION_ERROR');
  if (typeof req.body.password !== 'string' || req.body.password.length < 10 || req.body.password.length > 128) fail('Password must be 10-128 characters', 422, 'VALIDATION_ERROR');
  if (req.body.role && req.body.role !== 'student') fail('Public registration is limited to students', 403, 'FORBIDDEN');
  const user = await User.create({
    name: text(req.body.name, 'name', 120), email,
    passwordHash: await bcrypt.hash(req.body.password, 12),
    studentId: req.body.studentId ? text(req.body.studentId, 'studentId', 80) : undefined,
    department: req.body.department ? text(req.body.department, 'department', 120) : undefined
  });
  req.user = user;
  await audit(req, 'user.registered', 'User', user.id);
  return response(res, { user: publicUser(user), token: tokenFor(user) }, 201);
}));

router.post('/login', asyncHandler(async (req, res) => {
  requireFields(req.body, ['email', 'password']);
  if (typeof req.body.email !== 'string' || typeof req.body.password !== 'string') fail('Email and password must be strings', 422, 'VALIDATION_ERROR');
  const user = await User.findOne({ email: String(req.body.email).toLowerCase().trim() }).select('+passwordHash');
  if (!user || !user.active || !(await bcrypt.compare(req.body.password, user.passwordHash))) fail('Invalid email or password', 401, 'INVALID_CREDENTIALS');
  req.user = user;
  await audit(req, 'auth.login', 'User', user.id);
  return response(res, { user: publicUser(user), token: tokenFor(user) });
}));

router.post('/forgot-password', asyncHandler(async (req, res) => {
  requireFields(req.body, ['email']);
  const hasSmtp = config.smtpHost && config.smtpFrom && config.passwordResetUrl;
  if (process.env.NODE_ENV === 'production' && !hasSmtp) fail('Password reset delivery is not configured', 503, 'RESET_DELIVERY_UNAVAILABLE');
  const user = await User.findOne({ email: String(req.body.email).toLowerCase().trim() });
  const result = { message: 'If the account exists, reset instructions will be sent.' };
  if (user) {
    const raw = crypto.randomBytes(32).toString('hex');
    user.resetTokenHash = crypto.createHash('sha256').update(raw).digest('hex');
    user.resetTokenExpiresAt = new Date(Date.now() + resetTtlMinutes * 60_000);
    await user.save();
    if (hasSmtp) {
      try {
        const nodemailer = require('nodemailer');
        const transport = nodemailer.createTransport({
          host: config.smtpHost, port: config.smtpPort, secure: config.smtpPort === 465,
          auth: config.smtpUser ? { user: config.smtpUser, pass: config.smtpPassword } : undefined
        });
        const resetLink = `${config.passwordResetUrl}${config.passwordResetUrl.includes('?') ? '&' : '?'}token=${encodeURIComponent(raw)}`;
        await transport.sendMail({
          from: config.smtpFrom, to: user.email, subject: 'College document portal password reset',
          text: `Use this one-time link to reset your password: ${resetLink}\nIt expires in ${resetTtlMinutes} minutes.`
        });
      } catch (error) {
        user.resetTokenHash = undefined; user.resetTokenExpiresAt = undefined;
        await user.save();
        throw Object.assign(new Error('Unable to deliver password reset instructions'), { status: 503, code: 'RESET_DELIVERY_FAILED' });
      }
    } else if (process.env.NODE_ENV !== 'production') result.resetToken = raw;
  }
  response(res, result);
}));

router.post('/reset-password', asyncHandler(async (req, res) => {
  requireFields(req.body, ['token', 'password']);
  if (typeof req.body.password !== 'string' || req.body.password.length < 10 || req.body.password.length > 128) fail('Password must be 10-128 characters', 422, 'VALIDATION_ERROR');
  const hash = crypto.createHash('sha256').update(String(req.body.token)).digest('hex');
  const passwordHash = await bcrypt.hash(req.body.password, 12);
  const user = await User.findOneAndUpdate({
    resetTokenHash: hash, resetTokenExpiresAt: { $gt: new Date() }
  }, {
    $set: { passwordHash }, $unset: { resetTokenHash: 1, resetTokenExpiresAt: 1 }, $inc: { tokenVersion: 1 }
  }, { new: true });
  if (!user) fail('Reset token is invalid or expired', 400, 'INVALID_RESET_TOKEN');
  response(res, { message: 'Password has been reset' });
}));

router.get('/me', authenticate, (req, res) => response(res, { user: publicUser(req.user) }));
router.post('/logout', authenticate, asyncHandler(async (req, res) => {
  await User.updateOne({ _id: req.user._id }, { $inc: { tokenVersion: 1 } });
  response(res, { message: 'Logged out' });
}));

module.exports = router;
