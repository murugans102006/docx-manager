function isConfiguredWorkflow(selected, configured) {
  if (!Array.isArray(configured) || configured.length === 0) return false;
  if (selected === undefined) return true;
  return Array.isArray(selected) && selected.length === configured.length &&
    selected.every((step, index) =>
      String(step.authority) === String(configured[index].authority) && step.label === configured[index].label);
}

function statusAfterStep(hasNextStep) {
  return hasNextStep ? 'in_workflow' : 'final_verification';
}

function workflowMatchesDocumentType(documentTypeId, workflowId) {
  return !workflowId || String(workflowId) === String(documentTypeId);
}

function studentMayReadFile(request, versionId, userId) {
  return request.status === 'published' &&
    String(request.student) === String(userId) &&
    String(request.finalVersion) === String(versionId);
}

module.exports = { isConfiguredWorkflow, statusAfterStep, workflowMatchesDocumentType, studentMayReadFile };
