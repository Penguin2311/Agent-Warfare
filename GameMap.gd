# GameMap.gd
extends Node

# Dictionary to hold all nodes: node_name (String) -> MapNode object
var nodes: Dictionary = {}
# Dictionary for units if you add them later: unit_name -> Unit object
var units: Dictionary = {}

# --- Methods ---
func clear_map():
	print("Clearing existing map data.")
	nodes.clear()
	units.clear()
	# Any other cleanup needed when generating a new map

func add_node(node: MapNode):
	if not nodes.has(node.node_name):
		nodes[node.node_name] = node
		# print("Node '%s' added to map." % node.node_name) # Optional debug print
	else:
		push_warning("Node '%s' already exists in GameMap." % node.node_name)

func get_unit(unit_name):
	return units[unit_name]
	
func get_map_node(node_name: String) -> MapNode:
	return nodes.get(node_name, null) # Return null if not found

# Add unit functions similar to your Python version if needed later
# func add_unit(unit): ...
# func get_unit(unit_name): ...

func add_connection(name1: String, name2: String):
	var node1 = get_map_node(name1)
	var node2 = get_map_node(name2)

	if node1 and node2:
		node1.add_neighbor(node2)
		# print("Connection added between '%s' and '%s'." % [name1, name2]) # Optional
	else:
		if not node1: push_warning("Node '%s' not found for connection." % name1)
		if not node2: push_warning("Node '%s' not found for connection." % name2)

func get_map_string() -> String:
	# Generate a string representation for debugging or display
	var output: PackedStringArray = ["GameMap State:"]
	for node_name in nodes:
		var node: MapNode = nodes[node_name]
		var neighbor_names = node.neighbors.values()
		output.append("  Node(%s): Neighbors[%s]" % [node._to_string(), ", ".join(neighbor_names)])
	return "\n".join(output)

# --- Helper for Visualization ---
func assign_random_positions(area_rect: Rect2):
	# Give nodes random positions within a specified area for drawing
	# Simple random placement, not a sophisticated layout algorithm
	print("Assigning random positions...")
	for node_name in nodes:
		var node: MapNode = nodes[node_name]
		node.position = Vector2(
			randf_range(area_rect.position.x, area_rect.end.x),
			randf_range(area_rect.position.y, area_rect.end.y)
		)
		node.drawn = false # Reset drawing flag
	print("Positions assigned.")
	
