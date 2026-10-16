const multer = require('multer');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { storageDir, maxUploadBytes } = require('../config');
const { AppError } = require('../utils/errors');

fs.mkdirSync(storageDir, { recursive: true });
const storage = multer.diskStorage({
  destination: (req, file, callback) => callback(null, storageDir),
  filename: (req, file, callback) => callback(null, `${crypto.randomUUID()}.pdf`)
});
const pdfOnly = (req, file, callback) => {
  if (path.extname(file.originalname).toLowerCase() !== '.pdf') {
    return callback(new AppError('Only PDF documents are accepted', 415, 'UNSUPPORTED_FILE_TYPE'));
  }
  callback(null, true);
};
const upload = multer({ storage, limits: { fileSize: maxUploadBytes, files: 1 }, fileFilter: pdfOnly });
const supportingUpload = multer({ storage, limits: { fileSize: maxUploadBytes, files: 6 }, fileFilter: pdfOnly });

function removeUploadedFile(req) {
  if (req.file?.path) fs.promises.unlink(req.file.path).catch(() => {});
  const files = Array.isArray(req.files) ? req.files : Object.values(req.files || {}).flat();
  for (const file of files) if (file.path) fs.promises.unlink(file.path).catch(() => {});
}

async function verifyPdfSignatures(req) {
  const files = [
    ...(req.file ? [req.file] : []),
    ...(Array.isArray(req.files) ? req.files : Object.values(req.files || {}).flat())
  ];
  for (const file of files) {
    const handle = await fs.promises.open(file.path, 'r');
    try {
      const header = Buffer.alloc(5);
      const { bytesRead } = await handle.read(header, 0, header.length, 0);
      if (!hasPdfSignature(header, bytesRead)) {
        throw new AppError('The selected file is not a valid PDF document', 415, 'INVALID_PDF_SIGNATURE');
      }
      file.mimetype = 'application/pdf';
    } finally {
      await handle.close();
    }
  }
}

function hasPdfSignature(header, bytesRead = header.length) {
  return bytesRead >= 5 && header.subarray(0, 5).toString('ascii') === '%PDF-';
}

function verifiedUpload(parser) {
  return (req, res, next) => parser(req, res, (error) => {
    if (error) {
      removeUploadedFile(req);
      return next(error);
    }
    verifyPdfSignatures(req).then(
      () => next(),
      (verificationError) => {
        removeUploadedFile(req);
        next(verificationError);
      }
    );
  });
}

module.exports = {
  singlePdf: (field) => verifiedUpload(upload.single(field)),
  supportingFiles: verifiedUpload(supportingUpload.array('supportingFiles', 5)),
  removeUploadedFile,
  hasPdfSignature
};
