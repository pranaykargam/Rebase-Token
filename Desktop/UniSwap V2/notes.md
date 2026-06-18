mkdir UniSwapV2
cd UniSwapV2
forge init

01.State variables (immutable first)
2. Modifiers
3. Constructor
4. Fallback/receive functions
5. Public/external functions


01.  SPDX license identifier and pragma

02.  NatSpec contract-level comment (optional)

03.  Imports and using statements

04.  Contract declaration

05.  Type declarations (enums, structs)

06.  State variables (grouped by visibility and purpose)

07.  Events

08.  Errors (custom errors) and modifiers



09.  Constructor
// “starting setup” of a contract
// A contract can have only one constructor.
// It cannot return a value.

10.  External/public functions (API surface) — ordered by importance and mutability: view/pure first, then non-view (readers often prefer view functions earlier)

11.  Internal/private helper functions

12.  Hooks, fallback and receive functions (if any)


## immutable + constructor (src/routerLiquidity)
	Factory/WETH set once at deploy, stored in bytecode (not storage), can never change

