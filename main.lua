return function(mod)
  if mod.generation ~= 3 then return end

  local installed = false
  local function install()
    if installed then return true end

    local okUntamed, untamed = pcall(function() return mod:find("untamed_advanced") end)
    local engine = okUntamed and untamed and untamed.exports and untamed.exports.engine
    if type(engine) ~= "table" then
      mod.log:error("Hoenn Latias + Latios Roamers requires Untamed Advanced")
      return false
    end

    local Roamer = require("src.core.game3.roamer")
    local Objects = require("src.core.game3.objects")
    local Rng = require("src.core.game3.rng")
    local Message = require("src.ui.game3.message")
    local FieldEffects = require("src.core.game3.field_effects")

    local LATIAS, LATIOS = 380, 381
    local LEVEL = 50
    local ROUTE_101 = "FR_HOENN_ROUTE101"
    local SCENE_LATIAS_ID, SCENE_LATIOS_ID = 128, 129

    local HOENN_ROUTES = {}
    for n = 101, 134 do HOENN_ROUTES[#HOENN_ROUTES + 1] = "FR_HOENN_ROUTE" .. n end

    local function isHoennMap(mapId)
      return tostring(mapId or ""):upper():find("HOENN_", 1, true) ~= nil
    end

    local function randomHoennRoute(except)
      local pick = except
      for _ = 1, 12 do
        pick = HOENN_ROUTES[(Rng.Random() % #HOENN_ROUTES) + 1]
        if pick ~= except then break end
      end
      return pick or ROUTE_101
    end

    local function state(session)
      session.modData = session.modData or {}
      session.modData[mod.id] = session.modData[mod.id] or {}
      return session.modData[mod.id]
    end

    local function isMulti(r)
      return type(r) == "table" and type(r.beasts) == "table"
    end

    local function withBeast(session, beast, fn, ...)
      local saved = session.roamer
      session.roamer = beast
      local result = fn(session, ...)
      session.roamer = saved
      return result
    end

    local function moveHoenn(beast, randomJump)
      if not beast or not beast.active then return end
      if randomJump or (Rng.Random() % 16) == 0 then
        beast.map = randomHoennRoute(beast.map)
        return
      end
      local n = tonumber(tostring(beast.map or ""):match("ROUTE(%d+)"))
      if not n or n < 101 or n > 134 then
        beast.map = randomHoennRoute()
        return
      end
      local choices = {}
      if n > 101 then choices[#choices + 1] = n - 1 end
      if n < 134 then choices[#choices + 1] = n + 1 end
      -- Occasionally make a longer jump so the pair do not get trapped walking
      -- numerically through routes whose actual Hoenn connections branch.
      if (Rng.Random() % 8) == 0 then
        beast.map = randomHoennRoute(beast.map)
      else
        beast.map = "FR_HOENN_ROUTE" .. choices[(Rng.Random() % #choices) + 1]
      end
    end

    -- Standalone grouped-roamer support. If Navel Rock has already installed
    -- its compatible patch, reuse it instead of wrapping the same methods twice.
    if not Roamer._allBeastsInstalled then
      local rawInit = Roamer.init
      local rawMove = Roamer.move
      local rawJump = Roamer.jump
      local rawTryEncounter = Roamer.tryEncounter
      local rawBattleEnd = Roamer.onBattleEnd

      Roamer.init = function(session, starterChoice)
        if not session then return false end
        local preserved = {}
        if isMulti(session.roamer) then
          for _, beast in ipairs(session.roamer.beasts) do
            if beast.hoennLatiasLatios or beast.darkrai then preserved[#preserved + 1] = beast end
          end
        end
        rawInit(session, starterChoice)
        local native = session.roamer
        local beasts = { native }
        for _, beast in ipairs(preserved) do beasts[#beasts + 1] = beast end
        session.roamer = { active=true, beasts=beasts }
        return true
      end

      Roamer.move = function(session, reason, mapId)
        local group = session and session.roamer
        if not isMulti(group) then return rawMove(session, reason, mapId) end
        for _, beast in ipairs(group.beasts) do
          if beast.active then
            if beast.hoennLatiasLatios then moveHoenn(beast, reason == "warp_random")
            else withBeast(session, beast, rawMove, reason, mapId) end
          end
        end
      end

      Roamer.jump = function(session)
        local group = session and session.roamer
        if not isMulti(group) then
          if group and group.hoennLatiasLatios then return moveHoenn(group, true) end
          return rawJump(session)
        end
        for _, beast in ipairs(group.beasts) do
          if beast.active then
            if beast.hoennLatiasLatios then moveHoenn(beast, true)
            else withBeast(session, beast, rawJump) end
          end
        end
      end

      Roamer.tryEncounter = function(session, mapId, terrain)
        local group = session and session.roamer
        if not isMulti(group) then return rawTryEncounter(session, mapId, terrain) end
        local candidates = {}
        for _, beast in ipairs(group.beasts) do
          if beast.active and Roamer.normalizeMapId(beast.map) == Roamer.normalizeMapId(mapId) then
            candidates[#candidates + 1] = beast
          end
        end
        if #candidates == 0 then return nil end
        local start = (Rng.Random() % #candidates) + 1
        for offset = 0, #candidates - 1 do
          local beast = candidates[((start + offset - 1) % #candidates) + 1]
          local enc = withBeast(session, beast, rawTryEncounter, mapId, terrain)
          if enc then return enc end
        end
        return nil
      end

      Roamer.onBattleEnd = function(session, foeState, battleResult, endReason)
        local group = session and session.roamer
        if not isMulti(group) then return rawBattleEnd(session, foeState, battleResult, endReason) end
        local species = foeState and (foeState.species or foeState.speciesId)
        for _, beast in ipairs(group.beasts) do
          if beast.active and beast.species == species then
            if beast.hoennLatiasLatios then
              if foeState then
                beast.hp = math.max(0, tonumber(foeState.hp) or beast.hp)
                beast.status = foeState.status or beast.status
                beast.statusNum = foeState.statusNum or beast.statusNum
              end
              if battleResult == "caught" or (foeState and tonumber(foeState.hp) and foeState.hp <= 0) then
                beast.active = false
              else
                moveHoenn(beast, true)
              end
              return
            end
            return withBeast(session, beast, rawBattleEnd, foeState, battleResult, endReason)
          end
        end
      end

      Roamer._allBeastsInstalled = true
    end

    -- Untamed's visible roamer OWE needs the exact member of the grouped
    -- roamer state pinned while it is on the player's current map.
    if engine.roamerAt and not engine._groupedRoamerOWEInstalled then
      local visibleRoamer
      engine.roamerAt = function(index)
        if index ~= 0 then return nil end
        local session = engine.Runtime and engine.Runtime.getSession and engine.Runtime.getSession()
        local mapId = session and session.map
        if not session or not mapId then visibleRoamer = nil return nil end

        if visibleRoamer and visibleRoamer.mapId == mapId then
          local beast = visibleRoamer.beast
          if beast and beast.active
            and Roamer.normalizeMapId(beast.map) == Roamer.normalizeMapId(mapId) then
            return visibleRoamer.species, visibleRoamer.level, visibleRoamer.foe
          end
          visibleRoamer = nil
        end

        local enc = Roamer.tryEncounter(session, mapId, "land")
        if not enc then enc = Roamer.tryEncounter(session, mapId, "water") end
        if not enc then return nil end
        local chosen
        if isMulti(session.roamer) then
          for _, beast in ipairs(session.roamer.beasts) do
            if beast.active and beast.species == enc.species
              and Roamer.normalizeMapId(beast.map) == Roamer.normalizeMapId(mapId) then
              chosen = beast break
            end
          end
        end
        visibleRoamer = { mapId=mapId, beast=chosen, species=enc.species, level=enc.level, foe=enc.foe }
        return enc.species, enc.level, enc.foe
      end

      local rawRoamerMove = engine.roamerMove
      engine.roamerMove = function(index)
        visibleRoamer = nil
        if rawRoamerMove then return rawRoamerMove(index) end
      end
      mod.events:on("map.entered", function() visibleRoamer = nil end)
      engine._groupedRoamerOWEInstalled = true
    end

    local function addRoamer(session, species, key)
      local group = session.roamer
      if not isMulti(group) then
        local existing = group
        group = { active=true, beasts={} }
        if type(existing) == "table" and existing.species then group.beasts[#group.beasts + 1] = existing end
        session.roamer = group
      end
      for _, beast in ipairs(group.beasts) do
        if beast[key] or beast.species == species then return beast end
      end
      local mon = Roamer.generateMon(species, LEVEL)
      local beast = {
        active=true, hoennLatiasLatios=true, [key]=true,
        species=species, level=LEVEL,
        hp=mon.hp or mon.maxHp, maxHp=mon.maxHp or mon.hp,
        status=0, statusNum=0, pid=mon.pid, ivs=mon.ivs,
        moves=mon.moves, pp=mon.pp, map=randomHoennRoute(),
      }
      group.beasts[#group.beasts + 1] = beast
      return beast
    end

    local sceneActors = {}
    local sceneBusy = false

    if not Objects._latiasLatiosIdleAnim then
      Objects._latiasLatiosIdleAnim = true
      local rawUpdate = Objects.update
      Objects.update = function(game, ...)
        local result = rawUpdate(game, ...)
        for _, lid in ipairs({SCENE_LATIAS_ID, SCENE_LATIOS_ID}) do
          local actor = Objects._byId and Objects._byId[lid]
          if actor and actor._uadvIdleSheet and actor._uadvIdleRow then
            actor._uadvIdleTick = ((actor._uadvIdleTick or 0) + 1) % 32
            -- While scattering, cycle the walk frames continuously instead of
            -- using the subtle stationary idle cadence.
            local frame
            if actor._latiasLatiosEscaping then
              -- Untamed follower sheets encode direction in directional frame
              -- pairs. Keep each Pokémon facing its own escape direction.
              local base = actor._latiasLatiosEscapeFrameBase or 0
              frame = base + (math.floor(actor._uadvIdleTick / 4) % 2)
            elseif actor.moving then
              frame = (math.floor(actor._uadvIdleTick / 4) % 2)
            else
              frame = actor._uadvIdleTick >= 20 and actor._uadvIdleTick < 28 and 1 or 0
            end
            local gid = string.format("uadv:%d:%d:0:%d:0", actor._uadvIdleSheet, frame, actor._uadvIdleRow)
            actor.graphicsId, actor.sprite = gid, gid
          end
        end
        return result
      end
    end

    local function clearSceneActors()
      for _, lid in ipairs({SCENE_LATIAS_ID, SCENE_LATIOS_ID}) do
        if Objects._byId then Objects._byId[lid] = nil end
        for i = #(Objects._order or {}), 1, -1 do
          if Objects._order[i] == lid then table.remove(Objects._order, i) end
        end
      end
      sceneActors = {}
    end

    local function makeSceneActor(session, species, lid, x, y)
      local personality = engine.random32 and engine.random32() or 0
      -- Latias/Latios are native Gen III species IDs; unlike Gen IV additions,
      -- do not remap them through expansionSpecies before asking Untamed for
      -- their overworld follower sheet.
      local female = engine.femaleFor and engine.femaleFor(species, personality) or false
      local sheet, row = engine.Gfx.sheetFor(species, female, false)
      if not sheet then return nil end
      local gid = string.format("uadv:%d:0:0:%d:0", sheet, row)
      local elevation = engine.elevationAt and engine.elevationAt(x, y) or 3
      local actor = {
        active=true, localId=lid, originLocalId=lid, originMapId=session.map,
        cellX=x, cellY=y, px=x*16, py=y*16, homeX=x, homeY=y, targetX=x, targetY=y,
        facing="down", sprite=gid, graphicsId=gid, elevation=elevation, currentElevation=elevation,
        movementType=0x09, movement="STAY", range="DOWN", radius={x=0,y=0}, rangeX=0, rangeY=0,
        visible=true, hidden=false, invisible=false, frozen=true, passable=false,
        moving=false, progress=0, stepFrames=16, scriptBusy=false,
        _uadvIdleSheet=sheet, _uadvIdleRow=row, _uadvIdleTick=8,
        def={localId=lid,x=x,y=y,graphicsId=gid,movementType=0x09,facing="down"},
      }
      Objects._byId[lid] = actor
      Objects._order[#Objects._order + 1] = lid
      sceneActors[lid] = actor
      return actor
    end

    local function releaseRoamers(session)
      addRoamer(session, LATIAS, "latias")
      addRoamer(session, LATIOS, "latios")
      state(session).latiasLatiosReleased = true
    end

    local function showWaitingPair()
      local session = engine.Runtime and engine.Runtime.getSession and engine.Runtime.getSession()
      if not session or session.map ~= ROUTE_101 or sceneBusy then return false end
      if state(session).latiasLatiosReleased then return false end
      if sceneActors[SCENE_LATIAS_ID] and sceneActors[SCENE_LATIOS_ID] then return true end
      local P = engine.Player
      if not P or not P.cellX or not P.cellY then return false end

      -- Establish their waiting position once per save from the Route 101 entry
      -- point. The player remains fully controllable and can walk up to them.
      local st = state(session)
      if not st.sceneX or not st.sceneY then
        st.sceneX, st.sceneY = P.cellX - 2, P.cellY - 3
      end
      local latias = makeSceneActor(session, LATIAS, SCENE_LATIAS_ID, st.sceneX - 1, st.sceneY)
      local latios = makeSceneActor(session, LATIOS, SCENE_LATIOS_ID, st.sceneX + 1, st.sceneY)
      if not latias or not latios then clearSceneActors() return false end
      return true
    end

    local function tryReleaseScene()
      local session = engine.Runtime and engine.Runtime.getSession and engine.Runtime.getSession()
      if not session or session.map ~= ROUTE_101 or sceneBusy then return false end
      if state(session).latiasLatiosReleased then return false end
      if not sceneActors[SCENE_LATIAS_ID] or not sceneActors[SCENE_LATIOS_ID] then
        if not showWaitingPair() then return false end
      end
      local P = engine.Player
      local a = sceneActors[SCENE_LATIAS_ID]
      local b = sceneActors[SCENE_LATIOS_ID]
      if not P or not a or not b then return false end
      local da = math.abs(P.cellX - a.cellX) + math.abs(P.cellY - a.cellY)
      local db = math.abs(P.cellX - b.cellX) + math.abs(P.cellY - b.cellY)
      if math.min(da, db) > 2 then return false end

      sceneBusy = true
      engine.Field.locked = true
      if P.cellX < a.cellX then P.facing = "right"
      elseif P.cellX > b.cellX then P.facing = "left"
      else P.facing = "up" end

      -- Show a proper encounter reaction before the pair flee.
      local finished = 0
      local function gone()
        finished = finished + 1
        if finished < 2 then return end
        clearSceneActors()
        releaseRoamers(session)
        Message.show("The two POKéMON flew away!", function()
          engine.Field.locked = false
          sceneBusy = false
        end)
      end

      local function scatter()
        a._latiasLatiosEscaping, b._latiasLatiosEscaping = true, true
        a.facing, b.facing = "left", "up"
        -- Latias keeps the confirmed left-facing 4/5 pair. Latios uses the
        -- confirmed up/back-facing 2/3 pair and escapes north.
        a._latiasLatiosEscapeFrameBase = 4
        b._latiasLatiosEscapeFrameBase = 2
        if a.def then a.def.facing = "left" end
        if b.def then b.def.facing = "up" end
        a._uadvIdleTick, b._uadvIdleTick = 0, 0
        Objects.startTrack(SCENE_LATIAS_ID, {
          {kind="step",dir="left"},{kind="step",dir="left"},
          {kind="step",dir="left"},{kind="step",dir="left"},
          {kind="step",dir="left"},{kind="step",dir="left"},
          {kind="step",dir="left"},{kind="step",dir="left"},
          {kind="step",dir="left"},{kind="step",dir="left"},
          {kind="step",dir="left"},{kind="step",dir="left"}
        }, gone)
        Objects.startTrack(SCENE_LATIOS_ID, {
          {kind="step",dir="up"},{kind="step",dir="up"},
          {kind="step",dir="up"},{kind="step",dir="up"},
          {kind="step",dir="up"},{kind="step",dir="up"},
          {kind="step",dir="up"},{kind="step",dir="up"},
          {kind="step",dir="up"},{kind="step",dir="up"},
          {kind="step",dir="up"},{kind="step",dir="up"}
        }, gone)
      end

      -- Use the exact Gen3 field-effect path used by TrainerSight. This draws
      -- the native FRLG exclamation sprite above an EventObject and plays SE_PIN.
      FieldEffects.startExclamation(a, function()
        FieldEffects.startExclamation(b, scatter)
      end)
      return true
    end

    mod.events:on("map.entered", function()
      local session = engine.Runtime and engine.Runtime.getSession and engine.Runtime.getSession()
      clearSceneActors()
      if session and state(session).latiasLatiosReleased then
        addRoamer(session, LATIAS, "latias")
        addRoamer(session, LATIOS, "latios")
      elseif session and session.map == ROUTE_101 then
        showWaitingPair()
      end
    end)

    mod.events:on("world.stepped", function()
      local session = engine.Runtime and engine.Runtime.getSession and engine.Runtime.getSession()
      if session and session.map == ROUTE_101 and not state(session).latiasLatiosReleased then
        showWaitingPair()
        tryReleaseScene()
      end
    end)

    installed = true
    mod.log:info("Hoenn Latias + Latios roaming events installed")
    return true
  end

  mod.events:on("game.ready", install, -40)
end
