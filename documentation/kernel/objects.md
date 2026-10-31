# Objects

Since 1.7.0 the kernel has a small object model: classes with a parent and a method table, objects that point at their class, and message sending that looks a method up through the parent chain. It is the base for the object desktop (1.7–1.9 in `../../ROADMAP.md`). The code is `kernel/object.asm`.

## Classes

A class is a 12-byte record in kernel data:

| Offset | Field | Meaning |
|--------|-------|---------|
| 0 | `CLS_NAME` | ASCIIZ class name |
| 4 | `CLS_PARENT` | the parent class, or 0 |
| 8 | `CLS_METHODS` | the method table |

The method table is a list of (selector, handler) dword pairs that ends with a selector of 0. A selector is an ASCIIZ name such as `area`. A subclass lists only the methods it adds or overrides.

`obj_class` records a class in the class table (32 entries) so later tools can list it (`1.7-objs` in `../../TODO.md`). Recording the same class again does nothing.

## Objects

An object is a 32-byte slot in a table of 32. Its first dword (`OBJ_CLASS`) points at its class; a free slot has 0 there. `obj_new` takes the first free slot and clears it. Fields in the other 28 bytes come with `1.7-fields`, and freeing with `obj_free` with `1.7-objs`.

## Sending a message

`obj_send` takes the object in eax and the selector in esi; ebx, ecx and edx are the arguments. It compares the selector with each entry of the object's class's table, then of its parent's, and so on. The first match runs, with eax = the object (self) and the arguments as they were, and what the method returns in eax comes back with CF clear. If no class in the chain has the selector, or eax is 0, it returns eax = −1 with CF set and nothing runs. A method may send messages itself, to self or to other objects; edi is free for it to use.

| Routine | In | Out |
|---------|----|-----|
| `obj_class` | esi = class record | eax = the class, or 0 if the table is full |
| `obj_new` | eax = class | eax = object, or 0 if no slot is free |
| `obj_send` | eax = object, esi = selector, ebx/ecx/edx = arguments | eax = the method's result, CF clear; or eax = −1, CF set |

## objtest

`objtest` records two classes: `Shape` with `name` (returns the string `Shape`), `area` (returns 0) and `describe` (sends `area` to self and adds 100), and `Square` under `Shape`, which overrides only `area` (ebx × ebx). It makes one of each and checks:

- `name` sent to the square runs Shape's method (inherited).
- `area` with ebx = 3 gives 9 for the square (overridden) and 0 for the shape.
- `describe` sent to the square gives 109: Shape's method runs and its `area` message reaches Square's override.
- `colour`, which no class has, returns with CF set.

It then gives both slots back and prints `obj: PASS`, or `obj: FAIL` (checks `objtest`, `objtest-text`). With Square's `area` taken out of its table, it prints FAIL.
