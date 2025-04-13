# main.gd
extends Control

# --- UI Node References ---
@onready var prompt_input: LineEdit = $VBoxContainer/PromptInput # Keep if you want custom prompts
@onready var send_button: Button = $VBoxContainer/SendButton # Now used for map generation
@onready var response_label: Label = $VBoxContainer/ResponseLabel
@onready var http_request: HTTPRequest = $GeminiRequest
@onready var map_display: Node2D = $MapDisplay
@onready var city_count_spinbox: SpinBox = $VBoxContainer/CityCountSpinBox
@onready var field_count_spinbox: SpinBox = $VBoxContainer/FieldCountSpinBox
@onready var player_instruction_input: LineEdit = $VBoxContainer/PlayerInstructionInput 
# --- NEW UI References (Add these buttons in your scene!) ---
@onready var start_game_button: Button = $VBoxContainer/StartGameButton # Add this button
@onready var next_turn_button: Button = $VBoxContainer/NextTurnButton # Add this button

# --- API and Game State ---
var api_key = 'AIzaSyDEyEJnccvexj6WNPwnFW2ptzFkwK-pGwc' # Replace with your actual key or load securely
var gemini_api_url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=" # Using 1.5 Flash as example

var current_turn_faction: Unit.Faction = Unit.Faction.PLAYER
var game_started: bool = false
var game_over: bool = false
var waiting_for_llm_response: bool = false # To prevent spamming requests

# Load resources once
const UnitRes = preload("res://unit.gd")
const MapNodeRes = preload("res://MapNode.gd")

func _ready():
	# --- Connect Signals ---
	send_button.pressed.connect(_on_generate_map_pressed)
	start_game_button.pressed.connect(_on_start_game_pressed)
	next_turn_button.pressed.connect(_on_next_turn_pressed)
	http_request.request_completed.connect(_on_request_completed)

	# --- Initial UI State ---
	start_game_button.disabled = true # Disabled until map is generated
	next_turn_button.disabled = true  # Disabled until game starts
	send_button.text = "Generate Map"

	if api_key == null or api_key.is_empty() or api_key == "YOUR_API_KEY":
		response_label.text = "ERROR: API Key not set in main.gd."
		send_button.disabled = true
		printerr("ERROR: API Key not set in main.gd.")
	else:
		response_label.text = "Ready to generate map."


# =============================================================================
#region Map Generation
# =============================================================================
func _on_generate_map_pressed():
	if api_key == null or api_key.is_empty():
		response_label.text = "API Key is missing. Cannot send request."
		return
	if waiting_for_llm_response:
		response_label.text = "Please wait for the previous request to complete."
		return

	send_button.disabled = true
	start_game_button.disabled = true
	next_turn_button.disabled = true
	response_label.text = "Generating map via Gemini..."
	waiting_for_llm_response = true
	game_started = false # Ensure game state is reset if regenerating
	game_over = false

	var num_cities = int(city_count_spinbox.value)
	var num_fields = int(field_count_spinbox.value)

	var prompt = """
	Generate a simple game map structure for a fantasy strategy game. It contains Cities and Fields
	Include exactly %d cities and exactly %d fields.

	Designate exactly one node as 'Player Start' and exactly one node as 'Enemy Start'.
	Try to place the Player Start and Enemy Start nodes relatively far apart within the connection graph.
	Provide connections between nodes slightly more than just enough to ensure the map is connected (no isolated nodes).

	Output the map data in the following format EXACTLY:

	NODES:
	NodeName1: Type (e.g., Crossroads: Field)
	NodeName2: Type (e.g., Capital: City)
	NodeName3: Type, Player Start (e.g., HomeBase: City, Player Start)
	NodeName4: Type, Enemy Start (e.g., DarkFortress: City, Enemy Start)
	...

	CONNECTIONS:
	NodeName1: NeighborNameA, NeighborNameB, NeighborNameC
	NodeName2: NeighborNameD
	...

	Do not include any other text, introductions, or explanations outside of this format.
	""" % [num_cities, num_fields]

	send_gemini_request(prompt)

