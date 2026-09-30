dofile(os.getenv("OMARCHY_PATH") .. "/default/hypr/bootstrap.lua")

package.loaded["default.hypr.autostart"] = true

hl.config({
  misc = { disable_watchdog_warning = true },
  xwayland = { enabled = false },
})

hl.monitor({
  output = "",
  mode = os.getenv("OMARCHY_MODE"),
  position = "0x0",
  scale = tonumber(os.getenv("OMARCHY_SCALE")),
})

require("default.hypr.omarchy")
require("default.hypr.toggles")

hl.on("hyprland.start", function()
  hl.exec_cmd("omarchy-launch-shell")
end)
