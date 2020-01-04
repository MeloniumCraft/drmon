-- modifiable variables
local reactorSide = "back"
local fluxGateSide = "right"

local targetStrength = 10
local targetTemperature = 7900
local maxTemperature = 8000
local safeTemperature = 6000
local maxOutput = 10e6
local lowestFieldPercent = 5

local activateOnCharged = true

-- please leave things untouched from here on
os.loadAPI("lib/f")

local version = "0.3"
-- toggleable via the monitor, use our algorithm to achieve our target field strength or let the user tweak it
local autoInputGate  = true
local autoOutputGate = true
local curInputGate   = 200000
local curOutputGate  = 500000

-- monitor 
local mon = {}

-- peripherals
local reactor
local outputFluxGate
local inputFluxGate

-- reactor information
local ri

-- last performed action
local action = "None since reboot"
local emergencyCharge = false
local emergencyTemp = false

mon.monitor = peripheral.find("monitor", function(_, object) return object.isColour() end)
outputFluxGate = peripheral.wrap(fluxGateSide)
inputFluxGate = peripheral.find("flux_gate", function(name, _) return name ~= fluxGateSide end)
reactor = peripheral.wrap(reactorSide)

if not mon.monitor then
	error("No valid monitor was found")
end

if not outputFluxGate then
	error("No valid output flux gate was found")
end

if not reactor then
	error("No valid reactor was found")
end

if not inputFluxGate then
	error("No valid input flux gate was found")
end

mon.X, mon.Y = mon.monitor.getSize()

--write settings to config file
function saveConfig()
  sw = fs.open("config.txt", "w")   
  sw.writeLine(version)
  sw.writeLine(autoInputGate)
  sw.writeLine(autoOutputGate)
  sw.writeLine(curInputGate)
  sw.writeLine(curOutputGate)
  sw.close()
end

--read settings from file
function loadConfig()
  sr = fs.open("config.txt", "r")
  version_conf = sr.readLine()
  autoInputGate_conf = tonumber(sr.readLine())
  autoOutputGate_conf = (sr.readLine() == "true")
  curInputGate_conf = tonumber(sr.readLine())
  curOutputGate_conf = (sr.readLine() == "true")
  sr.close()
end


-- 1st time? save our settings, if not, load our settings
if not fs.exists("config.txt") then
  saveConfig()
else
  if not pcall(loadConfig) then
    saveConfig()
  else
    if version ~= version_conf then
      saveConfig()
    else
      autoInputGate, autoOutputGate, curInputGate, curOutputGate = autoInputGate_conf, autoOutputGate_conf, curInputGate_conf, curOutputGate_conf
    end
  end
end

function buttons()

  while true do
    -- button handler
    event, side, xPos, yPos = os.pullEvent("monitor_touch")


    if yPos == 8 then
      if autoOutputGate then
        -- output gate toggle
        if xPos >= 14 and xPos <= 16 then
          autoOutputGate = not autoOutputGate
        end
      else
        -- output gate controls
        -- 2-4 = -1000, 6-9 = -10000, 10-12,8 = -100000
        -- 18-20 = +1000, 22-24 = +10000, 26-28 = +100000
        if xPos >= 2 and xPos <= 4 then
          curOutputGate = curOutputGate-1000, maxOutput
        elseif xPos >= 6 and xPos <= 9 then
          curOutputGate = curOutputGate-10000
        elseif xPos >= 10 and xPos <= 12 then
          curOutputGate = curOutputGate-100000
        elseif xPos >= 18 and xPos <= 19 then
          curOutputGate = curOutputGate+100000
        elseif xPos >= 22 and xPos <= 23 then
          curOutputGate = curOutputGate+10000
        elseif xPos >= 26 and xPos <= 27 then
          curOutputGate = curOutputGate+1000
        end
        outputFluxGate.setSignalLowFlow(curOutputGate)
      end
      saveConfig()
    elseif yPos == 10 then
      if autoInputGate then
        -- input gate toggle
        if xPos >= 14 and xPos <= 16 then
          autoInputGate = not autoInputGate
        end
      else
        -- input gate controls
        -- 2-4 = -1000, 6-9 = -10000, 10-12,8 = -100000
        -- 18-20 = +1000, 22-24 = +10000, 26-28 = +100000
        if xPos >= 2 and xPos <= 4 then
          curInputGate = curInputGate-1000
        elseif xPos >= 6 and xPos <= 9 then
          curInputGate = curInputGate-10000
        elseif xPos >= 10 and xPos <= 12 then
          curInputGate = curInputGate-100000
        elseif xPos >= 18 and xPos <= 20 then
          curInputGate = curInputGate+100000
        elseif xPos >= 22 and xPos <= 24 then
          curInputGate = curInputGate+10000
        elseif xPos >= 26 and xPos <= 28 then
          curInputGate = curInputGate+1000
        end
        inputFluxGate.setSignalLowFlow(curInputGate)
      end
      saveConfig()
    end
  end
