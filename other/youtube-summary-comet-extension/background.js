function bridgeUrl(message) {
  const port = Number(message.port);
  const token = String(message.token || "");
  if (!Number.isInteger(port) || port < 1024 || port > 65535) {
    throw new Error("Invalid local bridge port.");
  }
  if (!/^[A-Za-z0-9_-]{20,}$/.test(token)) {
    throw new Error("Invalid local bridge token.");
  }

  const path = message.type === "getPayload" ? "payload" : "status";
  return `http://127.0.0.1:${port}/${path}?token=${encodeURIComponent(token)}`;
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (!message || !["getPayload", "postStatus"].includes(message.type)) {
    return false;
  }

  (async () => {
    try {
      const options = message.type === "postStatus"
        ? {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(message.status),
          }
        : { cache: "no-store" };
      const response = await fetch(bridgeUrl(message), options);
      const body = await response.json();
      sendResponse({ ok: response.ok, status: response.status, body });
    } catch (error) {
      sendResponse({ ok: false, status: 0, body: { error: String(error) } });
    }
  })();

  return true;
});
