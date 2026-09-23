const MYPIU_ORIGIN = "https://mypiu.austin.kim";

export class PerformanceImportError extends Error {
  constructor(message, { code = null, recovery = null, status = null } = {}) {
    super(message);
    this.name = "PerformanceImportError";
    this.code = code;
    this.recovery = recovery;
    this.status = status;
  }
}

export async function uploadPerformancePayload(payload, { fetchImpl = fetch } = {}) {
  const response = await fetchImpl("/api/mobile/v1/performance/import", {
    method: "POST",
    credentials: "same-origin",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify(payload)
  });
  let body;
  try {
    body = await response.json();
  } catch {
    if (response.ok) throw invalidImportReceipt(response.status);
    body = {};
  }
  if (!response.ok) throw importError(response, body);
  if (!isImportReceipt(body)) throw invalidImportReceipt(response.status);

  return {
    importedRecentPlays: body.importedRecentPlays,
    duplicateRecentPlays: body.duplicateRecentPlays,
    duplicateRequest: body.duplicateRequest
  };
}

export function importError(response, body = {}) {
  const code = typeof body.error === "string" ? body.error : null;
  const message = typeof body.message === "string" ? body.message : null;
  if (response.status === 401) {
    return new PerformanceImportError("Sign in to MyPIU again, then retry.", {
      code,
      status: response.status,
      recovery: { kind: "mypiu", url: MYPIU_ORIGIN }
    });
  }
  if (response.status === 429) {
    const retryAfter = Number.parseInt(response.headers.get("Retry-After") ?? "60", 10);
    const seconds = Number.isFinite(retryAfter) && retryAfter > 0 ? retryAfter : 60;
    return new PerformanceImportError(`MyPIU is receiving syncs too quickly. Retry in ${seconds} seconds.`, {
      code,
      status: response.status
    });
  }
  if (code === "piu_username_mismatch") {
    return new PerformanceImportError("The linked MyPIU account does not match this PIUGAME player.", {
      code,
      status: response.status
    });
  }
  if (code === "import_in_progress") {
    return new PerformanceImportError("Another sync is finishing. Retry in a moment.", {
      code,
      status: response.status
    });
  }
  return new PerformanceImportError(message ?? `MyPIU import returned HTTP ${response.status}.`, {
    code,
    status: response.status
  });
}

function invalidImportReceipt(status) {
  return new PerformanceImportError("MyPIU returned an invalid sync response. Sign in again, then retry.", {
    code: "invalid_import_receipt",
    status,
    recovery: { kind: "mypiu", url: MYPIU_ORIGIN }
  });
}

function isImportReceipt(value) {
  return Boolean(
    value &&
    typeof value === "object" &&
    Number.isInteger(value.importedRecentPlays) &&
    value.importedRecentPlays >= 0 &&
    Number.isInteger(value.duplicateRecentPlays) &&
    value.duplicateRecentPlays >= 0 &&
    typeof value.duplicateRequest === "boolean"
  );
}
