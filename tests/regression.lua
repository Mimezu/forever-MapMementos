-- Run from the game directory: lua Interface/AddOns/MapMementos/tests/regression.lua
local root = "Interface/AddOns/MapMementos/"
local frames, messages = {}, {}
local methods = {}
local function noop() end
local function frame(name, parent)
    local f = {name=name, parent=parent, scripts={}, shown=true, alpha=1, text=""}
    setmetatable(f, {__index=function(_, k) if methods[k] then return methods[k] end; if k:match("^[A-Z]") then return noop end end})
    frames[#frames+1]=f; if name then _G[name]=f end; return f
end
function methods:SetScript(k,v) self.scripts[k]=v end
function methods:GetScript(k) return self.scripts[k] end
function methods:HookScript(k,v) local old=self.scripts[k]; self.scripts[k]=function(...) if old then old(...) end; v(...) end end
function methods:RegisterEvent(e) self[e]=true end
function methods:SetText(s) self.text=s end
function methods:GetText() return self.text end
function methods:CreateTexture() return frame(nil,self) end
function methods:CreateMaskTexture() return frame(nil,self) end
function methods:GetWidth() return 140 end
function methods:GetHeight() return 140 end
function methods:GetFrameLevel() return self.frameLevel or 1 end
function methods:SetFrameLevel(level) self.frameLevel=level end
function methods:SetPoint(...) self.point={...} end
function methods:CreateFontString() return frame(nil,self) end
function methods:Hide() self.shown=false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
function methods:Show() self.shown=true end
function methods:IsShown() return self.shown end
function methods:SetParent(p) self.parent=p end
function methods:GetEffectiveAlpha() return self.alpha * (self.parent and self.parent:GetEffectiveAlpha() or 1) end
function methods:SetIgnoreParentAlpha(v) self.ignore=v end
function methods:SetEnabled(v) self.enabled=v end
function methods:SetTexture(v) self.texture=v end
function CreateFrame(_,name,parent,template)
 local f=frame(name,parent)
 if template=="PortraitFrameTemplate" then
  f.CloseButton=frame(nil,f)
  f.CloseButton:SetScript("OnClick",function() error("Standalone journal entered Blizzard's panel manager") end)
 end
 return f
end
UIParent=frame(); Minimap=frame(nil,UIParent); WorldMapFrame=frame(nil,UIParent)
GameTooltip=frame(); function GameTooltip:IsOwned() return false end
DEFAULT_CHAT_FRAME={AddMessage=function(_,s) messages[#messages+1]=s end}
UISpecialFrames={}; SlashCmdList={}; tinsert=table.insert
function wipe(t) for k in pairs(t) do t[k]=nil end end
function GetZoneText() return "Elwynn Forest" end
function GetSubZoneText() return "Quiet grove" end
local x,y,available=.4,.6,true
C_Map={GetBestMapForUnit=function() if available then return 37 end end,
 GetPlayerMapPosition=function() return {GetXY=function() return x,y end} end,
 GetMapInfo=function() return {name="Elwynn Forest"} end}
local mini,world={},{}
function CreateFromMixins(...)
 local t={}; for _,m in ipairs({...}) do for k,v in pairs(m) do t[k]=v end end; return t
end
MapCanvasPinMixin={OnReleased=function() end}
MapCanvasDataProviderMixin={GetMap=function(self) return self.map end}
function WorldMapFrame:AddDataProvider() error("Native map provider mutation") end
function WorldMapFrame:GetMapID() return 37 end
function WorldMapFrame:RemoveAllPinsByTemplate() world={} end
function WorldMapFrame:AcquirePin(_,id,px,py) world[#worldPins()+1]={id=id,x=px,y=py} end
local pins={
 RemoveAllMinimapIcons=function() mini={} end, RemoveAllWorldMapIcons=function() world={} end,
 AddMinimapIconMap=function(_,ref,b,map,px,py) b:SetParent(Minimap); mini[#mini+1]=b; return true end,
 AddMinimapIconWorld=function(_,ref,b,instance,wx,wy) b:SetParent(Minimap); mini[#mini+1]=b end,
 AddWorldMapIconMap=function(_,ref,b,map,px,py) b:SetParent(WorldMapFrame); world[#worldPins()+1]=b end}
LibStub=function(name) if name=="MapMementos-MinimapPins-1.0" then return pins end; return {GetPlayerZonePosition=function() end, GetPlayerWorldPosition=function() return 100,200,1 end} end
HBD_PINS_WORLDMAP_SHOW_CONTINENT=2
local canvas
function WorldMapFrame:GetCanvas() return canvas end
local poiLevel=120
function WorldMapFrame:GetPinFrameLevelsManager()
 return {GetValidFrameLevel=function(_,kind)
  assert(kind=="PIN_FRAME_LEVEL_AREA_POI")
  return poiLevel
 end}
end
local function worldPins()
 local result={}
 for _,f in ipairs(frames) do
  if f.parent and f.parent.parent==canvas and f.markerID and f.shown then
   assert(f:GetFrameLevel()>poiLevel, "Marker is underneath native map artwork")
   result[#result+1]={id=f.markerID,x=f.point[4]/140,y=-f.point[5]/140}
  end
 end
 return result
end
local function load(saved)
    canvas=frame(nil,WorldMapFrame)
    MapMementosDB=saved
    local ns={}; assert(loadfile(root.."Core.lua"))("MapMementos",ns)
    local ev=frames[#frames]; ev.scripts.OnEvent(ev,"ADDON_LOADED","MapMementos"); ev.scripts.OnEvent(ev,"PLAYER_LOGIN")
    return ns
end
local ns=load(nil)
ns.command("add Old oak ; A good place to rest.")
assert(MapMementosDB.markers[1].description=="A good place to rest.")
assert(#mini==1 and #worldPins()==1 and mini[1].ignore==false)
assert(worldPins()[1].x==.4 and worldPins()[1].y==.6, "World pins must use saved normalized coordinates")
local px,py=ns.mapPosition({map=9999,x=.2,y=.8},9999)
assert(px==.2 and py==.8, "Custom maps must not require HBD map data")
MapMementosDB.minimapAngle=0; ns.positionLauncher(MapMementosMinimapButton)
assert(math.abs(MapMementosMinimapButton.point[4]-72)<.001)
MapMementosDB.minimapAngle=90; ns.positionLauncher(MapMementosMinimapButton)
assert(math.abs(MapMementosMinimapButton.point[5]-72)<.001)
Minimap.alpha=.25; assert(mini[1]:GetEffectiveAlpha()==.25); Minimap.alpha=1
x,y=.7,.8
ns.command("")
local j=MapMementosJournal
assert(j.name:GetText()=="Old oak")
j.CloseButton.scripts.OnClick(j.CloseButton)
assert(not j:IsShown(), "Close button must hide the standalone journal directly")
ns.command("")
j.name:SetText("Old oak revisited"); j.notes:SetText("Bring a fishing pole.")
j.symbols[7].scripts.OnClick(j.symbols[7])
local function click(text)
 for _,f in ipairs(frames) do if type(f.text)=="table" and f.text.text==text and f.parent==j then f.scripts.OnClick(f); return end end
 error("Button missing: "..text)
end
click("Save entry")
assert(MapMementosDB.markers[1].x==.4 and MapMementosDB.markers[1].y==.6, "Editing moved the marker")
assert(MapMementosDB.markers[1].icon==7 and MapMementosDB.markers[1].description=="Bring a fishing pole.")
ns.command("add Second spot")
assert(MapMementosDB.markers[2].x==.7)
local saved=MapMementosDB
ns=load(saved)
assert(#mini==2 and #worldPins()==2 and MapMementosDB.markers[1].name=="Old oak revisited")
ns.command("add Third spot")
assert(MapMementosDB.markers[3] and MapMementosDB.nextID==4)
available=false
ns.command("add Unavailable")
assert(MapMementosDB.nextID==4)
ns.command(""); j=MapMementosJournal
assert(j:IsShown(), "Saved entries must remain accessible without current coordinates")
local before=0; for _ in pairs(MapMementosDB.markers) do before=before+1 end
click("Delete")
local count=0; for _ in pairs(MapMementosDB.markers) do count=count+1 end
assert(count==before, "Delete needs the second click")
click("Confirm?")
count=0; for _ in pairs(MapMementosDB.markers) do count=count+1 end
assert(count==before-1 and #mini==count and #worldPins()==count)
-- Older saved entries have no captured world coordinates. A missing library
-- map must recover through C_Map rather than quietly discarding the pin.
local legacy={version=1,nextID=2,markers={[1]={map=37,x=.3,y=.9,zone="Custom zone",name="Older spot",description="",icon=3}}}
pins.AddMinimapIconMap=function() return false end
C_Map.GetWorldPosFromMapPos=function(map,p) assert(map==37 and p.x==.3 and p.y==.9); return 1,{GetXY=function() return 200,100 end} end
function CreateVector2D(x,y) return {x=x,y=y} end
ns=load(legacy)
assert(#mini==1 and #worldPins()==1 and worldPins()[1].x==.3)
assert(MapMementosMinimapButton.scripts.OnUpdate==nil, "Idle launcher must not run per-frame work")
for _,b in ipairs(mini) do assert(b.scripts.OnUpdate==nil, "Idle minimap pins must not run per-frame work") end
MapMementosDB.minimapShape="square"; MapMementosDB.minimapAngle=45; ns.positionLauncher(MapMementosMinimapButton)
assert(math.abs(MapMementosMinimapButton.point[4]-72)<.01 and math.abs(MapMementosMinimapButton.point[5]-72)<.01, "Square minimap puts the button in the corner")
MapMementosDB.minimapShape=nil
-- Build 70009 gamepad world map: the soft cursor shows a marker's note.
local overlay, marker
for _,f in ipairs(frames) do if f.parent==canvas and f.scripts.OnUpdate then overlay=f end end
for _,f in ipairs(frames) do if overlay and f.parent==overlay and f.markerID and f.shown then marker=f end end
assert(overlay and marker, "world overlay and marker exist")
local owned
function GameTooltip:SetOwner(o) owned=o end
function GameTooltip:IsOwned(o) return owned==o end
function GameTooltip:Hide() owned=nil end
function methods:GetCenter() return self.cx, self.cy end
function methods:GetEffectiveScale() return self.scale or 1 end
marker.cx, marker.cy = 100, 100
local gamepadUI = true
InputUtil={IsGamepadUIEnabled=function() return gamepadUI end}
SoftCursor=frame(nil,UIParent); SoftCursor.cx, SoftCursor.cy = 105, 104
overlay.scripts.OnUpdate(overlay,.2)
assert(owned==marker, "gamepad cursor resting on a marker shows its note")
SoftCursor.cx = 140; overlay.scripts.OnUpdate(overlay,.2)
assert(owned==nil, "moving the cursor away hides the note")
-- Marker at (100,100) scale 2 sits at screen (200,200); cursor at scale 1.
SoftCursor.cx, SoftCursor.cy, marker.scale = 210, 206, 2; overlay.scripts.OnUpdate(overlay,.2)
assert(owned==marker, "reach compares screen positions across scales")
SoftCursor.cy, marker.scale = 104, nil
overlay.scripts.OnHide(overlay)
assert(owned==nil, "closing the map hides the note")
SoftCursor.cx = 105; gamepadUI=false; overlay.scripts.OnUpdate(overlay,.2)
assert(owned==nil, "keyboard mode ignores the soft cursor")
SoftCursor.shown=false; gamepadUI=true; overlay.scripts.OnUpdate(overlay,.2)
assert(owned==nil, "hidden soft cursor shows nothing")
InputUtil, SoftCursor = nil, nil
print("PASS: gamepad world-map soft cursor shows marker notes read-only")
-- Build 70009: Blizzard's gamepad navigation hooks CreateFrame. A marker button
-- created under the open map in the gamepad UI would taint its navigation.
local function worldButtons()
 local n=0; for _,f in ipairs(frames) do if f.parent==overlay and f.scripts.OnClick then n=n+1 end end; return n
end
local function markerCount() local n=0; for _ in pairs(MapMementosDB.markers) do n=n+1 end; return n end
assert(worldButtons()==markerCount(), "one world-map button per marker, made while the map is closed")
local realCreateFrame, underMap = CreateFrame, 0
CreateFrame=function(kind,name,parent,...) if parent==overlay then underMap=underMap+1 end; return realCreateFrame(kind,name,parent,...) end
gamepadUI=true; InputUtil={IsGamepadUIEnabled=function() return gamepadUI end}
local timers={}; C_Timer={After=function(_,fn) timers[#timers+1]=fn end}
available=true; WorldMapFrame.shown=true
ns.command("add Gamepad spot")
assert(underMap==0, "no button is created under the open gamepad map")
assert(worldButtons()==markerCount()-1)
WorldMapFrame.shown=false; overlay.scripts.OnHide(overlay)
assert(underMap==0 and #timers==1, "the missing button waits until the map has closed")
timers[1]()
assert(underMap==1 and worldButtons()==markerCount(), "the button is made once the map is closed")
gamepadUI=false; WorldMapFrame.shown=true
ns.command("add Mouse spot")
assert(underMap==2 and worldButtons()==markerCount(), "keyboard/mouse mode still creates buttons at once")
CreateFrame, InputUtil, C_Timer = realCreateFrame, nil, nil
print("PASS: no world-map button is created under the open gamepad map; it follows once the map closes")
print("PASS: create, tooltip data, edit, preserve location, icon, reload, ID allocation, unavailable location, delete, pin cleanup, inherited alpha")
print("PASS: custom world maps, legacy minimap fallback, draggable launcher geometry")


-- Verify the shipped library cannot silently restore the native integration.
local file=assert(io.open(root.."Libs/HereBeDragons-Pins-2.0.lua","r"))
local source=file:read("*a"); file:close()
assert(not source:find('WorldMapFrame:AddDataProvider',1,true))
assert(not source:find('WorldMapFrame.pinPools[',1,true))
assert(source:find('"MapMementos-MinimapPins-1.0"',1,true))
print("PASS: private minimap library and no native world-map provider/pool registration")
