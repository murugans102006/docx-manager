# College Document Request and Management System

A Flutter Android client and Express/MongoDB API for requesting, preparing, sequentially signing, verifying, and securely delivering official college documents. A designated coordinator manages the lifecycle. Authorities act only on their assigned signing tasks; students only see their own requests and published documents.

## Architecture

```text
Flutter app
  role-specific portals · progress timeline · secure token storage
        │ authenticated REST / multipart file uploads
        ▼
Express API
  validation · authentication/authorization · workflow transitions
  ├── request and signing-task services
  ├── notification, history, and audit services
  └── private storage adapter (local development / persistent production)
        │ Mongoose
        ▼
MongoDB
  users · document types/templates · requests · versions · tasks · history
```

The backend is authoritative for workflow state and access control. Flutter does not directly choose arbitrary statuses or grant access. Files live outside ordinary MongoDB documents; metadata and private storage references are persisted in MongoDB. Downloads and previews pass through authenticated, resource-scoped API routes.

## Roles and authority boundaries

| Role | Allowed work |
|---|---|
| Student | Submit requests, supply corrections, view own progress, download a final published document. |
| Coordinator | Review requests, prepare documents, select a configured workflow, route documents, verify each returned version, and publish after final verification. |
| Authority | View and act on currently assigned signing tasks, return a signed version or request correction, and see own task history. |
| Administrator | Manage accounts, document types/templates/workflow configuration and audit information. Admin status alone does not confer authority to sign or publish. |

Every protected action validates both role and resource assignment/ownership. Only the first configured authority gets an actionable task. The next task is created only after the coordinator verifies the latest returned version. Publication is blocked until every mandatory step has been verified.

## Request lifecycle and state

```text
Student submits
  → Coordinator review
  → Information correction (when needed) / reject / accept
  → Coordinator prepares and previews document
  → Coordinator starts a configured workflow snapshot
  → Authority signs and uploads version
  → Coordinator verifies: accept and forward OR return for correction
  → Repeat one authority at a time
  → Coordinator final verification
  → Coordinator publishes
  → Student downloads final document
```

Each request preserves a snapshot of its configured workflow so later configuration changes do not rewrite work already in progress. Every upload is a separate version. The active authority receives the latest verified version, never an older or unverified file. A returned file is not treated as legal proof of an electronic signature; institutions must use their approved signing process.

Overall request status is derived from actual request/task records, not a client-provided status:

`Submitted`, `Under Review`, `Additional Information Required`, `Document Preparation`, `Awaiting Signature`, `Returned for Verification`, `Correction Required`, `Final Verification`, `Ready for Download`, `Completed`, `Rejected`, `Cancelled`.

Signing stages maintain their own statuses, assigned authority, current version, remarks, and timestamps. Request history and audit events record actors, actions, and status transitions. Internal remarks are not exposed in the student progress view.

## Database design

| Collection | Main information and relationships |
|---|---|
| User | Hashed password, email, role, department/student profile, responsibilities, account state. |
| DocumentType | Requirements, dynamic fields, department, template/workflow references, processing target, enabled flag. |
| Template | Approved document template and generation metadata. |
| SigningWorkflow | Ordered authority roles/assignments, scope, optional steps, active configuration version. |
| DocumentRequest | Unique request number, student/type/coordinator, request fields, supporting references, workflow snapshot, current state, final version, important timestamps. |
| DocumentVersion | Request, private storage key, original name/type/size/checksum, uploader, purpose/stage/task, verification decision and timestamp. |
| SigningTask | Request/workflow step, assigned authority, active version, status, remarks, assignment/return/verification timestamps. |
| RequestHistory | Request, action, old/new state, actor, student-visible remark where appropriate, timestamp. |
| Notification | Recipient, event, related request/task, read/delivery state and timestamps. |
| AuditLog | Actor, sensitive action, resource and safe metadata. |

Mongoose schemas validate fields, use timestamps and indexes, and refer to related entities. Passwords are hashed. Store only opaque storage references in MongoDB, not file contents, credentials, reset tokens, or physical paths.

## Project structure

```text
backend/
  config/ models/ controllers/ routes/ middleware/
  services/ validators/ utils/ tests/ storage/
  server.js package.json .env.example
lib/
  core/ models/ repositories/ services/ providers/ widgets/
  screens/auth/ screens/student/ screens/coordinator/
  screens/authority/ screens/admin/ main.dart
test/
```

## Requirements

- Windows 10/11, PowerShell, and VS Code.
- Node.js LTS with npm.
- Flutter stable and its included Dart SDK.
- Android Studio/Android SDK and an emulator or Android device.
- MongoDB Community Server locally or a MongoDB Atlas database.
- VS Code Flutter and Dart extensions are recommended.

## Local setup

### Backend

```powershell
Set-Location .\backend
npm install
Copy-Item .env.example .env
```