func parse_map_from_text(text: String) -> bool:
	GameMap.clear_map() # Clear previous map data first

	var lines = text.strip_edges().split("\n")
	var current_section = "" # "NODES", "CONNECTIONS", or ""
	var success = true

	# Temporary storage for connections before nodes are fully created
	var connections_to_make: Dictionary = {} # NodeName -> [NeighborName1, NeighborName2,...]
	var player_start_node_name : String = ""
	var enemy_start_node_name : String = ""

	for line in lines:
		line = line.strip_edges()
		if line.is_empty(): continue

		if line.begins_with("NODES:"):
			current_section = "NODES"
			continue
		elif line.begins_with("CONNECTIONS:"):
			current_section = "CONNECTIONS"
			continue

		match current_section:
			"NODES":
				var parts = line.split(":", true, 1)
				if parts.size() != 2:
					printerr("Parsing NODES Error: Invalid format -> ", line)
					success = false; continue

				var node_name = parts[0].strip_edges()
				var type_and_flags = parts[1].strip_edges()
				var flag_parts = type_and_flags.split(",", true)
				var type_string = flag_parts[0].strip_edges().to_lower()

				var node_type = MapNodeRes.NodeType.FIELD # Default
				var is_player_start = false
				var is_enemy_start = false

				# Check for flags first
				if flag_parts.size() > 1:
					for i in range(1, flag_parts.size()):
						var flag = flag_parts[i].strip_edges().to_lower()
						if flag == "player start":
							is_player_start = true
							player_start_node_name = node_name
						elif flag == "enemy start":
							is_enemy_start = true
							enemy_start_node_name = node_name

				# Determine Node Type (Flags override type string)
				if is_player_start:
					node_type = MapNodeRes.NodeType.PLAYER_START
				elif is_enemy_start:
					node_type = MapNodeRes.NodeType.ENEMY_START
				elif type_string == "city":
					node_type = MapNodeRes.NodeType.CITY
				elif type_string == "field":
					node_type = MapNodeRes.NodeType.FIELD
				else:
					print("Note: Unknown node type '%s' for node '%s', defaulting to FIELD." % [type_string, node_name])
					node_type = MapNodeRes.NodeType.FIELD

				# Create and add the node
				var new_node = MapNodeRes.new(node_name, node_type)
				GameMap.add_node(new_node)

			"CONNECTIONS":
				var parts = line.split(":", true, 1)
				if parts.size() != 2:
					printerr("Parsing CONNECTIONS Error: Invalid format -> ", line)
					success = false; continue

				var node_name = parts[0].strip_edges()
				var neighbors_str = parts[1].strip_edges()
				var neighbor_names = []

				if not neighbors_str.is_empty():
					var raw_neighbors = neighbors_str.split(",")
					for raw_neighbor in raw_neighbors:
						var clean_neighbor = raw_neighbor.strip_edges()
						if not clean_neighbor.is_empty():
							neighbor_names.append(clean_neighbor)

				if not node_name.is_empty() and not neighbor_names.is_empty():
					connections_to_make[node_name] = neighbor_names

			_:
				pass # Ignore lines before sections

	# --- Phase 2: Establish Connections ---
	print("Making connections...")
	for node_name in connections_to_make:
		var neighbor_list = connections_to_make[node_name]
		for neighbor_name in neighbor_list:
			GameMap.add_connection(node_name, neighbor_name)

	# --- Phase 3: Place Initial Units ---
	if player_start_node_name.is_empty() or enemy_start_node_name.is_empty():
		printerr("Map Generation Error: Missing Player Start or Enemy Start node in definition.")
		response_label.text = "Error: Map invalid (missing start nodes)."
		return false

	# Clear any lingering units from previous games/maps
	GameMap.units.clear()
	for node in GameMap.nodes.values():
		node.units.clear()

	# Create and Place Units
	place_unit_on_node(UnitRes.new(UnitRes.Faction.PLAYER, "Player1"), player_start_node_name)
	place_unit_on_node(UnitRes.new(UnitRes.Faction.PLAYER, "Player2"), player_start_node_name)
	place_unit_on_node(UnitRes.new(UnitRes.Faction.PLAYER, "Player3"), player_start_node_name)
	place_unit_on_node(UnitRes.new(UnitRes.Faction.PLAYER, "Player4"), player_start_node_name)
	place_unit_on_node(UnitRes.new(UnitRes.Faction.ENEMY, "Enemy1"), enemy_start_node_name)
	place_unit_on_node(UnitRes.new(UnitRes.Faction.ENEMY, "Enemy2"), enemy_start_node_name)
	place_unit_on_node(UnitRes.new(UnitRes.Faction.ENEMY, "Enemy3"), enemy_start_node_name)
	place_unit_on_node(UnitRes.new(UnitRes.Faction.ENEMY, "Enemy4"), enemy_start_node_name)

	print("Map parsing finished. Success: ", success)
	if not success:
		response_label.text = "Map parsed with errors. Check console."
	return success

