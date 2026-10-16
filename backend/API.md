# Backend API notes

All endpoints are rooted at `/api`. Send a bearer JWT in `Authorization` except public register, login, forgot-password, and reset-password endpoints. Responses use `{ "success": true, "data": ... }`; errors use `{ "success": false, "error": { "message": "...", "code": "..." } }`.

## Multipart uploads

Uploads are PDF-only multipart form data. The original filename must have a `.pdf` extension and the server verifies the file's `%PDF-` signature; browser MIME labels are not trusted:

* `POST /requests`: student multipart form fields `documentTypeId`, `fields` (JSON string), optional `message`, and up to five `supportingFiles` PDF parts. Supporting file metadata is saved with the request; invalid submissions clean up uploaded files. `fields` may also be an object in JSON requests. The legacy `documentType` field is also accepted.
* `POST /requests/:id/prepare-upload`: coordinator/admin prepared document; optional text `message` and JSON text `workflow`.
* `POST /authority/tasks/:id/upload-signed-document`: assigned authority's signed copy; optional text `message`.
* `POST /requests/:id/verification/complete`: coordinator/admin final verification; optional `file` is the final PDF being verified, plus optional text `message`. If omitted, the last accepted signed PDF is verified.
* `POST /requests/:id/publish`: publishes only the exact version already verified; it does not accept a replacement file.

If an authority returns a task before uploading a signed version, the request enters `authority_correction`. The assigned coordinator can upload a corrected prepared PDF through `prepare-upload`; this cancels the previous task records, preserves them and their versions in history, and requires the configured signing workflow to be started again from its first authority. Pending authorities cannot stream the current document; the assigned active authority can access only the current version.

The generated-document endpoint takes JSON `{ "templateId": "...", "workflow": [...] }`. `POST /requests/:id/submit-for-signature` may take `workflowId` (the request's document type id) and optional JSON `workflow`; the id must match the request type and the chain is always copied from that type's active configured workflow. `POST /requests/:id/submit-for-signature` starts the prepared chain and is deliberately separate from uploading/generating it.

## Main route groups

* Auth: `POST /auth/register|login|forgot-password|reset-password`, `GET /auth/me`, `POST /auth/logout`.
* Catalog: authenticated `GET /document-types[/:id]`; admin `POST/PATCH /document-types[/:id]` and `POST /document-types`; coordinator/admin `GET/POST/PATCH /templates[/:id]`.
* Student: `POST /requests`, `GET /requests/my`, `GET /requests/:id/progress|history`, `POST /requests/:id/submit-correction|cancel`. Progress response data is `{ request, timeline }`, with timeline entries in chronological order.
* Coordinator/admin: `GET /coordinator/requests|stats`; stats includes `signingWorkflows: [{ id, label }]` for active configured document types. Request actions `POST /requests/:id/accept|request-information|reject|generate-document|prepare-upload|submit-for-signature|verification/accept|verification/return|verification/complete|publish|cancel`.
* Authority: `GET /authority/tasks[/:id]`, `POST /authority/tasks/:id/upload-signed-document|return-for-correction`.
* All authenticated roles: `GET /files/:versionId/preview|download`, `GET /notifications`, `PATCH /notifications/:id/read`.
* Admin: `GET /admin/users`, `PATCH /admin/users/:id`, `GET /admin/audit-logs`.

## Runtime

Copy `.env.example` to `.env`; set a strong `JWT_SECRET` (at least 32 characters), `MONGODB_URI`, and storage path. Workflow transitions use MongoDB transactions; configure MongoDB as a replica set (including a single-node development replica set). Files are written outside the public web root to the configured local storage directory. Reset tokens are exposed in non-production responses only when SMTP is not configured. Production password reset requires SMTP and PASSWORD_RESET_URL; delivery failures are reported rather than treated as successful.

The public registration endpoint creates students only. Provision the first administrator through a trusted database/bootstrap process; then admins can promote/manage accounts with `PATCH /admin/users/:id`.
