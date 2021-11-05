# Codea-Docs

Craft was an update for Codea released back in 2016, since then various undocumented features were added but not all of them were properly documented. This repository serves as a hub for correcting that mistake, allowing contributors from [Codea-Talk](https://codea.io/talk/) who have been extremely patient and creative in figuring out what the heck some of these things do

Lets update the Codea documentation! I've included here the complete source for both the Codea documentation (written in YAML) and the Craft Lua bindings (`Source/Bindings/LuaBindings.mm`, written in Objective-C++ mostly using the LuaIntf library)

The `LuaBindings.mm` file contains all Craft API bindings available in Codea, and as much as I don't want to reveal how the sausage is made, here it is! The code is quite a mess so I apologise in advance

Feel free to ask me any questions about the API and I'll try to answer as best I can

## YAML documentation sources

The `Source/YAML` directory structure contains `.yaml` files for each of the main documentation categories. The formatting we use is as old as Codea, so some stuff will look a bit janky. I'll be accepting pull requests if anyone wants to make changes or add things. I'm not doing this to be lazy, I just find it difficult to keep everything up to date and I feel like this will help motivate me to do so