#endregion
# =============================================================================


# =============================================================================
#region Game Flow and Turns
# =============================================================================
func _on_start_game_pressed():
	if GameMap.nodes.is_empty():
		response_label.text = "Generate a map first!"
		return
	if game_started:
		response_label.text = "Game already in progress."
		return

	game_started = true
	game_over = false
	current_turn_faction = UnitRes.Faction.PLAYER # Player goes first
	start_game_button.disabled = true
	next_turn_button.disabled = false
	send_button.disabled = true # Don't allow regeneration during game
	update_status_label()
	print("Game Started!")

func _on_next_turn_pressed():
	if not game_started or game_over or waiting_for_llm_response:
		if game_over: response_label.text = "Game is over."
		elif waiting_for_llm_response: response_label.text = "Waiting for LLM..."
		else: response_label.text = "Start the game first."
		return

	print("\n--- Turn Start: %s ---" % UnitRes.Faction.keys()[current_turn_faction])
	next_turn_button.disabled = true # Disable until both factions have acted
	waiting_for_llm_response = true
	response_label.text = "Requesting actions for %s..." % UnitRes.Faction.keys()[current_turn_faction]
	request_llm_actions(current_turn_faction)

func advance_turn():
	# Check for game over *after* the last faction's actions
	var winner = check_game_over()
	if winner != null:
		game_over = true
		response_label.text = "GAME OVER! %s Wins!" % UnitRes.Faction.keys()[winner]
		next_turn_button.disabled = true
		# Optionally re-enable map generation here
		# send_button.disabled = false
		print("GAME OVER!")
		return

	# Switch to the next faction
	if current_turn_faction == UnitRes.Faction.PLAYER:
		current_turn_faction = UnitRes.Faction.ENEMY
	else:
		current_turn_faction = UnitRes.Faction.PLAYER

	update_status_label()
	# Re-enable button for the *next* full turn cycle
	next_turn_button.disabled = false
	print("--- Ready for next turn ---")


func update_status_label():
	if not game_started:
		response_label.text = "Generate a map and press Start Game."
	elif game_over:
		# Game over message handled in advance_turn
		pass
	else:
		response_label.text = "Current Turn: %s. Press Next Turn." % UnitRes.Faction.keys()[current_turn_faction]

func check_game_over() -> Variant: # Returns winning Faction enum value or null
	var player_units_alive = false
	var enemy_units_alive = false

	for unit in GameMap.units.values():
		if unit.is_alive():
			if unit.faction == UnitRes.Faction.PLAYER:
				player_units_alive = true
			else: # ENEMY
				enemy_units_alive = true
		# Optimization: If we find one alive for each, we can stop early
		if player_units_alive and enemy_units_alive:
			return null # Game not over

	if not player_units_alive:
		return UnitRes.Faction.ENEMY # Enemy wins
	elif not enemy_units_alive:
		return UnitRes.Faction.PLAYER # Player wins
	else:
		return null # Should not happen if loop finished, but good practice

#endregion
# =============================================================================


