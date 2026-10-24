local function add_lines(args, tip)
    for _, line in ipairs(psc.run(args) or {}) do
        local name = psc.trim(line)
        if name ~= "" then
            psc.add({ name = name, tip = tip })
        end
    end
end

local function add_sessions()
    add_lines({ "tmux", "list-sessions", "-F", "#{session_name}" }, { ["en-US"] = "session", ["zh-CN"] = "会话" })
end

local function add_windows()
    add_lines({ "tmux", "list-windows", "-a", "-F", "#{session_name}:#{window_index}" }, { ["en-US"] = "window", ["zh-CN"] = "窗口" })
end

local function add_panes()
    add_lines({ "tmux", "list-panes", "-a", "-F", "#{session_name}:#{window_index}.#{pane_index}" }, { ["en-US"] = "pane", ["zh-CN"] = "窗格" })
end

local function add_clients()
    add_lines({ "tmux", "list-clients", "-F", "#{client_name}" }, { ["en-US"] = "client", ["zh-CN"] = "客户端" })
end

psc.on({
    { command = "attach-session", option = "-t" },
    { command = "detach-client", option = "-s" },
    { command = "has-session", option = "-t" },
    { command = "kill-session", option = "-t" },
    { command = "last-window", option = "-t" },
    { command = "list-clients", option = "-t" },
    { command = "list-windows", option = "-t" },
    { command = "lock-session", option = "-t" },
    { command = "new-session", option = "-t" },
    { command = "next-window", option = "-t" },
    { command = "previous-window", option = "-t" },
    { command = "rename-session", option = "-t" },
    { command = "set-environment", option = "-t" },
    { command = "show-environment", option = "-t" },
    { command = "switch-client", option = "-t" },
}, add_sessions)

psc.on({
    { command = "break-pane", option = "-t" },
    { command = "kill-window", option = "-t" },
    { command = "last-pane", option = "-t" },
    { command = "link-window", option = "-s" },
    { command = "link-window", option = "-t" },
    { command = "list-panes", option = "-t" },
    { command = "move-window", option = "-s" },
    { command = "move-window", option = "-t" },
    { command = "new-window", option = "-t" },
    { command = "next-layout", option = "-t" },
    { command = "previous-layout", option = "-t" },
    { command = "rename-window", option = "-t" },
    { command = "resize-window", option = "-t" },
    { command = "respawn-window", option = "-t" },
    { command = "rotate-window", option = "-t" },
    { command = "select-window", option = "-t" },
    { command = "set-window-option", option = "-t" },
    { command = "show-window-options", option = "-t" },
    { command = "swap-window", option = "-s" },
    { command = "swap-window", option = "-t" },
    { command = "unlink-window", option = "-t" },
}, add_windows)

psc.on({
    { command = "break-pane", option = "-s" },
    { command = "capture-pane", option = "-t" },
    { command = "choose-buffer", option = "-t" },
    { command = "choose-client", option = "-t" },
    { command = "choose-tree", option = "-t" },
    { command = "clear-history", option = "-t" },
    { command = "clock-mode", option = "-t" },
    { command = "copy-mode", option = "-s" },
    { command = "copy-mode", option = "-t" },
    { command = "customize-mode", option = "-t" },
    { command = "display-menu", option = "-t" },
    { command = "display-message", option = "-t" },
    { command = "display-popup", option = "-t" },
    { command = "display-panes", option = "-t" },
    { command = "find-window", option = "-t" },
    { command = "if-shell", option = "-t" },
    { command = "join-pane", option = "-s" },
    { command = "join-pane", option = "-t" },
    { command = "kill-pane", option = "-t" },
    { command = "move-pane", option = "-s" },
    { command = "move-pane", option = "-t" },
    { command = "new-pane", option = "-t" },
    { command = "paste-buffer", option = "-t" },
    { command = "pipe-pane", option = "-t" },
    { command = "resize-pane", option = "-t" },
    { command = "respawn-pane", option = "-t" },
    { command = "run-shell", option = "-t" },
    { command = "select-layout", option = "-t" },
    { command = "select-pane", option = "-t" },
    { command = "send-keys", option = "-t" },
    { command = "send-prefix", option = "-t" },
    { command = "server-access", option = "-t" },
    { command = "set-hook", option = "-t" },
    { command = "set-option", option = "-t" },
    { command = "show-hooks", option = "-t" },
    { command = "show-options", option = "-t" },
    { command = "source-file", option = "-t" },
    { command = "split-window", option = "-t" },
    { command = "swap-pane", option = "-s" },
    { command = "swap-pane", option = "-t" },
    { command = "switch-mode", option = "-t" },
}, add_panes)

psc.on({
    { command = "command-prompt", option = "-t" },
    { command = "confirm-before", option = "-t" },
    { command = "detach-client", option = "-t" },
    { command = "display-menu", option = "-c" },
    { command = "display-message", option = "-c" },
    { command = "display-popup", option = "-c" },
    { command = "load-buffer", option = "-t" },
    { command = "lock-client", option = "-t" },
    { command = "refresh-client", option = "-t" },
    { command = "send-keys", option = "-c" },
    { command = "set-buffer", option = "-t" },
    { command = "show-messages", option = "-t" },
    { command = "suspend-client", option = "-t" },
    { command = "switch-client", option = "-c" },
}, add_clients)
