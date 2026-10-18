"use strict";

// A local, fictional workflow preview. No file access, uploads, storage, or telemetry.
(() => {
  const $ = (id) => document.getElementById(id);
  const demo = $("demo");
  const wheelSVG = $("wheel-svg");
  const modes = [...document.querySelectorAll("[data-mode]")];
  const ns = "http://www.w3.org/2000/svg";
  const sample = "morning-light.heic";
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
  const operations = {
    convert: [
      { title: "PNG", extension: "png" }, { title: "JPG", extension: "jpg" },
      { title: "TIFF", extension: "tiff" }, { title: "WEBP", extension: "webp", engine: "ImageMagick" },
      { title: "AVIF", extension: "avif", engine: "ImageMagick" },
      { title: "BMP", extension: "bmp" }, { title: "PDF", extension: "pdf" }
    ],
    tools: [
      { title: "Compress", detail: "The Mac app asks for image quality before creating a new copy." },
      { title: "Resize", detail: "The Mac app asks for new dimensions and keeps the image's aspect ratio." },
      { title: "Crop", detail: "The Mac app asks for a width and height for a centered crop." },
      { title: "Rotate", detail: "The Mac app lets you rotate in 90-degree steps." },
      { title: "Flip", detail: "The Mac app creates a horizontally mirrored copy." },
      { title: "Remove Metadata", detail: "The Mac app creates a copy with metadata removed." }
    ],
    actions: [
      { title: "AirDrop", detail: "The Mac app opens sharing options for nearby devices." },
      { title: "Float", detail: "The Mac app keeps selected files on a floating shelf for another drag." },
      { title: "Copy To…", detail: "The Mac app asks you to choose a destination folder." },
      { title: "Move To…", detail: "The Mac app asks you to choose a destination folder, then moves the files." },
      { title: "Copy Path", detail: "The Mac app copies the selected file paths to your clipboard." },
      { title: "Terminal", detail: "The Mac app opens Terminal in the containing folder." }
    ]
  };
  let phase = "idle";
  let mode = "convert";
  let selectedIndex = 0;
  let timer;
  let drag = null;
  let suppressClick = false;
  let history = [];
  let currentView = "workspace";

  // GitHub Pages works without an account-specific value in the source.
  // A custom domain can set data-repository="https://github.com/OWNER/REPO" on <html>.
  let repository = document.documentElement.dataset.repository;
  if (!repository && location.hostname.endsWith(".github.io")) {
    const owner = location.hostname.slice(0, -10);
    const project = location.pathname.split("/").filter(Boolean)[0];
    if (owner && project) repository = `https://github.com/${encodeURIComponent(owner)}/${encodeURIComponent(project)}`;
  }
  if (repository && /^https:\/\/github\.com\/[\w.-]+\/[\w.-]+\/?$/.test(repository)) {
    document.querySelectorAll("[data-repo-path]").forEach((link) => {
      link.href = repository.replace(/\/$/, "") + link.dataset.repoPath;
    });
  }

  function announce(message) { $("announcer").textContent = message; }
  function svgElement(name, attributes) {
    const element = document.createElementNS(ns, name);
    for (const [key, value] of Object.entries(attributes)) element.setAttribute(key, value);
    return element;
  }
  function point(radius, angle) {
    const rad = angle * Math.PI / 180;
    return [210 + radius * Math.cos(rad), 210 + radius * Math.sin(rad)];
  }
  function segmentPath(index, count) {
    const step = 360 / count;
    const start = -90 + index * step - step / 2 + 1.3;
    const end = start + step - 2.6;
    const a = point(62, start), b = point(168, start), c = point(168, end), d = point(62, end);
    return `M${a}L${b}A168,168 0 0 1 ${c}L${d}A62,62 0 0 0 ${a}Z`;
  }
  function renderWheel() {
    wheelSVG.replaceChildren();
    operations[mode].forEach((operation, index, all) => {
      const group = svgElement("g", {
        class: "wheel-choice", role: "button", tabindex: phase === "wheel" ? "0" : "-1",
        "aria-label": `Preview ${operation.title}${mode === "convert" ? " conversion" : ""}`,
        "aria-disabled": phase === "wheel" ? "false" : "true", "data-index": index
      });
      group.append(svgElement("path", { class: "wheel-segment", d: segmentPath(index, all.length) }));
      const [x, y] = point(117, -90 + index * 360 / all.length);
      const icon = svgElement("path", { class: "sector-icon", d: `M${x - 6},${y - 22}h8l4,4v14h-12zM${x + 2},${y - 22}v4h4M${x - 3},${y - 11}h6` });
      group.append(icon);
      const text = svgElement("text", { x, y: y + 14 });
      if (operation.title === "Remove Metadata") {
        const line1 = svgElement("tspan", { x, dy: "0" }); line1.textContent = "Remove";
        const line2 = svgElement("tspan", { x, dy: "14" }); line2.textContent = "Metadata";
        text.append(line1, line2);
      } else { text.textContent = operation.title; }
      group.append(text);
      group.addEventListener("pointerenter", () => { if (phase === "wheel") selectIndex(index); });
      group.addEventListener("focus", () => selectIndex(index));
      group.addEventListener("click", () => { if (phase === "wheel" && !suppressClick) chooseOperation(index); });
      group.addEventListener("keydown", (event) => {
        if (["Enter", " "].includes(event.key)) { event.preventDefault(); chooseOperation(index); }
      });
      wheelSVG.append(group);
    });
    selectIndex(selectedIndex);
  }
  function selectIndex(index, focus = false) {
    selectedIndex = (index + operations[mode].length) % operations[mode].length;
    const items = [...wheelSVG.querySelectorAll(".wheel-choice")];
    items.forEach((item, i) => item.classList.toggle("selected", phase === "wheel" && i === selectedIndex));
    if (focus) items[selectedIndex]?.focus();
  }
  function setPhase(next) {
    phase = next; demo.dataset.phase = next;
    $("reset").disabled = phase === "idle" && history.length === 0;
    $("selection-tag").hidden = phase === "idle" || phase === "queued" || phase === "done";
    $("wheel-frame").hidden = phase === "queued" || phase === "done";
    $("result").hidden = phase !== "queued" && phase !== "done";
    $("next-step").disabled = phase === "queued";
    const steps = {
      idle: [1, "Pick Up the Sample.", "Drag the image, or use the button.", "Pick Up Sample"],
      picked: [2, "Bring the Tools to You.", "Tap Shift, or open the wheel below.", "Open Wheel"],
      wheel: [3, "Choose What Comes Next.", "Drop onto a format, or choose it with a click.", mode === "convert" ? "Try PNG" : `Try ${operations[mode][0].title}`],
      queued: [3, "Queued in the Preview.", "This is an example, not a real conversion.", "Previewing…"],
      done: [3, "That's the Idea.", "Try another mode, or get the Mac app.", "Try Another Spin"]
    };
    const [number, title, detail, button] = steps[phase];
    $("step-counter").replaceChildren(document.createTextNode(String(number)));
    const total = document.createElement("span"); total.textContent = "/3"; $("step-counter").append(total);
    $("step-title").textContent = title; $("step-detail").textContent = detail;
    $("next-step").firstChild.textContent = button;
    const center = $("wheel-center");
    center.querySelector("span").textContent = phase === "wheel" ? "Cancel" : "Open Wheel";
    center.querySelector("use").setAttribute("href", phase === "wheel" ? "#icon-close" : "#icon-arrow");
    center.setAttribute("aria-label", phase === "wheel" ? "Close the wheel" : "Pick up the sample and open the wheel");
    $("wheel-help").textContent = phase === "wheel" ? "Choose an operation · Arrow keys + Enter · Esc to close" : "Pick up the sample. Then tap Shift.";
    [...wheelSVG.children].forEach((item) => {
      item.setAttribute("tabindex", phase === "wheel" ? "0" : "-1");
      item.setAttribute("aria-disabled", phase === "wheel" ? "false" : "true");
    });
    selectIndex(selectedIndex);
  }
  function showView(view, focus = false) {
    currentView = view;
    for (const name of ["workspace", "activity"]) {
      const active = name === view, tab = $(`${name}-tab`);
      tab.classList.toggle("active", active); tab.setAttribute("aria-selected", String(active));
      tab.tabIndex = active ? 0 : -1; $(`${name}-panel`).hidden = !active;
    }
    $("view-label").textContent = view === "workspace" ? "Workspace" : "Activity";
    if (focus) $(`${view}-tab`).focus();
  }
  function pickUp() {
    clearTimeout(timer); showView("workspace"); setPhase("picked");
    announce("Sample selected. Press Shift or choose Open Wheel.");
  }
  function openWheel(nextMode = mode, focus = false) {
    clearTimeout(timer); mode = nextMode; selectedIndex = 0; showView("workspace");
    modes.forEach((button) => {
      const active = button.dataset.mode === mode;
      button.classList.toggle("active", active); button.setAttribute("aria-pressed", String(active));
    });
    setPhase("wheel"); renderWheel();
    announce(`${mode === "convert" ? "Conversion" : mode === "tools" ? "Tools" : "Actions"} wheel open. Choose an operation.`);
    if (focus) selectIndex(0, true);
  }
  function closeWheel() {
    setPhase("picked"); $("wheel-center").focus(); announce("Wheel closed. Sample is still selected.");
  }
  function chooseOperation(index) {
    if (phase !== "wheel") return;
    const focusResult = wheelSVG.contains(document.activeElement) || document.activeElement === $("wheel-center");
    const operation = operations[mode][index], chosenMode = mode;
    const filename = operation.extension ? `morning-light.${operation.extension}` : operation.title;
    const detail = operation.extension ? (operation.engine ? `The Mac app creates this output with the optional ${operation.engine} engine.` : "The Mac app creates a new file and keeps the original.") : operation.detail;
    setPhase("queued"); $("result-label").textContent = "Queued in Preview";
    $("result-filename").textContent = filename; $("result-detail").textContent = "Showing the next step in the example…";
    $("result-symbol").setAttribute("href", "#icon-history");
    $("result").querySelector(".result-original").hidden = chosenMode === "actions";
    if (focusResult) $("result").focus({ preventScroll: true });
    announce(`${operation.title} queued in the preview. No real files are being changed.`);
    timer = setTimeout(() => {
      setPhase("done"); $("result-label").textContent = operation.extension ? "Example Result" : "In the Mac App";
      $("result-detail").textContent = detail; $("result-symbol").setAttribute("href", "#icon-check");
      history.unshift({ filename, title: operation.title, mode: chosenMode });
      history = history.slice(0, 12); renderActivity();
      announce(`Preview complete. ${filename}. ${detail} No real files were changed.`);
    }, reducedMotion.matches ? 0 : 850);
  }
  function renderActivity() {
    const list = $("activity-list"); list.replaceChildren(); $("activity-empty").hidden = history.length > 0;
    $("activity-count").hidden = history.length === 0; $("activity-count").textContent = String(history.length);
    history.forEach((entry) => {
      const item = document.createElement("li"); item.className = "activity-item";
      const icon = svgElement("svg", { class: "icon", "aria-hidden": "true" }); icon.append(svgElement("use", { href: "#icon-check" }));
      const body = document.createElement("div"), title = document.createElement("strong"), detail = document.createElement("p"), badge = document.createElement("span");
      title.textContent = entry.filename; detail.textContent = `${sample} · ${entry.mode === "convert" ? `Convert to ${entry.title}` : entry.title}`;
      badge.className = "activity-badge"; badge.textContent = "Preview Only";
      body.append(title, detail); item.append(icon, body, badge); list.append(item);
    });
  }
  function reset() {
    clearTimeout(timer); finishDrag(); history = []; mode = "convert"; selectedIndex = 0;
    modes.forEach((button) => {
      const active = button.dataset.mode === mode; button.classList.toggle("active", active); button.setAttribute("aria-pressed", String(active));
    });
    renderActivity(); showView("workspace"); setPhase("idle"); renderWheel();
    announce("Preview reset. Pick up the sample to start again.");
  }
  $("next-step").addEventListener("click", () => {
    showView("workspace");
    if (phase === "idle") pickUp();
    else if (phase === "picked") openWheel(mode, true);
    else if (phase === "wheel") chooseOperation(0);
    else if (phase === "done") openWheel(mode, true);
  });
  $("wheel-center").addEventListener("click", () => phase === "wheel" ? closeWheel() : openWheel(mode, true));
  $("sample-file").addEventListener("click", () => { if (!suppressClick) pickUp(); });
  modes.forEach((button) => button.addEventListener("click", () => openWheel(button.dataset.mode)));
  $("reset").addEventListener("click", reset);
  $("workspace-tab").addEventListener("click", () => showView("workspace"));
  $("activity-tab").addEventListener("click", () => showView("activity"));
  document.querySelector(".demo-nav").addEventListener("keydown", (event) => {
    if (["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) {
      event.preventDefault(); showView(event.key === "Home" ? "workspace" : event.key === "End" ? "activity" : currentView === "workspace" ? "activity" : "workspace", true);
    }
  });
  $("view-activity").addEventListener("click", () => showView("activity", true));
  $("back-workspace").addEventListener("click", () => { showView("workspace"); openWheel(mode, true); });
  $("keyboard-toggle").addEventListener("click", () => {
    const visible = $("keyboard-help").hidden;
    $("keyboard-help").hidden = !visible; $("keyboard-toggle").setAttribute("aria-expanded", String(visible));
  });
  demo.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && phase === "wheel") { event.preventDefault(); closeWheel(); return; }
    if (event.key === "Shift" && !event.repeat && phase === "picked") { openWheel("convert"); return; }
    if (phase === "wheel" && event.target.closest("#wheel-svg") && ["ArrowLeft", "ArrowUp", "ArrowRight", "ArrowDown"].includes(event.key)) {
      event.preventDefault(); selectIndex(selectedIndex + (["ArrowLeft", "ArrowUp"].includes(event.key) ? -1 : 1), true);
    }
  });

  // Pointer dragging uses only the illustrated sample, never DataTransfer files.
  function indexAt(clientX, clientY) {
    const rect = wheelSVG.getBoundingClientRect();
    const x = (clientX - rect.left) * 420 / rect.width - 210;
    const y = (clientY - rect.top) * 420 / rect.height - 210;
    const radius = Math.hypot(x, y); if (radius < 62 || radius > 168) return null;
    const count = operations[mode].length;
    const degrees = ((Math.atan2(y, x) * 180 / Math.PI + 90) % 360 + 360) % 360;
    return Math.floor((degrees + 180 / count) / (360 / count)) % count;
  }
  function finishDrag() {
    drag = null; demo.classList.remove("dragging"); $("drag-ghost").hidden = true;
  }
  $("sample-file").addEventListener("pointerdown", (event) => {
    if (event.button !== 0) return;
    drag = { id: event.pointerId, x: event.clientX, y: event.clientY, moved: false };
    $("sample-file").setPointerCapture(event.pointerId);
  });
  $("sample-file").addEventListener("pointermove", (event) => {
    if (!drag || drag.id !== event.pointerId) return;
    if (!drag.moved && Math.hypot(event.clientX - drag.x, event.clientY - drag.y) > 6) {
      drag.moved = true; pickUp(); demo.classList.add("dragging"); $("drag-ghost").hidden = false;
    }
    if (!drag.moved) return;
    $("drag-ghost").style.transform = `translate(${event.clientX + 13}px, ${event.clientY + 15}px)`;
    if (event.shiftKey && phase !== "wheel") openWheel("convert");
    if (phase === "wheel") { const index = indexAt(event.clientX, event.clientY); if (index !== null) selectIndex(index); }
  });
  $("sample-file").addEventListener("pointerup", (event) => {
    if (!drag || drag.id !== event.pointerId) return;
    const moved = drag.moved;
    if (moved && phase === "wheel") { const index = indexAt(event.clientX, event.clientY); if (index !== null) chooseOperation(index); }
    if (moved) { suppressClick = true; setTimeout(() => { suppressClick = false; }, 0); }
    finishDrag();
  });
  $("sample-file").addEventListener("pointercancel", finishDrag);
  document.addEventListener("keydown", (event) => {
    if (drag?.moved && event.key === "Shift" && !event.repeat && phase !== "wheel") openWheel("convert");
  });
  // Prevent the browser from navigating away if someone drops an actual file.
  demo.addEventListener("dragover", (event) => event.preventDefault());
  demo.addEventListener("drop", (event) => { event.preventDefault(); announce("This preview uses the illustrated sample only. Open the Mac app to work with your own files."); });
  window.addEventListener("blur", finishDrag);
  renderWheel(); setPhase("idle");
})();