# =============================================================================
#region LLM Action Handling
# =============================================================================
func request_llm_actions(faction: Unit.Faction):
	var faction_name = UnitRes.Faction.keys()[faction]
	print("Requesting LLM actions for faction: ", faction_name)

	# --- Build Game State String ---
	var state_lines : PackedStringArray = ["Game State:"]

	# NODES (Include unit presence)
	state_lines.append("NODES:")
	var sorted_node_names = GameMap.nodes.keys()
	sorted_node_names.sort() # Consistent order helps the LLM
	for node_name in sorted_node_names:
		var node: MapNode = GameMap.nodes[node_name]
		var node_info = "  %s: Type=%s" % [node.node_name, MapNodeRes.NodeType.keys()[node.node_type]]
		var unit_names_on_node : PackedStringArray = []
		for unit in node.units:
			if unit.is_alive(): # Only show alive units
				unit_names_on_node.append(unit.unit_name)
		if not unit_names_on_node.is_empty():
			node_info += ", Units=[%s]" % ", ".join(unit_names_on_node)
		state_lines.append(node_info)

	# CONNECTIONS
	state_lines.append("CONNECTIONS:")
	for node_name in sorted_node_names:
		var node: MapNode = GameMap.nodes[node_name]
		var neighbor_names = node.neighbors.keys()
		neighbor_names.sort()
		if not neighbor_names.is_empty():
			state_lines.append("  %s: %s" % [node_name, ", ".join(neighbor_names)])

	# UNITS (Detailed list)
	state_lines.append("UNITS:")
	var sorted_unit_names = GameMap.units.keys()
	sorted_unit_names.sort()
	for unit_name in sorted_unit_names:
		var unit: Unit = GameMap.units[unit_name]
		if unit.is_alive():
			state_lines.append("  %s: Faction=%s, HP=%d, Node=%s" % [
				unit.unit_name,
				UnitRes.Faction.keys()[unit.faction],
				unit.hp,
				unit.current_node_name
			])
		else:
			# Optionally show dead units for context, or omit them
			# state_lines.append("  %s: Faction=%s, HP=0 (DEAD)" % [unit.unit_name, UnitRes.Faction.keys()[unit.faction]])
			pass


	var game_state_string = "\n".join(state_lines)

	# --- Build the Prompt ---
	var prompt = """
%s

RULES:
- Win by eliminating all enemy units.
- Units can move to adjacent connected nodes. A unit cannot move to a node occupied ONLY by enemy units. A unit CAN move to a node occupied by friendly units or if it's empty.
- Units on the same node or adjacent connected nodes can attack each other.
- Units attacking from a CITY node gain +2 attack power for that attack. The defender's node type does not affect damage taken.
- A unit can only perform ONE action per turn: either MOVE or ATTACK.
- Only units belonging to the current turn faction can act.

Current Turn: %s Faction

Task: Decide the action for EACH ALIVE unit belonging to the %s faction.
Output the actions in the following format ONLY, one action per line:
MOVE UnitName TargetNodeName
ATTACK AttackerUnitName TargetUnitName

Example:
MOVE Unit1 SouthGate
ATTACK Unit1 Unit4

Constraints:
- Provide exactly one action (MOVE or ATTACK) for every alive unit of the %s faction.
- Do not try to move a unit that is attacking, or attack with a unit that is moving.
- Ensure MOVE target nodes are valid neighbors.
- Ensure ATTACK targets are valid (alive, enemy, in range - same or adjacent node).
- Do not include any other text, introductions, explanations, or comments.
""" % [game_state_string, faction_name, faction_name, faction_name]

	send_gemini_request(prompt)


