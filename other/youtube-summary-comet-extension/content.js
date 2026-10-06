(() => {
  const params = new URLSearchParams(location.search);
  const token = params.get("yt_summary_run");
  const port = Number(params.get("yt_summary_port"));
  if (!token || !Number.isInteger(port)) return;

  const startedAt = performance.now();
  const elapsedMs = () => Math.round(performance.now() - startedAt);

  function send(message) {
    return chrome.runtime.sendMessage({ ...message, token, port });
  }

  function report(state, details = {}) {
    return send({
      type: "postStatus",
      status: { state, elapsed_ms: elapsedMs(), ...details },
    });
  }

  function delay(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  async function getPayload() {
    const deadline = performance.now() + 30000;
    while (performance.now() < deadline) {
      const response = await send({ type: "getPayload" });
      if (response.ok && response.status === 200) return response.body;
      if (response.status !== 202) {
        throw new Error(response.body?.error || "The transcript bridge failed.");
      }
      await delay(75);
    }
    throw new Error("Timed out while fetching the transcript.");
  }

  function waitFor(find, timeoutMs, description) {
    const existing = find();
    if (existing) return Promise.resolve(existing);

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        observer.disconnect();
        reject(new Error(`Timed out waiting for ${description}.`));
      }, timeoutMs);
      const observer = new MutationObserver(() => {
        const value = find();
        if (!value) return;
        clearTimeout(timeout);
        observer.disconnect();
        resolve(value);
      });
      observer.observe(document.documentElement, { childList: true, subtree: true, attributes: true });
    });
  }

  function findComposer() {
    const selectors = [
      "#prompt-textarea",
      "[data-testid='composer'] [contenteditable='true']",
      "main [contenteditable='true'][role='textbox']",
    ];
    return selectors.map((selector) => document.querySelector(selector)).find(Boolean) || null;
  }

  function composerText(composer) {
    return (composer.innerText || composer.value || "").trim();
  }

  function insertPrompt(composer, prompt) {
    composer.focus();

    if (composer instanceof HTMLTextAreaElement) {
      const setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value")?.set;
      setter?.call(composer, prompt);
      composer.dispatchEvent(new InputEvent("input", {
        bubbles: true,
        inputType: "insertText",
        data: prompt,
      }));
      return;
    }

    const inserted = document.execCommand("insertText", false, prompt);
    if (inserted && composerText(composer).length >= prompt.length * 0.9) return;

    composer.replaceChildren();
    const paragraph = document.createElement("p");
    paragraph.textContent = prompt;
    composer.append(paragraph);
    composer.dispatchEvent(new InputEvent("input", {
      bubbles: true,
      inputType: "insertText",
      data: prompt,
    }));
  }

  // The send button by structure first (the composer form's submit button),
  // which works in any ChatGPT interface language; known labels as fallbacks.
  function findEnabledSendButton(composer) {
    const form = composer?.closest("form");
    const candidates = [
      form?.querySelector("button[type='submit']"),
      document.querySelector("button[data-testid='send-button']"),
      document.querySelector("button[data-testid='composer-submit-button']"),
      ...["Send", "Send prompt", "Send message", "Send melding"].map((label) => document.querySelector(`button[aria-label='${label}']`)),
    ];
    const button = candidates.find(Boolean);
    if (!button || button.disabled || button.getAttribute("aria-disabled") === "true") return null;
    return button;
  }

  function pressEnter(composer) {
    composer.focus();
    for (const type of ["keydown", "keypress", "keyup"]) {
      composer.dispatchEvent(new KeyboardEvent(type, { key: "Enter", code: "Enter", keyCode: 13, which: 13, bubbles: true, cancelable: true }));
    }
  }

  function waitForConversation(timeoutMs) {
    const deadline = performance.now() + timeoutMs;
    return new Promise((resolve, reject) => {
      const check = () => {
        if (/^\/c\/[A-Za-z0-9-]+/.test(location.pathname)) {
          resolve();
        } else if (performance.now() >= deadline) {
          reject(new Error("ChatGPT did not create a conversation."));
        } else {
          setTimeout(check, 50);
        }
      };
      check();
    });
  }

  async function run() {
    await report("extension_started");
    const payloadPromise = getPayload();
    const composerPromise = waitFor(findComposer, 20000, "the ChatGPT composer");
    const [payload, composer] = await Promise.all([payloadPromise, composerPromise]);
    await report("ready", { prompt_chars: payload.prompt.length });

    insertPrompt(composer, payload.prompt);
    if (composerText(composer).length < Math.min(payload.prompt.length * 0.9, 500)) {
      throw new Error("ChatGPT did not accept the complete prompt.");
    }
    await report("prompt_inserted");

    const sendButton = await waitFor(() => findEnabledSendButton(composer), 10000, "an enabled Send button").catch(() => null);
    if (sendButton) {
      sendButton.click();
      await report("send_clicked");
    } else {
      pressEnter(composer);
      await report("send_enter");
    }

    await waitForConversation(15000);
    await report("conversation_created", { url: location.href });
  }

  run().catch(async (error) => {
    await report("failed", { error: error?.message || String(error) });
  });
})();
