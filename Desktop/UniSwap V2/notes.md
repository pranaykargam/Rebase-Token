mkdir UniSwapV2
cd UniSwapV2
forge init



01.  SPDX license identifier and pragma

02.  NatSpec contract-level comment (optional)

03.  Imports and using statements

04.  Contract declaration

05.  Type declarations (enums, structs)

06.  State variables (grouped by visibility and purpose)

07.  Events

08.  Errors (custom errors) and modifiers

09.  Constructor

10.  External/public functions (API surface) — ordered by importance and mutability: view/pure first, then non-view (readers often prefer view functions earlier)

11.  Internal/private helper functions

12.  Hooks, fallback and receive functions (if any)