func parse_llm_actions(text: String, faction: Unit.Faction) -> Array[Dictionary]:
	var actions: Array[Dictionary] = [] # <--- FIX HERE: Explicitly type the array
	var lines = text.strip_edges().split("\n")
	var faction_name = UnitRes.Faction.keys()[faction]
	var units_acted_this_turn = {} # Track units to ensure one action per unit

	print("--- Parsing LLM Actions for %s ---" % faction_name)
	#print("Raw LLM Response:\n", text) # Debugging

	for line in lines:
		line = line.strip_edges()
		if line.is_empty(): continue

		var parts = line.split(" ", false, 2) # Split into command, arg1, arg2...
		if parts.size() < 2:
			printerr("Parse Action Error: Invalid format -> ", line)
			continue

		var command = parts[0].to_upper()
		var unit_name = parts[1]

		# Basic Validation: Does the unit exist and belong to the current faction?
		var unit = GameMap.get_unit(unit_name)
		if not unit:
			printerr("Parse Action Error: Unit '%s' not found. Line: %s" % [unit_name, line])
			continue
		if not unit.is_alive():
			print("Parse Action Info: Skipping action for dead unit '%s'." % unit_name)
			continue # Don't process actions for dead units
		if unit.faction != faction:
			printerr("Parse Action Error: Unit '%s' belongs to wrong faction (%s), current is %s. Line: %s" % [unit_name, UnitRes.Faction.keys()[unit.faction], faction_name, line])
			continue
		if units_acted_this_turn.has(unit_name):
			printerr("Parse Action Error: Unit '%s' already has an action assigned this turn. Line: %s" % [unit_name, line])
			continue


		match command:
			"MOVE":
				if parts.size() != 3:
					printerr("Parse Action Error: MOVE requires 3 parts (MOVE Unit Target). Line: %s" % line)
					continue
				var target_node_name = parts[2]
				# This dictionary implicitly matches the expected type
				actions.append({"type": "MOVE", "unit_name": unit_name, "target_node_name": target_node_name})
				units_acted_this_turn[unit_name] = true
			"ATTACK":
				if parts.size() != 3:
					printerr("Parse Action Error: ATTACK requires 3 parts (ATTACK Attacker Target). Line: %s" % line)
					continue
				var target_unit_name = parts[2]
				# This dictionary implicitly matches the expected type
				actions.append({"type": "ATTACK", "attacker_name": unit_name, "target_name": target_unit_name})
				units_acted_this_turn[unit_name] = true
			_:
				printerr("Parse Action Error: Unknown command '%s'. Line: %s" % [command, line])

	print("Parsed %d actions." % actions.size())
	return actions # Now 'actions' is guaranteed to be of type Array[Dictionary]


func execute_llm_actions(actions: Array[Dictionary], faction: Unit.Faction):
	var faction_name = UnitRes.Faction.keys()[faction]
	print("--- Executing Actions for %s ---" % faction_name)
	response_label.text = "Executing actions for %s..." % faction_name

	if actions.is_empty():
		print("No actions provided by LLM for ", faction_name)
		# This might happen, proceed to next phase
		return


	for action in actions:
		match action.type:
			"MOVE":
				var unit = GameMap.get_unit(action.unit_name)
				var target_node = GameMap.get_map_node(action.target_node_name)

				# --- Validation before moving ---
				if not unit or not target_node:
					printerr("Execute MOVE Error: Unit '%s' or Node '%s' not found." % [action.unit_name, action.target_node_name])
					continue
				if not unit.is_alive(): # Double check, might have died mid-turn if we allow simultaneous attacks later
					print("Execute MOVE Info: Unit '%s' is no longer alive." % action.unit_name)
					continue

				var current_node = GameMap.get_map_node(unit.current_node_name)
				if not current_node:
					printerr("Execute MOVE Error: Unit '%s' has invalid current node '%s'." % [unit.unit_name, unit.current_node_name])
					continue

				if not current_node.neighbors.has(target_node.node_name):
					print("Execute MOVE Warning: LLM tried to move '%s' from '%s' to non-neighbor '%s'. Skipping." % [unit.unit_name, current_node.node_name, target_node.node_name])
					continue # LLM made an illegal move suggestion

				# Check occupancy rule: Can't move to a node *only* occupied by enemies
				var target_has_enemies = false
				var target_has_friendlies = false
				for other_unit in target_node.units:
					if other_unit.is_alive():
						if other_unit.faction != unit.faction:
							target_has_enemies = true
						else:
							target_has_friendlies = true
				
				if target_has_enemies and not target_has_friendlies and target_node.units.size() > 0: # Make sure there are actually units there
					print("Execute MOVE Warning: LLM tried to move '%s' to enemy-occupied node '%s'. Skipping." % [unit.unit_name, target_node.node_name])
					continue # Illegal move based on rules


				move_unit(unit, target_node.node_name)

			"ATTACK":
				var attacker = GameMap.get_unit(action.attacker_name)
				var target = GameMap.get_unit(action.target_name)

				# --- Validation before attacking ---
				if not attacker or not target:
					printerr("Execute ATTACK Error: Attacker '%s' or Target '%s' not found." % [action.attacker_name, action.target_name])
					continue
				if not attacker.is_alive() or not target.is_alive():
					print("Execute ATTACK Info: Attacker '%s' or Target '%s' is not alive." % [action.attacker_name, action.target_name])
					continue
				if attacker.faction == target.faction:
					print("Execute ATTACK Warning: LLM tried friendly fire ('%s' attacking '%s'). Skipping." % [action.attacker_name, action.target_name])
					continue # Prevent friendly fire

				var attacker_node = GameMap.get_map_node(attacker.current_node_name)
				var target_node = GameMap.get_map_node(target.current_node_name)

				if not attacker_node or not target_node:
					printerr("Execute ATTACK Error: Could not find nodes for attacker '%s' or target '%s'." % [action.attacker_name, action.target_name])
					continue

				# Check range (same node or adjacent)
				if attacker_node != target_node and not attacker_node.neighbors.has(target_node.node_name):
					print("Execute ATTACK Warning: LLM target '%s' is out of range for attacker '%s'. Skipping." % [action.target_name, action.attacker_name])
					continue # Out of range

				perform_combat(attacker, target)

	map_display.queue_redraw() # Update visual display after actions


