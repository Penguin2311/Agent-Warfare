# MapDisplay.gd
extends Node2D

# Customizable Drawing Colors and Properties
@export var default_color: Color = Color.WHITE
@export var city_color: Color = Color.YELLOW
@export var player_start_color: Color = Color.GREEN
@export var enemy_start_color: Color = Color.RED
@export var line_color: Color = Color(0.5, 0.5, 0.5) 
@export var node_radius: float = 15.0
@export var font_size: int = 16
@export var drawing_area_margin = 100

# Customizable Force-Directed Layout Parameters
@export var layout_iterations: int = 100 # Number of simulation steps
@export var optimal_distance: float = 200.0 # Ideal distance between connected nodes
@export var repulsion_strength: float = 10000.0 # How strongly nodes repel each other
@export var attraction_strength: float = 0.5 # How strongly edges pull nodes together
@export var initial_temperature: float = 1.0 # Starting temperature for cooling
@export var cool_down_factor: float = 0.99 # Multiplier for temperature each iteration (0.9 - 0.99)
@export var max_displacement: float = 10.0 # Maximum movement per iteration (prevents instability)

# Cache font reference if needed, or load dynamically
var font: Font 

func _ready():
	# Optionally load a specific font, otherwise default will be used
	# font = load("res://path/to/your/font.ttf") # Example
	pass

func _draw():
	# Check if GameMap and its nodes exist before trying to draw
	if not GameMap or GameMap.nodes.is_empty():
		# print("MapDisplay: No map data to draw.") # Optional debug
		return

	# print("MapDisplay: Drawing map...") # Optional debug

	# Use a theme font or load one if needed
	var draw_font = ThemeDB.get_fallback_font()
	var draw_font_size = font_size

	# 1. Draw Connections (Lines)
	for node_name in GameMap.nodes:
		var node1: MapNode = GameMap.nodes[node_name]
		# Avoid drawing connections if node1 doesn't exist (shouldn't happen if using GameMap.nodes keys)
		if not node1: continue 

		for neighbor_name in node1.neighbors:
			# Check if the neighbor also exists in the main nodes dictionary
			if GameMap.nodes.has(neighbor_name):
				var node2: MapNode = GameMap.nodes[neighbor_name]
				# Avoid drawing the line twice
				if node1.node_name < node2.node_name: # Ensure consistent ordering for drawing each edge only once
					draw_line(node1.position, node2.position, line_color, 2.0, true) # Antialiased

	# 2. Draw Nodes (Circles) and Labels
	for node_name in GameMap.nodes:
		var node: MapNode = GameMap.nodes[node_name]
		# Avoid drawing if node doesn't exist
		if not node: continue

		var color = default_color

		# Determine color based on type
		match node.node_type:
			MapNode.NodeType.CITY:
				color = city_color
			MapNode.NodeType.PLAYER_START:
				color = player_start_color
			MapNode.NodeType.ENEMY_START:
				color = enemy_start_color
			_: # Default case (FIELD)
				color = default_color

		# Draw the node circle
		draw_circle(node.position, node_radius, color)
# NEW: Draw units
		if not node.units.is_empty():
			# For now, just draw a simple indicator (e.g., a small square)
			var unit_offset = Vector2(0, -node_radius-5)  # Offset to the right
			for i in range(node.units.size()):
				var unit = node.units[i]
				var unit_color = Color.BLUE if unit.faction == Unit.Faction.PLAYER else Color.ORANGE # Different color based on faction
				print(str(unit.faction))
				draw_rect(Rect2(node.position + unit_offset + Vector2(-i * 15, 0), Vector2(7, 7)), unit_color) # Small square
		
		# Draw the node name label slightly below the circle
		var text_position = node.position + Vector2(0, node_radius + 5)
		# Center text horizontally - calculate width
		var text_width = draw_font.get_string_size(node.node_name, HORIZONTAL_ALIGNMENT_LEFT, -1, draw_font_size).x
		text_position.x -= text_width / 2
		draw_string(draw_font, text_position, node.node_name, HORIZONTAL_ALIGNMENT_LEFT, -1, draw_font_size, Color.WHITE)
	

func update_map_display():
	# This function is called from outside (e.g., Main.gd) after map data is ready.
	# It triggers the _draw() function to be called by the engine.
	if not GameMap or GameMap.nodes.is_empty():
		print("MapDisplay: No map data to display.")
		return

	print("MapDisplay: Received update request. Applying layout...")
	
	# Call the layout function *before* queueing redraw
	apply_force_directed_layout() 
	
	print("MapDisplay: Layout complete. Queueing redraw.")
	queue_redraw()

# --- Force-Directed Layout Implementation ---

