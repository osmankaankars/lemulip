"use strict";
// Illustrations of supported workflows, not native recordings or converters.
(() => {
  const byId = id => document.getElementById(id);
  const panel = byId("feature-panel");
  const canvas = byId("feature-canvas");
  if (!panel || !canvas) return;
  const tabs = [...document.querySelectorAll("[data-feature]")];
  const reduced = matchMedia("(prefers-reduced-motion: reduce)");
  const toggles = [byId("showcase-toggle"), byId("feature-toggle")];
  let userPaused = false;
  const photo = '<img src="./assets/morning-light.jpg" width="384" height="288" alt="Generated sample landscape">';
  const arrow = '<svg class="icon" aria-hidden="true"><use href="#icon-arrow"/></svg>';
  const paper = (title, number) => `<div class="paper-page"><b>${title}</b><div class="paper-art"></div><i></i><i></i><i></i><i></i><span>Page ${number}</span></div>`;
  const waveform = Array.from({ length: 64 }, (_, i) => {
    const height = 12 + Math.abs(Math.sin(i * 1.7) * Math.cos(i * .31)) * 88;
    return `<b style="height:${height.toFixed(1)}%"></b>`;
  }).join("");
  const scenes = {
    images: {
      editor: "Crop Image", title: "Frame It Your Way.",
      summary: "Choose the part you want to keep. Your original stays as it is.",
      facts: [["Convert", "PNG · JPEG · HEIC · TIFF · BMP"], ["Refine", "Crop · Resize · Rotate · Remove Metadata"], ["Also Built In", "Images to PDF"]],
      link: "More Formats With ImageMagick", hint: "Select the part you want to keep.", result: "Create Copy",
      markup: `<div class="crop-demo">${photo}<div class="crop-box"><i></i><i></i><i></i><i></i></div></div>`
    },
    pdf: {
      editor: "Organize PDF", title: "Every Page in Place.",
      summary: "Put pages in order before saving. See what stays, what moves, and what goes.",
      facts: [["Arrange", "Reorder · Rotate · Remove · Extract"], ["Bring Together", "Preview and arrange documents before merging"], ["Also Built In", "Split · Page Images · Text Extraction · Offline OCR"]],
      link: "Explore PDF Tools", hint: "Reorder pages. Review the new arrangement.", result: "Create Copy",
      markup: `<div class="pdf-scene" role="img" aria-label="Illustrated PDF pages changing order">${paper("Field Notes", 1)}${paper("The Details", 2)}${paper("What's Next", 3)}</div>`
    },
    audio: {
      editor: "Trim Audio", title: "Keep the Good Part.",
      summary: "Find your selection in the waveform. In the app, play it back before making a shorter copy.",
      facts: [["Refine", "Visual Waveform · Trim · Selection Playback"], ["Export", "M4A · WAV · AIFF"], ["Optional Engine", "FFmpeg adds more audio formats and tools"]],
      link: "Explore Audio Tools", hint: "Illustrated selection only. No audio plays here.", result: "Create Copy",
      markup: `<div class="wave-scene" role="img" aria-label="Illustrated audio waveform with trim handles and a selection playhead"><span class="wave-name">morning-notes.wav</span><div class="waveform">${waveform}<div class="wave-selection"></div><div class="wave-playhead"></div></div><div class="wave-time"><span>0:00</span><span>0:15</span><span>0:30</span></div><span class="selection-note">Choose your start and end points.</span></div>`
    },
    video: {
      editor: "Trim Video", title: "A Little Less. Just Right.",
      summary: "Find your cut with a visual timeline. Crop the frame and preview the part you want to keep.",
      facts: [["Refine", "Visual Trim · Crop · Native Preview"], ["Export", "MP4 · MOV"], ["Optional Engine", "FFmpeg adds more video formats and tools"]],
      link: "Explore Video Tools", hint: "Illustrated timeline, not a video recording.", result: "Create Copy",
      markup: `<div class="video-scene" role="img" aria-label="Illustrated video preview and a selected timeline range">${photo}<span class="video-label">morning-walk.mov</span><div class="video-timeline"><div class="video-playhead"></div></div></div>`
    },
    documents: {
      editor: "Documents & Tables", title: "Ready for the Next App.",
      summary: "Turn a simple table into an Excel workbook. Bring notes into a Word document, without installing Office.",
      facts: [["Built-In Word Export", "TXT · Basic RTF · Basic Markdown → DOCX"], ["Built-In Tables", "CSV / TSV → XLSX · CSV ↔ TSV"], ["More Complex Files", "Optional LibreOffice and Pandoc routes"]],
      link: "Read Document Format Limits", hint: "One worksheet. Values stay as text.", result: "CSV → XLSX",
      markup: `<div class="document-scene" role="img" aria-label="Illustrated CSV to Excel conversion preserving leading zeros"><div class="data-sheet"><strong>inventory.csv</strong><pre>Code,Item\n0012,Notebook\n0013,Pencil\n0014,Folder</pre></div>${arrow}<div class="data-sheet xlsx-sheet"><strong>inventory.xlsx</strong><table aria-hidden="true"><tr><th>Code</th><th>Item</th></tr><tr><td>0012</td><td>Notebook</td></tr><tr><td>0013</td><td>Pencil</td></tr><tr><td>0014</td><td>Folder</td></tr></table></div></div>`
    },
    archives: {
      editor: "Create Archive", title: "Bring It All Together.",
      summary: "Pack related files for their next stop. Extract supported archives into a fresh folder.",
      facts: [["Pack", "Create ZIP · Create TAR"], ["Compress", "GZIP individual files"], ["Unpack", "Extract supported archives into a new folder"]],
      link: "Read Archive Support", hint: "A new archive. Your source files stay in place.", result: "Create ZIP",
      markup: `<div class="archive-scene" role="img" aria-label="Illustration of three sample files being packed into a ZIP"><div class="archive-inputs"><span>field-notes.pdf</span><span>morning-light.png</span><span>inventory.csv</span></div>${arrow}<div class="archive-output"><span class="zip-teeth"></span><b>weekend.zip</b></div></div>`
    }
  };
  function restartIllustration() {
    panel.classList.remove("is-visible");
    void panel.offsetWidth;
    if (panel.getBoundingClientRect().bottom > 0 && panel.getBoundingClientRect().top < innerHeight) panel.classList.add("is-visible");
  }
  function selectFeature(tab, focus = false) {
    const key = tab.dataset.feature;
    const scene = scenes[key];
    if (!scene) return;
    tabs.forEach(item => {
      const selected = item === tab;
      item.setAttribute("aria-selected", String(selected));
      item.tabIndex = selected ? 0 : -1;
    });
    panel.setAttribute("aria-labelledby", tab.id);
    canvas.dataset.scene = key;
    canvas.innerHTML = scene.markup;
    byId("editor-title").textContent = scene.editor;
    byId("feature-title").textContent = scene.title;
    byId("feature-summary").textContent = scene.summary;
    byId("editor-hint").textContent = scene.hint;
    byId("editor-result").textContent = scene.result;
    byId("feature-facts").replaceChildren(...scene.facts.map(([term, description]) => {
      const row = document.createElement("div"), dt = document.createElement("dt"), dd = document.createElement("dd");
      dt.textContent = term; dd.textContent = description; row.append(dt, dd); return row;
    }));
    const link = byId("feature-link");
    link.replaceChildren(document.createTextNode(scene.link + " "));
    const icon = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    icon.setAttribute("class", "icon"); icon.setAttribute("aria-hidden", "true");
    const use = document.createElementNS("http://www.w3.org/2000/svg", "use");
    use.setAttribute("href", "#icon-arrow"); icon.append(use); link.append(icon);
    byId("feature-announcer").textContent = tab.textContent + ": " + scene.title;
    if (focus) { tab.focus({ preventScroll: true }); tab.scrollIntoView({ block: "nearest", inline: "nearest", behavior: "instant" }); }
    restartIllustration();
  }
  tabs.forEach((tab, i) => {
    tab.addEventListener("click", () => selectFeature(tab));
    tab.addEventListener("keydown", event => {
      let index;
      if (event.key === "ArrowRight") index = (i + 1) % tabs.length;
      else if (event.key === "ArrowLeft") index = (i - 1 + tabs.length) % tabs.length;
      else if (event.key === "Home") index = 0;
      else if (event.key === "End") index = tabs.length - 1;
      else return;
      event.preventDefault(); event.stopPropagation(); selectFeature(tabs[index], true);
    });
  });
  function updateMotion() {
    const paused = userPaused || reduced.matches || document.hidden;
    document.documentElement.dataset.motion = paused ? "paused" : "playing";
    toggles.forEach(button => {
      button.textContent = reduced.matches ? "Reduced Motion On" : paused ? "Play Animation" : "Pause Animation";
      button.setAttribute("aria-pressed", String(paused));
      button.disabled = reduced.matches;
    });
  }
  toggles.forEach(button => button.addEventListener("click", () => { userPaused = !userPaused; updateMotion(); }));
  byId("feature-replay").addEventListener("click", () => {
    if (!reduced.matches) { userPaused = false; updateMotion(); }
    restartIllustration();
    byId("feature-announcer").textContent = reduced.matches ? "Preview reset. Your reduced-motion preference is respected." : "Illustrated preview restarted.";
  });
  reduced.addEventListener("change", updateMotion);
  document.addEventListener("visibilitychange", updateMotion);
  if ("IntersectionObserver" in window) {
    const observer = new IntersectionObserver(entries => entries.forEach(entry => entry.target.classList.toggle("is-visible", entry.isIntersecting)), { threshold: .12 });
    document.querySelectorAll(".motion-region").forEach(region => observer.observe(region));
  } else document.querySelectorAll(".motion-region").forEach(region => region.classList.add("is-visible"));
  updateMotion();
})();