#endregion
# =============================================================================


# =============================================================================
#region Unit Management and Combat
# =============================================================================
func place_unit_on_node(unit: Unit, node_name: String):
	var node = GameMap.get_map_node(node_name)
	if node:
		if GameMap.units.has(unit.unit_name):
			push_warning("Unit '%s' already exists in GameMap.units. Overwriting/replacing." % unit.unit_name)
		# Ensure unit isn't somehow still listed on another node
		for existing_node in GameMap.nodes.values():
			if existing_node.units.has(unit):
				existing_node.units.erase(unit)

		node.units.append(unit)
		GameMap.units[unit.unit_name] = unit # Add/update in global list
		unit.current_node_name = node.node_name
		print("Placed unit '%s' on node '%s'." % [unit.unit_name, node_name])
	else:
		push_warning("Could not place unit '%s': Node '%s' not found." % [unit.unit_name, node_name])


func move_unit(unit: Unit, target_node_name: String) -> bool:
	if not unit.is_alive():
		print("Move Error: Unit '%s' is not alive." % unit.unit_name)
		return false

	var current_node = GameMap.get_map_node(unit.current_node_name)
	var target_node = GameMap.get_map_node(target_node_name)

	if not current_node:
		printerr("Move Error: Unit '%s' has invalid current node name '%s'." % [unit.unit_name, unit.current_node_name])
		return false
	if not target_node:
		print("Move Error: Target node '%s' does not exist." % target_node_name)
		return false

	# Check adjacency (already done in execute_llm_actions, but good failsafe)
	#if not current_node.neighbors.has(target_node_name):
	#	print("Move Error: Target node '%s' is not adjacent to '%s'." % [target_node_name, current_node.node_name])
	#	return false

	# Perform the move

	# --- FIX STARTS HERE ---
	# 1. Check if the unit exists in the current node's list *before* erasing
	var found_in_old_node = current_node.units.has(unit)

	if found_in_old_node:
		# 2. If found, then erase it (erase returns void, so no assignment)
		current_node.units.erase(unit)
	else:
		# 3. If not found, log the warning (this matches your original intent)
		push_warning("Unit '%s' was not found in units list of node '%s' during move." % [unit.unit_name, current_node.node_name])
	# --- FIX ENDS HERE ---


	target_node.units.append(unit) # Add to new node's list
	unit.current_node_name = target_node_name # Update unit's reference

	print("Unit '%s' moved from '%s' to '%s'." % [unit.unit_name, current_node.node_name, target_node.node_name])
	# map_display.queue_redraw() # Redraw handled after all actions execute
	return true