Set the MongoDB URI, a strong random JWT secret, upload limits/storage path, and allowed origins in `backend\.env`. Workflow transitions use MongoDB transactions, so configure a replica set even for local development. On Windows, start MongoDB with `mongod --dbpath C:\data\db --replSet rs0`, run `rs.initiate()` once in `mongosh`, and set `MONGODB_URI=mongodb://127.0.0.1:27017/college_documents?replicaSet=rs0`. Public registration creates student accounts only; provision the first administrator through a trusted database/bootstrap process. Never use a default account or development secret in production.

```powershell
npm run dev
```

For a fresh local database, open a second terminal in `backend\` and run `npm run setup:demo`. It creates a sample Bonafide Certificate type, approved demo template, and admin/coordinator/authority accounts with randomly generated passwords printed once in that terminal. Save those credentials privately for local testing. The sample template is clearly marked as not an official college document. This command is disabled in production and refuses to overwrite existing demo data.

### Flutter

The API base URL is configured once in the Flutter app:

- Android emulator: `http://10.0.2.2:3000/api`
- Physical Android device: `http://<computer-LAN-IP>:3000/api` (same network; permit the API port through Windows Firewall).
- Production: your deployed API's HTTPS base URL.

```powershell
Set-Location ..
flutter pub get
flutter run
```

On Android, `localhost` refers to the device/emulator, not the development computer. Do not hardcode separate host URLs into feature modules.
The Android app permits cleartext HTTP only in its debug manifest for local testing; release builds should use HTTPS.

## API overview

Successful JSON responses use `{ "success": true, "data": ... }`; errors use `{ "success": false, "error": { "message": "...", "code": "..." } }`. Protected requests use `Authorization: Bearer <access-token>`. Upload routes accept multipart files with the field names described in the API implementation.

| Method | Route | Purpose |
|---|---|---|
| POST / GET | `/api/auth/register`, `/api/auth/login`, `/api/auth/me` | Account registration/login/current session. |
| POST | `/api/auth/logout`, `/api/auth/forgot-password`, `/api/auth/reset-password` | Logout and password recovery. |
| GET / POST / PATCH | `/api/document-types`, `/api/document-types/:id` | Read or administer request types and their requirements. |
| GET / POST / PATCH | `/api/templates`, `/api/templates/:id` | Read or administer approved templates. |
| POST | `/api/requests` | Student submits multipart `documentTypeId`, JSON-string `fields`, optional `message`, and up to five PDF `supportingFiles`. |
| GET | `/api/requests/my`, `/api/requests/:id/progress`, `/api/requests/:id/history` | Student's own request list and timeline/history. |
| GET | `/api/coordinator/requests`, `/api/coordinator/stats` | Coordinator queue and database-backed counts. |
| POST | `/api/requests/:id/accept`, `/request-information`, `/reject` | Coordinator review actions. |
| POST | `/api/requests/:id/submit-correction`, `/cancel` | Student correction or permitted cancellation. |
| POST | `/api/requests/:id/generate-document` | Generate a PDF from an approved template and verified request fields. |
| POST | `/api/requests/:id/prepare-upload`, `/submit-for-signature` | Upload a prepared PDF (`file` field), then start the configured signing sequence. |
| GET | `/api/authority/tasks`, `/api/authority/tasks/:id` | Current authority tasks and task details. |
| POST | `/api/authority/tasks/:id/upload-signed-document`, `/return-for-correction` | Authority submits a signed version or requests correction. |
| POST | `/api/requests/:id/verification/accept`, `/verification/return` | Coordinator verifies an authority's returned version or sends it back for correction. |
| POST | `/api/requests/:id/verification/complete`, `/publish` | Coordinator completes final verification, then publishes the verified version. |
| GET | `/api/files/:versionId/preview`, `/download` | Authorized authenticated file streaming. |
| GET / PATCH | `/api/notifications`, `/api/notifications/:id/read` | Read and update notification state. |
| GET / PATCH | `/api/admin/users`, `/api/admin/users/:id`, `/api/admin/audit-logs` | Admin-only user management and audit access. |

Exact request fields, file fields, workflow configuration, and response shapes are documented in [backend/API.md](./backend/API.md). Uploads are currently restricted to PDF files.

## Testing and build

From `backend\`:

```powershell
npm test
```

From the Flutter project root:

```powershell
flutter analyze
flutter test
flutter build apk --release
```

Use a dedicated test MongoDB database; never run test fixtures against production. The full acceptance path to exercise is student submission → coordinator preparation → one authority upload at a time with coordinator verification → final verification/publication → student download. Include unauthorized ID guessing, duplicate actions, out-of-order actions, missing signature correction, and failed upload/notification cases.

## Deployment and privacy

- Serve the API over HTTPS, set explicit CORS origins, secure JWT expiry/secrets, rate limits, safe production errors, and least-privilege MongoDB credentials.
- Use private persistent storage or a private object-storage bucket with restricted access. Local disk is for development only; some hosting platforms erase local files during redeploy/restart.
- Back up MongoDB and documents, define retention/deletion policy, and protect audit logs.
- Do not commit `.env`, secrets, private keys, generated official documents, or student uploads.
- Document generation must use approved templates and verified information; coordinator review is required before circulation. Configure legal/electronic signatures only through the college-approved provider/process.
