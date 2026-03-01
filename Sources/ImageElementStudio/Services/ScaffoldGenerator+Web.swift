import Foundation

// MARK: - Web Full App Templates

extension ScaffoldGenerator {

    static func generatedWebFullAppReadme(manifest: StudioViewModel.BuildManifest) -> String {
        """
        # Generated Web App

        Generated from screenshot + conversation context.

        ## Run
        Open `index.html` directly or serve folder:

        ```bash
        cd ./full-app/web
        python3 -m http.server 8080
        ```

        ## Context
        - Project: \(manifest.projectName)
        - App Type: \(manifest.appType ?? "Unclassified")
        - Controls: \(manifest.inferredControls.count)
        - States: \(manifest.inferredStates.count)
        """
    }

    // MARK: - Web HTML

    static func generatedWebHTML(manifest: StudioViewModel.BuildManifest) -> String {
        let title = escapedHTML(manifest.appType ?? manifest.projectName)
        let subtitle = escapedHTML(manifest.productIntent ?? "Generated from screenshot and strategy conversation.")

        return """
        <!doctype html>
        <html lang="en">
          <head>
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1" />
            <title>\(title) - Generated Scaffold</title>
            <link rel="stylesheet" href="./styles.css" />
          </head>
          <body>
            <main class="app">
              <aside class="panel">
                <h2>Screens</h2>
                <ul id="screen-list" class="screen-list"></ul>
              </aside>

              <section class="workspace">
                <header>
                  <h1>\(title)</h1>
                  <p>\(subtitle)</p>
                  <div class="state-row">
                    <label for="state-select">State</label>
                    <select id="state-select"></select>
                    <span id="state-badge" class="state-badge"></span>
                  </div>
                </header>

                <section class="panel">
                  <h2>Current Screen</h2>
                  <p id="screen-summary" class="screen-summary"></p>
                </section>

                <section class="panel">
                  <h2>Capabilities</h2>
                  <div id="capability-grid" class="capability-grid"></div>
                </section>

                <section class="panel">
                  <h2>Controls</h2>
                  <div id="controls" class="controls"></div>
                </section>

                <section class="panel">
                  <h2>Activity</h2>
                  <ul id="activity-log" class="activity-log"></ul>
                </section>
              </section>
            </main>
            <script src="./app.js"></script>
          </body>
        </html>
        """
    }

    // MARK: - Web CSS

    static func generatedWebCSS() -> String {
        """
        :root {
          --bg: #0c111b;
          --panel: #182235;
          --panel-soft: #1f2b43;
          --text: #f6f8ff;
          --muted: #a6b1cb;
          --accent: #5ea1ff;
          --success: #2ec49d;
        }

        * { box-sizing: border-box; }
        body {
          margin: 0;
          background: radial-gradient(circle at top left, #16223a 0%, var(--bg) 55%);
          color: var(--text);
          font-family: "Avenir Next", "Segoe UI", sans-serif;
        }
        .app {
          max-width: 1180px;
          margin: 32px auto;
          padding: 24px;
          display: grid;
          grid-template-columns: 260px 1fr;
          gap: 12px;
          background: color-mix(in srgb, var(--panel) 88%, black);
          border: 1px solid rgba(255, 255, 255, 0.08);
          border-radius: 16px;
        }
        .workspace {
          display: flex;
          flex-direction: column;
          gap: 12px;
        }
        header { margin-bottom: 16px; }
        h1, h2 { margin-top: 0; margin-bottom: 8px; }
        p { color: var(--muted); }
        .panel {
          background: var(--panel-soft);
          border: 1px solid rgba(255, 255, 255, 0.08);
          border-radius: 12px;
          padding: 14px;
          margin-bottom: 12px;
        }
        .state-row {
          display: flex;
          align-items: center;
          gap: 10px;
        }
        select {
          background: #0f1a2d;
          color: var(--text);
          border: 1px solid rgba(255, 255, 255, 0.22);
          border-radius: 8px;
          padding: 6px 8px;
        }
        .state-badge {
          background: color-mix(in srgb, var(--success) 60%, black);
          border-radius: 999px;
          padding: 4px 10px;
          font-size: 12px;
        }
        .screen-list {
          list-style: none;
          margin: 0;
          padding: 0;
          display: flex;
          flex-direction: column;
          gap: 6px;
        }
        .screen-item {
          width: 100%;
          border: 1px solid rgba(255, 255, 255, 0.12);
          border-radius: 8px;
          background: rgba(255, 255, 255, 0.04);
          color: var(--text);
          text-align: left;
          padding: 8px 10px;
          cursor: pointer;
        }
        .screen-item.active {
          border-color: var(--accent);
          background: color-mix(in srgb, var(--accent) 18%, transparent);
        }
        .screen-summary {
          margin: 0;
          font-size: 14px;
          line-height: 1.4;
        }
        .capability-grid {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
          gap: 8px;
        }
        .capability-card {
          background: rgba(255, 255, 255, 0.06);
          border-radius: 8px;
          padding: 10px;
          font-size: 14px;
        }
        .controls {
          display: flex;
          flex-wrap: wrap;
          gap: 8px;
        }
        .control-btn {
          background: var(--accent);
          border: none;
          color: #041126;
          font-weight: 600;
          border-radius: 8px;
          padding: 8px 10px;
          cursor: pointer;
        }
        .activity-log {
          margin: 0;
          padding-left: 18px;
          max-height: 180px;
          overflow: auto;
        }
        .activity-log li {
          margin: 5px 0;
          font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
          font-size: 12px;
        }
        @media (max-width: 900px) {
          .app {
            grid-template-columns: 1fr;
          }
        }
        """
    }

