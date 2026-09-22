const button = document.querySelector("#sync");
const status = document.querySelector("#status");

button.addEventListener("click", async () => {
  button.disabled = true;
  status.textContent = "Reading PIUGAME...";
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!tab?.id || !tab.url?.startsWith("https://mypiu.austin.kim/")) {
      throw new Error("Open MyPIU in the active tab first.");
    }
    const result = await chrome.tabs.sendMessage(tab.id, { type: "mypiu:sync" });
    if (!result?.ok) throw new Error(result?.error ?? "PIUGAME sync failed.");
    status.textContent = `${result.displayName ?? "Player"}: ${result.recentPlayCount} recent plays read.`;
  } catch (error) {
    status.textContent = error instanceof Error ? error.message : "PIUGAME sync failed.";
  } finally {
    button.disabled = false;
  }
});