func perform_combat(attacker: Unit, target: Unit):
	if not attacker.is_alive() or not target.is_alive():
		print("Combat Info: Attacker or Target is already dead.")
		return

	print("Combat: '%s' (%s) attacks '%s' (%s)" % [attacker.unit_name, attacker.current_node_name, target.unit_name, target.current_node_name])

	var attacker_node = GameMap.get_map_node(attacker.current_node_name)
	var damage = attacker.attack_power

	# Apply City Bonus
	if attacker_node and attacker_node.node_type == MapNodeRes.NodeType.CITY:
		damage += 2 # Bonus damage from city
		print("  Attacker gets +2 damage bonus from city '%s'." % attacker_node.node_name)

	print("  Dealing %d damage." % damage)
	target.take_damage(damage) # Unit handles its own HP reduction and prints message

	if not target.is_alive():
		print("  Target '%s' eliminated!" % target.unit_name)
		remove_unit_from_game(target)


func remove_unit_from_game(unit: Unit):
	print("Removing unit '%s' from game." % unit.unit_name)
	# Remove from current node
	var current_node = GameMap.get_map_node(unit.current_node_name)
	if current_node:
		current_node.units.erase(unit)
	else:
		push_warning("Couldn't find node '%s' to remove dead unit '%s' from." % [unit.current_node_name, unit.unit_name])

	# Remove from global map list
	if GameMap.units.has(unit.unit_name):
		GameMap.units.erase(unit.unit_name)
	else:
		push_warning("Dead unit '%s' was not found in GameMap.units." % unit.unit_name)

	# Let unit know it's effectively gone (optional, good practice)
	unit.current_node_name = "REMOVED"

	map_display.queue_redraw() # Update display after removal


#endregion
# =============================================================================


# =============================================================================
#region HTTP Request Handling
# =============================================================================
func send_gemini_request(prompt_text: String):
	var headers = ["Content-Type: application/json"]
	var request_body = {
		"contents": [ { "parts": [ {"text": prompt_text} ] } ],
		# Add safety settings and generation config as before
		"safetySettings": [
			{"category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_MEDIUM_AND_ABOVE"},
			{"category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_MEDIUM_AND_ABOVE"},
			{"category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_MEDIUM_AND_ABOVE"},
			{"category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_MEDIUM_AND_ABOVE"}
		],
		"generationConfig": {
			"temperature": 0.7, # Adjust temperature as needed
			"maxOutputTokens": 1024 # Might need more tokens for complex states/actions
		}
	}

	var body_json = JSON.stringify(request_body)
	var error = http_request.request(gemini_api_url + api_key, headers, HTTPClient.METHOD_POST, body_json)

	if error != OK:
		response_label.text = "Error making HTTP request: %s" % error
		# Re-enable buttons if request fails immediately
		if not game_started: send_button.disabled = false
		if game_started and not game_over: next_turn_button.disabled = false
		waiting_for_llm_response = false


