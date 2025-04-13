# Unit.gd
extends Resource

class_name Unit

enum Faction {
	PLAYER,
	ENEMY
}

@export var faction: Faction
@export var unit_name: String = "Generic Unit"
var hp: int = 30         # Starting health points
var attack_power: int = 5 # Damage dealt per combat round
# Add other unit stats here: health, attack, etc.

var current_node_name: String = "" # The name of the MapNode the unit is currently located at

func _init(faction_type: Faction, name: String = "Generic Unit"):
	faction = faction_type
	unit_name = name


func take_damage(amount: int):
	hp -= amount
	print("%s (%s) takes %d damage, HP remaining: %d" % [unit_name, Faction.keys()[faction], amount, hp])
	if hp <= 0:
		print("%s (%s) has been eliminated!" % [unit_name, Faction.keys()[faction]])
		# The GameMap will handle removing the unit from the game state

func is_alive() -> bool:
	return hp > 0

func _to_string() -> String:
	return "Unit(%s, Faction: %s, HP: %d, Node: %s)" % [unit_name, Faction.keys()[faction], hp, current_node_name]
