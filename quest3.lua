-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil
Game = Game or nil
InAction = InAction or false

Logs = Logs or {}

colors = {
  red = "\27[31m",
  green = "\27[32m",
  blue = "\27[34m",
  reset = "\27[0m",
  gray = "\27[90m"
}

function addLog(msg, text) -- Function definition commented for performance, can be used for debugging
  Logs[msg] = Logs[msg] or {}
  table.insert(Logs[msg], text)
end
-- Determines proximity between two points.
function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

-- Function to determine if a position is safe based on the positions of other players.
function isPositionSafe(myPosition, players, safeRange)
  for _, state in pairs(players) do
    if inRange(myPosition.x, myPosition.y, state.x, state.y, safeRange) then
      return false
    end
  end
  return true
end

-- Function to find a safe direction to move to.
function findSafeDirection(myPosition, players)
  local directions = {"Up", "Down", "Left", "Right", "UpRight", "UpLeft", "DownRight", "DownLeft"}
  for _, direction in ipairs(directions) do
    local newPosition = calculateNewPosition(myPosition, direction)
    if isPositionSafe(newPosition, players, 3) then
      return direction
    end
  end
  return nil
end

-- Function to calculate the new position based on the direction.
function calculateNewPosition(position, direction)
  local directionVectors = {
    Up = {x = 0, y = -1},
    Down = {x = 0, y = 1},
    Left = {x = -1, y = 0},
    Right = {x = 1, y = 0},
    UpRight = {x = 1, y = -1},
    UpLeft = {x = -1, y = -1},
    DownRight = {x = 1, y = 1},
    DownLeft = {x = -1, y = 1}
  }
  return {
    x = position.x + directionVectors[direction].x,
    y = position.y + directionVectors[direction].y
  }
end

-- Evaluates if it's beneficial to attack based on player's and target's energy and health.
function shouldAttack(player, target)
    local energyDifference = player.energy - target.energy
    local healthAdvantage = player.health > target.health
    return energyDifference > 0 and healthAdvantage
end

-- Main function to decide the next action.
function decideNextAction()
  local player = LatestGameState.Players[ao.id]
  local safeDirection = findSafeDirection(player.Position, LatestGameState.Players)

  if player.energy > 20 and player.health > 50 then
    -- Find a target and decide whether to attack
    for target, state in pairs(LatestGameState.Players) do
      if target ~= ao.id and inRange(player.Position.x, player.Position.y, state.Position.x, state.Position.y, 3) then
        if shouldAttack(player, state) then
          print("Strategic advantage identified. Attacking player " .. target .. ".")
          ao.send({Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(player.energy / 2), TargetPlayer = target})
          return
        end
      end
    end
  end

  if safeDirection then
    -- Move to a safer position if health or energy is low
    print("Moving to a safer position in direction: " .. safeDirection)
    ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = safeDirection})
  else
    print("No safe positions detected. Staying put.")
  end
end
-- Handler to print game announcements and trigger game state updates.
Handlers.add(
  "PrintAnnouncements",
  Handlers.utils.hasMatchingTag("Action", "Announcement"),
  function (msg)
    if msg.Event == "Started-Waiting-Period" then
      ao.send({Target = ao.id, Action = "AutoPay"})
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
      InAction = true
      -- print("Getting game state...")
      ao.send({Target = Game, Action = "GetGameState"})
    elseif InAction then
      print("Previous action still in progress. Skipping.")
    end
    print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
  end
)

-- Handler to trigger game state updates.
Handlers.add(
  "GetGameStateOnTick",
  Handlers.utils.hasMatchingTag("Action", "Tick"),
  function ()
    if not InAction then
      InAction = true
      print(colors.gray .. "Getting game state..." .. colors.reset)
      ao.send({Target = Game, Action = "GetGameState"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)

-- Handler to automate payment confirmation when waiting period starts.
Handlers.add(
  "AutoPay",
  Handlers.utils.hasMatchingTag("Action", "AutoPay"),
  function (msg)
    print("Auto-paying confirmation fees.")
    ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1"})
  end
)

-- Handler to update the game state upon receiving game state information.
Handlers.add(
  "UpdateGameState",
  Handlers.utils.hasMatchingTag("Action", "GameState"),
  function (msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    ao.send({Target = ao.id, Action = "UpdatedGameState"})
    print("Game state updated. Print \'LatestGameState\' for detailed view.")
  end
)

-- Handler to decide the next best action.
Handlers.add(
  "decideNextAction",
  Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
  function ()
    if LatestGameState.GameMode ~= "Playing" then 
      InAction = false
      return 
    end
    print("Deciding next action.")
    decideNextAction()
    ao.send({Target = ao.id, Action = "Tick"})
  end
)
-- Handler to automatically attack when hit by another player.
Handlers.add(
  "ReturnAttack",
  Handlers.utils.hasMatchingTag("Action", "Hit"),
  function (msg)
    if not InAction then
      InAction = true
      local playerEnergy = LatestGameState.Players[ao.id].energy
      local attackerId = msg.Attacker -- Assuming 'msg' contains the ID of the attacker

      if playerEnergy == nil then
        print("Unable to read energy. Attack failed.")
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy."})
      elseif playerEnergy == 0 then
        print("Player has insufficient energy. Attack failed.")
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Player has no energy."})
      else
        print("Returning attack to player " .. attackerId .. ".")
        ao.send({Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(playerEnergy / 2), TargetPlayer = attackerId})
      end
      InAction = false
      ao.send({Target = ao.id, Action = "Tick"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)
