# MapNode.gd
extends RefCounted

class_name MapNode # IMPORTANT: Declare this as a class

# Using an enum for Node Types is cleaner than strings
enum NodeType { FIELD, CITY, PLAYER_START, ENEMY_START }

var node_name: String
var node_type: NodeType = NodeType.FIELD
var neighbors: Dictionary = {} # Store neighbor names -> MapNode instances (or just names initially)

# --- Visualization Data ---
var position: Vector2 = Vector2.ZERO # Position on the screen for drawing
var drawn: bool = false # Helper flag for drawing connections once
var units: Array[Unit] = []

func _init(n: String, type: NodeType = NodeType.FIELD):
	self.node_name = n
	self.node_type = type
	self.position = Vector2(0,0)

func add_neighbor(neighbor_node):
	if not neighbors.has(neighbor_node.node_name):
		neighbors[neighbor_node.node_name] = neighbor_node
		# Ensure the connection is two-way
		if not neighbor_node.neighbors.has(self.node_name):
			neighbor_node.add_neighbor(self)
func add_unit(unit: Unit):
	if not units.has(unit):
		units.append(unit)
		unit.current_node_name = node_name # Ensure unit knows its location

func remove_unit(unit: Unit):
	units.erase(unit)
	# Don't reset unit.current_node_name here, the move function will do that
func _to_string() -> String:
	# Basic string representation for debugging
	var unit_names = []
	for unit in units:
		unit_names.append("Name: %s, Faction: %s" % [unit.unit_name, unit.faction])
	var unit_str
	if unit_names:
		unit_str = "Units: %s" % str(unit_names)
	return "MapNode(Name: %s, Type: %s,%s)" % [node_name, NodeType.keys()[node_type], unit_str]
