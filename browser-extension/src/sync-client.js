export async function parseAndUploadSync({
  pages,
  context,
  installationId,
  appVersion,
  parseSyncPayload,
  uploadPerformancePayload
}) {
  const payload = parseSyncPayload(pages, {
    username: context.piuUsername,
    expectedDisplayName: context.piuDisplayName,
    installationId,
    appVersion
  });
  const importResult = await uploadPerformancePayload(payload);

  return {
    displayName: payload.profile.displayName,
    recentPlayCount: payload.recentPlays.length,
    importedRecentPlays: importResult.importedRecentPlays,
    duplicateRecentPlays: importResult.duplicateRecentPlays,
    duplicateRequest: importResult.duplicateRequest
  };
}
