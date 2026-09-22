const button = document.querySelector("#sync");
const status = document.querySelector("#status");
const recoveryButton = document.querySelector("#recovery");
let recoveryURL = null;

button.addEventListener("click", async () => {
  button.disabled = true;
  recoveryButton.hidden = true;
  recoveryURL = null;
  status.textContent = "Syncing from PIUGAME...";
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!tab?.id || !tab.url?.startsWith("https://mypiu.austin.kim/")) {
      throw new Error("Open MyPIU in the active tab first.");
    }
    const result = await chrome.tabs.sendMessage(tab.id, { type: "mypiu:sync" });
    if (!result?.ok) {
      showRecovery(result?.recovery);
      throw new Error(result?.error ?? "PIUGAME sync failed.");
    }
    status.textContent = successMessage(result);
  } catch (error) {
    const message = error instanceof Error ? error.message : "PIUGAME sync failed.";
    status.textContent = message.includes("Receiving end does not exist")
      ? "Refresh the MyPIU tab once after installing, then retry."
      : message;
  } finally {
    button.disabled = false;
  }
});

recoveryButton.addEventListener("click", async () => {
  if (!recoveryURL) return;
  await chrome.tabs.create({ url: recoveryURL });
  window.close();
});

function showRecovery(recovery) {
  if (!recovery?.url) return;
  recoveryURL = recovery.url;
  recoveryButton.textContent = recovery.kind === "piugame" ? "Sign in to PIUGAME" : "Open MyPIU";
  recoveryButton.hidden = false;
}

function successMessage(result) {
  const player = result.displayName ?? "Player";
  if (result.duplicateRequest) return `${player}: this sync was already saved.`;
  const imported = result.importedRecentPlays ?? 0;
  const duplicates = result.duplicateRecentPlays ?? 0;
  return `${player}: ${imported} new ${plural(imported, "play")}, ${duplicates} already saved.`;
}

function plural(count, word) {
  return count === 1 ? word : `${word}s`;
}
