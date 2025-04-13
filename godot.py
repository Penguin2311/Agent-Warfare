from dotenv import load_dotenv
import os
from portia import (
    Config,
    LLMProvider,
    LLMModel,
    Portia,
)
from portia.tool import Tool, ToolRunContext
from portia import InMemoryToolRegistry
from pydantic import BaseModel, Field
import sys # Import the sys module

load_dotenv()  # Load environment variables from .env file
GOOGLE_API_KEY = 'AIzaSyDEyEJnccvexj6WNPwnFW2ptzFkwK-pGwc'

game_map = GameMap()

class UnitType:
    KING = "King"
    GENERAL = "General"


class UnitStatus:
    ALIVE = "Alive"
    DEAD = "Dead"


class Unit:
    """Base class for Kings and Generals."""

    def __init__(self, name, unit_type: UnitType, start_node , soldiers: int, faction: str):
        self.name = name
        self.unit_type = unit_type
        self.location = start_node
        self.soldiers = soldiers
        self.faction = faction
        self.status = "alive"
        self.current_action = None

        # Add self to the starting node
        if self.location:
            self.location.units.append(self)
            game_map.add_unit(self)


class Move_schema(BaseModel):
    """Schema for the MoveTool command."""

    unit_name: str = Field(description="The name of the object/unit to move.")
    destination: str = Field(description="The name of the destination neighbour node.")


class MoveTool(Tool):
    """Moves a unit to a neighbor node."""

    id: str = "move_tool"
    name: str = "MoveTool"
    description: str = "Moves a unit to a neighbor node."
    args_schema: type[BaseModel] = Move_schema
    output_schema: tuple[str, str] = ("str", "A string describing the result of the move.")

    def run(self, context: ToolRunContext, unit_name: str, destination: str):
        """Moves the unit to the specified destination."""
        return f"Moved {unit_name} to {destination}."


def get_portia_plan(command: str) -> str:
    """
    Generates a Portia plan for a given command and returns it as a JSON string.

    Args:
        command: The command to be planned.

    Returns:
        A JSON string representing the Portia plan.
    """

    my_config = Config.from_default(
        llm_provider=LLMProvider.GOOGLE_GENERATIVE_AI,
        llm_model_name=LLMModel.GEMINI_2_0_FLASH,
        google_api_key=GOOGLE_API_KEY,  # Use the API key loaded from the environment
    )

    custom_tool_registry = InMemoryToolRegistry.from_local_tools(
        [
            MoveTool(),
        ],
    )

    # Instantiate a Portia instance.
    portia = Portia(config=my_config, tools=custom_tool_registry)

    # Generate the plan
    plan = portia.plan(command)

    # Return the plan as a JSON string
    return plan.model_dump_json(indent=2)


if __name__ == "__main__":
    # Get the command from the command line arguments
    if len(sys.argv) > 1:
        command = sys.argv[1]
    else:
        print("Error: No command provided as a command line argument.", file=sys.stderr)
        sys.exit(1)  # Exit with a non-zero error code

    try:
        json_plan = get_portia_plan(command)
        print(json_plan)  # Print the JSON output to stdout.
    except Exception as e:
        print(f"Error: An error occurred: {e}", file=sys.stderr)  # Print error to stderr
        sys.exit(1) # Exit with a non-zero error code
