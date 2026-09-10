// JXA browser adapter. Arguments and results are JSON, never interpolated code.
function run(argv) {
    const name = argv[0], action = argv[1], p = JSON.parse(argv[2] || '{}');
    const app = Application(name), safari = name === 'Safari';
    if (action === 'snapshot') {
        if (!app.running()) return JSON.stringify([]);
        return JSON.stringify(app.windows().map(w => {
            const tabs = w.tabs();
            const selected = safari ? w.currentTab().index() : w.activeTabIndex();
            return {id: w.id(), tabs: tabs.map((t, i) => ({
                window: w.id(), index: i + 1, url: t.url() || '', active: i + 1 === selected
            }))};
        }));
    }
    if (action === 'ready') {
        return JSON.stringify(safari || !app.windows[0].activeTab().loading());
    }
    if (action === 'open') {
        app.activate();
        if (!app.windows.length) {
            if (safari) app.Document().make(); else app.Window().make();
        }
        const w = app.windows[0];
        w.tabs.push(app.Tab({url: p.url}));
        if (safari) w.currentTab = w.tabs[w.tabs.length - 1];
        else w.activeTabIndex = w.tabs.length;
        return;
    }
    const w = app.windows.byId(p.window);
    if (!w.exists()) throw Error('The source window was closed. Run the command again.');
    const t = w.tabs[p.index - 1];
    if (!t.exists() || (t.url() || '') !== p.url) throw Error('The source tab changed. Run the command again.');
    if (action === 'navigate') {
        const selected = safari ? w.currentTab().index() : w.activeTabIndex();
        t.url = p.target;
        // Some Chromium variants select a tab when its URL is changed.
        if (safari) w.currentTab = w.tabs[selected - 1];
        else w.activeTabIndex = selected;
        return;
    }
    if (action === 'close') { t.close(); return; }
    if (action === 'focus') {
        if (safari) w.currentTab = t; else w.activeTabIndex = p.index;
        if (!safari) w.minimized = false;
        w.index = 1;
        app.activate();
        return;
    }
    throw Error('Unknown browser action: ' + action);
}