func _on_request_completed(result, response_code, headers, body):
	waiting_for_llm_response = false # Response received

	if result != HTTPRequest.RESULT_SUCCESS:
		response_label.text = "Request Error: %s" % result
		printerr("Request failed: %s" % result)
		# Re-enable buttons on error
		if not game_started: send_button.disabled = false
		if game_started and not game_over: next_turn_button.disabled = false
		return

	var response_text = ""
	var response_body_string = body.get_string_from_utf8()

	if response_code >= 400:
		response_label.text = "API Error (Code: %s). See console." % response_code
		printerr("Gemini API Error (Code: %s): %s" % [response_code, response_body_string])
		# Re-enable buttons on error
		if not game_started: send_button.disabled = false
		if game_started and not game_over: next_turn_button.disabled = false
		return

	var json_data = JSON.parse_string(response_body_string)

	if json_data == null:
		response_label.text = "Error parsing JSON response."
		printerr("Failed to parse JSON: %s" % response_body_string)
		# Re-enable buttons on error
		if not game_started: send_button.disabled = false
		if game_started and not game_over: next_turn_button.disabled = false
		return

	# Extract the generated text safely
	if json_data.has("candidates") and json_data.candidates.size() > 0 and \
	   json_data.candidates[0].has("content") and json_data.candidates[0].content.has("parts") and \
	   json_data.candidates[0].content.parts.size() > 0 and json_data.candidates[0].content.parts[0].has("text"):
		response_text = json_data.candidates[0].content.parts[0].text
	else:
		response_label.text = "Error: Unexpected response format from Gemini. See console."
		printerr("Unexpected Gemini response format: %s" % json_data)
		if json_data.has("error") and json_data.error.has("message"):
			response_label.text += "\nAPI Error: " + json_data.error.message
			printerr("Gemini API Error Message: " + json_data.error.message)
		# Re-enable buttons on error
		if not game_started: send_button.disabled = false
		if game_started and not game_over: next_turn_button.disabled = false
		return

	# --- Process the Response Based on Game State ---
	if not game_started:
		# --- Handle Map Generation Response ---
		response_label.text = "Received map data. Parsing..."
		if parse_map_from_text(response_text):
			response_label.text = "Map generated and parsed successfully! Ready to Start."
			GameMap.assign_random_positions(map_display.get_viewport_rect()) # Assign positions for drawing
			map_display.update_map_display() # Tell MapDisplay to draw
			print(GameMap.get_map_string()) # Print state for verification
			start_game_button.disabled = false # Enable start button
			send_button.disabled = false # Can generate another if desired
		else:
			response_label.text = "Failed to parse map from response. Check console."
			printerr("Map parsing failed. Response was:\n" + response_text)
			send_button.disabled = false # Allow retry
	else:
		# --- Handle Action Response ---
		response_label.text = "Received actions for %s. Executing..." % UnitRes.Faction.keys()[current_turn_faction]
		var actions = parse_llm_actions(response_text, current_turn_faction)

		if actions.is_empty() and response_text.strip_edges() != "":
			# LLM responded, but we couldn't parse any valid actions
			response_label.text = "Warning: Could not parse valid actions from LLM for %s. Skipping turn phase." % UnitRes.Faction.keys()[current_turn_faction]
			printerr("Could not parse valid actions for %s. Response was:\n%s" % [UnitRes.Faction.keys()[current_turn_faction], response_text])
			# Decide how to handle this - maybe skip this faction's turn?
			# For now, we'll proceed as if they did nothing.

		execute_llm_actions(actions, current_turn_faction)

		# --- Sequence the Turn ---
		if current_turn_faction == UnitRes.Faction.PLAYER:
			# Player turn finished, now request actions for Enemy
			var winner = check_game_over() # Check if player won before enemy turn
			if winner != null:
				game_over = true
				response_label.text = "GAME OVER! %s Wins!" % UnitRes.Faction.keys()[winner]
				next_turn_button.disabled = true
				print("GAME OVER!")
				return # End turn processing

			current_turn_faction = UnitRes.Faction.ENEMY
			response_label.text = "Requesting actions for ENEMY..."
			waiting_for_llm_response = true # Set waiting flag again
			request_llm_actions(current_turn_faction)
			# Don't re-enable next_turn_button yet

		elif current_turn_faction == UnitRes.Faction.ENEMY:
			# Enemy turn finished, advance to the next full turn cycle
			advance_turn() # This handles game over check and re-enables button if applicable


#endregion
# =============================================================================

# --- Need GameMap.gd methods ---
# Add these stubs if GameMap doesn't have them, or implement them fully there

# Add to GameMap.gd if missing:
# func get_unit(unit_name: String) -> Unit:
#     return units.get(unit_name, null)


# --- Need MapDisplay.gd method ---
# Add this stub if MapDisplay doesn't have it, or implement it fully there

# Add to MapDisplay.gd if missing:
# func update_map_display():
#     queue_redraw() # Or however you trigger drawing update

# func queue_redraw(): # If MapDisplay inherits from CanvasItem/Node2D
#	 get_viewport().canvas_item_set_dirty(self) # Force redraw