    // MARK: - Web JS

    static func generatedWebJS(manifest: StudioViewModel.BuildManifest) -> String {
        let appSpec = generatedAppSpec(
            manifest: manifest,
            target: .web,
            deterministicHash: manifest.deterministicHash,
            generatedAt: manifest.generatedAt
        )
        return generatedWebJS(appSpec: appSpec)
    }

    static func generatedWebJS(appSpec: GeneratedAppSpec) -> String {
        let stateLiteral = jsStringArrayLiteral(appSpec.states)
        let controlLiteral = jsStringArrayLiteral(appSpec.controls)
        let capabilityLiteral = jsStringArrayLiteral(appSpec.capabilities)
        let screenLiteral = jsGeneratedScreenArrayLiteral(appSpec.screens)
        let transitionLiteral = jsTransitionObjectLiteral(appSpec.transitions)
        return """
        const blueprint = {
          states: \(stateLiteral),
          controls: \(controlLiteral),
          capabilities: \(capabilityLiteral),
          screens: \(screenLiteral),
          transitions: \(transitionLiteral)
        };

        const stateSelect = document.getElementById("state-select");
        const stateBadge = document.getElementById("state-badge");
        const screenList = document.getElementById("screen-list");
        const screenSummary = document.getElementById("screen-summary");
        const controls = document.getElementById("controls");
        const capabilityGrid = document.getElementById("capability-grid");
        const activityLog = document.getElementById("activity-log");

        let selectedState = blueprint.states[0] || "Default";
        let selectedScreenID = blueprint.screens[0]?.id || "";

        function activeScreen() {
          return blueprint.screens.find((screen) => screen.id === selectedScreenID) || blueprint.screens[0] || null;
        }

        function chooseScreenForState(state) {
          return blueprint.screens.find((screen) => screen.state === state) || blueprint.screens[0] || null;
        }

        function renderState() {
          stateSelect.innerHTML = "";
          blueprint.states.forEach((state) => {
            const option = document.createElement("option");
            option.value = state;
            option.textContent = state;
            option.selected = state === selectedState;
            stateSelect.appendChild(option);
          });
          stateBadge.textContent = selectedState;
        }

        function renderCapabilities() {
          const screen = activeScreen();
          const sourceCapabilities = (screen && screen.capabilityHints && screen.capabilityHints.length)
            ? screen.capabilityHints
            : blueprint.capabilities;
          capabilityGrid.innerHTML = "";
          sourceCapabilities.forEach((capability) => {
            const card = document.createElement("div");
            card.className = "capability-card";
            card.textContent = capability;
            capabilityGrid.appendChild(card);
          });
        }

        function renderScreens() {
          screenList.innerHTML = "";
          blueprint.screens.forEach((screen) => {
            const item = document.createElement("li");
            const button = document.createElement("button");
            button.type = "button";
            button.className = `screen-item ${screen.id === selectedScreenID ? "active" : ""}`;
            button.textContent = `${screen.name} (${screen.state})`;
            button.addEventListener("click", () => {
              selectedState = screen.state;
              selectedScreenID = screen.id;
              renderState();
              renderScreens();
              renderScreenSummary();
              renderCapabilities();
              pushActivity(`screen selected -> ${screen.name}`);
            });
            item.appendChild(button);
            screenList.appendChild(item);
          });
        }

        function renderScreenSummary() {
          const screen = activeScreen();
          if (!screen) {
            screenSummary.textContent = "No screens generated.";
            return;
          }
          screenSummary.textContent = `${screen.name}: ${screen.summary}`;
        }

        function pushActivity(message) {
          const line = document.createElement("li");
          const timestamp = new Date().toLocaleTimeString();
          line.textContent = `${timestamp} \u{2022} ${message}`;
          activityLog.prepend(line);
          while (activityLog.children.length > 28) {
            activityLog.removeChild(activityLog.lastChild);
          }
        }

        function rotateState() {
          if (!blueprint.states.length) {
            return;
          }
          const index = blueprint.states.indexOf(selectedState);
          const nextIndex = index >= 0 ? (index + 1) % blueprint.states.length : 0;
          selectedState = blueprint.states[nextIndex];
          renderState();
        }

        function trigger(control) {
          if (blueprint.transitions[control]) {
            selectedState = blueprint.transitions[control];
          } else {
            rotateState();
          }
          const candidate = chooseScreenForState(selectedState);
          if (candidate) {
            selectedScreenID = candidate.id;
          }
          renderState();
          renderScreens();
          renderScreenSummary();
          renderCapabilities();
          pushActivity(`${control} -> ${selectedState}`);
        }

        function renderControls() {
          controls.innerHTML = "";
          blueprint.controls.forEach((control) => {
            const button = document.createElement("button");
            button.className = "control-btn";
            button.type = "button";
            button.textContent = control;
            button.addEventListener("click", () => trigger(control));
            controls.appendChild(button);
          });
        }

        stateSelect.addEventListener("change", (event) => {
          selectedState = event.target.value;
          const candidate = chooseScreenForState(selectedState);
          if (candidate) {
            selectedScreenID = candidate.id;
          }
          renderState();
          renderScreens();
          renderScreenSummary();
          renderCapabilities();
          pushActivity(`state changed -> ${selectedState}`);
        });

        renderState();
        renderScreens();
        renderScreenSummary();
        renderCapabilities();
        renderControls();
        pushActivity("app initialized");

        console.log("Generated full app blueprint:", blueprint);
        """
    }
}
