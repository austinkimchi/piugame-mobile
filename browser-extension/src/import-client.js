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
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw importError(response, body);

  return {
    importedRecentPlays: nonnegativeInteger(body.importedRecentPlays),
    duplicateRecentPlays: nonnegativeInteger(body.duplicateRecentPlays),
    duplicateRequest: body.duplicateRequest === true
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

function nonnegativeInteger(value) {
  return Number.isInteger(value) && value >= 0 ? value : 0;
}