func apply_force_directed_layout():
	print("Applying force-directed layout...")
	
	# 1. Initialize Node Positions (Use random as a starting point, or a tighter cluster)
	# You can keep your existing random assignment, or place them closer together
	assign_random_positions() 
	
	var current_temperature = initial_temperature
	var nodes_list = GameMap.nodes.values() # Get a list of the MapNode objects

	# 2. Simulation Loop
	for iter in range(layout_iterations):
		var forces = {} # Dictionary to store the total force on each node for this iteration
		
		# Initialize forces for all nodes to zero
		for node in nodes_list:
			forces[node.node_name] = Vector2.ZERO

		# Calculate Repulsive Forces (Node vs Node)
		# O(n^2) complexity - can be slow for very large graphs
		for i in range(nodes_list.size()):
			for j in range(i + 1, nodes_list.size()): # Only calculate for unique pairs (i, j) where i < j
				var node_i = nodes_list[i]
				var node_j = nodes_list[j]
				
				var delta = node_i.position - node_j.position
				var distance = delta.length()
				
				# Avoid division by zero and extreme forces for overlapping nodes
				if distance < 0.1: distance = 0.1 

				# Force magnitude (using inverse square law for simplicity)
				var force_magnitude = repulsion_strength / (distance * distance)
				
				# Force direction (away from each other)
				var force_direction = delta.normalized()
				
				# Apply force to both nodes
				forces[node_i.node_name] += force_direction * force_magnitude
				forces[node_j.node_name] -= force_direction * force_magnitude

		# Calculate Attractive Forces (Edge vs Edge)
		# O(m) complexity where m is the number of edges
		for node in nodes_list:
			for neighbor_name in node.neighbors:
				if GameMap.nodes.has(neighbor_name):
					var neighbor_node = GameMap.nodes[neighbor_name]
					
					# Only calculate force once per edge (e.g., from node -> neighbor, not neighbor -> node)
					if node.node_name < neighbor_node.node_name: # Consistent ordering prevents double calculation
						var delta = neighbor_node.position - node.position
						var distance = delta.length()
						
						# Avoid division by zero and extreme forces
						if distance < 0.1: distance = 0.1 
						
						# Force magnitude (based on deviation from optimal distance)
						var force_magnitude = attraction_strength * (distance - optimal_distance)
						
						# Force direction (towards each other)
						var force_direction = delta.normalized()
						
						# Apply force to both nodes
						forces[node.node_name] += force_direction * force_magnitude
						forces[neighbor_node.node_name] -= force_direction * force_magnitude


		# 3. Update Node Positions based on calculated forces
		# Apply damping (temperature) and limit movement
		var viewport_rect = get_viewport_rect()
		# Define a slightly smaller drawing area to constrain nodes
		var drawing_rect = viewport_rect.grow_individual(
			-drawing_area_margin, # left
			-drawing_area_margin, # top
			-drawing_area_margin, # right
			-drawing_area_margin # bottom
		)

		for node in nodes_list:
			var force = forces[node.node_name]
			
			# Scale force by temperature
			var displacement = force * current_temperature
			
			# Clamp displacement to prevent large jumps
			if displacement.length() > max_displacement:
				displacement = displacement.normalized() * max_displacement

			# Apply displacement
			node.position += displacement

			# Optional: Clamp position to stay within the drawing area
			node.position.x = clamp(node.position.x, drawing_rect.position.x, drawing_rect.end.x)
			node.position.y = clamp(node.position.y, drawing_rect.position.y, drawing_rect.end.y)

		# 4. Cool Down
		current_temperature *= cool_down_factor

		# Optional: Print progress (e.g., every 10 iterations)
		# if (iter + 1) % 10 == 0:
		# 	print("Layout Iteration: ", iter + 1, "/", layout_iterations)

	print("Force-directed layout simulation finished.")


# Keep the initial random assignment function, as it's still useful
# for starting the simulation from scratch each time.
func assign_random_positions():
	print("Assigning initial random positions...")
	# Get the viewport rect to constrain positions
	var viewport_rect = get_viewport_rect()
	# Add some padding
	var drawing_area = viewport_rect.grow_individual(
		-drawing_area_margin, # left
		-drawing_area_margin, # top
		-drawing_area_margin, # right
		-drawing_area_margin # bottom
	)

	for node_name in GameMap.nodes:
		var node: MapNode = GameMap.nodes[node_name]
		node.position = Vector2(
			randf_range(drawing_area.position.x, drawing_area.end.x),
			randf_range(drawing_area.position.y, drawing_area.end.y)
		)
		# node.drawn = false # This flag isn't used in the current _draw logic, can be removed
	print("Initial positions assigned.")
