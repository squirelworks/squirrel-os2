# Objects

Since 1.7.0 the kernel has a small object model: classes with a parent and a method table, objects that point at their class, and message sending that looks a method up through the parent chain. It is the base for the object desktop (1.7–1.9 in `../../ROADMAP.md`). The code is `kernel/object.asm`.

## Classes

A class is a 20-byte record in kernel data:

| Offset | Field | Meaning |
|--------|-------|---------|
| 0 | `CLS_NAME` | ASCIIZ class name |
| 4 | `CLS_PARENT` | the parent class, or 0 |
| 8 | `CLS_METHODS` | the method table |
| 12 | `CLS_FIELDS` | this class's own field names: a list of pointers to ASCIIZ names ending with 0, or 0 for none (1.7.1) |
| 16 | `CLS_TEXT` | which of this class's own fields hold text: bit n for its n-th own field (1.8.0) |

The method table is a list of (selector, handler) dword pairs that ends with a selector of 0. A selector is an ASCIIZ name such as `area`. A subclass lists only the methods it adds or overrides.

`obj_class` records a class in the class table (32 entries) so later tools can list it (`1.7-objs` in `../../TODO.md`). Recording the same class again does nothing. It refuses (eax = 0) a class whose fields, its parents' included, do not fit in an object.

## Objects

An object is a 32-byte slot in a table of 32. Its first dword (`OBJ_CLASS`) points at its class; a free slot has 0 there. `obj_new` takes the first free slot and clears it. The other 28 bytes hold up to 7 dword fields (below). `obj_free` (1.7.3) gives the slot back: it clears the class pointer, and refuses (CF set) an address that is not a slot of the table or a slot that is already free.

## objs (1.7.3)

The shell command `objs` prints `Classes:` and one line per recorded class, with ` < ` and the parent's name if it has one; then `Objects:` and one line per live object, `slot: class`; then the number of live objects and ` live`. After boot both lists are empty; after `objtest` the classes are `Shape` and `Square < Shape` and no object is live, since `objtest` frees its two (checks `objs-empty`, `objs-tree`). The object table is in kernel data, so `mem` is the same before and after (`objtest-mem`).

## Fields (1.7.1)

A class names only its own fields. Its fields come after all of its parent's, so field *n* of a class is field *n* of every subclass too, and a parent's method that works on its fields works on a subclass's object unchanged. Field *i* of an object is the dword at offset 4 + 4*i*.

`obj_field` finds a name in the object's class, then its parents, and returns the index: the number of fields the class's parents have, plus the name's position in the class's own list. `obj_get` and `obj_set` take the index and return CF set if the object's class does not have that many fields. `obj_nfields` gives the count for a class.

| Routine | In | Out |
|---------|----|-----|
| `obj_nfields` | eax = class | eax = number of fields, the parents' included |
| `obj_field` | eax = object, esi = field name | eax = index, CF clear; or eax = −1, CF set |
| `obj_get` | eax = object, ebx = index | eax = value, CF clear; or eax = −1, CF set |
| `obj_set` | eax = object, ebx = index, ecx = value | CF set if no such field |

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

It prints `obj: PASS`, or `obj: FAIL` (checks `objtest`, `objtest-text`). With Square's `area` taken out of its table, it prints FAIL.

Since 1.7.1 `Shape` has a field `size` and a method `resize` (ebx), which finds `size` by name and sets it; `Square` adds a field `colour` and a method `perimeter`, which reads field 0 and returns 4 times it. `objtest` then checks:

- `resize` 5 sent to the square, then `perimeter`, gives 20: set through the parent's method, read through the subclass's.
- `colour` is field 1 of the square; a shape has no `colour`, and setting its field 1 fails.
- The shape's own `size` is still 0.

It gives both slots back with `obj_free`, checks that freeing the shape again is refused (1.7.3), and prints `obj fields: PASS`, or FAIL (check `objfields`). With `perimeter` returning twice the size instead, it prints FAIL.

## Object files (1.8.0)

`obj_save` writes an object to a file on the data disk and `obj_load` reads one back into a new object. The file is:

| Bytes | Meaning |
|-------|---------|
| 4 | `SQOB` |
| 16 | the class name, padded with zeros (at most 15 characters) |
| 1 | the field count, the parents' fields included |
| per field | `0` and a dword; or `1`, a length byte and that many characters of text |

A field whose bit is set in its class's `CLS_TEXT` holds the address of an ASCIIZ string; it is saved as the text (at most 31 characters), not as the address. `obj_load` finds the class by name among the recorded classes (`obj_class`), checks that the field count matches, and puts each text into a 512-byte kernel pool that keeps one copy of each string; a loaded text field points into that pool. A file shorter than its header or its fields, an unknown class, a different field count or a full pool is refused, and no object is left behind.

| Routine | In | Out |
|---------|----|-----|
| `obj_save` | eax = object, esi = path | CF set if it could not be written |
| `obj_load` | esi = path | eax = a new object, CF clear; or eax = −1, CF set |

`objtest` then saves a square of size 5 whose `colour` is the text `red` to `objtest.obj`, frees it and loads it: `perimeter` gives 20 again, and `colour` is a copy of `red`, not the old address. It saves and loads a second square coloured `blue` and checks that the first still reads `red`. A `Ghost` object, whose class is not recorded, is saved and its file is refused. It prints `obj store: PASS`, or FAIL (check `objstore`). It needs the data disk. With `obj_load` taking an unknown class, with the integer fields not read, or with text fields pointing at the read buffer instead of the pool, it prints FAIL.

## objcat (1.8.1)

`objcat <file>` loads an object file, prints its class and then each field as `name: value`, a text field as its text and any other as a decimal number, and frees the object. A file that is missing, damaged, or of a class that is not recorded prints `objcat: not an object file of a known class`.

So that a file saved before a reboot can be read after it, the kernel records its own classes at boot (`obj_init`): `Shape`, `Square`, `DesktopObject` and `Program`. `objs` lists them from the start; `obj_fieldname` gives the name of a field by its index.

```
> objcat objtest.obj
Square
  size: 5
  colour: red
```