end

function drawButtons(y)

  -- 2-4 = -1000, 6-9 = -10000, 10-12 = -100000
  -- 18-20 = +1000, 22-24 = +10000, 26-28 = +100000

  f.draw_text(mon, 2, y, " < ", colors.white, colors.gray)
  f.draw_text(mon, 6, y, " <<", colors.white, colors.gray)
  f.draw_text(mon, 10, y, "<<<", colors.white, colors.gray)

  f.draw_text(mon, 18, y, ">>>", colors.white, colors.gray)
  f.draw_text(mon, 22, y, ">> ", colors.white, colors.gray)
  f.draw_text(mon, 26, y, " > ", colors.white, colors.gray)
end

function update()
  while true do 

    f.clear(mon)

    ri = reactor.getReactorInfo()

    -- print out all the infos from .getReactorInfo() to term

    if ri == nil then
      error("reactor has an invalid setup")
    end

    for k, v in pairs (ri) do
      print(k, ": ", v)
    end
    print("Output Gate: ", outputFluxGate.getSignalLowFlow())
    print("Input Gate: ", inputFluxGate.getSignalLowFlow())

    -- monitor output

    local statusColor
    statusColor = colors.red

    if ri.status == "running" then
      statusColor = colors.green
    elseif ri.status == "cold" then
      statusColor = colors.gray
    elseif ri.status == "warming_up" then
      statusColor = colors.orange
    end

    f.draw_text_lr(mon, 2, 2, 1, "Reactor Status", string.upper(ri.status), colors.white, statusColor, colors.black)

    f.draw_text_lr(mon, 2, 4, 1, "Generation", f.format_int(ri.generationRate) .. " rf/t", colors.white, colors.lime, colors.black)

    local tempColor = colors.red
    if ri.temperature <= 5000 then tempColor = colors.green end
    if ri.temperature >= 5000 and ri.temperature <= 6500 then tempColor = colors.orange end
    f.draw_text_lr(mon, 2, 6, 1, "Temperature", f.format_int(ri.temperature) .. "C", colors.white, tempColor, colors.black)

    f.draw_text_lr(mon, 2, 7, 1, "Output Gate", f.format_int(outputFluxGate.getSignalLowFlow()) .. " rf/t", colors.white, colors.blue, colors.black)

    -- buttons
    if autoOutputGate then
      f.draw_text(mon, 14, 8, "AUT", colors.white, colors.gray)
    else
      f.draw_text(mon, 14, 8, "MAN", colors.white, colors,gray)
      drawButtons(8)
    end

    f.draw_text_lr(mon, 2, 9, 1, "Input Gate", f.format_int(inputFluxGate.getSignalLowFlow()) .. " rf/t", colors.white, colors.blue, colors.black)

    if autoInputGate then
      f.draw_text(mon, 14, 10, "AUT", colors.white, colors.gray)
    else
      f.draw_text(mon, 14, 10, "MAN", colors.white, colors.gray)
      drawButtons(10)
    end

    local satPercent = math.ceil(ri.energySaturation / ri.maxEnergySaturation * 10000)*.01

    f.draw_text_lr(mon, 2, 11, 1, "Energy Saturation", satPercent .. "%", colors.white, colors.white, colors.black)
    f.progress_bar(mon, 2, 12, mon.X-2, satPercent, 100, colors.blue, colors.gray)

    local fieldPercent, fieldColor
    fieldPercent = math.ceil(ri.fieldStrength / ri.maxFieldStrength * 10000)*.01

    fieldColor = colors.red
    if fieldPercent >= 50 then fieldColor = colors.green end
    if fieldPercent < 50 and fieldPercent > 30 then fieldColor = colors.orange end

    if autoInputGate then
      f.draw_text_lr(mon, 2, 14, 1, "Field Strength T:" .. targetStrength, fieldPercent .. "%", colors.white, fieldColor, colors.black)
    else
      f.draw_text_lr(mon, 2, 14, 1, "Field Strength", fieldPercent .. "%", colors.white, fieldColor, colors.black)
    end
    f.progress_bar(mon, 2, 15, mon.X-2, fieldPercent, 100, fieldColor, colors.gray)

    local fuelPercent, fuelColor

    fuelPercent = 100 - math.ceil(ri.fuelConversion / ri.maxFuelConversion * 10000)*.01

    fuelColor = colors.red

    if fuelPercent >= 70 then fuelColor = colors.green end
    if fuelPercent < 70 and fuelPercent > 30 then fuelColor = colors.orange end

    f.draw_text_lr(mon, 2, 17, 1, "Fuel ", fuelPercent .. "%", colors.white, fuelColor, colors.black)
    f.progress_bar(mon, 2, 18, mon.X-2, fuelPercent, 100, fuelColor, colors.gray)

    f.draw_text_lr(mon, 2, 19, 1, "Action ", action, colors.gray, colors.gray, colors.black)

    -- actual reactor interaction
    --
    if emergencyCharge then
      fluxval = math.max(900000, ri.fieldDrainRate / (1 - (targetStrength/100)))
      inputFluxGate.setSignalLowFlow(fluxval)
      if ri.temperature < 7000 and fieldPercent > 20 and activateOnCharged then
        emergencyCharge = false
        reactor.activateReactor()
      else
        reactor.chargeReactor()
      end
    end
    
    -- are we charging? open the floodgates
    if ri.status == "warming_up" then
      inputFluxGate.setSignalLowFlow(900000)
      emergencyCharge = false
    end

    -- are we stopping from a shutdown and our temp is better? activate
    if emergencyTemp and ri.status == "stopping" then
      if fieldPercent < 10 then
        fluxval = ri.fieldDrainRate / (1 - (targetStrength/100))
        inputFluxGate.setSignalLowFlow(fluxval)
      else
        inputFluxGate.setSignalLowFlow(curInputGate)
      end
      if ri.temperature < safeTemperature then
        reactor.activateReactor()
        emergencyTemp = false
      end
    end

    -- are we charged? lets activate
    if ri.status == "warming_up" and ri.temperature >= 2000 and activateOnCharged then
      reactor.activateReactor()
    end

    -- auto output flux gate
    if ri.status == "running" then
      if autoOutputGate then
        curOutputGate = math.min(math.max(0, math.min((targetTemperature - ri.temperature) * 200, -(8 - fieldPercent) * 1e6) + ri.generationRate), maxOutput)
        print("Target output: ".. curOutputGate)
      end
      outputFluxGate.setSignalLowFlow(curInputGate)
    end

    -- are we on? regulate the input fludgate to our target field strength
    -- or set it to our saved setting since we are on manual
    if ri.status == "running" then
      if autoInputGate then
        curInputGate = ri.fieldDrainRate / (1 - (targetStrength/100) )
        print("Target Input: ".. curInputGate)
      end
      inputFluxGate.setSignalLowFlow(curInputGate)
    end

    -- safeguards
    --
    
    -- out of fuel, kill it
    if fuelPercent <= 10 then
      reactor.stopReactor()
      action = "Fuel below 10%, refuel"
    end

    -- field strength is too dangerous, kill and it try and charge it before it blows
    if fieldPercent <= lowestFieldPercent and ri.status == "running" then
      action = "Field Str < " ..lowestFieldPercent.."%"
      reactor.stopReactor()
      reactor.chargeReactor()
      emergencyCharge = true
    end

    -- temperature too high, kill it and activate it when its cool
    if ri.temperature > maxTemperature then
      reactor.stopReactor()
      action = "Temp > " .. maxTemperature
      emergencyTemp = true
    end
    saveConfig()
    sleep(0.1)
  end
end

parallel.waitForAny(buttons, update)

